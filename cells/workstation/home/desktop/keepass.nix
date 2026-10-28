# KeePassXC unsandboxed: nixpak would need a bind per .kdbx location. The app
# rewrites keepassxc.ini, so the theme key is set in place.
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
