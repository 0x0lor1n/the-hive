# Gate for agents-bump: what hermes-seed-proxy (agent-proxy.nix) and the skin
# build rely on, run against the pinned binaries in a throwaway HOME. Patch
# application and herdr-integrations' own asserts already fail at build time.
{
  lib,
  runCommand,
  hermes-agent,
  claude-code,
  opencode,
  herdr,
  herdr-integrations,
  rtk-hermes-plugin,
  rtk,
}:
runCommand "agents-check" {} ''
  export HOME=$TMPDIR/home HERMES_HOME=$TMPDIR/home/.hermes
  mkdir -p $HERMES_HOME/plugins
  cd $TMPDIR
  h=${lib.getExe hermes-agent}

  $h --version
  ${claude-code}/bin/claude --version
  ${opencode}/bin/opencode --version
  ${herdr}/bin/herdr --version

  # agent-proxy.nix reads banner.py by this path for the skin art.
  test -f ${hermes-agent}/lib/python3*/site-packages/hermes_cli/banner.py

  $h config set model.base_url http://pxpipe.anthropic.com:1/anthropic
  test "$($h config get model.base_url)" = http://pxpipe.anthropic.com:1/anthropic
  # seedHermes parses the list back as "- <name>" lines.
  $h config set plugins.enabled '["rtk-rewrite","herdr-agent-state"]'
  $h config get plugins.enabled | grep -qx -- '- herdr-agent-state'

  ln -s ${rtk-hermes-plugin} $HERMES_HOME/plugins/rtk-rewrite
  ln -s ${herdr-integrations}/hermes $HERMES_HOME/plugins/herdr-agent-state
  # doctor --ci passes a plugin that registered nothing; count the hooks.
  PATH=${rtk}/bin:$PATH $h plugins doctor --ci rtk-rewrite | tee rtk.log
  grep -q '1 hook(s)' rtk.log
  $h plugins doctor --ci herdr-agent-state | tee herdr.log
  grep -q '3 hook(s)' herdr.log

  touch $out
''
