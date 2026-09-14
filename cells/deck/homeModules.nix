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
}: {
  zsh = import ./homeModules/zsh.nix {inherit inputs cell;};
}
