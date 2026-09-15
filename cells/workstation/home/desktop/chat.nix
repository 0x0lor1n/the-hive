# Chat clients outside the nixpak set (packages.nix has slack + telegram
# for the Entra home). Ported from ~/nixos-config users/shared/gui/
# {simplex,mattermost}.nix (2026-09-15); the nonNixos/nixGL branches are gone
# with the platform.
#
# Both stay unsandboxed on purpose:
# - simplex-chat-desktop is an AppImage under appimageTools.wrapType2, i.e.
#   already bwrap'd; nesting it in nixpak's bwrap means userns-in-userns and
#   a second /etc, not worth debugging for a personal messenger.
# - mattermost-desktop is Electron; NIXOS_OZONE_WL comes from
#   layer-session.nix (system sessionVariables), so it is Wayland-native
#   without a wrapper.
# State to persist (impermanence lists in layer-users-local.nix /
# auth-entra.nix): ~/.config/Mattermost, ~/.local/share/simplex.
{pkgs, ...}: {
  home.packages = [
    pkgs.simplex-chat-desktop
    pkgs.mattermost-desktop
  ];
}
