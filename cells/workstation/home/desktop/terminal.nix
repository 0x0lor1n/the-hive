# foot, the dwl terminal. DWL's terminal keybind execs `foot` by name, so it
# must be on PATH. Desktop-only: an admin account without `desktop` has no
# compositor to open it from and gets no foot config.
{
  pkgs,
  theme,
  ...
}: let
  k = theme.colors;
  r = theme.roles;
  inherit (theme) ansi;
in {
  programs.foot = {
    enable = true;
    settings = {
      # 10 fits more on 1920x1080 than the default 12 and stays readable.
      main.font = "monospace:size=10";
      main.pad = "8x8";
      # Every foot window lands in tmux: sesh attaches to the "the-hive"
      # session or creates it. Ctrl+Shift+<key> is translated to CSI-u so the
      # tmux prefix (C-S-b) and the C-S-* binds actually arrive; foot's own
      # bindings for those chords are disabled so they don't eat them.
      main.shell = "${pkgs.sesh}/bin/sesh connect the-hive";
      key-bindings = {
        scrollback-up-page = "none";
        scrollback-down-page = "none";
        spawn-terminal = "none";
        unicode-input = "none";
        prompt-prev = "none";
        prompt-next = "none";
      };
      text-bindings = {
        "\\x1b[98;6u" = "Control+Shift+b";
        "\\x1b[100;6u" = "Control+Shift+d";
        "\\x1b[102;6u" = "Control+Shift+f";
        "\\x1b[107;6u" = "Control+Shift+k";
        "\\x1b[108;6u" = "Control+Shift+l";
        "\\x1b[110;6u" = "Control+Shift+n";
        "\\x1b[112;6u" = "Control+Shift+p";
        "\\x1b[113;6u" = "Control+Shift+q";
        "\\x1b[116;6u" = "Control+Shift+t";
        "\\x1b[117;6u" = "Control+Shift+u";
        "\\x1b[119;6u" = "Control+Shift+w";
        # Enter chords: tmux binds C-Enter / C-S-Enter (swap / split), and
        # hermes/claude take Shift+Enter as newline. foot only encodes these
        # once an app pushes kitty-keyboard/modifyOtherKeys — which never
        # reaches it through tmux — so emit CSI-u unconditionally.
        # Super+Shift+Return is the muscle-memory split chord; tmux has no
        # Super modifier, so it is sent as the same C-S-Enter sequence (dwl
        # does not bind it -- new window is Super+Alt+T).
        "\\x1b[13;2u" = "Shift+Return";
        "\\x1b[13;5u" = "Control+Return";
        "\\x1b[13;6u" = "Control+Shift+Return Super+Shift+Return";
        # Inverse of the spawn chord: herdr binds it to the kill picker.
        "\\x1b[127;6u" = "Control+Shift+BackSpace";
      };
      # Palette from common/theme.nix (foot uses rrggbb, no #); the 16 ANSI slots
      # come from theme.ansi, same list the VT console uses.
      # foot >= 1.23 moved cursor.color into the colors section, and 1.27
      # renamed [colors] -> [colors-dark] ([colors] is deprecated, cursor.color
      # is a hard error). The CachyOS nixpkgs pin ships 1.27.
      colors-dark =
        {
          foreground = r.fg;
          background = r.bg;
          cursor = "${r.bg} ${k.oldWhite}";
          selection-foreground = k.oldWhite;
          selection-background = r.selection;
        }
        // builtins.listToAttrs (pkgs.lib.imap0 (i: c: {
            name =
              if i < 8
              then "regular${toString i}"
              else "bright${toString (i - 8)}";
            value = c;
          })
          ansi);
    };
  };
}
