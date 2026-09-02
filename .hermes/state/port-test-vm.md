# port-test-vm

Source: ~/workspace/playground/test-vm (divnix/hive, 5.8k lines). Target: a
new cells/workstation in this repo, isolated from cells/server.

phase: 5 kernel -- DONE (VM boots gen 7 on 7.2.2-cachyos, SB enabled, TPM unlock ok). Phase 4 leftover: tuigreet/dwl NOT yet verified on the GTK display (WS_DISPLAY=1)
phases: 1 storage+boot (zfs native enc, tpm unlock, pcr15, lanzaboote,
           impermanence) | 2 secrets (agenix + rekey) | 3 auth (himmelblau,
           layer-users-local) | 4 desktop (dwl, home-manager as NixOS module)

## ported
cells/workstation/flake.nix (+lock): utils, disko(65fb947), lanzaboote d232658 (master; v1.0.0 sets boot.bootspec.enable which nixpkgs 34ab990 rejects), mkcreds 112d95f, nixpkgs pinned = root
cells/workstation/profiles: storage-zfs, storage-zfs-rollback, hardware-zfs-unlock, hardware-zfs-tpm (+__mkzfscreds, __zfs-fingerprint), hardware-secureboot, platform-virtio, gpu-virtio, dev-9p-share   <- test-vm profiles/ + devices/, mechanically
cells/workstation/disks/vm-zfs.nix     <- diskoConfigurations.nix vm-zfs target via utilsLib.mkDisk
cells/workstation/nixosConfigurations.nix  mkHost vm-zfs = foundation(common) + zfs + vmGuest + zfsNative; disko.imageBuilder.pkgs vmTools kernelImage=bzImage workaround (new nixpkgs vmTools vs disko aggregateModules)
cells/workstation/devshells.nix        ws-image / ws-switch / ws-secureboot-reset / ws-vm-run (justfile image / switch / secureboot-reset / vm-run-secureboot-tpm) + agenix CLI, state in .ren/vm/
cells/workstation/profiles/secrets.nix  <- test-vm profiles/secrets.nix, ONLY zfs-rpool-passphrase (logins stay in globals); hostPubkey from globals.hosts.<h>.sshHostPubkey (new option), master = jarvis-nopin-rage.pub only, age.identityPaths=/persist/etc/ssh/ssh_host_ed25519_key
cells/workstation/agenixRekey.nix      agenix-rekey.configure over cell.nixosConfigurations; root flake exposes `agenix-rekey` via new cell block (simple "agenixRekey")
secrets/generated/vm-zfs/zfs-rpool-passphrase.age + secrets/rekeyed/vm-zfs/7322449f...age
cells/workstation/flake.nix: + himmelblau 791372a (test-vm lock rev; main), follows nixpkgs
cells/workstation/profiles/layer-users-local.nix  <- test-vm, mechanical (user = host.userName, keyFiles secrets/generated/<host>/user-ssh-key.pub)
cells/workstation/profiles/auth-entra.nix + patches/himmelblau/0001-*.patch  <- test-vm, mechanical; pamServices minus greetd/swaylock (phase 4 re-adds)
cells/workstation/profiles/secrets.nix: + age.secrets.user-ssh-key generator (.pub committed); secrets/generated/vm-zfs/user-ssh-key.{age,pub} + rekeyed/vm-zfs/fd7d82c6...age
cells/common: globals-options + isVm/hasTpm/userName/homeDir/hashedPassword per host, user.uid; globals.nix hosts.vm-zfs (public throwaway hashes), userName/homeDir resolution
flake.nix: nixosConfigurations = server // workstation; devShells += workstation. colmenaHive unchanged (server only).

## invariants
osgiliath-unchanged: `nix eval --raw .#colmenaHive.toplevel.osgiliath.drvPath` == /nix/store/nxca0xf2iphm3qgg118vcavj5h85dxps-nixos-system-osgiliath-26.11pre-git.drv   last: /nix/store/nxca0xf2iphm3qgg118vcavj5h85dxps-nixos-system-osgiliath-26.11pre-git.drv @ 2026-09-02 (after phase-3 edits)
server-isolation: `nix eval --json .#x86_64-linux.server.nixosConfigurations.osgiliath --apply 'x: builtins.attrNames x' 2>/dev/null; jq -r '.nodes.root.inputs|keys[]' cells/server/flake.lock` must not gain lanzaboote/himmelblau/home-manager/cachyos   last: `disko utils`, osgiliath `config ? age || services ? himmelblau` = false @ 2026-09-02 (phase 3)

## blocked_on
(none)

## verified
1-eval: `nix eval --raw .#nixosConfigurations.vm-zfs.config.system.build.toplevel.drvPath` -> /nix/store/0pziad3hpwhw81fqbp8wgiq3kiz5ab8y-nixos-system-vm-zfs-26.11pre-git.drv; zfsUnlock.devices = {rpool={pcrBank=sha256}}; kernel 6.18.48 (stock)
1-build: `nix build .#nixosConfigurations.vm-zfs.config.system.build.toplevel` -> /nix/store/vh817lvmhz346j77srp7fxs8y936vr88-nixos-system-vm-zfs-26.11pre-git; `...diskoImages` -> /nix/store/8sic0flskqmk9q8r38q6nvl0x0vzb8gy-vm-zfs-disko-images (main.raw 20G); `ws-image` -> .ren/vm/vm-zfs.raw
1-boot (ws-vm-run, serial console):
  boot1: bootctl `Secure Boot: disabled (setup)`, TPM2 yes; passphrase prompt -> qwerty123; /boot/loader/keys/auto/{PK,KEK,db}.auth written; generate-sb-keys + prepare-sb-auto-enroll finished; systemctl --failed empty
  boot2: `Secure Boot: enabled (user)`, lanzastub 1.1.0; passphrase prompt; `mkzfscreds --devices rpool --print-pcr15` = 3ba11bda...7070 (fp 710afecb...7e61); sealed to /boot/zfs-unlock/rpool.cred (537 B)
  boot3: NO prompt. journal: `zfs-unlock: PCR extend for rpool (fingerprint: 710afecb...)` -> `TPM unlock for rpool` -> `Unlocked rpool` -> `Anti-replay PCR 15 extension`; PCR15 after = d8534895...92f9; keystatus available; / = rpool/local/root, /persist = rpool/safe/persist; /var/lib/sbctl/keys/db persisted; snapshot rpool/local/root@blank; --failed empty
2-eval: toplevel drv /nix/store/6snfbx3v78h5vadp6bbxs4jrfq9w6l29-nixos-system-vm-zfs-26.11pre-git.drv; zfsUnlock.passphraseFile=/run/agenix/zfs-rpool-passphrase; agenix-rekey.x86_64-linux = [edit-view generate rekey update-masterkeys]
2-secrets: `agenix generate` -> secrets/generated/vm-zfs/zfs-rpool-passphrase.age (git add before rekey or "rekeyFile doesn't exist"); `agenix rekey` -> rekeyed/vm-zfs/7322449f...; host pubkey captured via ssh-keyscan = ...IJEkHLFGCFphGyc0GGyxCENyE/762o1ZPOVa1Ar15ee5
2-activate (ws-switch + activate.sh in VM, gen mb1xv9pg...): agenix decrypted (48 B); zfs-key-sync: `rotating rpool to the agenix passphrase` -> `sealing credential for PCR 15 of the next boot` (expected PCR15 44d0cf49...5b23) -> `done`; /boot/zfs-unlock/rpool.cred 589 B; --failed empty
2-boot4 (FAIL, fixed): TPM unlock OK but `[agenix] identityPaths entry /etc/ssh/ssh_host_ed25519_key not present` -> agenixInstall failed, zfs-key-sync `no readable secret`. Cause: activation runs before impermanence binds /etc/ssh. Fix: age.identityPaths=[/persist/etc/ssh/ssh_host_ed25519_key].
2-boot5 (gen jsgwkdap...): `zfs-unlock: Unlocked rpool` (no prompt), agenix gen 1 decrypted at boot, `zfs load-key -n -L file:///run/agenix/zfs-rpool-passphrase rpool` = 1/1 verified, zfs-key-sync `already in sync`, --failed empty

## notes
- zfs-key-sync.service is gated on zfsUnlock.passphraseFile (null -> service absent); profiles/secrets.nix sets it. Pool passphrase qwerty123 is now ROTATED on the current image; agenix view / /run/agenix in the VM is the only copy.
- Not ported from test-vm secrets.nix: root-password/user-password/luks-passphrase/user-ssh-key (no runtime consumer here; logins come from globals; user-ssh-key -> phase 3 with layer-users-local), isPlayground dev-values, dellvis master identity.
- New host bootstrap: boot on disko key, `ssh-keyscan -t ed25519`, set globals.hosts.<h>.sshHostPubkey, `agenix generate && git add secrets && agenix rekey`, ws-switch. secrets.nix asserts the pubkey is non-null.
- ssh root@vm is prohibit-password; activation goes over serial console (ws-vm-run) until vmuser exists (phase 3).
- layer-kernel (CachyOS) NOT ported in phase 1: stock kernel + zfs. Needs nix-cachyos-kernel input + overlay in the workstation cell; do it in phase 1b or 4.
- VM logins (public, from test-vm AGENTS.md): root/onion, vmuser/Qwerty123! (no vmuser yet in phase 1); pool passphrase qwerty123. ssh -p 2222.
- sbctl not on the VM PATH (common/base.nix has no sbctl; test-vm base had it). Add to a workstation profile when needed.
- gpu-virtio sets WLR_* env + mesa; harmless without a desktop, kept so phase 4 does not re-port it.
- Scope: port ONLY the vm-zfs host (native zfs enc + pcr15). Do not port luksTpm / hardware-luks-tpm.nix.
- Runner (test-vm justfile; reproduce in cells/workstation): `just image` -> `just secureboot-reset` -> `just vm-run-secureboot` (lanzaboote 3-boot enrollment, OVMFFull varstore starts in Setup Mode) -> inside VM as root: `mkzfscreds --devices rpool --print-pcr15`, then `just seal-zfs-cred` (seal onto ESP). swtpm state in ./swtpm-state/; delete to re-enroll after a new image.
- Target: test VM only; later the basis for the dellvis laptop.
- utils.mkHome is broken upstream (bee.home); test-vm uses HM as a NixOS module via home-manager.users.<name>, so mkHome is not needed.
- globals-options was trimmed for the server; isVm/hasTpm/gpu/entra.*/user.* come back for workstations. Encrypted half already sets user.*/entra.*.
- test-vm secrets are agenix + agenix-rekey by host key; server uses colmena deployment.keys. Different mechanism, phase 2.
- test-vm profiles are {inputs, cell}: module -- port mechanically like the server ones.

## phase 3 result (2026-09-02)
- VM rebooted in agent pty (old qemu on /dev/pts/35 was unreachable — killed; root@blank rollback + /persist ZFS made this safe). TPM unlock silent, zfs-key-sync OK.
- activate.sh 559pw1mz…-vm-zfs-26.11pre-git → RC=0, /run/current-system points to it.
- systemctl --failed: empty. himmelblaud, himmelblaud-tasks, nscd, sshd active; 3 sockets in /var/run/himmelblaud/; hsm-pin + himmelblau.cache.db created; HTTP/2 to login.microsoftonline.com OK.
- vmuser ssh -p 2222 works (key: `agenix view secrets/generated/vm-zfs/user-ssh-key.age` — file path, no --host).
- Persist mounts: /persist/home/vmuser/.ssh, /var/lib/himmelblaud, /var/cache/himmelblaud created 0700/0755.
- Not tested: real Entra login (needs tenant user + interactive flow) — phase 4 candidate.
- Console fact: VM console lives in the pty of whoever ran ws-vm-run; tmux `nix-rensa` has no VM window. Root pw `onion` works on ttyS0.

## phase 4 progress (2026-09-02, paused)
- Ported: profiles/layer-session.nix (greetd+tuigreet from nixpkgs 0.11.1, NO tuigreet input), profiles/layer-compositor.nix (dwl-custom, somebar patch, HM as NixOS module; test-vm dwl-startup.nix dropped — /etc/dwl/startup was unreferenced), home/default.nix + home/desktop/* (foot, fuzzel, swaylock, mako, swayidle, swaybg, cliphist, avizo). coding-agents + copy-files NOT ported.
- flake.nix: + home-manager release-25.05 (follows nixpkgs), lock updated. auth-entra pamServices += swaylock only: greetd here is `substack login` with useDefaultRules=false -> himmelblau module fails on `account.unix` if greetd is listed (inherits himmelblau via login anyway).
- ws-vm-run: WS_DISPLAY=1 -> nixGL + virtio-vga-gl venus + GTK display + virtio keyboard/tablet, 8G memfd; default path unchanged. Devshell builds (SC2054 excluded).
- Eval OK; osgiliath drv unchanged (nxca0xf2...), server lock inputs still `disko utils`.
- Toplevel /nix/store/gyi0pk4vzkw6ma2r3zsyg0svh6ndbymz-nixos-system-vm-zfs-26.11pre-git activated via activate.sh RC=0 (--failed empty). greetd did not start on switch (needs boot / vt1 handoff); `systemctl stop getty@tty1; systemctl start greetd` -> active, but pgrep found no tuigreet a few seconds later -- CHECK journalctl -u greetd and the GTK window next. Likely a reboot is the honest test (vt=1 + XDG env at boot).
- VM is running in agent pty (proc_084571385aa6, WS_DISPLAY=1), root logged in on ttyS0; user key at $(cat .ren/vm/.userkey-path). Files staged, NOT committed.
- Next: reboot VM -> tuigreet on GTK window -> login vmuser/Qwerty123! -> dwl + somebar visible, foot on Ctrl+Shift+Return, `systemctl --user` mako/avizo/swayidle active, dwl-session-bridge active; then commit "workstation: phase 4 (desktop)" + state update. Still open: layer-kernel (CachyOS), real Entra login.

## Фаза 4 — итерация 3 (dwl-startup env)
- Логин через tuigreet → dwl работает (пользователь подтвердил).
- Проблема: avizo/swayidle не стартуют — ConditionEnvironment=WAYLAND_DISPLAY not met в user manager.
- Фикс: в dwl-startup перед `systemctl --user start dwl-session-bridge.service` добавлен
  `systemctl --user import-environment` + `dbus-update-activation-environment --systemd`
  для WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE (layer-compositor.nix).
- Пересборка toplevel: .ren/vm/phase4-build2.log (фон). Далее: nixos-rebuild switch в VM (ssh -p 2222),
  релогин, проверить `systemctl --user status avizo swayidle`.
- РЕЗУЛЬТАТ: toplevel rla3pv79... активирован (ACT_RC=0), релогин через tuigreet -> graphical-session.target,
  dwl-session-bridge, avizo, swayidle = active; --failed пусто; user env содержит WAYLAND_DISPLAY=wayland-0,
  XDG_SESSION_TYPE=wayland. Фаза 4 (greetd -> dwl -> HM user units) ЗАКРЫТА.
- Мелочь: XDG_CURRENT_DESKTOP не был в env (greetd его не ставит) -> dwl-startup теперь экспортирует `dwl` по умолчанию
  (нужно для xdg-desktop-portal). Не активировано в VM, проверить при следующем switch.
- Разлогин из VM без Alt-хоткеев (QEMU перехватывает Alt): root@serial `loginctl terminate-user vmuser`.

## Фаза 5 — layer-kernel (CachyOS) (2026-09-02)
- Источник: chaotic-cx/nyx (НЕ xddxdd/nix-cachyos-kernel как в test-vm — у него нет кэша под наш nixpkgs; nyx его pin == наш 34ab9907 → hash-совпадение, бинарный кэш nyx-cache.chaotic.cx). Оба репо живые (pushed 2026-09-02), nyx не archived.
- cells/workstation/flake.nix: + input chaotic = nyx@43fe0699 (follows nixpkgs). Комментарий: бампать вместе с nixpkgs, иначе локальная сборка ядра.
- nixosConfigurations.nix: `pkgs = inputs.pkgs.extend inputs.chaotic.overlays.default` (nixpkgs.overlays в модуле — no-op, mkSystem задаёт nixpkgs.pkgs).
- profiles/layer-kernel.nix: linuxPackages_cachyos (7.2.2) + zfs_cachyos, mkOverride 99; specialisation.safe (по PedroHLC/system-setup seat.nix): stock linuxPackages 6.18.48 + stock zfs, mkOverride 98/mkForce. Оба zfs = 2.4.4 → пул совместим. nix.settings += nyx substituter/key для гостя.
- Проверка: eval OK; dry-run toplevel c nyx substituter: kernel 20dxgk1x…-7.2.2, modules, zfs-all/zfs-user — все в "will be fetched"; из 207 "to build" тяжёлого нет (dwl, somebar, edge .deb, units). osgiliath drv nxca0xf2… не изменился, server lock всё ещё `disko utils`.
- Host-side: для сборки образа/toplevel на хосте нужны substituter+key nyx в nix.conf хоста или --option (в dry-run передавал через --option).
- Не сделано: реальный switch/reboot VM на CachyOS ядре + проверка boot entry "safe" в systemd-boot/lanzaboote меню (lanzaboote подписывает специализации тоже — проверить, что появляется второй UKI).

## Phase 5 — build (2026, cachyos kernel)
- vm-zfs toplevel builds: /nix/store/8580z4cp0xxrx4crb5ahkizikx2k05ly-nixos-system-vm-zfs-26.11pre-git
- kernel 7.2.2 + modules + zfs-all-2.4.4 fetched from nyx-cache.chaotic.cx (not rebuilt)
- host: ~/.config/nix/nix.conf now has nyx-cache substituter+key (nixq/ws-switch ignore flake nixConfig). /etc/nix/nix.conf untouched (no sudo).
- old no-cache build log: .ren/vm/phase5-build.nocache.log
- 5-activate: ws-switch -> 8580z4cp… ; activate.sh via serial console (root/onion; ssh+sudo -S is blocked by the agent tooling) RC=0; zfs-key-sync `already in sync`; --failed empty.
- 5-boot (reboot into gen 7, default entry): `uname -r` = 7.2.2-cachyos; /run/current-system = 8580z4cp…; Secure Boot: enabled (user); zfs-unlock: PCR extend (fp ea3106cb…41d1) -> TPM unlock -> Unlocked rpool -> Anti-replay; keystatus available; zfs module loaded; --failed empty.
- bootctl list: gen 7 `Linux 7.2.2-cachyos` (default) + `nixos-generation-7-specialisation-safe-…efi` = "lts-zfs-stable-26.11pre-git (Linux 6.18.48) (Generation 7-safe)" — lanzaboote signs specialisation UKIs too. Gen 6 (6.18.48) still in menu.
- Not tested: actually booting the `safe` entry (needs menu pick in serial console during boot) — optional.
- NEXT: phase 4 leftover (tuigreet/dwl on GTK display) or wrap up port.

## Phase 5 wrap-up — GTK display + XDG_CURRENT_DESKTOP (2026-09-02, manual by user)
- WS_DISPLAY=1 ws-vm-run: UKI -> TPM unlock -> tuigreet on GTK window -> vmuser login -> dwl + somebar, foot OK.
- foot env: WAYLAND_DISPLAY=wayland-0, XDG_SESSION_TYPE=wayland, XDG_CURRENT_DESKTOP was EMPTY.
  Cause: systemd.services.greetd.environment does not reach the PAM session; export in dwl-startup-with-bar
  only reaches the user manager / session bus, not dwl's own env (foot/fuzzel inherit from dwl).
  Fix: layer-compositor.nix dwl-session exports XDG_CURRENT_DESKTOP=dwl + XDG_SESSION_TYPE=wayland before exec dwl.
- Toplevel xbxgnxy23fhzidciv6ib5jw4swh75p1p activated via `sudo bash /mnt/share/.ren/vm/hb-cache/activate.sh <top>`
  (note: ws-switch only exports the closure; activate.sh must be run in the VM). Relogin -> XDG_CURRENT_DESKTOP=dwl. ✓
- bootctl list shows `safe` specialisation entry. Noise in xdg-open output (UPower DisplayDevice not activatable,
  MESA radv/vdrm on virtio-gpu) is VM/edge-specific, not a portal failure.
- Phase 5 CLOSED. Port test-vm -> nix-rensa complete except: real Entra login (needs tenant), booting `safe` entry (optional).
