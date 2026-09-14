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
- names in this file are ANONYMISED: clients are client-a..e, work hosts are work-*,
  personal trees are personal-*. The repo is public and globals deliberately keeps the
  tenant domain in the encrypted half; the real mapping stays out of git.
- SHARED verbatim between both accounts, no per-account variation: zsh (+p10k, plugins, functions),
  neovim, tmux, and the rest of cli/. Checked 2026-09-14: nothing in cli/zsh, tui/tmux or
  tui/neovim references an account, a UPN or a workspace path, so these are plain shared imports —
  the account split applies ONLY to credentials (ssh keys, git identities, vpn) and to which
  project tree the shell starts in.
  AMENDED 2026-09-14: the CONTENT stays identical, but the DELIVERY may differ per account —
  live editing for nvim/tmux/zsh needs a readable checkout, which the Entra account may not
  have (see blocked_on). Identical content, possibly different mechanism.
- home/ is built TWICE (layer-compositor.nix:20-49): HM NixOS module for the local user, and
  standalone activationPackage for the Entra user. Decision 2026-09-14: the Entra account IS the
  daily driver, the local user only holds sudo/the checkout and rebuilds — so cli+dev go to BOTH,
  same modules, and the split is a short deny-list, not a profile system.
  Entra must NOT get: git commit identity (stays null, home/default.nix:16-19 — a stray commit
  must fail loudly rather than leak the work UPN) and personal security/* (vpn, osint, personal ssh).
- Anything from nixos-config that only exists for standalone/genericLinux is DROPPED, not ported:
  `nonNixos.enable`, `targets.genericLinux`, nixGL wrapping, make-zsh-default-shell activation.
  `programs.home-manager.enable` STAYS (home/default.nix:35) — the Entra branch is standalone.
- Secrets: nixos-config `userSecrets` is an EVAL-TIME attrset (repo.secrets.<name>, decrypted from
  .nix.age), not a runtime path — ssh.nix matchBlocks, vpn creds and OPENCODE_API_KEY all need it
  during eval. The equivalent channel here is rageImportEncrypted (nix/extra-builtins.nix,
  cells/common/globals.nix:20), same oddlama pattern. Runtime-only secrets stay agenix-rekey.
  Never copy .age files across repos raw — re-encrypt to penrose host key + masterIdentities.
- Nothing in home/ may reference ~/nixos-config after phase 2 (grep gate, see verified).
- ~/workspace is data, not config: rsync, not git-clone (Clients/ and certs/ have untracked material).
- Ubuntu jarvis keeps working the whole time; no destructive step on jarvis before phase 5.

## inventory (nixos-config/users -> where it goes)
Checked against the real tree 2026-09-14 (clone at ~/nixos-config, nvim-wochap-resync fdb88b3).
Rows marked [NEW] were missing from the first pass.
| source                          | target                                  | note |
| shared/default.nix              | home/default.nix + home/cli/            | [NEW] top-level shared: ~20 home.packages, shellAliases, .bashrc HISTFILE=/dev/null trick, fonts.fontconfig, gpg, systemd.user.startServices="suggest". DROP slack (repo has cell.packages.slack under nixpak) and the nixGL-wrapped wine/slack branches; reconcile ungoogled-chromium with the repo's chromium+linux_entra_sso |
| shared/cli/zsh (+p10k, fns)     | home/cli/zsh.nix + home/cli/zsh/        | keep config files verbatim, drop nonNixos guards. SEE the out-of-store symlink note below — 4 of its files are NOT store-backed today |
| shared/cli/{fzf,skim,zoxide,bat,lazygit} | home/cli/*.nix                 | 1:1 |
| shared/cli/{eza,dircolors,direnv} | home/cli/*.nix                        | [NEW] were not listed; dircolors is a catppuccin call site |
| shared/gui/foot (+foot.ini)     | home/desktop/terminal.nix                | penrose has dwl/greetd; foot fits. foot.ini is out-of-store; colors come from theme via lib._custom.unwrapHex |
| shared/gui/kitty                | DROPPED 2026-09-14                       | foot is the terminal |
| shared/gui/firefox              | a NEW workstation profile (not home/)     | REPLACED 2026-09-14 (user): librewolf decommissioned, nur dropped. Browser = STABLE firefox + Phoenix, wired as a NIXOS module (see the browser item in phase 1). The 8 nur addons and the librewolf pin both go away; the search engines (4get default, np/no/nl/gh/wru aliases) get re-declared as a SearchEngines policy, which works on stable since Fx139 |
| shared/gui/microsoft-edge       | already covered by auth-entra.nix?       | verify, else home/desktop/edge.nix |
| shared/gui/{simplex,mattermost,spicetify} | home/desktop/chat.nix, media.nix | telegram DROPPED: cell.packages.telegram-desktop (nixpak) already covers it; spicetify needs input |
| shared/gui/mpv (+vpy)           | home/desktop/mpv.nix                     | vapoursynth plugin: check pkgs build |
| shared/dev/lang-*.nix, android  | home/dev/*.nix                           | lang-ai is 5 lines (OPENCODE_API_KEY only) — merge with post-dellvis-tooling §2 |
| shared/tui/{tmux,neovim}        | home/dev/ (or home/cli/)                 | [NEW] both out-of-store; neovim ships 93 files under config/nvim plus a dead config/nvim.bak (drop the .bak) |
| shared/tui/coding-agents/claude | home/dev/claude.nix                      | keep llm-agents pkg + skills; drop the oh-my-claudecode marketplace wiring |
| shared/tui/coding-agents/{opencode,skills} | home/dev/*.nix                | [NEW] opencode ships 3 json + omo.jsonc, skills ship 3 SKILL.md — all out-of-store |
| shared/security/{ssh,vpn,tor,osint} | home/security/*.nix                  | vpn-{work-a,work-b,work-c} secrets -> agenix-rekey |
| jarvis/default.nix sessionVariables (OTEL, SNYK) | home/default.nix via userSecrets equiv | secrets |
| jarvis/secrets/ssh-keys.tar.age | NEW mechanism, see phase 1 "ssh identities" — NOT the user-ssh-key pattern | 8 outbound client keys |
| ~/.ssh/ssh-identities/* (on disk) | same                                   | the live copies; tarball is the only backup |
| ../../secrets/git-hosts-{work,personal}.nix.age | secrets/ + home/dev/git.nix | see phase 1 "git identities": drives BOTH programs.git.includes and ssh matchBlocks from one attrset |
| modules/secrets.nix             | eval-time attrset via rageImportEncrypted (see invariants), not age.secrets.path | |
| users/crookedmirror/default.nix | nothing to port                          | [NEW] 28 lines, a second account that already imports ../shared on dellvis with NO secrets at all (no repo.secretFiles, no userSecretsName). Useful as PRECEDENT — the shared home was always meant to build twice — but see notes: it probably does not evaluate today |
| lib/default.nix (lib._custom)   | DROPPED if the symlink decision goes to "store" | [NEW] 4 helpers, 9 call sites. relativeSymlink/mkOutOfStoreSymlink/runtimePath exist only for out-of-store symlinks; unwrapHex (1 use, foot colors) is 20 characters and gets inlined |
| modules/symlinks.nix            | DROPPED                                  | [NEW] home.symlinks option, zero call sites in users/ |

## next
### phase 1 — inputs + skeleton (runs on penrose, this repo, no deploy)
Run from the devshell (direnv): globals.nix:16 asserts builtins.extraBuiltins, eval fails without it.

ORDER OF WORK (each step ends with a check; do not start the next before it passes):

  0. PROBES — 30 minutes, before writing any module. All three can invalidate a design below.
     a) can the Entra (NSS) user read a system age.secret? add one throwaway secret with
        owner = the Entra cn, rebuild, `sudo -u <cn> cat /run/agenix/<x>`.
        FAIL -> ssh keys for the entra set need the tmpfiles fallback (auth-entra.nix:324).
     b) `nix show-config | grep substituters` as the Entra user -> nyx-cache present?
        FAIL -> devshells rebuild the kernel from source on the daily-driver account.
     c) `git --version` >= 2.36 (hasconfig: matcher) and `getent passwd <cn>` shows zsh.
     Record results under ## verified, they decide 3 and 5.
  1. DECISIONS still open (blocked_on): out-of-store symlinks (NEW — blocks every cli/tui
     module, decide first), nur/librewolf, client-e key/identity mismatch, client-a project
     vs key, id_rsa ownership, vpn mechanism for a wheel-less account, project tree paths.
     Blocking phase 1: the vpn one and the symlink one. The rest block phase 2.
  2. flake.nix inputs — add/drop per the detail below. Check: `nix flake metadata` clean,
     `nix flake check` no worse than before.
  3. secrets channel — secrets/user-<name>.nix.age via rageImportEncrypted, own identity list.
     Check: a trivial attr reads back at eval (`nix eval` on a test binding), no TPM prompt
     beyond the first.
  4. ssh keys as static age.secrets — one entry per key, no generator, rekey to penrose.
     Check: `agenix rekey` succeeds and `secrets/rekeyed/penrose/` gains the files; pubkey of
     each decrypted key still matches the .pub committed next to it (ssh-keygen -y).
  5. mkHome signature — per-account secret set (layer-compositor.nix:20), both call sites updated.
     Check: eval only, nothing else changed yet.
  6. skeleton — home/{cli,dev,security}/default.nix empty stubs wired into home/default.nix
     per the split. Check: build stays green with empty modules.
  7. impermanence carve-outs for both homes (auth-entra.nix + layer-users-local.nix).
     Check: `nixos-rebuild build` and grep the resulting config for each new path.
  8. GATE: `nix build .#nixosConfigurations.penrose.config.system.build.toplevel --no-link`
     green, and the same for sevastopol (shared home must not break the VM).

DETAIL (rationale and facts for the steps above):
- [x] flake.nix inputs — DONE 2026-09-14 (cells/workstation/flake.nix + flake.lock, commit below):
      ADDED phoenix (tag 2026.09.01.1 = rev 164d383; `dev` is the default branch and moves daily,
      nix/ identical between tag and dev HEAD) and spicetify (Gerg-L/spicetify-nix HEAD 09eed5c;
      its own nixpkgs is a channel tarball, so it follows ours). Both `inputs.nixpkgs.follows`,
      lock confirms `follows 'nixpkgs'` — the lanzaboote "same rev" concern does not apply to
      inputs that follow.
      NOT added, per user decision 2026-09-14: zsh-vi-mode / zsh-defer come from the nixpkgs pin
      (0.12.0 / 57a6650; jarvis had 9 / 1 commits newer — two small fixes + OSC52, nothing
      critical). llm-agents is NOT a workstation input: cells/repo/flake.nix already pins it
      (304ada96) and cells/repo/packages.nix re-exports hermes-agent — claude-code 2.1.239,
      opencode 1.18.21, oh-my-opencode 5.0.0-beta.7 exist at that rev; add re-exports there in
      phase 2, do not declare it twice.
      phoenix overlay applied in nixosConfigurations.nix (`pkgs = (... chaotic).extend
      phoenix.overlays.default`): pkgs.phoenix, pkgs.withPhoenix present, penrose toplevel drv
      unchanged (k6pgf1qq) — purely additive. The withPhoenix wrapping itself is phase 2.
      Checks: `nix flake metadata` clean; `nix flake check --no-build` fails identically before
      and after (hisilome-src not valid — unrelated host); penrose + sevastopol toplevel eval OK.
      Original plan for reference:
      add llm-agents (claude-code, opencode), zsh-defer, zsh-vi-mode; spicetify if media.nix is kept.
      DROP: chaotic (unused in users/ — checked), nixgl (invariant),
      oh-my-claudecode (user is on hermes + opencode; claude/default.nix keeps only the
      llm-agents package + skills, omcRoot/extraKnownMarketplaces/enabledPlugins go away),
      ayugram-desktop (repo already has cell.packages.telegram-desktop under nixpak).
      DROP per user decision 2026-09-14: nur (the 8 firefox addons go with librewolf) and
      nixpkgs-librewolf-pin (librewolf decommissioned). ADD: phoenix.
      NOTE where they go: this repo has no root-level user inputs — every workstation input is
      declared in cells/workstation/flake.nix (a cell flake with its own lock), which is where
      phoenix/llm-agents/zsh-* belong. Cell flakes cannot `follows` a root input, so pin
      phoenix.inputs.nixpkgs to the SAME rev as the cell's nixpkgs (34ab9907), exactly as the
      existing comment for lanzaboote demands.
- [ ] browser: stock firefox + Phoenix as a NIXOS module (decision 2026-09-14). Verified by
      reading celenity/Phoenix nix/module.nix — it is NixOS-only by construction, so the user's
      recollection is right and there is nothing to work around:
      it sets environment.etc."firefox/*", environment.variables, programs.firefox.policies
      (read from the flake's policies.json) and nixpkgs.overlays. home-manager has none of
      those four options.
      PITFALL specific to this repo: the module's `nixpkgs.overlays` is SILENTLY IGNORED here.
      nixosConfigurations.nix:13-18 passes a ready `pkgs` to utilsLib.mkSystem (nixpkgs.pkgs is
      set), and the file already documents that nixpkgs.overlays inside a module does nothing —
      which is why the chaotic overlay is applied with `inputs.pkgs.extend` instead. So Phoenix's
      withPhoenix wrapper will NOT be applied by importing the module alone: extend the pkgs at
      nixosConfigurations.nix:18 with phoenix's overlay the same way, then import the module for
      the /etc + policies half. Verify with `nix eval` that pkgs.firefox is the wrapped one.
      Placement: firefox is a browser for the ENTRA account (daily driver) and Phoenix is system
      scope, so this is a workstation profile next to layer-compositor (where microsoft-edge
      already lives as a systemPackage for exactly this reason), not a home/ module.
      Cost to accept: policies.json replaces programs.librewolf's declarative extensions and
      search engines. ExtensionSettings is a normal (non-ESR) policy, so addons can be declared
      there by AMO URL without nur.
      CORRECTION 2026-09-14 (the agent's earlier "SearchEngines is ESR-only" was OUT OF DATE):
      per Mozilla's own policy reference, SearchEngines is "available in all Firefox release
      channels" as of Firefox 139. The nixpkgs pin ships firefox 154.0.1, so the 4get default
      and the np/no/nl/gh/wru aliases CAN be declared whatever channel is chosen.
      CHANNEL DECIDED 2026-09-14 (user): stable `firefox`. ESR dropped (it was only ever wanted
      to preserve search settings, which turned out not to need it).
      Channel facts measured on this pin, for whoever revisits it:
        firefox 154.0.1 | firefox-esr 153.1.0esr | firefox-beta/devedition 155.0b5
        | firefox_nightly 156.0a1-20260825
      Phoenix's withPhoenix is a plain `.override { extraPoliciesFiles; extraPrefsFiles; }` and
      evaluates cleanly on firefox, firefox-esr AND firefox_nightly (tryEval-checked), so the
      channel choice is free as far as Phoenix is concerned.
      NIGHTLY, user asked about it (chaotic ships `firefox_nightly`, attr confirmed present at
      chaotic's pkgs/firefox-nightly/default.nix) — NOT recommended as the default browser here,
      for two reasons found while checking:
        1. STALENESS: the nightly in our closure is 156.0a1-20260825, i.e. ~3 weeks old as of
           2026-09-14, because the chaotic input is PINNED (flake.nix:43-45 pins the nyx rev so
           that its nixpkgs lock == ours, specifically to keep the CachyOS kernel a cache hit).
           A pinned nightly is the worst of both worlds: pre-release instability without the
           fresh fixes. Following nightly properly would mean bumping chaotic constantly, which
           the kernel pin explicitly forbids.
        2. It is a browser for the Entra WORK account with tenant SSO and enterprise policies;
           pre-release regressions there cost working days.
      Binary cache verified 2026-09-14 (narinfo probe, both wrapped and unwrapped):
        firefox-unwrapped 154.0.1 -> cache.nixos.org 200, nyx 404
        firefox-nightly-unwrapped -> nyx 200, cache.nixos.org 404
      So both are substitutable today (nightly only via nyx-cache, which layer-kernel.nix:32
      already configures system-wide). Note the wrapper output hash CHANGES when Phoenix's
      extraPoliciesFiles/extraPrefsFiles are applied — but only the cheap wrapper derivation is
      rebuilt locally; the expensive *-unwrapped stays a cache hit. No multi-hour browser build.
      Sanity check done: nixpkgs firefox is 154.0.1 on this pin, and librewolf currently carries
      NO knownVulnerabilities — i.e. the insecure-marking that forced nixpkgs-librewolf-pin has
      since been resolved upstream. Decommissioning it is a choice now, not a workaround.
- [ ] strip catppuccin while porting: users/shared/default.nix imports catppuccin.homeModules.catppuccin
      and modules read globals.theme.colors.flavour. Repo is kanagawa via theme.colors (_module.args.theme,
      home/default.nix:29) — rewrite those call sites, do NOT add the input. Also covers
      cli/dircolors.nix (catppuccin-dircolors input drops with it).
      Call sites enumerated 2026-09-14 (7, all small): shared/default.nix (catppuccin.enable +
      flavor + accent, catppuccin.nvim.enable=false, catppuccin.btop.enable), cli/zsh
      (catppuccin.zsh-syntax-highlighting), cli/git.nix (catppuccin.delta.enable and
      `features = "catppuccin-${flavour} side-by-side"` in programs.delta), cli/dircolors,
      gui/spicetify (colorScheme CatppuccinMocha/Latte via globals.theme.preferDark).
      Only 3 of the 12 globals refs are theme ones — the rest are configDirectory.
- [ ] mkHome takes a per-account secret set, not a bool (layer-compositor.nix:20): cli+dev are
      unconditional for both accounts, while ssh keys / git includeIf blocks / vpn are selected
      per account (see the items below). Personal-only: osint, tor.
      VPN SPLIT SETTLED 2026-09-14 (user). Three profiles, 1:1 with the three source secret
      files, no collecting from jarvis needed:
        entra (employer work): work-a (wireguard, secret vpn-owt) + work-b (openvpn, vpn-t)
        local (FREELANCE, not employer): work-c (openvpn, vpn-w)
      The user's "client-w"/"client-w" were the same network as work-c, remembered under other names.
      Note the local account's profile is freelance work, which is why it sits with the personal
      identity rather than with the tenant.
      MECHANISM CONFIRMED by the user: the two Entra profiles go through NetworkManager, with
      "networkmanager" added to himmelblau's local_groups (auth-entra.nix:119-123) — NOT wheel.
      NM is already enabled (laptop.nix:15) and its system-connections are already persisted
      (laptop.nix:33); group membership covers NM's polkit actions with no password prompt.
      Declare with networking.networkmanager.ensureProfiles, secrets via environmentFiles ->
      agenix runtime secrets. The local account needs nothing new (it already has wheel +
      networkmanager), so its `sudo openvpn` alias ports unchanged.
      SECURITY BUG TO FIX WHILE PORTING, do not copy as-is: security/vpn.nix writes credentials
      into xdg.configFile as plain `text = ...` — wireguard PrivateKey, and the openvpn
      auth-user-pass files with username+password. home-manager renders those through the NIX
      STORE, i.e. world-readable on the machine. These must become runtime age.secrets (or NM
      environmentFiles), never store-rendered text.
      SETTLED: host-global VPN routing is ACCEPTABLE — a tunnel raised by one account carries
      the other account's traffic too. No namespacing needed.
- [ ] impermanence carve-outs for the Entra home — THE load-bearing part of "Entra is the daily
      driver". auth-entra.nix:189-223 is an explicit allowlist of absolute paths (NSS account, so
      no persistence.users.<name>); anything cli/dev writes and is not listed is gone next reboot.
      New entries needed, entraHome-style: .ssh (0700 — known_hosts, agent sockets; the identity
      keys themselves come from age.secrets, see below), .local/share/direnv, .local/share/zsh
      (histfile — mirror the bash HISTFILE trick at auth-entra.nix:227), .config/opencode +
      whatever opencode/hermes keep outside .hermes, .cache/nix. Local user already has its own
      list (layer-users-local.nix:44-68) — keep the two in sync.
- [ ] git identities — one encrypted attrset feeds TWO consumers, port them together or neither
      works. Each entry in git-hosts-{work,personal}.nix.age carries `.git.includes`,
      `.git.defaultUser` and `.ssh.matchBlocks`; cli/git.nix and security/ssh.nix each collect
      every `repo.secrets` attr prefixed "git-identities" and merge them (foldl'), so adding a
      file is the whole registration mechanism.
      Matching is `includeIf "hasconfig:remote.*.url:<glob>"` — per-REMOTE-URL, not per-directory,
      so a repo gets the right author wherever it is checked out. Live globs on jarvis:
      git@github.com:*/*, git@*.work-gitlab.tld:*/*, git@git.client-e.tld:*/*, git@work-azure:v3/*/*/*,
      git@work-gh:*/* (last two share one identity file). Needs git >= 2.36.
      The ssh Host aliases in those globs (work-azure, work-gh) are the same aliases matchBlocks
      defines and IdentityFile points at — so glob, alias and key must stay in lockstep.
      In this repo the local user already has a public identity in globals (globals.user.git,
      cells/common/globals.nix:31) wired to programs.git in home/default.nix:46: keep it as the
      default `user`, and layer the includeIf blocks on top; secretDefaultUser then has no job.
      Split includeIf blocks per account, following the ssh key split below — an account should
      not carry a block whose remote it cannot authenticate to:
        entra: git@*.work-gitlab.tld (work identity A), git@work-azure + git@work-gh (work identity B)
        local: github.com remotes (personal identity)
      MISMATCH to resolve first: git.client-e.tld commits under a WORK identity (same as
      work-azure/work-gh) but its key was assigned to the local account. Either the key moves to
      entra or the commit identity becomes the personal one — pick before writing the module.
      Entra keeps no default `user` (nothing in globals for it); a repo outside every glob must
      fail rather than silently commit under a work UPN.
- [ ] ssh identities — NEW mechanism, nothing in either repo does this today.
      Keys were placed BY HAND on jarvis (ssh-keys.tar.age is referenced by zero .nix files —
      a backup tarball, not a deployment) because agenix-rekey did not work with standalone
      home-manager. They must be transplanted VERBATIM: the pubkeys are registered on
      GitHub/Azure/client servers, so an agenix *generator* (mints a new random key,
      secrets.nix:91) is exactly the wrong tool.
      Split per account (decision 2026-09-14) — keys are NOT shared, each account gets only its own:
      | key          | ssh alias(es)                                        | account |
      | work-azure   | work-azure                                           | entra   |
      | work-github  | work-gh                                              | entra   |
      | work-gitlab  | gitlab.work-gitlab.tld                               | entra   |
      | work-prod    | work-prod                                            | entra   |
      | github       | github.com                                           | local   |
      | client-e-key | git.client-e.tld                                     | local   |
      | client-a     | client-a-db1, client-a-db2, client-a-h1, client-a-h2 | local   |
      matchBlocks split the same way: an account must not carry Host entries whose IdentityFile
      it cannot read. So security/ssh.nix takes the account's key set as an argument rather than
      being gated by a plain withSecrets bool.
      Deployment: one static age.secrets entry per key (no generator, rekeyed to the penrose host
      key), mode 0600; IdentityFile points at age.secrets.<k>.path.
      STILL OPEN for the entra set: system age.secrets land in /run/agenix owned by a users.users
      account, and the Entra user is NSS-only (age.secrets.<k>.owner takes a name, not a uid).
      Verify early; fallback is a tmpfiles rule like auth-entra.nix:324.
      Do NOT confuse with this repo's existing `user-ssh-key`: that is an INBOUND key
      (authorizedKeys.pub, layer-users-local.nix:35), unrelated to these.
      ~/.ssh/penrose (deploy key) belongs to the local account; ~/.ssh/id_rsa unassigned — see notes.
- [x] secrets channel — DONE 2026-09-14 (commit b483d2f). cells/workstation/home/secrets.nix:
      `{flakeRoot, role}` -> attrset from secrets/user-<role>.nix.age, role in {local, entra},
      identities = [dellvis-nix-rage.pub] only (PIN) + recovery key as extra recipient. The nopin
      identity is deliberately NOT a recipient. Missing file -> {}. Named by ROLE, not account:
      both usernames are in the encrypted half of globals. Files are `{ _probe = "<role>"; }`
      placeholders; real content lands with git identities (step 4/phase 2).
      NOT WIRED yet: mkHome (layer-compositor.nix) does not call it — the signature (`secrets`
      arg next to `git`) is decided by its first consumer.
      unlock-secrets now primes globals + every user-*.nix.age in one PIN session, skips cached.
      Verified: agent eval (no tty) fails with the unlock-secrets hint, not a rage trace; after one
      interactive eval the cache entry exists and `nix develop -c nix eval` returns {"_probe":"entra"}
      with no TPM contact. NOTE: bare `rage -d` does not populate the cache — only eval or
      unlock-secrets do; a manual rage -d costs a PIN for nothing.
      Still open from the original item: decide what stops
      being eval-time: OPENCODE_API_KEY/SNYK_TOKEN via sessionVariables land in /nix/store in
      cleartext (acknowledged in nixos-config opencode README) — candidates for runtime age.secrets.
- [ ] home/{cli,dev,security}/default.nix stubs; cli+dev unconditional, security takes the
      account's key/vpn set
- [ ] consequences of "Entra is the daily driver, local rebuilds" that the split creates:
      - nix builds: trusted-users is root + @wheel (common/profiles/base.nix:11), Entra is not in
        wheel. `nix develop`/direnv still work, but anything needing a trusted user (adding a
        substituter, nix-copy from a remote store) fails from the daily-driver account. Confirm
        the nyx-cache substituter (layer-kernel.nix:32) is system-level so devshells still hit it.
      - agent tooling is SHARED, not per-account (decision 2026-09-14). Precedent already in the
        repo: pxpipe is one system service, not a user unit, for exactly this reason
        (agent-proxy.nix:1-5 — "two logged-in users would fight over it").
        - claude-code + opencode (with oh-my-openagent): SHARED PACKAGES in cli/dev, not
          containers. Considered and rejected 2026-09-14: they are interactive TTY tools that
          edit files in place, so a container would need both project trees bind-mounted (which
          re-joins the work/personal split inside one namespace) plus a way in — and
          `machinectl shell/login` is polkit auth_admin (verified: allow_any=auth_admin,
          allow_active=auth_admin_keep), which the Entra account cannot satisfy without wheel.
          Per-home state stays per-account (CLAUDE_CONFIG_DIR is $HOME/.claude,
          layer-session.nix:142) — credentials and history stay split, the binaries are shared.
        - hermes: nixos-container, one instance for both accounts. Fits because it is a
          long-running service reached over a socket, not a per-tty tool. Nothing
          container-related exists in the repo yet (grep: zero hits) — new work, size it first.
          Open points: unix socket in a group-owned dir (no auth story needed, and it sidesteps
          the polkit problem above); repo checkout bind-mounted for .hermes/skills; container
          state persisted (/var/lib/nixos-containers is NOT in impermanence today); API key
          reaching the container without landing in either home.
        - shared session history across work/personal is ACCEPTED (2026-09-14), not a concern.
      - ssh-agent: nothing in the repo enables one. With keys split per account there is no
        sharing to worry about, but each account needs its own agent (HM programs.ssh has
        addKeysToAgent; or systemd user unit) or every git push prompts.
      - the local account has no desktop autologin path: it is reached via tuigreet or a VT.
        Verify a rebuild is comfortable from there before phase 5 makes penrose primary.
- [ ] `nix build .#nixosConfigurations.penrose.config.system.build.toplevel --no-link` green
      (covers both branches: the Entra activationPackage is pulled in via layer-compositor.nix:150)

### phase 2 — port modules (on penrose, file by file, table above)
- [ ] cli/* (zsh first — it is what everything else is used through). NOTE from probe 0c:
      zsh has a SYSTEM half in this repo — `programs.zsh.enable` (absent today), then
      auth-entra.nix:135 `shell` repointed at it for the Entra account and
      users.users.<local>.shell for the local one. HM's programs.zsh alone leaves both on bash.
- [ ] dev/* incl. git identities; merge lang-ai with post-dellvis-tooling (pxpipe unit, hermes, claude, rtk)
- [ ] desktop additions (foot, firefox, mpv, chat)
- [ ] security/* + rekey vpn/ssh secrets for penrose (per-account key sets, phase 1 table)
- [ ] grep gate: `grep -rn 'nixos-config\|nonNixos\|genericLinux\|nixGL' cells/workstation/home` -> empty
- [ ] eval + build toplevel for penrose AND sevastopol/osgiliath (shared home must not break them)

### phase 3 — deploy to penrose
- [ ] penrose reachable from jarvis (ssh alias resolves; today: "Could not resolve hostname penrose" — LAN name / tailscale / yggdrasil? fix first)
- [ ] colmena apply / nixos-rebuild switch --flake .#penrose --target-host
- [ ] login as Entra user, verify zsh/p10k, foot, firefox+SSO, git identities, vpn profiles

### phase 4 — workspace to penrose (split work / personal)
- [x] free space check on penrose — 1TB free, not a constraint
- [ ] the split is by ACCOUNT HOME, not by subdirectory: an Entra-only tree under the local
      user's home would be readable by the wrong account and vice versa. Measured on jarvis:
        work     -> Clients/ 26G (client-b 23G, client-c 1.5G, client-d 1.1G), work-org/ 6.2G
                    (3 of 5 repos point at work-azure), playground/client-a 7.1G
        personal -> 0xOLOR1N/ 2.3G, playground/nix-rensa 8.3G, playground/personal-b 5.7G,
                    certs/ ~2.5G (htb-cjca, after excluding .venv)
      Cross-check each repo's remote against the ssh key table in phase 1 before moving it —
      remote host decides the account, not the current directory.
- [ ] nix-rensa is the exception: it lives in the LOCAL user's home (already persisted as
      "the-hive" in layer-users-local.nix:52) because that account is the one that rebuilds.
- [ ] order & method:
      1. git repos first, personal set: `rsync -aHAXS --info=progress2 --exclude target
         --exclude node_modules --exclude .direnv --exclude .venv --exclude result`
         (or clone + rsync untracked); nix-rensa before everything so penrose can rebuild itself
      2. work set into the Entra home, same excludes; Clients/ verify with `rsync -nc`
      3. certs/ ~2.5G real (see notes: 85 of 92G are 17 disposable .venv) — plain rsync with
         --exclude .venv, no external disk needed
- [ ] impermanence: both project trees must be carved out — the Entra one in auth-entra.nix
      (absolute paths, NSS account), the local one in layer-users-local.nix. Neither is
      covered today beyond "the-hive".
- [ ] devshell smoke test on penrose per repo (`nix develop` in nix-rensa, pxpipe, nixq)
- [ ] hermes/claude state: ~/.hermes, ~/.claude, ~/.claude.json — rsync after home-manager lands (post-dellvis-tooling §2 decides which parts become declarative)

### phase 5 — jarvis cutover
- [ ] jarvis daily work stops; penrose is primary for >= 3 working days without going back
- [ ] jarvis: new host in nixosConfigurations.nix (hardware facts: Latitude? see nix-rensa/latitude-5580-upgrade.md if that is jarvis; else collect lspci/disks first), disks/jarvis.nix, secrets/generated/jarvis
- [ ] install via same path as port-dellvis phase 4 (Secure Boot user keys, ZFS+TPM, himmelblau enroll)
- [ ] ~/nixos-config: archive (tag `pre-rensa`), stop using; post-dellvis-tooling §5 cleanup

## blocked_on
- CHECKOUT LAYOUT DECIDED 2026-09-14 (user): ONE tree. /srv/the-hive is the single source of
  config — no second dotfiles repo. The Entra account may write the dev-tool configs; it must
  still not be able to write what root builds.
  DESIGN THAT SATISFIES BOTH (measured, see below): one repo, per-directory ACLs.
    /srv/the-hive            crookedmirror:<sharedgrp> 0750  — group reads, only owner writes
    /srv/the-hive/cells      same — the rebuild source stays owner-write-only
    /srv/the-hive/dotfiles/  group-writable via a DEFAULT POSIX ACL — nvim/tmux/zsh live here
  home-manager then points at it with a plain
    config.lib.file.mkOutOfStoreSymlink "/srv/the-hive/dotfiles/nvim"
  for both accounts. Identical content, identical mechanism, one repo, and the flake never
  reads those files at eval (see the runtime-path note below), so nothing in dotfiles/ can
  influence a build.
  WHY ACLs AND NOT THE OBVIOUS THINGS — all three were tried on this host 2026-09-14:
    * `git config core.sharedRepository group`: does NOT affect worktree files. Measured: files
      still land 0644 after checkout. It only fixes .git/ internals. Useless here.
    * setgid bit (chmod 2770) on the dir: fixes the GROUP of new files, not the MODE. Measured:
      0644 under the default umask, so group still cannot write.
    * umask 002: works, but is a per-shell/per-session property. A `git checkout` run from a
      shell with umask 022 silently re-creates files 0644 and quietly breaks group write.
      Measured both ways. Too fragile to rely on.
    * DEFAULT POSIX ACL on the directory: WORKS and is umask-proof. Measured — with
      `setfacl -d -m g::rwx dotfiles`, a checkout under umask 022 still produced rw-rw----,
      and the default ACL is inherited by subdirectories created later (nvim/lua/... came out
      group-writable without further action). rpool already has acltype=posix and setfacl is
      in the system closure, so nothing new is needed.
  PITFALL, must be handled declaratively: ACLs are NOT stored in git and are LOST on a fresh
  clone. Measured: cloning the repo produced a plain 0755 dotfiles/ with no ACL. So the rule
  must be re-applied by the system, not by hand. systemd.tmpfiles with an `A+` line does
  exactly this and was verified to work on this host:
    A+ /srv/the-hive/dotfiles - - - - d:group:<grp>:rwx,group:<grp>:rwx
  After that line, a file created under umask 022 came out rw-rw-r--+ as intended. Put it next
  to the other tmpfiles rules (auth-entra.nix:321 is the precedent) so it survives re-clones
  and reboots.
  Group: the Entra account is NSS-only, so the shared group must be one himmelblau grants via
  local_groups (auth-entra.nix:119-123) — same mechanism as the networkmanager grant.
  KEY FACT that makes this safe (verified in nixos-config lib/default.nix): the symlink target
  is a RUNTIME PATH STRING, never an eval-time input. mkOutOfStoreSymlink only does
  `toString path` + `ln -s`; it never reads the file. So dotfiles/ being writable cannot affect
  the system closure, and the whole runtimePath/relativeSymlink assertion machinery from
  nixos-config collapses into a one-line mkOutOfStoreSymlink. Less code than the source.
  * scope reminder: only nvim/tmux/zsh get the symlink treatment. foot.ini, opencode's 3 json
    and the 3 SKILL.md stay store-backed.
- /srv on this host is on rpool/local/root, which is ROLLED BACK to @blank every boot
  (storage-zfs-rollback). Verified: /srv exists at 0755 but is not persisted and not a dataset.
  So whatever lands in /srv needs one of:
    (a) impermanence entries under environment.persistence."/persist" (bind mounts), or
    (b) its OWN ZFS DATASET mounted there — no rollback applies, nothing to declare.
  Recommend (b) for the project trees (tens of GB: bind-mounting 40G+ of source through
  impermanence is pointless indirection) and either for the small repos. Datasets go in
  cells/workstation/disks/penrose.nix next to local/nix and safe/persist.
  NOTE for the disk file: new datasets on an ALREADY INSTALLED host are not created by disko —
  add them to the .nix for reproducibility AND create them by hand once with `zfs create`.
- NEW 2026-09-14: ~/nixos-config cannot be cloned by the agent (user did it manually, resolved).
  Knock-on still open for phase 1 step 4: `ssh-keygen -y` on a passphrase-protected key
  prompts, and this shell has no askpass/agent (crookedmirror has no logind session, see
  MEMORY), so regenerating the 3-4 missing .pub files is a user-run step.
- penrose not resolvable from jarvis right now (phase 3/4 need a route) — check NetworkManager/LAN, or use IP
- (resolved) penrose has 1TB free
- open: git.client-e.tld — work commit identity but local-account ssh key (see phase 1 git item)
- SETTLED 2026-09-14: project trees move to /srv too (user), not into either home:
    /srv/work     — employer + client work, Entra-owned
    /srv/projects — personal + freelance, crookedmirror-owned
  This REPLACES the earlier "~/work and ~/projects inside the respective home" proposal and is
  strictly better for phase 4: the account split becomes directory ownership on a shared parent
  instead of two homes, and neither tree is subject to a home rollback. Same /srv persistence
  question as above — give each its own ZFS dataset.
  Consequence for the ssh/git split: the tree an account cannot read is the tree it cannot
  commit from, so ownership must match the key table (phase 1 ssh identities).
- open: git.client-e.tld — user does not recognise the client, so this cannot be answered from
  memory. RESOLVE BY MEASUREMENT during phase 2, not by asking again: on jarvis, find which
  worktrees have a git.client-e.tld remote (`grep -rl client-e ~/workspace/*/.git/config`),
  read the last commit's author and date, and check whether the key still authenticates.
  A tree with no commits in a year is dead weight — archive it and drop both key and identity.
  Default if it is still live: it goes to /srv/work with the work identity, and client-e-key
  moves to the entra key set (the commit identity is the stronger signal of who owns the work).
- SETTLED 2026-09-14: the two remote-less repos (work-org/poc, 0xOLOR1N/gopro-video-cutter) go
  to /srv/projects for now. Revisit only if one turns out to be employer property.
- ~/.ssh/id_rsa: user believes it is the same key as `github` and only a git-clone default.
  VERIFY before deleting, do not take it on faith — an RSA key and an ed25519 key cannot be the
  same key, so at best the two are both registered on the same GitHub account. Check with
  `ssh-keygen -y -f ~/.ssh/id_rsa` vs the github pubkey, and a `ssh -i ~/.ssh/id_rsa -T` probe
  against the github host alias. If it authenticates nowhere, drop it (do NOT port it); if it
  does, it needs an owner in the key table. Cheap to test, expensive to guess wrong.
- open: vpn — SETTLED, nothing left (3 profiles, NM + networkmanager group for entra, confirmed).
- open: playground/client-a is a client project but the client-a ssh key was assigned to local
- open: hermes-in-a-container — does it get the ssh keys / git identities of BOTH accounts, or
  none (agent proposes, the user commits from their own session)? Decides how much of the
  credential split survives. Also: which project trees are bind-mounted into it.
  (shared session history itself is settled: acceptable)
- otherwise only phase-3 reachability is blocking
- settled 2026-09-14: chaotic dropped (unused), oh-my-claudecode dropped (hermes + opencode),
  ayugram-desktop dropped (nixpak telegram-desktop), stateVersion is 24.11 on both sides,
  nur dropped and librewolf DECOMMISSIONED — browser is STABLE firefox + Phoenix as a NixOS
  module (ESR and chaotic's firefox_nightly both considered and rejected 2026-09-14; see the
  browser item in phase 1 for the measured reasons),
  vpn: 3 profiles (entra work-a+work-b employer, local work-c freelance), NM + networkmanager
  group for the entra pair, host-global routing accepted,
  /srv is the shared parent: /srv/the-hive (ONE repo, cells/ owner-write-only, dotfiles/
  group-writable via default POSIX ACL + a tmpfiles A+ rule), /srv/work (entra),
  /srv/projects (local) — each needs its own ZFS dataset, /srv itself is rolled back,
  live editing (out-of-store symlinks) KEPT for nvim/tmux/zsh and dropped for everything else,
  Entra = daily driver / local = sudo+rebuild only (both get the same cli+dev tooling),
  Entra already has a shell login, kitty dropped, catppuccin dropped (kanagawa only),
  certs/ stays on /home (~2.5G after excluding .venv), ssh keys split per account,
  work/personal projects live in separate trees, shell+nvim+tmux identical for both accounts,
  agents shared: claude-code/opencode as packages (container rejected: polkit auth_admin on
  machinectl shell + both trees would need mounting), hermes as a nixos-container,
  shared agent session history across work/personal accepted

## verified
phase 1 step 0 PROBES, run on penrose 2026-09-14:
- 0c git: `git --version` -> 2.55.0, >= 2.36 -> hasconfig: matcher available. PASS
- 0c shell: `getent passwd <entra-upn>` -> /run/current-system/sw/bin/bash, NOT zsh.
  FAIL, and worse than a per-user setting: the Entra shell is himmelblau's `shell` string
  (auth-entra.nix:135, hardcoded bash) and zsh is not in the system at all (no programs.zsh
  anywhere in cells/, no /run/current-system/sw/bin/zsh). Porting cli/zsh therefore has a
  SYSTEM half: enable programs.zsh, then point auth-entra's shell at it, and set
  users.users.<local>.shell separately. Neither account gets zsh from home-manager alone.
- 0b substituters: /etc/nix/nix.conf carries `extra-substituters = https://nyx-cache.chaotic.cx/`
  + its trusted-public-key at DAEMON level, so every user inherits it regardless of
  trusted-users. PASS, devshells on the Entra account hit the cache.
  Corollary confirmed: `trusted-substituters` is empty, so that account can never ADD one
  (flake nixConfig prompts will just be declined) — it does not need to.
- 0a agenix owner for an NSS-only account: PASS by inspection, no tmpfiles fallback needed.
  Evidence: agenix modules/age.nix:126-128 emits a literal `chown ${owner}:${group} "$_truePath"`
  into the activation script — no users.users lookup at activation time, so a numeric uid
  string works (same trick the repo already uses at auth-entra.nix:193). `/run/agenix.d` and
  the per-generation dir are 0751 root:keys (o+x, traversable by any uid); secrets land 0400
  owned by the declared owner. CAVEAT: the `group` default is `users.${owner}.group or "0"`,
  which for a numeric owner silently resolves to root — pass group = the uid explicitly.
  Empirical confirmation rides along with step 4 (the first real entra age.secrets entry);
  no separate throwaway rebuild spent on it.

## theme-debt (GUI tools ported WITHOUT the custom theme — revisit after cutover)
Rule: while porting, a tool that had a catppuccin/kanagawa-specific colour config in jarvis
gets ported with its UPSTREAM DEFAULT look; the theming is a separate pass once the account
works. Every such drop is listed here so nothing is forgotten. Format: tool — what jarvis had
— what penrose gets now — how to bring it back.
- spicetify — colorScheme CatppuccinMocha/Latte selected by globals.theme.preferDark
  (users/shared/gui/spicetify.nix) — stock Spotify look, no theme, extensions only —
  spicetify-nix ships `themes.text`/catppuccin under legacyPackages.themes; wire to the repo's
  kanagawa palette via lib._custom.unwrapHex or just pick theme+colorScheme in the HM module.
(append below as more GUI modules are ported: foot colours, btop, delta, dircolors are CLI/TUI
 and tracked in the catppuccin call-site list under phase 1 instead)

## notes
- SOURCE MECHANICS, read before porting (verified 2026-09-14 against the clone):
  - `repo.secrets` lives in TOP-LEVEL modules/secrets.nix (not users/modules/), and is the
    generic half: secretFiles (attrsOf path) -> secrets (readOnly, mapAttrs importEncrypted).
    users/modules/secrets.nix is only 22 lines of sugar on top: `userSecretsName` (defaults to
    "user-${name}") and `userSecrets` = repo.secrets.${userSecretsName}. Port BOTH halves or
    neither — ssh.nix/vpn.nix/lang-ai.nix read userSecrets, git.nix/ssh.nix read repo.secrets.
  - importEncrypted wraps a bare attrset in a function (`constSet`) and returns {} for a
    missing path, so a host with no secret files still evaluates. Worth keeping: it is what
    lets the shared home build for an account that has no secrets at all.
  - the jarvis home is a flake-parts homeConfigurations."jarvis" (flake/home-configurations.nix)
    with 3 overlays that DO NOT come along: packages/default.nix, the librewolf pin, and
    `nix = nixVersions.nix_2_31` (needed because HM activation must be ABI-compatible with the
    repo's nix-plugins build — this repo pins its own nix elsewhere, check before dropping).
- users/crookedmirror/default.nix (dellvis) is the precedent that ../shared builds for a second
  account — BUT it sets no repo.secretFiles and no userSecretsName, so `userSecrets` resolves to
  repo.secrets.user-crookedmirror = missing attr. It is imported by hosts/dellvis, and dellvis is
  the machine this repo already replaced, so it is likely simply broken/unevaluated rather than a
  working example of the split. Do not treat it as proof the deny-list approach evaluates.
- users/jarvis/default.nix drops: nonNixos.enable, targets.genericLinux/nixGL, make-zsh-default-shell
  (NixOS sets users.users.<name>.shell). Confirmed the whole file is 63 lines and contains
  nothing else except the 6 repo.secretFiles bindings and the OTEL/SNYK sessionVariables.
- home.stateVersion: both are 24.11 (home/default.nix:34, nixosConfigurations.nix:114) — nothing to
  reconcile, no release-note sweep needed.
- The Intune dead end on jarvis is documented in the session of 2026-09-09; do not retry
  intune-portal on Ubuntu — the fix is this port.
- certs/ measured 2026-09-14: 92G total, single tree htb-cjca (Academy 87G, infra 324M, exams 5.4M,
  boxes/vpn/patches <100K). 85G of it is 17 per-exercise .venv, each with its own torch
  (libtorch_cuda.so 440M x17). Real content ~2.5G. Recreate an env on demand from the flake
  instead of rsyncing them; M620 makes the CUDA build dead weight anyway.
- ssh key inventory on jarvis 2026-09-14: ~/.ssh/ssh-identities/{work-azure,client-e-key,github,
  work-github,work-gitlab,work-prod,client-a} + ~/.ssh/id_rsa (legacy RSA — check if still used
  anywhere before porting) + ~/.ssh/penrose (deploy key to the new host) + ~/.ssh/host (pre-nixos
  leftover). Only 5 have a .pub next to them; regenerate the missing ones with `ssh-keygen -y`
  before re-encrypting, so the tarball is not the single source of truth.
- git identity wiring as generated on jarvis (~/.config/git/config): 5 includeIf blocks, each
  pointing at a store file holding just [user] name+email — 3 distinct identities across them.
  No commit signing configured anywhere (no signingkey/gpgsign), only gpg.format=openpgp left
  over from defaults — decide during the port whether to add ssh signing, since the keys will
  finally be declarative.
- shared-tooling sizes for the port: cli/zsh 116K, tui/neovim 944K, tui/tmux 36K,
  tui/coding-agents 108K — config only, all of it goes to both accounts unchanged.
