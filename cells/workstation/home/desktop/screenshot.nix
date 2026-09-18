# takeshot: full/area/delayed screenshots -> ~/Pictures/Screenshots/*.webp,
# file:// URI on the clipboard, mako notification with open/edit/png actions
# (edit = satty). Bound in packages/dwl/config.h to Super+Print (--now) and
# Super+Alt+S (--area).
#
# hyprpicker is only used as a screen freezer under slurp (-r -z); it works
# on any wlroots compositor with layer-shell + screencopy, dwl included.
{
  pkgs,
  theme,
  ...
}: let
  takeshot = pkgs.writeShellApplication {
    name = "takeshot";
    runtimeInputs = with pkgs; [
      grim
      slurp
      satty
      hyprpicker
      imagemagick
      wl-clipboard
      libnotify
      xdg-user-dirs
      xdg-utils
      procps
      coreutils
    ];
    text =
      builtins.replaceStrings
      ["@theme_bg@" "@theme_focus@"]
      [theme.roles.bg theme.roles.focus]
      (builtins.readFile ./takeshot.sh);
  };
  k = theme.colors;
in {
  # satty also on PATH for `satty -f some.png` by hand.
  home.packages = [takeshot pkgs.satty];

  # satty: same palette as the rest of the desktop.
  xdg.configFile."satty/config.toml".source = (pkgs.formats.toml {}).generate "satty-config.toml" {
    general = {
      fullscreen = true;
      early-exit = true;
      initial-tool = "brush";
      copy-command = "wl-copy";
      output-filename = "$HOME/Pictures/Screenshots/satty-%Y-%m-%d_%H-%M-%S.png";
    };
    color-palette = {
      palette = [
        "#${k.autumnRed}"
        "#${k.springGreen}"
        "#${k.crystalBlue}"
        "#${k.fujiWhite}"
        "#${k.sumiInk3}"
      ];
    };
  };
}
