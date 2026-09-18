# direnv: per-project envs, owned by the system module on NixOS
# (common/profiles/base.nix: programs.direnv + nix-direnv). That module
# exports DIRENV_CONFIG=/etc/direnv, so direnv never reads
# ~/.config/direnv/direnv.toml and an HM-side whitelist is dead config
# (2026-09-15: `direnv status` -> whitelist.prefix [], `direnv allow`
# demanded in /srv/the-hive despite the HM toml). programs.direnv here would
# also hook zsh a second time on top of /etc/zshrc.
#
# So: no programs.direnv, no toml. The whitelist lives next to the paths it
# trusts (workstation/profiles/srv-the-hive.nix, srv-workspace.nix). Only the
# silent direnv stays HM-side (empty DIRENV_LOG_FORMAT = no "direnv:
# export ..." lines) -- per account, not for root/scripts.
{
  inputs,
  cell,
}: {...}: {
  home.sessionVariables.DIRENV_LOG_FORMAT = "";
}
