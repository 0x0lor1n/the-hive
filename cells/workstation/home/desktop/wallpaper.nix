# Static solid-color wallpaper (no asset management overhead); the
# startup script sets `swaybg -c '#1f1f28' &` (kanagawa sumiInk3).
{pkgs, ...}: {
  home.packages = [pkgs.swaybg];
}
