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
{pkgs, ...}: {
  home.packages = [pkgs.keepassxc];
}
