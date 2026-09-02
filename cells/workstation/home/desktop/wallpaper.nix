# Static solid-color wallpaper (no asset management overhead); the
# startup script sets `swaybg -c '#1e1e2e' &`.
{pkgs, ...}: {
  home.packages = [pkgs.swaybg];
}
