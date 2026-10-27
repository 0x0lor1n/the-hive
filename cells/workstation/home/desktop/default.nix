# Desktop companions for an account's home-manager config: foot, fuzzel,
# swaylock, mako, swayidle, swaybg, cliphist, avizo, waybar, gtk/qt/cursor/fonts,
# xdg mime defaults, plus mpv, mpd/rmpc, the non-nixpak chat clients, KeePassXC
# and qBittorrent. One small module each. Skipped as a whole for `desktop =
# false` (admin-only) accounts.
#
# A plain helper directory, NOT a cell block: imported from
# ../default.nix, which layer-compositor.nix feeds to home-manager.users.
# The bar (waybar, bar.nix) is an HM user unit; dwl's status pipe reaches it
# through dwl-status in layer-compositor.nix.
{...}: {
  imports = [
    ./terminal.nix
    ./mime.nix
    ./launcher.nix
    ./lock.nix
    ./notify.nix
    ./idle.nix
    ./outputs.nix
    ./wallpaper.nix
    ./clipboard.nix
    ./screenshot.nix
    ./recorder.nix
    ./bar.nix
    ./menus.nix
    ./osd.nix
    ./gtk.nix
    ./qt.nix
    ./mpv
    ./music
    ./chat.nix
    ./chat-themes.nix
    ./keepass.nix
    ./torrent.nix
    ./zathura.nix
    ./firefox.nix
    ./darkreader.nix
  ];
}
