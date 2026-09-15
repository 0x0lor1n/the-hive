# port-jarvis-home (make penrose the daily driver; jarvis = Ubuntu 24.04 + home-manager standalone)

Source: /srv/workspace/projects/nixos-config/users/{shared,jarvis,modules} (home-manager standalone,
targets.genericLinux + nixGL, 1647 lines / ~45 files) + ~/workspace (146G, 9 git repos).
Target: penrose (cells/workstation, home-manager as NixOS module, home/ = 363 lines,
only desktop/ + default.nix so far).
Decision 2026-09-09: stop fixing intune-portal on jarvis (server-side 1001/InteractionRequired,
1.2607.4 is latest, clean re-enroll x3 failed). Ubuntu stays until penrose has home+workspace,
then jarvis gets reinstalled from cells/workstation (own host, not a port of penrose).

## where this runs
Phases 1-3 run ON PENROSE (hermes there). Setup on penrose:
  git clone https://github.com/0x0lor1n/the-hive.git ~/workspace/playground/nix-rensa   # this repo, main
  git clone -b nvim-wochap-resync https://github.com/crookedmirror/nixos-config.git /srv/workspace/projects/nixos-config  # SOURCE, read-only (shared clone, 2026-09-14)
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
Checked against the real tree 2026-09-14 (clone at /srv/workspace/projects/nixos-config, nvim-wochap-resync 355ea40).
Rows marked [NEW] were missing from the first pass.
| source                          | target                                  | note |
| shared/default.nix              | home/default.nix + home/cli/            | [NEW] top-level shared: ~20 home.packages, shellAliases, .bashrc HISTFILE=/dev/null trick, fonts.fontconfig, gpg, systemd.user.startServices="suggest". DROP slack (repo has cell.packages.slack under nixpak) and the nixGL-wrapped wine/slack branches; reconcile ungoogled-chromium with the repo's chromium+linux_entra_sso |
| shared/cli/zsh (+p10k, fns)     | home/cli/zsh.nix + home/cli/zsh/        | keep config files verbatim, drop nonNixos guards. SEE the out-of-store symlink note below — 4 of its files are NOT store-backed today |
| shared/cli/{fzf,skim,zoxide,bat,lazygit} | home/cli/*.nix                 | 1:1 |
| shared/cli/{eza,dircolors,direnv} | home/cli/*.nix                        | [NEW] were not listed; dircolors is a catppuccin call site |
| shared/gui/foot (+foot.ini)     | home/desktop/terminal.nix                | penrose has dwl/greetd; foot fits. foot.ini is out-of-store; colors come from theme via lib._custom.unwrapHex |
| shared/gui/kitty                | DROPPED 2026-09-14                       | foot is the terminal |
| shared/gui/firefox              | a NEW workstation profile (not home/)     | REPLACED 2026-09-14 (user): librewolf decommissioned, nur dropped. Browser = STABLE firefox + Phoenix, wired as a NIXOS module (see the browser item in phase 1). The 8 nur addons and the librewolf pin both go away; the search engines (4get default, np/no/nl/gh/wru aliases) get re-declared as a SearchEngines policy, which works on stable since Fx139 |
| shared/gui/microsoft-edge       | DONE 2026-09-15: pkg was already in layer-compositor.nix; the policy JSON moved to /etc/opt/edge/policies/managed (system scope) | jarvis wrote it under ~/.config/microsoft-edge/policies, which Chromium on Linux never reads — extensions were never force-installed there |
| shared/gui/{simplex,mattermost} | DONE 2026-09-15: home/desktop/chat.nix (unsandboxed, both homes) + persist .config/Mattermost, .local/share/simplex | telegram DROPPED: cell.packages.telegram-desktop (nixpak) already covers it |
| shared/gui/spicetify            | DEFERRED (input is in flake.nix, module not imported) | Spotify itself is not in the closure yet; wire in media.nix when someone actually needs it, with kanagawa colours (see accepted-loss list) |
| shared/gui/mpv (+vpy)           | DONE 2026-09-15: home/desktop/mpv/ (default.nix + .vpy) | mpv-unwrapped built with vapoursynthSupport against vapoursynth.withPlugins [mvtools ffms] — K now works (jarvis had the binding but stock mpv); hwdec vaapi (iGPU), ao pipewire, `vf=format=rgba` dropped |
| shared/dev/lang-*.nix, android  | home/dev/*.nix                           | lang-ai is 5 lines (OPENCODE_API_KEY only) — merge with post-dellvis-tooling §2 |
| shared/tui/{tmux,neovim}        | home/dev/ (or home/cli/)                 | [NEW] both out-of-store; neovim ships 93 files under config/nvim plus a dead config/nvim.bak (drop the .bak) |
| shared/tui/coding-agents/claude | home/dev/claude.nix                      | keep llm-agents pkg + skills; drop the oh-my-claudecode marketplace wiring |
| shared/tui/coding-agents/{opencode,skills} | home/dev/*.nix                | [NEW] opencode ships 3 json + omo.jsonc, skills ship 3 SKILL.md — all out-of-store. USER 2026-09-15: anthropic is no longer used with opencode — keep ONLY the `go` profile from omo.jsonc (opencode-go/* models) and make it the default; drop `work` + `work-uncensored` (38 anthropic model refs), the `opencode-anthropic-oauth` plugin in opencode.json, and the omg/omw/omwc aliases (one profile = plain `opencode`). oc-swap in functions.zsh already deleted for the same reason |
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
- [x] browser: stock firefox + Phoenix as a NIXOS module (decision 2026-09-14). DONE 2026-09-15:
      profiles/browser-firefox.nix + phoenix overlay via pkgs.extend in nixosConfigurations.nix,
      built + switched on penrose. Original analysis kept below. Verified by
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
- [x] strip catppuccin while porting (DONE 2026-09-15: no catppuccin option/input left in cells/, only
      theme-debt comments — see ## theme-debt). Original: users/shared/default.nix imports catppuccin.homeModules.catppuccin
      and modules read globals.theme.colors.flavour. Repo is kanagawa via theme.colors (_module.args.theme,
      home/default.nix:29) — rewrite those call sites, do NOT add the input. Also covers
      cli/dircolors.nix (catppuccin-dircolors input drops with it).
      Call sites enumerated 2026-09-14 (7, all small): shared/default.nix (catppuccin.enable +
      flavor + accent, catppuccin.nvim.enable=false, catppuccin.btop.enable), cli/zsh
      (catppuccin.zsh-syntax-highlighting), cli/git.nix (catppuccin.delta.enable and
      `features = "catppuccin-${flavour} side-by-side"` in programs.delta), cli/dircolors,
      gui/spicetify (colorScheme CatppuccinMocha/Latte via globals.theme.preferDark).
      Only 3 of the 12 globals refs are theme ones — the rest are configDirectory.
- [x] mkHome takes a per-account secret set, not a bool (layer-compositor.nix:20): cli+dev are
      DONE for the secrets arg 2026-09-14 (step 4): `secrets = userSecrets "<role>"` per call
      site; vpn still open (below).
      unconditional for both accounts, while ssh keys / git includeIf blocks / vpn are selected
      per account (see the items below). Personal-only: osint, tor.
      VPN SPLIT SETTLED 2026-09-14 (user). Three profiles, 1:1 with the three source secret
      files, no collecting from jarvis needed:
        entra (employer work): work-a (wireguard, secret vpn-owt) + work-b (openvpn, vpn-tiko)
        local (FREELANCE, not employer): work-c (openvpn, vpn-wrs)
      The user's "mdaudit"/"qvalon" were the same network as work-c, remembered under other names.
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
- [x] impermanence carve-outs for the Entra home — DONE 2026-09-14 (step 5). auth-entra.nix
      allowlist += .ssh, .local/share/direnv, .local/share/zsh, .cache/nix, .config/opencode,
      .local/share/opencode (entraHome, 0700). layer-users-local.nix += the same four new ones
      (.ssh/direnv were already there). .config/git and .ssh/config deliberately NOT persisted:
      HM store symlinks, re-created at activation. Verified via eval of persistence."/persist".
      Phase 2 must point zsh HISTFILE at ~/.local/share/zsh (bash trick, auth-entra.nix:~240).
      NSS account, so no persistence.users.<name>; original rationale kept below.
      auth-entra.nix:189-223 is an explicit allowlist of absolute paths (NSS account, so
      no persistence.users.<name>); anything cli/dev writes and is not listed is gone next reboot.
      New entries needed, entraHome-style: .ssh (0700 — known_hosts, agent sockets; the identity
      keys themselves come from age.secrets, see below), .local/share/direnv, .local/share/zsh
      (histfile — mirror the bash HISTFILE trick at auth-entra.nix:227), .config/opencode +
      whatever opencode/hermes keep outside .hermes, .cache/nix. Local user already has its own
      list (layer-users-local.nix:44-68) — keep the two in sync.
- [x] git identities — DONE 2026-09-14 (step 4). secrets/user-{local,entra}.nix.age now carry
      `git.includes` (includeIf blocks) + `ssh.matchBlocks`; home/default.nix reads both
      (`sec.git.includes or []`, `sec.ssh.matchBlocks or {}`). Local: mdaudit block on top of the
      public default author; entra: tiko.ch, azure-owt, gh-work blocks, no default. Verified in
      the built generations (.config/git/config, .ssh/config) for both accounts.
      One encrypted attrset feeds TWO consumers, port them together or neither
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
      MISMATCH RESOLVED 2026-09-14 (user): the key table below is final — client-e stays on the
      local account together with github and client-a; every work-* key is entra. So the
      git.client-e.tld includeIf block lives in user-local.nix.age, not in entra's; which
      name/email it carries is that file's business (encrypted, never a public path). The rule
      "no block whose remote the account cannot authenticate to" is what decides, not the
      identity string.
      Entra keeps no default `user` (nothing in globals for it); a repo outside every glob must
      fail rather than silently commit under a work UPN.
- [x] ssh identities — DONE 2026-09-14 (step 4). secrets/ssh/<name>{,.pub}.age (7 keys, 14
      files, master identities + recovery) -> profiles/secrets.nix `sshIdentities`: static
      age.secrets, no generator, mode 0600/0644, rekeyed/penrose written directly with
      `rage -r <hostPubkey>` (identHash = sha256(sha256(pubkey)+sha256(file))[0:32]) so no PIN
      round-trip through `agenix rekey`. .pub shipped next to each key: the private halves are
      passphrase-protected, without the .pub ssh prompts even when the agent holds the key.
      Owner for entra = numeric uid (chown takes it; users.users has no entry) — the "STILL
      OPEN" below is settled by that, verify on first login. Skipped on isVm hosts (no rekeyed
      bundle for sevastopol). HM: programs.ssh addKeysToAgent=yes + services.ssh-agent per
      account. Names: ssh-github, ssh-qvalon, ssh-git-mdaudit (local); ssh-azure-owt,
      ssh-github-owt, ssh-id-engie, ssh-id-engie-prod (entra). Real aliases replace the
      work-*/client-* placeholders of the table below.
      NEW mechanism, nothing in either repo does this today.
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
- [x] home/{cli,dev,security}/default.nix stubs — DONE 2026-09-14 (step 6). Empty `imports = []`
      modules with the contract in the header comment; home/default.nix imports all three and
      exports `_module.args.secrets = sec` so security/ can read the role's attrset without
      re-plumbing. Toplevel hash unchanged after adding them (expected: no options set yet).
- [x] consequences of "Entra is the daily driver, local rebuilds" — CHECKED 2026-09-14 (step 6):
      trusted-users = root + @wheel (eval'd), nyx-cache substituter is nix.settings on the host
      (layer-kernel.nix:32, eval'd) so devshells from the Entra account hit it; ssh-agent is
      already per-account (home/default.nix:93, services.ssh-agent + addKeysToAgent, applies to
      both homes). Left open on purpose: hermes container (phase 2, size first) and the
      "rebuild from tuigreet/VT is comfortable" check (needs a live penrose, phase 4).
      Original notes kept below.
      consequences of "Entra is the daily driver, local rebuilds" that the split creates:
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
- [x] `nix build .#nixosConfigurations.penrose.config.system.build.toplevel --no-link` green
      — 2026-09-14, /nix/store/8pxkrrfg6wdpqvakqwmvv03dw4z5fmn8-nixos-system-penrose-26.11pre-git
      (covers both branches: the Entra activationPackage is pulled in via layer-compositor.nix:150)
      PHASE 1 CLOSED. Phase 2 (port modules) starts in a fresh session.

### phase 2 — port modules (on penrose, file by file, table above)
- [x] /srv/the-hive infra — DONE 2026-09-15 (prerequisite for the live-edited dotfiles):
      disks/{penrose,sevastopol}.nix += rpool/safe/srv (canmount=off) + safe/srv/the-hive
      (legacy, mounted /srv/the-hive); profiles/srv-the-hive.nix = users.groups.hive, local
      user in it, tmpfiles `z /srv/the-hive 0750 <local> hive` + `A+ .../dotfiles d:group:hive:rwx,
      group:hive:rwx`; auth-entra local_groups += hive. Verified by eval: fileSystems entry,
      both tmpfiles lines, extraGroups. dotfiles/ lives at REPO ROOT (the-hive/dotfiles/zsh/).
      USER STEPS still open (new datasets are not created by disko on an installed host):
        sudo -S -p '' zfs create -o canmount=off -o mountpoint=none rpool/safe/srv
        sudo -S -p '' zfs create -o mountpoint=legacy rpool/safe/srv/the-hive
        rebuild; git clone the-hive /srv/the-hive (as local user); sudo -S -p '' systemd-tmpfiles --create
      Until then the 4 zsh symlinks dangle and .zshrc's `source` of them fails at shell start
      (the p10k line is guarded, the other three are not — acceptable, this is the deploy step).
- [x] cli/zsh — DONE 2026-09-15. home/cli/zsh.nix (initContent kept verbatim modulo paths),
      dotfiles/zsh/{config,key-bindings}.zsh + .p10k.zsh copied VERBATIM; functions.zsh minus
      oc-swap (user 2026-09-15: anthropic/opencode model toggling is dead, see the opencode row).
      HM points at them with config.lib.file.mkOutOfStoreSymlink — verified the built
      xdg.configFile source is a bare symlink to /srv/the-hive/dotfiles/zsh/config.zsh.
      HISTFILE = ~/.local/share/zsh/history, HISTDB_FILE = ~/.local/share/zsh/history.db (the
      carve-out). Plugins from the nixpkgs pin (zsh-defer, zsh-vi-mode, ...) EXCEPT zsh-histdb:
      nixpkgs ships 90a6c10 (2024-04-18) = the HISTORY_IGNORE merge (7b010a6 + f73d9c8) that
      broke jarvis; upstream has nothing newer (checked 2026-09-15), and jarvis's 30797f0
      (2022-01-18) is exactly the last commit before it. Kept via pkgs.zsh-histdb.overrideAttrs
      with src = 30797f0 (nixpkgs' sqlite3 substitution still applies). zsh-histdb-skim is NOT
      in nixpkgs: ported to
      cells/workstation/packages/zsh-histdb-skim.nix (0.9.7, cargoHash from jarvis), exported
      as cell.packages.zsh-histdb-skim.
      2026-09-15 MOVED to cells/deck (new cell, name from Neuromancer's cyberspace deck):
      deck/homeModules/zsh.nix + deck/packages.nix. Block `homeModules` added to flake.nix.
      Modules are `{inputs, cell, ...}: hmModule` so they read `cell.packages` directly;
      home/default.nix takes `deck ? {}` (= inputs.cells.deck.homeModules from layer-compositor)
      and imports `builtins.attrValues deck`. home/cli/ is gone; further account-agnostic
      shell tools (fzf, skim, eza, bat, zoxide, direnv, dircolors, tmux, neovim) go to deck/.
      catppuccin.zsh-syntax-highlighting dropped (fsh default theme; theme-debt).
      SYSTEM half: layer-users-local.nix programs.zsh.enable (enableGlobalCompInit=false,
      promptInit="" — HM's compinit via zsh-autocomplete must be the only one) +
      users.users.<local>.shell = pkgs.zsh; auth-entra.nix shell = /run/current-system/sw/bin/zsh.
      Verified by eval: local shell -> zsh-5.9.2, rendered .zshrc has the right HISTFILE/HISTDB
      paths and sources config/functions/key-bindings by their ~/.config/zsh path.
      bash HISTFILE trick in auth-entra stays (bash is still there for scripts/fallback).
- [x] cli/* rest — 2026-09-15 DONE, all in cells/deck/homeModules (skim, fzf, zoxide, bat, eza,
      direnv, dircolors, lazygit, git), registered in deck/homeModules.nix via `mk`.
      git.nix = account-agnostic half only (aliases, nvimdiff mergetool, delta pager, side-by-side);
      identity/includeIf/ssh stay in workstation/home/default.nix, HM merges both into one config
      (verified by eval: [alias]/[core] pager=delta/[delta]/[user]/[includeIf] all in git/config).
      release-25.05 API: aliases/extraConfig/programs.git.delta (jarvis used settings/programs.delta = 25.11).
      skim: HM fileWidget*/changeDirWidget* options instead of jarvis's hand-exported SKIM_* vars;
      enableZshIntegration stays false (zsh.nix sources completion/key-bindings in zvm_after_init).
      fzf: both shell integrations off (skim owns Ctrl-T/Alt-C). direnv whitelist prefix
      ~/workspace -> /srv/workspace. bat's `help` fn inlined (was bat/functions.zsh).
      DROPPED (theme-debt, see that section): catppuccin.{fzf,bat,eza,lazygit,delta}, skim's
      `sk` wrapper + HISTDB_COLOR, catppuccin-dircolors input (HM default dircolors db instead).
- [x] tui/{tmux,neovim} — 2026-09-15 DONE, cells/deck/homeModules/{tmux,neovim}.nix.
      dotfiles/tmux/{config.conf,status-bar.tmux,sesh.toml} + dotfiles/nvim/ (92 files, the
      .bak dropped, .gitignore dropped) copied verbatim; sesh.toml's ~/nixos-config session
      -> /srv/the-hive. Both out-of-store via mkOutOfStoreSymlink. resurrect ps.sh patch
      (histdb sqlite3 filter) + tmux-server user unit kept. theme-colors.sh: jarvis dumped the
      catppuccin palette, the status bar uses only base/surface1/lavender -> generated from
      kanagawa roles (bg/border/focus) in tmux.nix; catppuccin.tmux dropped (border styles set
      from roles instead). nvim colorscheme is a lazy plugin (catppuccin, CATPPUCCIN_* env with
      mocha/mauve defaults, env not exported) -> theme-debt.
- [x] dev/* — 2026-09-15 DONE. home/dev/languages.nix = the 10 lang-*.nix + android.nix folded
      into one package list (python venv hack + GLOBAL_PYTHON_* kept for lang-python.lua).
      home/dev/agents.nix = claude-code + opencode + oh-my-opencode from cells/repo/packages
      (re-exports added next to hermes-agent; passed as `agentPkgs` from layer-compositor like
      deck). claude: settings.json declared (env incl. ANTHROPIC_BASE_URL -> pxpipe, jarvis's
      auto-commit PostToolUse hooks, rtk PreToolUse hook = what `rtk init -g` writes, RTK.md
      generated by the pinned rtk), statusline.sh, skills. oh-my-claudecode + the two jarvis
      directory marketplaces dropped. opencode: opencode.json/tui.json declared (anthropic-oauth
      plugin dropped), oh-my-openagent local-plugin shim kept, omo.jsonc = former `go` profile
      flattened to top level (no profiles, no OMO_PROFILE aliases, 0 anthropic refs) and
      LIVE-EDITED from dotfiles/opencode/omo.jsonc (OmO self-migration rewrites it in place —
      the one exception to "only nvim/tmux/zsh are out-of-store"). rtk: ~/.config/rtk/config.toml
      per post-dellvis-tooling §3 (exclude nix/nixos-rebuild/colmena/nom/just, tee failures).
      lang-ai (OPENCODE_API_KEY from eval-time secrets, world-readable in the store on jarvis)
      NOT ported: `opencode auth login` once per account instead, state under ~/.local/share.
      Git identities were already done in phase 1 (home/default.nix programs.git.includes).
      ~/.claude/CLAUDE.md declared too: "@RTK.md" + agents/CLAUDE.md (empty; global
      instructions go there, not by hand). USER STEPS after switch (credentials only):
      `opencode auth login`, `claude` login; optional `ln -s ~/.claude/skills/* ~/.hermes/skills/`.
- [x] desktop additions — 2026-09-15 DONE: foot (earlier), firefox+Phoenix (profiles/browser-firefox.nix,
      imported in nixosConfigurations.nix desktop list), mpv (home/desktop/mpv/), chat.nix, edge policy
      in layer-compositor.nix. spicetify deferred (table above).
- [x] security/* — 2026-09-15 DONE.
      osint.nix + tor.nix -> home/security/ (local account only: mkHome `personal = true`);
      vpn -> profiles/vpn.nix, SYSTEM units (wg-quick-owt, openvpn-{tiko,wrs}), credentials as
      agenix runtime secrets secrets/vpn/{owt.conf,tiko.ovpn,tiko-auth,wrs.ovpn,wrs-auth}.age
      (masters + recovery) + rekeyed/penrose, produced by .hermes/state/vpn-transplant.sh from
      jarvis's vpn-*.nix.age + user.nix.age in one PIN run. polkit lets the networkmanager group
      (Entra) manage the two employer units; `vpn up|down|status` in systemPackages.
      ssh matchBlocks already in home/default.nix (step 4). Verify after switch: `vpn status`,
      `vpn up owt` as the Entra user (no password prompt), `vpn up wrs` as local.
- [x] grep gate: `grep -rn 'nixos-config\|nonNixos\|genericLinux\|nixGL' cells/workstation/home dotfiles` -> empty
      (2026-09-15: clean after zsh; re-run after desktop+security — clean, comment mentions say "jarvis")
- [x] eval + build toplevel for penrose AND sevastopol/osgiliath (shared home must not break them) —
      2026-09-15 all three build; penrose switched, /run/agenix/vpn-* present.

### phase 3 — deploy to penrose
- [-] OBSOLETE 2026-09-15: penrose reachable from jarvis — not needed. penrose rebuilds
      itself from its own checkout (/srv/the-hive, local user); nothing is pushed from
      jarvis in phases 3-4 (workspace comes over by rsync jarvis -> penrose in phase 4, a
      route is needed in THAT direction only, or a disk). Left unfixed on purpose.
- [-] OBSOLETE 2026-09-15: colmena / --target-host — superseded by the local
      `nixos-rebuild switch --sudo --flake .#penrose` already run at the end of phase 2
      (toplevel = fe3333f). Remote deploy of penrose stays out of scope for this plan.
- [~] verify on penrose as the Entra user (daily driver) and the local user. Checks run
      by the user in foot; agent cannot su into the Entra account (fixes go to cells/,
      declarative only, no imperative edits in either home). ROUND 1 run 2026-09-15 after
      the reboot (toplevel 3c61b9c); results + fixes, round 2 pending switch+relogin:
      - [x] zsh first start: 0.10s wall, p10k instant prompt, 4 gitstatusd, histdb 99 rows,
            zoxide on rpool/safe/persist (Entra). NEW BUG: `[Errno 17] File exists
            ~/.venv/include/python3.11` — sesh restores N panes, every zsh raced into
            `python -m venv` (dir test, not bin/activate). FIXED: languages.nix tests
            bin/activate + flock -n on ~/.venv.lock.
      - [x] foot lands in tmux (sesh the-hive, panes 2->3 on C-S-Enter); foot's own
            spawn-terminal=none; Shift+Enter = \e[13;2u
      - [x] direnv whitelist.prefix [/srv/workspace /srv/the-hive] from /etc/direnv (both
            accounts). BUT under Entra the rensa hook fails: `git rev-parse --show-toplevel`
            -> "Not inside a git repository" — git 2.55 safe.directory refuses a repo owned by
            another uid (0750 crookedmirror:hive). FIXED: programs.git extraConfig
            safe.directory [/srv/the-hive /srv/workspace/*] (home/default.nix). Next failure
            behind it: .ren/ (REN_STATE) is 0755 owner-only -> EACCES for Entra. FIXED:
            tmpfiles `d .ren 2770 + A+ d:group:hive:rwx` (srv-the-hive.nix), same as dotfiles.
      - [x] firefox = Phoenix (801 hits in mozilla.cfg), policies.json has SearchEngines/
            ExtensionSettings/Nix Packages. himmelblau-broker.service inactive on Entra:
            EXPECTED — Type=dbus BusName=com.microsoft.identity.broker1, dbus-activated on
            first SSO request, not at login. M365 SSO itself not yet exercised.
      - [x] git identities: Entra 3 includeIf (tiko, azure-owt, gh-work) -> 3 distinct
            emails via hasconfig:remote.*.url, no default identity ("OK: no default identity").
            local: git.client-e.tld (mdaudit) + github -> 0xolorin. gh-work ssh auth OK
            (vsevolod-kokurin), passphrase prompted once (agent, see below).
      - [x] ssh matchBlocks resolve on both; IdentityFile /run/agenix/ssh-* 0600 owned by
            the account (Entra: 4 keys, local: 3 keys/6 hosts)
      - [x] vpn: `vpn up owt` as Entra -> active, tun 192.168.4.31/32, no prompt. `vpn up
            wrs` as local -> active but polkit ASKED A PASSWORD (wheel = auth_admin_keep on
            manage-units). FIXED: explicit polkit YES for wheel on openvpn-wrs.service only.
      - [!] HM user units on Entra never start: tmux-server.service + ssh-agent.service
            inactive (SSH_AUTH_SOCK=/ssh-agent points at nothing; the gh-work passphrase
            prompt every time proves it), avizo/swayidle no journal lines. ROOT CAUSE
            (journal 10:37:07): HM activate `reloadSystemd` -> "User systemd daemon not
            running. Skipping reload." — it gates on `is-system-running` == running|degraded
            and home-manager-entra runs INSIDE default.target startup, where the manager
            reports "starting". Links in default.target.wants get created after the target's
            job was already queued, so nothing pulls them in; sd-switch never runs. FIXED
            (layer-compositor.nix): ExecStartPost = daemon-reload + `systemctl --user start
            --no-block` every unit in the generation's default.target.wants;
            dwl-session-bridge After=home-manager-entra.service so graphical-session.target
            sees avizo/swayidle. Local account unaffected (HM via NixOS module, sd-switch runs
            at switch time with a live manager).
      - [x] vpn-transplant.sh: first run `mktemp: /run/user/1000/tmp.XXXX: No such file` —
            stale XDG_RUNTIME_DIR in the shell (fresh boot, tty not yet a logind session?);
            second run in the same shell went through (4 files rekeyed, PIN once). Not fixed:
            script already falls back to /dev/shm when the dir is missing; this was a race
            with the runtime dir appearing. Re-check on round 2; drop if it does not repeat.
      - [x] ROUND 2 run 2026-09-15 (toplevel c23594f, switch + relogin): ssh-agent active,
            SSH_AUTH_SOCK=/run/user/1737034432/ssh-agent, gh-work auth OK; direnv loads the
            rensa devshell, git sees the repo; `vpn up wrs` as local with no password; no
            venv traceback. THREE NEW, all diagnosed + fixed in 020f84b:
            - tmux-server inactive: DEADLOCK. sd-switch (inside home-manager-entra's
              activate) starts tmux-server blocking -> After=default.target waits for the
              target -> the target waits for home-manager-entra -> 180s timeout, unit
              killed, ExecStartPost never ran (journal 11:15:35 -> 11:18:34). FIXED: no
              After=default.target on tmux-server (tmux.nix). Confirmed after switch:
              home-manager-entra finishes in 1s, "Starting units: avizo, swayidle,
              tmux-server". Unit still shows inactive ONLY because the user's manual
              `tmux new-session -s the-hive` (pid 4397, pre-dates the switch) holds the
              socket; start-server exits 0 -> forking unit with no process. Resolves at
              next login/reboot, not a bug.
            - avizo/swayidle failed (start-limit-hit): relogin via greeter at 11:28:23 —
              old dwl died, Restart=always with no delay -> 5 crashes/s -> limit. The
              oneshot dwl-session-bridge stayed active from the old session, so the new
              dwl-startup's `systemctl start` was a no-op. FIXED (layer-compositor.nix):
              dwl-session no longer execs dwl — after dwl exits it stops the bridge
              (BindsTo takes graphical-session.target down -> PartOf units stop cleanly);
              dwl-startup does reset-failed + `restart` bridge so a relogin re-pulls the
              target's wants against the new WAYLAND_DISPLAY.
            - `git status` under Entra: Permission denied on secrets/vpn (0700) and
              home/dev/agents/* (0750, group users) — created under umask 077/027 by
              vpn-transplant.sh and the agents rsync. One-off `chmod o+rX`, not in git.
              Rule for later: anything copied into /srv/the-hive by hand gets `chmod -R
              o+rX` (the checkout's 0750 + hive group is the only gate).
      - [x] ROUND 3 (after reboot, toplevel 020f84b), Entra in foot:
            systemctl --user is-active home-manager-entra tmux-server ssh-agent avizo swayidle   # 5x active
            cd /srv/the-hive && git status --short | head -3                                      # no Permission denied
            then log out of dwl (kill it / greeter) and log in again:
            systemctl --user is-active avizo swayidle dwl-session-bridge                          # 3x active (the relogin path)
            Green -> phase 3 closed; phase 4 next (workspace rsync jarvis -> penrose).
            RESULT 2026-09-15: after reboot 5x active, git status clean (no Permission
            denied). Relogin path (MOD+Shift+Q -> greeter): dwl-session-bridge active but
            avizo/swayidle inactive — the bridge's stop on dwl exit did not take
            graphical-session.target down, so the PartOf units were never re-pulled.
            FIXED 2a20831 (layer-compositor.nix): dwl exit stops graphical-session.target
            explicitly, not just the bridge. Re-verified after switch + relogin: 3x active.
      - [x] Firefox fresh on every boot (found by user post-round-3): ~/.mozilla was not in
            the impermanence carve-out for either account — Phoenix + policies rebuilt the
            profile from scratch each reboot. FIXED 95f5d78: ~/.mozilla persisted for both
            accounts (findmnt shows rpool/safe/persist bind for the local one; Entra side
            checked on next login: `findmnt -T ~/.mozilla`).
      PHASE 3 CLOSED 2026-09-15 (toplevel 95f5d78). Phases 1–3 have no open items.

### phase 4 — workspace to penrose (shared /srv/workspace, NOT per-home)
- [x] free space check on penrose — 1TB free, not a constraint
- [x] DECIDED 2026-09-15 (user): project trees are SHARED between the two accounts in
      /srv/workspace (dataset rpool/safe/srv/workspace, 2770 <local>:hive + default ACL
      group:hive:rwx, direnv whitelist.prefix, git safe.directory /srv/workspace/* —
      all live since 097996c/3c61b9c). This supersedes both the "per account home" text
      that used to sit here and the "/srv/work Entra-owned vs /srv/projects local-owned"
      note in blocked_on: ownership-based isolation only isolates the admin account from
      itself (local user has sudo and rebuilds the box), costs a user switch to touch the
      other tree, and splits zoxide/sesh/hermes state — for nothing. Work vs personal is
      decided by the REMOTE (git includeIf hasconfig + ssh IdentityFile per host, verified
      round 1), the directory is for humans only.
        /srv/workspace/work/<org>/<repo>     employer + client repos (Parallax already there)
        /srv/workspace/projects/<repo>       personal + freelance (nixos-config already there)
      What stays per-account and OUT of /srv: anything holding a credential or agent state —
      .env, .venv, .direnv, ~/.hermes, ~/.claude, ~/.claude.json. Excluded from the rsync,
      regenerated on penrose.
      Exception clause: if a client ever demands "code only under the managed identity",
      THAT client gets ~<entra>/work/<client> (own carve-out in auth-entra.nix); nothing
      else moves. No such client today.
- [x] nix-rensa: no longer an exception — ordinary tenant of /srv/workspace/projects/
      (the-hive itself is the rebuild source and already lives in /srv/the-hive).
- [ ] inventory on jarvis (measured 2026-09-14, re-check sizes before the copy):
        work     -> Clients/ 26G (client-b 23G, client-c 1.5G, client-d 1.1G), work-org/ 6.2G
                    (3 of 5 repos point at work-azure), playground/client-a 7.1G
        personal -> 0xOLOR1N/ 2.3G, playground/nix-rensa 8.3G, playground/personal-b 5.7G,
                    certs/ ~2.5G (htb-cjca, after excluding .venv — 85 of 92G are 17
                    disposable .venv)
      Per repo before moving: `git remote -v` -> host must be in the phase 1 ssh key table
      (so includeIf/IdentityFile resolve on penrose); anything with a host not in the table
      is a NEW identity to add first, not a copy problem.
- [ ] route: jarvis not resolvable from penrose (2026-09-15: only .1 and .179 answer on
      :22 on 192.168.10.0/24). Either same LAN + IP, or ssh from jarvis -> penrose
      (penrose sshd: layer-users-local.nix authorizedKeys) and PUSH with rsync.
- [ ] order & method (run as the LOCAL user on penrose; the setgid dir + default ACL make
      the result group-writable for Entra without chmod):
      1. `rsync -aHAXS --info=progress2 --exclude target --exclude node_modules
         --exclude .direnv --exclude .venv --exclude result --exclude .env
         jarvis:~/workspace/<x>/ /srv/workspace/{work,projects}/<x>/`
      2. Clients/ (26G): verify with `rsync -nc` after the first pass
      3. after every batch: `chmod -R o-rwx` is NOT needed (ACL), but check one repo as
         Entra: `git -C /srv/workspace/work/<repo> status` -> no Permission denied
- [ ] devshell smoke test on penrose per repo (`nix develop` in nix-rensa, pxpipe, nixq),
      once as local, once as Entra (direnv whitelist covers both).
- [ ] hermes/claude state: ~/.hermes, ~/.claude, ~/.claude.json — rsync into EACH home
      that needs it (per-account by design), after home-manager lands. post-dellvis-tooling
      §2 decides which parts become declarative.
- [ ] impermanence: nothing to do — rpool/safe/srv/workspace survives the @blank rollback;
      the two homes only hold the per-account state above, already on persist.

### phase 5 — jarvis cutover
- [ ] jarvis daily work stops; penrose is primary for >= 3 working days without going back
- [ ] jarvis: new host in nixosConfigurations.nix (hardware facts: Latitude? see nix-rensa/latitude-5580-upgrade.md if that is jarvis; else collect lspci/disks first), disks/jarvis.nix, secrets/generated/jarvis
- [ ] install via same path as port-dellvis phase 4 (Secure Boot user keys, ZFS+TPM, himmelblau enroll)
- [ ] /srv/workspace/projects/nixos-config: archive (tag `pre-rensa`), stop using; post-dellvis-tooling §5 cleanup

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
- SUPERSEDED 2026-09-15 by phase 4: /srv/workspace/{work,projects}, SHARED (group hive),
  not per-account ownership. Original note kept for the record:
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
- deck CLI tools, ported 2026-09-15 with stock colours (all catppuccin/nix call sites, kanagawa target):
  - zsh — catppuccin.zsh-syntax-highlighting (fsh theme) — fsh default — fast-theme with a kanagawa ini,
    or set FAST_HIGHLIGHT_STYLES from theme.colors in deck/homeModules/zsh.nix
  - skim — `sk` wrapper appending `--color fg:..,bg:..` + `export HISTDB_COLOR=--color=...` for
    zsh-histdb-skim Ctrl-R — stock — programs.skim.defaultOptions ["--color ${kanagawaSkColors}"]
    built from theme.colors, and HISTDB_COLOR in zsh.nix initContent (same string)
  - fzf — catppuccin.fzf — stock — programs.fzf.colors = {fg/bg/hl/... from theme.colors}
  - bat — catppuccin.bat (.tmTheme) — bat default — programs.bat.themes.kanagawa (tmTheme file) +
    config.theme = "kanagawa"; a kanagawa tmTheme exists upstream (rebelot/kanagawa.nvim extras)
  - eza — catppuccin.eza (EZA_COLORS) — stock — home.sessionVariables.EZA_COLORS from theme.colors
  - dircolors — catppuccin-dircolors input (.dircolors per flavour) — dircolors built-in db —
    programs.dircolors.settings or extraConfig with LS_COLORS derived from theme.colors
  - lazygit — catppuccin.lazygit accent=mauve — stock — programs.lazygit.settings.gui.theme
    {activeBorderColor/selectedLineBgColor/...} from theme.roles
  - delta — catppuccin.delta + `features = catppuccin-<flavour> side-by-side` — delta default
    syntax theme — programs.git.delta.options.syntax-theme = "kanagawa" once bat has the
    theme (delta reads bat's theme dir), plus plus-style/minus-style from theme.colors
  - tmux — catppuccin.tmux (@catppuccin_* pane/popup borders, status plugin off) — kanagawa roles
    for borders + a 3-variable theme-colors.sh (base/surface1/lavender = bg/border/focus), so the
    status bar already matches — nothing left unless the popup/pane colours want tuning
  - nvim — catppuccin/nvim lazy plugin driven by CATPPUCCIN_FLAVOR/ACCENT (mocha/mauve
    defaults; jarvis exported them, penrose does not) — same plugin, defaults — swap the
    colorscheme spec in dotfiles/nvim/lua/custom/plugins/colorscheme/ to rebelot/kanagawa.nvim
    (hl_overrides.lua reads the catppuccin palette, needs the same treatment); lazy-lock.json
    then changes on first start

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
