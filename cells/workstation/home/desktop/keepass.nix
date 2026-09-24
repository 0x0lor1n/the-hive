# KeePassXC: the offline vault that holds the agenix recovery identity
# (profiles/secrets.nix) and the rest of the password store.
#
# Unsandboxed: it is Qt, Wayland-native without a wrapper, and it needs to
# reach the .kdbx wherever the user keeps it (a nixpak profile would turn
# every database location into a bind-mount to maintain).
# State to persist (impermanence lists in layer-users-local.nix /
# auth-entra.nix): ~/.config/keepassxc (settings) and
# ~/.local/share/keepassxc -- the directory to keep the .kdbx in; anything
# else under $HOME is rolled back at boot. ~/.cache is persisted whole.
#
# Theme "classic" = no own style/palette, so the qt6ct palette (qt.nix)
# applies; "auto" would pick KeePassXC's built-in DarkStyle. keepassxc.ini
# is rewritten by the app, so activation sets the one key in place instead
# of owning the file (HM programs.keepassxc would make it a read-only link).
{
  config,
  lib,
  pkgs,
  ...
}: {
  home.packages = [pkgs.keepassxc];

  home.activation.keepassxcTheme = lib.hm.dag.entryAfter ["writeBoundary"] ''
    conf=${lib.escapeShellArg "${config.xdg.configHome}/keepassxc/keepassxc.ini"}
    run mkdir -p "$(dirname "$conf")"
    run ${pkgs.crudini}/bin/crudini --ini-options=nospace --set "$conf" GUI ApplicationTheme classic
  '';
}
