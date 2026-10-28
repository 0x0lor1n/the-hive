# No programs.direnv: DIRENV_CONFIG=/etc/direnv makes the HM toml dead config,
# and it would hook zsh twice.
{
  inputs,
  cell,
}: {...}: {
  home.sessionVariables.DIRENV_LOG_FORMAT = "";
}
