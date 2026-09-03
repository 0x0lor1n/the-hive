# Static solid-color wallpaper (no asset management overhead); the
# startup script (layer-compositor.nix) sets `swaybg -c '#<theme.roles.bg>' &`.
{pkgs, ...}: {
  home.packages = [pkgs.swaybg];
}
