# Agent tooling

What the workstations put between the coding agents (Hermes, Claude Code,
OpenCode) and the model: one proxy on the wire, two filters on the terminal.
All pinned in `cells/repo/packages.nix`, wired in
`cells/workstation/profiles/agent-proxy.nix`.

## pxpipe

[pxpipe](https://github.com/evan-choi/pxpipe-go) (pinned by hash) is a local
proxy that compacts Claude requests before they leave the machine.
Workstations run one system instance for every session: the port is shared
and two logged-in accounts would fight over a user unit. It is stateless --
the API key travels in each request -- so sharing it leaks nothing. The
profile also pins `pxpipe.anthropic.com` to `127.0.0.1` so the `/anthropic`
suffix survives Hermes' base_url handling.

```bash
journalctl -u pxpipe -f              # per-request: applied= saved= cache_read=
```

Hermes reaches it via `base_url: http://pxpipe.anthropic.com:47821`. The
`hermes-seed-proxy` user unit writes that into each account's
`~/.hermes/config.yaml` on login (Hermes reads the endpoint from there only),
enables the rtk plugin and links the shared `skills/`, `memories/` from
`/srv/agents/hermes`.

## nixq

`cells/repo/nixq` is a Go PATH shim shipped as `nix`, for agents only:
hermes, claude and opencode are wrapped (`withNixq`) to prepend it to their own
PATH, so the shells they spawn get it and human shells keep the real client.
It squeezes progress noise out of stderr (plan lists, `copying path`,
`building '…'`) into one summary line. From the first `error:` line onward
everything is verbatim; warnings, traces and unknown lines always survive
(fail-open).

When stderr is a TTY, `NIXQ=off` is set, or the subcommand is interactive
(`run`, `shell`, `develop`, `repl`, `log`), nixq execs the real nix with zero
overhead. `NIXQ_REAL_NIX` pins the client nix-plugins was built against
(devshell: `pkgs.nix`; system: `config.nix.package`), so the plugin ABI match
survives PATH shadowing.

## rtk

[rtk](https://github.com/rtk-ai/rtk) (pinned tag) compresses common command
output (`git status/diff/log`, `cargo test`, `ls`, `grep`, …) before it reaches
the model. On the Hermes side a `pre_tool_call` plugin (`rtk-rewrite`) rewrites
`git status` to `rtk git status` and so on. `nix` is never rewritten: nix errors
go through nixq, whose contract is "verbatim after error". Telemetry is off
via `RTK_TELEMETRY_DISABLED=1`.
