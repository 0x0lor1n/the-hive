# Shell + terminal tooling shared by both accounts (phase 2 fills this in,
# table in .hermes/state/port-jarvis-home.md: zsh/p10k, zsh-vi-mode, fzf,
# eza, bat, ripgrep, direnv, ...). Unconditional: identical for the local
# and the Entra home. Reads the palette from _module.args.theme.
#
# zsh HISTFILE must live under ~/.local/share/zsh — that dir is the
# impermanence carve-out (auth-entra.nix / layer-users-local.nix), the home
# root itself is rolled back at boot.
{...}: {
  imports = [];
}
