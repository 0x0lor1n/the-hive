# Repo-built packages the deck's home modules need; not in nixpkgs.
{
  inputs,
  cell,
  ...
}: let
  pkgs = inputs.pkgs;
in {
  # Ctrl-R for zsh-histdb (homeModules/zsh.nix).
  zsh-histdb-skim = pkgs.callPackage ./packages/zsh-histdb-skim.nix {};
}
