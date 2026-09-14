# direnv + nix-direnv: per-project envs. Ported from jarvis; the whitelist
# prefix moves from ~/workspace to /srv/workspace, where projects live on
# penrose (profiles/srv-workspace, both accounts) — .envrc files under it
# are trusted without a manual `direnv allow`.
{
  inputs,
  cell,
}: {...}: {
  home.sessionVariables.DIRENV_LOG_FORMAT = "";

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };

  # https://github.com/direnv/direnv/pull/1475
  xdg.configFile."direnv/direnv.toml".text = ''
    [whitelist]
    prefix = [ "/srv/workspace" ]
  '';
}
