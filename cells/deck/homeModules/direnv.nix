# direnv: per-project envs. Ported from jarvis, but on NixOS the SYSTEM
# module owns it (common/profiles/base.nix: programs.direnv + nix-direnv).
# That module exports DIRENV_CONFIG=/etc/direnv, so direnv never reads
# ~/.config/direnv/direnv.toml -- an HM-side whitelist is dead config
# (measured on penrose 2026-09-15: `direnv status` -> whitelist.prefix [],
# `direnv allow` demanded in /srv/the-hive despite the HM toml). And
# programs.direnv here would hook zsh a second time on top of /etc/zshrc.
#
# So: no programs.direnv, no toml. The whitelist lives next to the paths it
# trusts (workstation/profiles/srv-the-hive.nix, srv-workspace.nix) as
# programs.direnv.settings.whitelist.prefix. What stays HM-side is the
# jarvis quirk of a silent direnv (empty DIRENV_LOG_FORMAT = no
# "direnv: export ..." lines) -- per account, not for root/scripts.
{
  inputs,
  cell,
}: {...}: {
  home.sessionVariables.DIRENV_LOG_FORMAT = "";
}
