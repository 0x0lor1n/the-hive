# port-jarvis-home (make penrose the daily driver; jarvis = Ubuntu 24.04 + home-manager standalone)

Source: ~/nixos-config/users/{shared,jarvis,modules} (home-manager standalone,
targets.genericLinux + nixGL, 1647 lines / ~45 files) + ~/workspace (146G, 9 git repos).
Target: penrose (cells/workstation, home-manager as NixOS module, home/ = 363 lines,
only desktop/ + default.nix so far).
Decision 2026-09-09: stop fixing intune-portal on jarvis (server-side 1001/InteractionRequired,
1.2607.4 is latest, clean re-enroll x3 failed). Ubuntu stays until penrose has home+workspace,
then jarvis gets reinstalled from cells/workstation (own host, not a port of penrose).

## where this runs
Phases 1-3 run ON PENROSE (hermes there). Setup on penrose:
  git clone https://github.com/0x0lor1n/the-hive.git ~/workspace/playground/nix-rensa   # this repo, main
  git clone -b nvim-wochap-resync https://github.com/crookedmirror/nixos-config.git ~/nixos-config  # SOURCE, read-only
  (branch nvim-wochap-resync = jarvis's live state as of 2026-09-09; main is 6 commits behind it)
Phase 4 (workspace rsync) is a PULL from penrose: `rsync jarvis:~/workspace/...` — only step
that needs a route between the two hosts; penrose has 1TB free, space is not a concern.
jarvis's role until phase 5: keep working, serve ~/workspace over ssh, nothing else.
Also port users/shared/tui/ (coding-agents/opencode etc.) — missed in the inventory table, goes to home/dev/.

## invariants
- home-manager stays a NixOS module in this repo (flake.nix:31 — mkHome broken upstream).
  Anything from nixos-config that only exists for standalone/genericLinux is DROPPED, not ported:
  `nonNixos.enable`, `targets.genericLinux`, nixGL wrapping, make-zsh-default-shell activation,
  `programs.home-manager.enable`.
- Secrets: nixos-config `repo.secretFiles`/`userSecrets` (users/modules/secrets.nix) ->
  this repo's agenix-rekey (cells/workstation/agenixRekey.nix, secrets/ generated|rekeyed/penrose).
  Never copy .age files across repos raw — re-encrypt to penrose host key + masterIdentities.
- Nothing in home/ may reference ~/nixos-config after phase 2 (grep gate, see verified).
- ~/workspace is data, not config: rsync, not git-clone (Clients/ and certs/ have untracked material).
- Ubuntu jarvis keeps working the whole time; no destructive step on jarvis before phase 5.

## inventory (nixos-config/users -> where it goes)
| source                          | target                                  | note |
| shared/cli/zsh (+p10k, fns)     | home/cli/zsh.nix + home/cli/zsh/        | keep config files verbatim, drop nonNixos guards |
| shared/cli/{fzf,skim,zoxide,bat,lazygit} | home/cli/*.nix                 | 1:1 |
| shared/gui/foot (+foot.ini)     | home/desktop/terminal.nix                | penrose has dwl/greetd; foot fits |
| shared/gui/kitty                | drop unless still used                   | ask |
| shared/gui/firefox              | home/desktop/firefox.nix                 | check policies vs. Entra SSO extension (linux_entra_sso.json already in /etc/chromium) |
| shared/gui/microsoft-edge       | already covered by auth-entra.nix?       | verify, else home/desktop/edge.nix |
| shared/gui/{telegram,simplex,mattermost,spicetify} | home/desktop/chat.nix, media.nix | spicetify needs input (flake.nix) |
| shared/gui/mpv (+vpy)           | home/desktop/mpv.nix                     | vapoursynth plugin: check pkgs build |
| shared/dev/lang-*.nix, android  | home/dev/*.nix                           | lang-ai: pxpipe/hermes/claude — merge with post-dellvis-tooling §2 |
| shared/security/{ssh,vpn,tor,osint} | home/security/*.nix                  | vpn-{owt,tiko,wrs} secrets -> agenix-rekey |
| jarvis/default.nix sessionVariables (OTEL, SNYK) | home/default.nix via userSecrets equiv | secrets |
| jarvis/secrets/ssh-keys.tar.age | secrets/generated/penrose/user-ssh-key.age pattern (see sevastopol) | |
| ../../secrets/git-hosts-{work,personal}.nix.age | secrets/ + home/dev/git.nix | git identities per host |
| modules/secrets.nix             | rewrite as small option in home/default.nix reading config.age.secrets | |

## next
### phase 1 — inputs + skeleton (jarvis, this repo, no penrose needed)
- [ ] flake.nix: add inputs used by users/shared (spicetify, nur if firefox needs it; chaotic — probably drop)
- [ ] home/{cli,dev,security}/default.nix stubs, imported from home/default.nix
- [ ] home/default.nix: userSecrets shim (option + config.age.secrets.<name>.path)
- [ ] `nix build .#nixosConfigurations.penrose.config.system.build.toplevel --no-link` green

### phase 2 — port modules (jarvis, file by file, table above)
- [ ] cli/* (zsh first — it is what everything else is used through)
- [ ] dev/* incl. git identities; merge lang-ai with post-dellvis-tooling (pxpipe unit, hermes, claude, rtk)
- [ ] desktop additions (foot, firefox, mpv, chat)
- [ ] security/* + rekey vpn/ssh secrets for penrose
- [ ] grep gate: `grep -rn 'nixos-config\|nonNixos\|genericLinux\|nixGL' cells/workstation/home` -> empty
- [ ] eval + build toplevel for penrose AND sevastopol/osgiliath (shared home must not break them)

### phase 3 — deploy to penrose
- [ ] penrose reachable from jarvis (ssh alias resolves; today: "Could not resolve hostname penrose" — LAN name / tailscale / yggdrasil? fix first)
- [ ] colmena apply / nixos-rebuild switch --flake .#penrose --target-host
- [ ] login as Entra user, verify zsh/p10k, foot, firefox+SSO, git identities, vpn profiles

### phase 4 — workspace to penrose
- [ ] free space check on penrose (need >150G; today unknown — df /home)
- [ ] order & method:
      1. git repos (9): `rsync -aHAXS --info=progress2 --exclude target --exclude node_modules --exclude .direnv --exclude result`
         (or clone + rsync untracked); nix-rensa itself first so penrose can rebuild itself
      2. Clients/ 26G (Engie 23G) — rsync, verify with `rsync -nc`
      3. certs/ 92G — decide: does penrose need all of it? candidate for external disk / NAS, not /home
      4. owt/ 6.2G, 0xOLOR1N/ 2.3G, playground/ rest
- [ ] devshell smoke test on penrose per repo (`nix develop` in nix-rensa, pxpipe, nixq)
- [ ] hermes/claude state: ~/.hermes, ~/.claude, ~/.claude.json — rsync after home-manager lands (post-dellvis-tooling §2 decides which parts become declarative)

### phase 5 — jarvis cutover
- [ ] jarvis daily work stops; penrose is primary for >= 3 working days without going back
- [ ] jarvis: new host in nixosConfigurations.nix (hardware facts: Latitude? see nix-rensa/latitude-5580-upgrade.md if that is jarvis; else collect lspci/disks first), disks/jarvis.nix, secrets/generated/jarvis
- [ ] install via same path as port-dellvis phase 4 (Secure Boot user keys, ZFS+TPM, himmelblau enroll)
- [ ] ~/nixos-config: archive (tag `pre-rensa`), stop using; post-dellvis-tooling §5 cleanup

## blocked_on
- penrose not resolvable from jarvis right now (phase 3/4 need a route) — check NetworkManager/LAN, or use IP
- (resolved) penrose has 1TB free
- decisions needed from user: kitty keep/drop; chaotic input keep/drop; certs/ 92G destination

## verified
- (none yet)

## notes
- users/jarvis/default.nix drops: nonNixos.enable, targets.genericLinux/nixGL, make-zsh-default-shell
  (NixOS sets users.users.<name>.shell), programs.home-manager.enable (module mode).
- home.stateVersion: nixos-config uses 24.11, this repo 25.11 — keep repo value; check hm release notes
  between for zsh/firefox option renames.
- The Intune dead end on jarvis is documented in the session of 2026-09-09; do not retry
  intune-portal on Ubuntu — the fix is this port.
