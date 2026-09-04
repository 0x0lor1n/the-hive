# Session layer: the NixOS side of any Wayland session (polkit, xdg-portal,
# hardware.graphics, greetd + tuigreet). DWL + home-manager live in
# layer-compositor.nix.
{
  inputs,
  cell,
}: {
  pkgs,
  config,
  lib,
  ...
}: let
  theme = inputs.cells.theme.palettes.kanagawa;
in {
  # wlroots takes the seat from logind. Do NOT also enable seatd, it would
  # contend for seat0.
  security.polkit.enable = true;

  # GPU-independent session environment. NixOS-level, not home.sessionVariables:
  # tuigreet's `--cmd` never sources ~/.profile, so HM vars are invisible to the
  # compositor greetd execs.
  environment.variables.LIBSEAT_BACKEND = "logind";

  # XKB reaches dwl only through compositorEnvironment (environment.variables
  # does not survive greetd's PAM-clean env). mkDefault: a platform profile
  # overrides the toggle where the host steals the chord.
  session.compositorEnvironment = {
    XKB_DEFAULT_RULES = lib.mkDefault "evdev";
    XKB_DEFAULT_MODEL = lib.mkDefault "pc105";
    XKB_DEFAULT_LAYOUT = lib.mkDefault "us,ru";
    XKB_DEFAULT_OPTIONS = lib.mkDefault "grp:alt_shift_toggle";
  };

  # Screen sharing, file pickers. "*" keeps the pre-1.17 behaviour (first
  # implementation found) now that 1.17+ wants explicit config.
  xdg.portal.enable = true;
  xdg.portal.wlr.enable = true;
  xdg.portal.extraPortals = [pkgs.xdg-desktop-portal-gtk];
  xdg.portal.config.common.default = "*";

  hardware.graphics.enable = true;
  programs.dconf.enable = true;
  services.dbus.enable = true;

  # NO autologin: the password is the last auth boundary once the TPM unlocks
  # the pool silently.
  #
  # XDG_SESSION_TYPE=wayland matters: pam_systemd reads it when opening the
  # session. Without it logind opens a Type=tty session and may revoke the
  # keyboard FDs before wlroots upgrades the type -> dead keyboard in the
  # compositor. tuigreet 0.11 has --env, but greetd's own environment is
  # inherited by PAM either way and covers the greeter too.
  # Only the session type belongs here: XDG_CURRENT_DESKTOP set this way does
  # NOT survive into the user session (verified on sevastopol) —
  # layer-compositor's dwl-session exports it right before exec dwl.
  systemd.services.greetd.environment = {
    XDG_SESSION_TYPE = "wayland";
  };

  # Kanagawa Wave on the kernel VT: tuigreet is a TUI and only names ANSI
  # colours (--theme below), so the actual hexes come from the console
  # palette, which is theme.ansi from cells/theme -- the 16 ANSI
  # slots: black red green yellow blue magenta cyan white, then bright.
  console.colors = theme.ansi;
  console.earlySetup = true;

  # tuigreet reads /etc/tuigreet/config.toml; CLI flags below win over it.
  environment.etc."tuigreet/config.toml".text = ''
    [display]
    show_time = true
    greeting = "NixOS ${config.networking.hostName} (nix-rensa)"
    align_greeting = "center"

    [remember]
    username = true
    session = false
    user_session = true
  '';

  services.greetd = {
    enable = true;
    settings.default_session = {
      # /etc/dwl/session (layer-compositor.nix) runs `dwl -s <startup>`; dwl's
      # own pipe feeds somebar, so nothing here may sit between them.
      command = lib.concatStringsSep " " [
        "${pkgs.tuigreet}/bin/tuigreet"
        "--time --remember --asterisks"
        # ratatui slot names -> console.colors above. Roles mirror hisilome
        # style.css: white=fujiWhite fg, darkgray=fujiGray muted, blue=crystalBlue
        # link, lightyellow=carpYellow highlight, lightgreen=springGreen accent,
        # magenta=oniViolet hover. (gray is slot 7 = oldWhite, NOT fujiGray.)
        "--theme 'border=blue;text=white;prompt=lightyellow;time=darkgray;action=lightgreen;button=magenta;container=black;input=white'"
        "--cmd /etc/dwl/session"
      ];
      user = "greeter";
    };
  };

  # `--remember` writes /var/cache/tuigreet/lastuser; keep it across @blank
  # so the greeter is prefilled with the last login.
  environment.persistence."/persist".directories = [
    {
      directory = "/var/cache/tuigreet";
      user = "greeter";
      group = "greeter";
      mode = "0755";
    }
  ];

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    inter
    noto-fonts
    noto-fonts-color-emoji
  ];

  # Only the PAM file; HM configures swaylock itself (programs.swaylock).
  security.pam.services.swaylock = {};

  # Chromium-based apps (microsoft-edge) run Wayland-native, not XWayland.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";
}
