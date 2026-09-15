# KeePassXC: the offline vault that holds the agenix recovery identity
# (profiles/secrets.nix) and the rest of the password store. Ported from
# jarvis users/shared/default.nix (`keepassxc` under # Privacy).
#
# Unsandboxed on purpose: it is Qt, Wayland-native without a wrapper, and it
# needs to reach the .kdbx wherever the user keeps it (a nixpak profile would
# turn every database location into a bind-mount to maintain).
# State to persist (impermanence lists in layer-users-local.nix /
# auth-entra.nix): ~/.config/keepassxc (settings) and ~/.cache/keepassxc
# (recent databases, window geometry).
{pkgs, ...}: {
  home.packages = [pkgs.keepassxc];
}
