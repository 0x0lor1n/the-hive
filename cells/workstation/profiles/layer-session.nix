# Session layer: the NixOS side of any Wayland session (polkit, xdg-portal,
# hardware.graphics, greetd + tuigreet). DWL + home-manager live in
# layer-compositor.nix. Was test-vm profiles/layer-session.nix.
{
  inputs,
  cell,
}: {pkgs, ...}: {
  # wlroots takes the seat from logind. Do NOT also enable seatd, it would
  # contend for seat0.
  security.polkit.enable = true;

  # GPU-independent session environment. NixOS-level, not home.sessionVariables:
  # tuigreet's `--cmd` never sources ~/.profile, so HM vars are invisible to the
  # compositor greetd execs.
  environment.variables = {
    LIBSEAT_BACKEND = "logind";
    XKB_DEFAULT_RULES = "evdev";
    XKB_DEFAULT_MODEL = "pc105";
    XKB_DEFAULT_LAYOUT = "us";
    XKB_DEFAULT_OPTIONS = "";
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
  # NOT survive into the user session (verified in port-test-vm) —
  # layer-compositor's dwl-session exports it right before exec dwl.
  systemd.services.greetd.environment = {
    XDG_SESSION_TYPE = "wayland";
  };

  # tuigreet reads /etc/tuigreet/config.toml; CLI flags below win over it.
  environment.etc."tuigreet/config.toml".text = ''
    [display]
    show_time = true
    greeting = "NixOS sevastopol (nix-rensa)"
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
      command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd /etc/dwl/session";
      user = "greeter";
    };
  };

  # Only the PAM file; HM configures swaylock itself (programs.swaylock).
  security.pam.services.swaylock = {};

  # Chromium-based apps (microsoft-edge) run Wayland-native, not XWayland.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";
}
