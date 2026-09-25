# agent-terminals — foot + tmux (personal) on tag 1, foot + herdr (agents) on tag 2, both pre-opened at dwl start

Status: PLANNING (2026-09). Owner: user; Claude = executor.
Prereq: the-hive at 6a0c14b or later (dwl 0.9 + raiseorspawn patch, `dwl-startup-with-bar` in `cells/workstation/profiles/layer-compositor.nix`, tmux in `cells/deck/homeModules/tmux.nix`). Do NOT touch `cells/deck/homeModules/tmux.nix` until Phase 3 — tmux stays as it is today.

Target: on elster, after login into dwl, tag 1 already shows one foot running `tmux new -A -s main`, tag 2 already shows one foot running the herdr TUI attached to a user-level `herdr` server that survives the compositor. Bar renders tag 1 as 🧑 and tag 2 as 🤖. Stretch: same on penrose/sevastopol once elster is daily-driven.
Source refs: `cells/workstation/profiles/layer-compositor.nix` (`dwl-startup-with-bar` = the only autostart hook; `dwl-status` `render_tags()` = bar tag labels), `cells/workstation/packages/dwl/config.h` (`rules[]` line 46, `termraise`/`raiseorspawn` line 149–177), `~/.hermes/cache/web/herdr.dev-*.md` (herdr docs: install-with-nix `nix run github:herdrdev/herdr/v0.x.y`, session-state, agents), `.hermes/state/theme-coverage.md` (invariant style, acceptance gate).
Repo: cell `workstation`; inputs pinned by commit in `cells/workstation/flake.nix`; packages in `cells/workstation/packages.nix` (`cell.packages.<name>`); `nix eval --raw .#nixosConfigurations.elster.config.system.build.toplevel.drvPath` is the build probe.
Naming: flake input `herdr` (`github:herdrdev/herdr/<tag>`), package `cell.packages.herdr`; foot app_ids `foot-tmux` / `foot-herdr` (via `foot --app-id`); tmux session `main`; systemd user unit `herdr-server.service`; dwl rules `{ "foot-tmux", NULL, 1 << 0, 0, -1 }` / `{ "foot-herdr", NULL, 1 << 1, 0, -1 }`; keys `Super+Alt+T` = raiseorspawn `foot-tmux`, `Super+Alt+H` = raiseorspawn `foot-herdr`, `Super+Return` stays plain `foot` (untagged, throwaway); bar labels array `taglabel` in `dwl-status` (`1`→🧑 `2`→🤖, rest numeric).
herdr CLI (v0.9.1, from 0.2): (a) server for systemd = `herdr server` (no flag; foreground until SIGTERM, `capabilities.detached_server_daemon=false`); stop = `herdr server stop`; health = `herdr status server --json` (`.running`). (b) TUI attach = bare `herdr` ("Launch or attach to the persistent session"; named: `herdr session attach <name>` / `herdr --session <name>`). (c) env: `HERDR_SOCKET_PATH` (default `$XDG_CONFIG_HOME/herdr/herdr.sock`, client socket = `<stem>-client.sock`), `HERDR_CONFIG_PATH` (default `$XDG_CONFIG_HOME/herdr/config.toml`); logs `$XDG_CONFIG_HOME/herdr/herdr-server.log`. No XDG_RUNTIME_DIR use — socket lives in `~/.config/herdr/`.

Invariants:
- `nix run nixpkgs#alejandra -- --check <touched .nix>` == exit 0.
- `nix eval --raw .#nixosConfigurations.elster.config.system.build.toplevel.drvPath` succeeds (user runs it when the TPM cache is cold).
- `grep -c 'app_id' cells/workstation/packages/dwl/config.h` — rules for `foot-tmux` and `foot-herdr` are the ONLY rules with a non-zero tags mask besides the existing tag-9 mirror rule; nothing else is pinned to a tag.
- Hard rule (no command form): tag 1 holds exactly one `foot-tmux` client, tag 2 exactly one `foot-herdr` client; all splitting happens inside tmux / herdr, never by tiling a second foot on those tags. `Super+Return` foots are never given a tags mask.
- `herdr-server.service` is `WantedBy=default.target`, NOT `graphical-session.target`: agent sessions must survive `MOD+Shift+Q` and a compositor crash.
- `cells/deck/homeModules/tmux.nix` is byte-identical to 6a0c14b until Phase 3 (`git diff 6a0c14b -- cells/deck/homeModules/tmux.nix` == empty).
- One phase = one Conventional Commit with why-body + Co-Authored-By: Claude; nothing pushed by Claude.
- User acceptance gate: a phase flips to ✅ only after the USER has tested it on the rebuilt elster and said so. Claude's evals are not acceptance.

## Phase 0 — Recon (kill-switch) ⏳
Autonomy: safe
0.1 Pin herdr: `git ls-remote --tags https://github.com/herdrdev/herdr | tail -5` → pick the latest `v0.x.y`; `nix build github:herdrdev/herdr/<tag> --print-out-paths` on elster. Record tag + store path here.
    Kill-switch: if the flake does not build on nixpkgs `34ab9907` (see `cells/workstation/flake.nix` line 9) and cannot be overridden via `inputs.nixpkgs.follows`, stop; fallback below.
    DONE 2026-09: tag `v0.9.1` (rev `065ef9d6a531c49fb8bee7e818ef837065b21ee9`, latest by `sort -V`). Flake inputs: `nixpkgs`, `rust-overlay` (its nixpkgs follows herdr's). Own lock: `/nix/store/vmgh0yp88y87waiv77ijl5m9yvky0x46-herdr-0.9.1`. With `--override-input nixpkgs github:NixOS/nixpkgs/34ab99075ac4f7e40cf037eef32cb1c360bb85e9`: `/nix/store/gkryfp3177lfq0b997xv3plry9hia6ck-herdr-0.9.1` (only `stdenv.isLinux/isDarwin` deprecation warnings) → `follows` works, kill-switch NOT fired. Binary: `bin/herdr`. Attr: `packages.<system>.default` (what `nix build github:…` resolves to).
0.2 CLI surface: `<store>/bin/herdr --help`, `herdr server --help`, `herdr attach --help` (or whatever the TUI-attach verb is). Write the exact verbs for (a) start server in foreground for systemd, (b) attach TUI to running server, (c) socket/state dir env var into `Naming:`.
    DONE 2026-09: verbs written under `Naming:` (`herdr CLI` line). Probe with isolated `XDG_CONFIG_HOME`/`HERDR_SOCKET_PATH` in a tmpdir: `herdr server` stayed up until `timeout` killed it (exit 124), `status server --json` saw `running:true`; only files created = `cfg/herdr/{herdr-server.log,.plugins.lock}`, nothing in real `~/.config/herdr`. (b) taken from `--help` only, not exercised (needs a tty) — first real check in 1.4/2.5.
0.3 `cat ~/.hermes/cache/web/herdr.dev-63cccd5320.md | grep -n -i 'socket\|XDG\|state dir'` → confirm where the server keeps session state, so `herdr-server.service` can be given the right `Environment=`/`ConditionPathExists=`.
    DONE 2026-09: the grep had no hits — `63cccd5320` is the Keyboard page; session-state = `herdr.dev-209af94041.md`, agents = `herdr.dev-bf16d7040f.md`. Server log (`persist.restore`/`persist.save`) + probe with `HERDR_SOCKET_PATH` moved to another dir: `session.json` (+ `session-history.json` if `[experimental] pane_history`, `session-backups/`) always in `$XDG_CONFIG_HOME/herdr/`, independent of the socket path; remote agent manifests in `$XDG_STATE_HOME/herdr/agent-detection/`. Server creates both dirs itself; `~/.config/herdr` does not exist yet on elster. Pane shells inherit the server env (probe panes wrote zsh/p10k cache into the tmp `XDG_CACHE_HOME`) → unit sets NO `Environment=` XDG/HERDR overrides and NO `ConditionPathExists=`; defaults are correct.
0.4 `grep -n 'noto-fonts-color-emoji' cells/workstation/home/default.nix` == hit (bar font can render 🧑🤖). If not, add to `To do` of Phase 2.
Exit criteria: `herdr` tag and store path written here; verbs (a)(b)(c) written into `Naming:`; emoji font confirmed present; `Blocked on:` == nothing.

## Phase 1 — herdr packaged + server unit ⏳
1.1 `cells/workstation/flake.nix`: add input `herdr.url = "github:herdrdev/herdr/<tag>"` with `inputs.nixpkgs.follows = "nixpkgs"`; `nix flake lock` in `cells/workstation/`.
1.2 `cells/workstation/packages.nix`: `herdr = inputs.herdr.packages.${system}.default;` (or the attr name 0.2 found). `nix build .#herdr` → binary present.
1.3 `cells/workstation/profiles/layer-session.nix` (home-manager side, next to the other user units): `systemd.user.services.herdr-server` = `ExecStart=${cell.packages.herdr}/bin/herdr server <foreground flag from 0.2>`, `Restart=on-failure`, `WantedBy=[default.target]`, no `PartOf=graphical-session.target`.
1.4 Rebuild elster; `systemctl --user status herdr-server.service` → `active (running)`; `MOD+Shift+Q`, relogin → still `active`, same PID.
Exit criteria: `systemctl --user is-active herdr-server.service` == `active` across one logout/login; `journalctl --user -u herdr-server -b` free of restarts; commit `feat(workstation): herdr server as a user service`.

## Phase 2 — two pinned foots + emoji tags ⏳
2.1 `cells/workstation/packages/dwl/config.h` `rules[]`: add the two rules from `Naming:`; keep `Gimp_EXAMPLE` line as-is.
2.2 `config.h` keys: `termraise` → new `Raise tmuxraise = { "foot-tmux", tmuxcmd }` with `tmuxcmd = { "foot", "--app-id", "foot-tmux", "-e", "tmux", "new", "-A", "-s", "main", NULL }`; `Raise herdrraise = { "foot-herdr", herdrcmd }` with the attach verb from 0.2; bind `MODKEY|WLR_MODIFIER_ALT, XKB_KEY_t` → `tmuxraise`, `MODKEY|WLR_MODIFIER_ALT, XKB_KEY_h` → `herdrraise`. Check `XKB_KEY_h` is free: `grep -n 'XKB_KEY_h,' config.h` == no hit before edit.
2.3 `layer-compositor.nix` `dwl-startup-with-bar`: after the clipboard watchers, `${pkgs.foot}/bin/foot --app-id foot-tmux -e ${pkgs.tmux}/bin/tmux new -A -s main &` and `${pkgs.foot}/bin/foot --app-id foot-herdr -e ${cell.packages.herdr}/bin/herdr <attach verb> &`. herdr foot must start after `herdr-server` is up: precede with `${pkgs.systemd}/bin/systemctl --user start herdr-server.service` (idempotent).
2.4 `layer-compositor.nix` `dwl-status` `render_tags()`: `declare -A taglabel=([1]="🧑" [2]="🤖")`; render `"''${taglabel[$i]:-$i}"` instead of `$i` in all four spans.
2.5 Rebuild elster; login; `swaymsg`-less check: `ls /run/user/$UID/dwl/` bar state shows tag 1 and 2 occupied; screenshot bar (`grim -g "$(slurp)"` on the bar strip) → 🧑 🤖 visible.
Exit criteria: fresh login → tag 1 = one foot with tmux `main`, tag 2 = one foot with herdr TUI, no extra foots; `Super+Alt+T`/`Super+Alt+H` from any tag jump to those windows instead of spawning; bar shows 🧑 🤖; user confirms on elster; commit `feat(desktop): personal and agent terminals pinned to tags 1/2`.

## Phase 3 — tmux/herdr polish (only after user drives Phase 2 for ≥ 3 days) ⏳
3.1 `cells/deck/homeModules/tmux.nix`: only what the user asked for after living with it (e.g. `set -g detach-on-destroy off`, session `main` default). Nothing speculative.
3.2 herdr: agent presets / workspaces per `~/.hermes/cache/web/herdr.dev-bf16d7040f.md` (agents doc), if the TUI needs them for Claude Code + Hermes.
3.3 Optional: replicate Phase 1–2 for penrose / sevastopol (same profile; only the rebuild target changes).
Exit criteria: user-named items from 3.1/3.2 committed, each with its own test note in Progress.

## Fallback at any phase
Phase 0 kill-switch fires → skip herdr entirely: tag 2 gets `foot --app-id foot-agents -e tmux new -A -s agents` (second tmux server via `-L agents`), same rules/keys/emoji. Half a session of work; Phase 2 unchanged except the command.

## Progress
- 2026-09: plan written. Decided in chat: foot is the only terminal; tmux = personal multiplexer, herdr = agent multiplexer; one foot per tag, splits live inside the multiplexer; `Super+Return` stays a plain throwaway foot. Nothing built yet.
- 2026-09: 0.1 done — herdr v0.9.1 builds on elster, also with nixpkgs overridden to our pin; kill-switch not fired, fallback not needed.
- 2026-09: 0.2 done — `herdr server` is a foreground process (fits `Type=simple`), attach = bare `herdr`, socket/config/logs default to `~/.config/herdr/`.
- 2026-09: 0.3 done — session state = `~/.config/herdr/session.json`, manifests under `~/.local/state/herdr/`; unit needs no env/conditions. Plan's doc refs were off: 3.2 "agents doc" repointed `209af94041` (session-state) → `bf16d7040f`.

## verified
0.1: `nix build 'github:herdrdev/herdr/v0.9.1' --override-input nixpkgs 'github:NixOS/nixpkgs/34ab99075ac4f7e40cf037eef32cb1c360bb85e9' --no-link --print-out-paths` -> `/nix/store/gkryfp3177lfq0b997xv3plry9hia6ck-herdr-0.9.1` @ 2026-09-25
0.2: `timeout 4 herdr server` (tmp XDG_CONFIG_HOME + HERDR_SOCKET_PATH) -> exit 124, `herdr status server --json` `.running=true` meanwhile @ 2026-09-25
0.3: `herdr server` (tmp XDG_*, `HERDR_SOCKET_PATH=$T/sock/herdr.sock`) + `herdr workspace create` + `herdr server stop` -> log `persist.save ok path=$T/cfg/herdr/session.json`, `$T/sock/` holds only the socket @ 2026-09-25

Next: Phase 0.4 — `grep -n 'noto-fonts-color-emoji' cells/workstation/home/default.nix`; bar font renders 🧑🤖 or goes to Phase 2 `To do`.
Blocked on: nothing.
