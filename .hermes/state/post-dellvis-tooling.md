# post-dellvis-tooling

Blocked on: cells/workstation running on the dellvis laptop (real hardware)
and home-manager living in this repo instead of ~/nixos-config.
Everything below is currently imperative on jarvis and must become
declarative in cells/workstation/home/ (+ a profile for the pxpipe unit).

## state today (jarvis, imperative)
pxpipe:   ~/.config/systemd/user/pxpipe.service, ExecStart hardcodes
          /nix/store/r9jlqggngbpw9g2rz92sghzvl2mcwxhf-pxpipe-0.4.19/bin/pxpipe -port 47821
          (breaks on GC; re-created by hand after every rebuild of cells/repo pxpipe)
hosts:    /etc/hosts line `127.0.0.1 pxpipe.anthropic.com` added by hand
hermes:   ~/.hermes/config.yaml  base_url: http://pxpipe.anthropic.com:47821
claude:   ~/.claude/settings.json  (env / hooks edited by hand; pxpipe base_url lives here too)
rtk:      not installed
nixq:     not written yet (see plan below)

## todo (after dellvis boots from cells/workstation)

### 1. pxpipe declarative
- [ ] cells/workstation/home/dev/pxpipe.nix: systemd.user.services.pxpipe
      ExecStart = ${cells.repo.packages.pxpipe}/bin/pxpipe -port 47821
      Restart=on-failure, WantedBy=default.target; drop the imperative unit
- [ ] networking.hosts."127.0.0.1" = [ "pxpipe.anthropic.com" ] (nixos side)
- [ ] pxpipe allow-list stays claude-fable-5 / claude-fable-5-1 (commit 784ef40);
      expose PXPIPE_MODELS via Environment= only if needed
- [ ] verify: journalctl --user -u pxpipe shows applied=true for fable, applied=false for others

### 2. hermes + claude configs
- [ ] home.file / xdg.configFile for ~/.hermes/config.yaml base_url (or at least the
      anthropic provider block) -- check what hermes tolerates as read-only
- [ ] ~/.claude/settings.json: env.ANTHROPIC_BASE_URL + hooks as home-manager json
      (programs.claude-code if the module exists in the pinned nixpkgs, else xdg.configFile)
- [ ] keep DISABLE_NON_ESSENTIAL_MODEL_CALLS=1

### 3. rtk (github.com/rtk-ai/rtk, not in nixpkgs)
- [ ] cells/repo/packages.nix: rtk via buildRustPackage (pin tag + cargoHash)
- [ ] ~/.config/rtk/config.toml via home-manager:
      [hooks] exclude_commands = ["nix","nixos-rebuild","colmena","nom","just"]
      [tee] enabled = true, mode = "failures"
      + RTK_TELEMETRY_DISABLED=1 in home.sessionVariables
- [ ] runtime once: `rtk init -g` (claude: PreToolUse hook + ~/.claude/RTK.md)
      and `rtk init --agent hermes` (-> ~/.hermes/plugins/rtk-rewrite/);
      backup settings.json first; check both are idempotent enough to be
      re-run or replaced by home.file
- [ ] verify: `rtk gain` after a day of use

### 4. nixq (own tool, cells/repo/nixq, Go like pxpipe)
- [ ] wrapper: nix/nixos-rebuild in PATH -> nixq; NIXQ=off or --raw = passthrough;
      tty stderr or interactive subcommands (repl/shell/develop) = passthrough
- [ ] filter stderr only via --log-format internal-json:
      drop start/stop/progress/substitute/fetch -> one summary line
      keep msg level<=warn verbatim
      buildLogLine: ring buffer 40 lines/drv, dump only on that drv failing
      eval trace: first 6 + last 6 frames, position/snippet untouched
      fail-safe: exit!=0 and no error event printed -> dump raw stderr
- [ ] fixtures: internal-json dumps for success / eval error / build fail
- [ ] add to cells/repo/devshells.nix (and rtk exclude_commands above so they don't stack)

### 5. cleanup on jarvis after migration
- [ ] rm ~/.config/systemd/user/pxpipe.service, /etc/hosts line, ~/.hermes/config.yaml.bak.pxpipe
- [ ] ~/nixos-config: remove home-manager bits that moved here

## order
1 -> 2 (pxpipe first: it is what everything else talks through), then 3 and 4 in parallel, 5 last.
