# post-dellvis-tooling

Unblocked 2026-09-04: penrose (ex-dellvis) runs cells/workstation on bare metal,
Secure Boot enabled (user keys), ZFS auto-unlock via TPM PCR15. Remaining blocker:
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
rtk:      0.47.0 in devshell (cells/repo/packages.nix); no hooks, no config.toml yet
nixq:     shipped as `nix` in devshell (cells/repo/nixq)

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
- [x] cells/repo/packages.nix: rtk 0.47.0 via buildRustPackage, in devshell PATH,
      RTK_TELEMETRY_DISABLED=1 set in shellHook (devshell only until home-manager lands)
- [ ] ~/.config/rtk/config.toml via home-manager:
      [hooks] exclude_commands = ["nix","nixos-rebuild","colmena","nom","just"]
      [tee] enabled = true, mode = "failures"
      + RTK_TELEMETRY_DISABLED=1 in home.sessionVariables
- [ ] runtime once: `rtk init -g` (claude: PreToolUse hook + ~/.claude/RTK.md)
      and `rtk init --agent hermes` (-> ~/.hermes/plugins/rtk-rewrite/);
      backup settings.json first; check both are idempotent enough to be
      re-run or replaced by home.file. Until then rtk nags once/day on stderr
      ("No hook installed") because ~/.claude exists — cosmetic.
- [ ] verify: `rtk gain` after a day of use

### 4. nixq (own tool, cells/repo/nixq, Go like pxpipe)
- [x] shipped as `nix` in cells/repo/devshells.nix, first in packages so it
      shadows nix_2_31; NIXQ_REAL_NIX pins the wrapped client (plugin ABI)
- [x] passthrough (exec): NIXQ=off, tty stderr, run/shell/develop/repl/log
- [x] line filter on plain stderr (not internal-json — simpler, and error text
      is what the model reads anyway): drop plan lists / copying / building,
      one summary line; verbatim from first `error` line; warning/trace/note
      and unknown lines always kept (fail-open). Tests: main_test.go
- [x] verified live: success -> 1 line; eval error verbatim, exit 1;
      build failure keeps "Last N log lines" + nix log hint; NIXQ=off exec
- [ ] nixos-rebuild / colmena wrappers — only if their noise turns out to matter
- [ ] optional later: --log-format internal-json for per-drv 40-line ring buffer
      (drops the "For full logs, run nix log" round-trip)

### 5. cleanup on jarvis after migration
- [ ] rm ~/.config/systemd/user/pxpipe.service, /etc/hosts line, ~/.hermes/config.yaml.bak.pxpipe
- [ ] ~/nixos-config: remove home-manager bits that moved here

## order
1 -> 2 (pxpipe first: it is what everything else talks through), then 3 and 4 in parallel, 5 last.
