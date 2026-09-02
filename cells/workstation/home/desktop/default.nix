# Desktop companions for the local user's home-manager config: fuzzel,
# swaylock, mako, swayidle, swaybg, cliphist, avizo. One small module each.
#
# A plain helper directory, NOT a hive cell block: imported from
# ../default.nix, which layer-compositor.nix feeds to home-manager.users.
# somebar has no module here on purpose -- its patched binary is a system
# package (layer-compositor.nix); a home.packages entry would add the
# unpatched one next to it.
{...}: {
  imports = [
    ./launcher.nix
    ./lock.nix
    ./notify.nix
    ./idle.nix
    ./wallpaper.nix
    ./clipboard.nix
    ./osd.nix
  ];
}
