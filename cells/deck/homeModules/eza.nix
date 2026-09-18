# eza: `ls` replacement. HM's programs.eza.enable already puts the package on
# PATH and, with enableZshIntegration defaulting to true, defines
# ls/ll/la/lt/lla — the two below override ll/lla.
{
  inputs,
  cell,
}: {...}: {
  programs.eza.enable = true;

  home.shellAliases = {
    ll = "eza -lhF --group-directories-first";
    lla = "eza -lahF --group-directories-first";
  };
}
