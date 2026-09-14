# The deck: the shell + terminal toolkit (Neuromancer's cyberspace deck).
# Home-manager modules shared by every account on every workstation, host-
# and account-agnostic: identical for the local and the Entra home. Imported
# as `inputs.cells.deck.homeModules.<name>` from workstation/home.
#
# Modules take `{inputs, cell}` (ren block signature) and return an HM
# module, so they can reach `cell.packages` without a cellPackages arg.
{
  inputs,
  cell,
  ...
}: let
  mk = f: import f {inherit inputs cell;};
in {
  zsh = mk ./homeModules/zsh.nix;
  skim = mk ./homeModules/skim.nix;
  fzf = mk ./homeModules/fzf.nix;
  zoxide = mk ./homeModules/zoxide.nix;
  bat = mk ./homeModules/bat.nix;
  eza = mk ./homeModules/eza.nix;
  direnv = mk ./homeModules/direnv.nix;
  dircolors = mk ./homeModules/dircolors.nix;
  lazygit = mk ./homeModules/lazygit.nix;
  git = mk ./homeModules/git.nix;
  tmux = mk ./homeModules/tmux.nix;
  neovim = mk ./homeModules/neovim.nix;
}
