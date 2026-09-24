# hermes-backup — ZFS snapshots + off-host replication for everything Hermes keeps

Status: PLANNING (2026-09). Owner: user; Claude = executor.
Prereq: the-hive at 28d7e3d or later. Do NOT `zfs rollback` any dataset at any phase — restores are file-level copies from `.zfs/snapshot/`.

Target: elster's `rpool/safe` is snapshotted automatically (hourly/daily/monthly), `state.db` has an extra daily SQLite `.backup`, `/srv/agents/hermes` (skills + memories) is a git repo with a daily auto-commit, and everything under `rpool/safe` is replicated off the laptop to osgiliath, encrypted at rest. Losing the NVMe costs ≤ 1 hour of Hermes history. Stretch: same profile on penrose/sevastopol.
Source refs: `cells/workstation/profiles/storage-zfs.nix` (existing ZFS profile; `services.zfs.autoScrub` gated on `!host.isVm` — same gate for snapshots), `cells/workstation/disks/elster.nix` (datasets: `rpool/safe/persist` → `/persist`, `rpool/safe/srv/agents`, `rpool/safe/srv/the-hive`, `rpool/safe/srv/workspace`, `rpool/safe/docker`), `cells/workstation/profiles/auth-entra.nix` line 252–290 (`environment.persistence."/persist".directories` includes `entraHome ".hermes"`), `cells/server/profiles/storage-btrfs-rollback.nix` (osgiliath is **btrfs**, not ZFS — no `zfs recv` there), `~/.hermes/cron/jobs.json` (Hermes cron for the SQLite backup + git commit).
Layout on disk (measured 2026-09-25): `~/.hermes` = bind from `rpool/safe/persist`, 204M of which `state.db` 68M (WAL mode, `state.db-wal` beside it), `lsp/` 99M + `bin/` 16M + `cache/` 7.6M regenerable; `~/.hermes/skills` → `/srv/agents/hermes/skills`, `~/.hermes/memories` → `/srv/agents/hermes/memories` on `rpool/safe/srv/agents` (18M). Only snapshot present: `rpool/local/root@blank` (impermanence). No sanoid/zrepl/autoSnapshot anywhere in the-hive. `rpool/safe` is `aes-256-gcm`, keyformat `passphrase`.
Repo: cell `workstation`; new profile `cells/workstation/profiles/storage-zfs-snapshots.nix` added to the `workstation` list in `cells/workstation/nixosConfigurations.nix` right after `p.storage-zfs-rollback`; `nix eval --raw .#nixosConfigurations.elster.config.system.build.toplevel.drvPath` is the build probe.
Naming: profile `storage-zfs-snapshots`; sanoid templates `safe` (hourly 48 / daily 30 / monthly 6) and `agents` (frequently 8 @ 15 min + `safe`); snapshot prefix sanoid default `autosnap_`; SQLite backups dir `~/.hermes/backups/state-<yyyy-mm-dd>.db`, keep 14; git repo `/srv/agents/hermes` (branch `main`, remote name `origin`, remote URL user-supplied); Hermes cron jobs `hermes-state-backup` (daily 03:00) and `hermes-brain-commit` (daily 03:10); replication unit `syncoid-safe` or `restic-safe` — decided in Phase 2.

Invariants:
- `nix run nixpkgs#alejandra -- --check <touched .nix>` == exit 0.
- `nix eval --raw .#nixosConfigurations.elster.config.system.build.toplevel.drvPath` succeeds (user runs it when the TPM cache is cold).
- `zfs list -t snapshot rpool/local/root -H | wc -l` == 1 — `local/*` is never snapshotted by sanoid (impermanence owns `@blank`).
- Never `zfs rollback` outside `storage-zfs-rollback.nix`'s boot-time `local/root@blank`; restores are `cp` from `/persist/.zfs/snapshot/<snap>/…` or `/srv/agents/.zfs/snapshot/<snap>/…`.
- Replication to a host that cannot see plaintext: `zfs send --raw` or a client-side-encrypted tool (restic). `auth.json`, `.env`, `config.yaml` never leave elster in the clear.
- `sqlite3 ~/.hermes/backups/state-<latest>.db "pragma integrity_check"` == `ok` after every backup run.
- One phase = one Conventional Commit with why-body + Co-Authored-By: Claude; nothing pushed by Claude.
- User acceptance gate: a phase flips to ✅ only after the USER has run the restore drill (Exit criteria) on elster and said so.

## Phase 0 — Recon + first manual snapshot ⏳
0.1 `sudo zfs snapshot -r rpool/safe@manual-2026-09-25` — the first safety net before any change. `zfs list -t snapshot -r rpool/safe -H | wc -l` == 7 (persist, srv, srv/agents, srv/data, srv/data/documents, srv/data/music, srv/the-hive, srv/workspace, docker → count them; record the number here).
0.2 Confirm sanoid is in the pinned nixpkgs: `nix eval nixpkgs#sanoid.version` with the flake's nixpkgs (`34ab9907`). Record the version.
0.3 `sqlite3 ~/.hermes/state.db "pragma journal_mode"` == `wal` and `ls ~/.hermes/state.db*` shows `.db` + `.db-wal` on the same dataset (both under `/persist`); this is what makes a snapshot crash-consistent for SQLite.
0.4 Decide replication path (see Phase 2 options); write the choice into `Naming:`. If undecided → `Blocked on:`.
0.5 Remove the manual pre-snapshot copies that 0.1 makes redundant: `rm -r ~/.hermes/skills.pre-shared-2026-09-20 ~/.hermes/memories.pre-shared-2026-09-20 ~/.hermes/config.yaml.bak-workdir-guard` (they are in `@manual-2026-09-25` now).
Exit criteria: `@manual-2026-09-25` exists recursively on `rpool/safe`; sanoid version recorded; journal mode confirmed; 0.5 done; replication choice written or in `Blocked on:`.

## Phase 1 — sanoid on elster ⏳
1.1 `cells/workstation/profiles/storage-zfs-snapshots.nix`: `services.sanoid = lib.mkIf (!host.isVm) { enable = true; interval = "*:0/15"; templates.safe = { hourly = 48; daily = 30; monthly = 6; autosnap = true; autoprune = true; }; templates.agents = { frequently = 8; useTemplate = ["safe"]; }; datasets."rpool/safe" = { useTemplate = ["safe"]; recursive = true; processChildrenOnly = true; }; datasets."rpool/safe/srv/agents" = { useTemplate = ["agents"]; }; }`. Comment block: why `local/*` is excluded, why recursive, why `frequently` only on agents.
1.2 `cells/workstation/nixosConfigurations.nix`: insert `p.storage-zfs-snapshots` after `p.storage-zfs-rollback` in `workstation`.
1.3 Rebuild elster. `systemctl status sanoid.timer` == active; wait one interval; `zfs list -t snapshot -r rpool/safe -H | grep -c autosnap_` ≥ 1 per dataset; `zfs list -t snapshot rpool/local/root -H | wc -l` == 1.
1.4 Restore drill (user): `ls /persist/.zfs/snapshot/` shows `autosnap_*`; `cp /persist/.zfs/snapshot/<newest>/home/<upn>/.hermes/state.db /tmp/state-drill.db && sqlite3 /tmp/state-drill.db "pragma integrity_check"` == `ok`.
Exit criteria: sanoid timer active; autosnaps on every `rpool/safe/*` dataset and none on `rpool/local/*`; drill 1.4 passed and dated in Progress; commit `feat(workstation): sanoid snapshots for rpool/safe`.

## Phase 2 — SQLite backup + git for skills/memories (Hermes cron) ⏳
2.1 `~/.hermes/scripts/state-backup.sh`: `mkdir -p ~/.hermes/backups && sqlite3 ~/.hermes/state.db ".backup ~/.hermes/backups/state-$(date +%F).db" && sqlite3 ~/.hermes/backups/state-$(date +%F).db "pragma integrity_check" && ls -1t ~/.hermes/backups/state-*.db | tail -n +15 | xargs -r rm`. Hermes cron `hermes-state-backup`, `0 3 * * *`, `no_agent`.
2.2 `/srv/agents/hermes`: `git init -b main`, `.gitignore` = nothing (skills + memories are both wanted). First commit `chore: hermes brain — initial import`. Remote per `Naming:` (user supplies URL; until then local-only).
2.3 `~/.hermes/scripts/brain-commit.sh`: `cd /srv/agents/hermes && git add -A && git diff --cached --quiet || git commit -qm "brain: $(date +%F)"` (+ `git push -q` once remote exists). Hermes cron `hermes-brain-commit`, `10 3 * * *`, `no_agent`.
2.4 Run both once by hand; `ls ~/.hermes/backups/` shows one file; `git -C /srv/agents/hermes log --oneline | head -3`.
Exit criteria: both cron jobs listed in `~/.hermes/cron/jobs.json`; one backup file with `integrity_check == ok`; `/srv/agents/hermes` has ≥ 2 commits (import + one daily); `Progress` records it. Not a the-hive commit (lives in `~/.hermes` and `/srv/agents`), so note the script paths here instead.

## Phase 3 — off-host replication ⏳
Options (choose in 0.4):
  A. **restic → osgiliath (sftp) or S3-compatible bucket.** Client-side encrypted, works against btrfs, dedups the 68M db daily. Source = the newest sanoid snapshot mounted via `.zfs/snapshot/` so the backup is a consistent point in time. `services.restic.backups.safe` in the new profile; paths `/persist/home/<upn>/.hermes` (exclude `lsp cache bin images pastes`), `/srv/agents`, `/srv/the-hive`, `/srv/workspace`; repo password + sftp key via agenix. Timer daily, `OnFailure` notify. **Recommended** — osgiliath has no ZFS.
  B. **`syncoid --sendoptions=raw`** to a ZFS host. Needs a ZFS pool somewhere (a file-backed pool on osgiliath's btrfs is possible but ugly). Only if a ZFS target appears.
3.1 Agenix secrets for the chosen option (`secrets/restic-safe.age` or ssh key), rekeyed for elster.
3.2 Profile block + timer; first run by hand; `restic snapshots` (or `zfs list` on the target) shows one entry.
3.3 Restore drill from the target: `restic restore latest --target /tmp/drill --include '**/state.db'` → `pragma integrity_check == ok`; and one skill file diffed against live == identical.
3.4 Offline behaviour: laptop off-network for a day → timer fails quietly, next run catches up; no error spam in `journalctl --user`/system.
Exit criteria: first replication done; drill 3.3 passed and dated; timer survives one offline day; commit `feat(workstation): restic replication of rpool/safe to osgiliath`.

## Phase 4 — other workstations ⏳
4.1 Profile is already in the `workstation` list, so penrose/sevastopol get sanoid on their next rebuild; only the restic secret must be rekeyed per host.
4.2 Per-host restore drill 1.4.
Exit criteria: `zfs list -t snapshot -H | grep -c autosnap_` ≥ 1 on each host; drill dated per host.

## Fallback at any phase
Phase 1 alone (local sanoid) + the manual `@manual-2026-09-25` snapshot already beats today's zero. If Phase 3 stalls on the target, run 2.1's backup file through `rclone` to any cloud bucket with `--crypt` — one script, no NixOS change.

## Progress
- 2026-09: plan written. Measured layout in `Source refs`. No snapshots, no replication, skills/memories not under git as of today.

Next: Phase 0.1 — `sudo zfs snapshot -r rpool/safe@manual-2026-09-25` on elster (seconds). Then 0.2 → 0.3 → 0.5 same session; 0.4 needs the user's replication choice.
Blocked on: replication target (0.4): restic → osgiliath sftp / S3 bucket / other; git remote URL for `/srv/agents/hermes` (2.2).
