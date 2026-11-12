# Workstation hosts. Isolated from cells/server: a different cell flake with its
# own inputs (lanzaboote, mkcreds), never part of colmenaHive.
#
# A host is composed from profiles in layers: storage + boot, secrets, auth,
# session/desktop, kernel (CachyOS with a stock "safe" specialisation).
{
  inputs,
  cell,
  system,
  ...
}: let
  inherit (inputs) utilsLib disko;
  # nyx overlay (linuxPackages_cachyos, zfs_cachyos) on top of the shared
  # instantiation. Applied here, not in a module: mkSystem sets nixpkgs.pkgs,
  # so nixpkgs.overlays inside the module system is ignored. Purely additive
  # attrs at this rev; the hashes match nyx's own CI (== cache hits) because
  # our nixpkgs pin equals nyx's lock. phoenix's overlay is additive too
  # (pkgs.phoenix, pkgs.withPhoenix); the browser profile applies withPhoenix
  # itself, since Phoenix's own module would go through the ignored path.
  pkgs =
    ((inputs.pkgs.extend inputs.chaotic.overlays.default).extend inputs.phoenix.overlays.default).extend xdpwOverlay;

  # xdg-desktop-portal-wlr snapshots toplevels before running the chooser, so
  # a window the chooser maps itself is "unknown". share-chooser
  # (profiles/layer-compositor.nix) answers a rotated output with a wl-mirror
  # window it just opened; the patch re-reads toplevels before matching.
  xdpwOverlay = _final: prev: {
    xdg-desktop-portal-wlr = prev.xdg-desktop-portal-wlr.overrideAttrs (old: {
      patches = (old.patches or []) ++ [./packages/xdg-desktop-portal-wlr/chooser-roundtrip.patch];
    });
  };

  globals = inputs.cells.common.globals;
  common = inputs.cells.common.profiles;
  p = cell.profiles;

  # Every installed host, regardless of class (same list as cells/server).
  foundation = [
    common.base
    common.storage-impermanence
    common.layer-users-root
  ];

  # The workstation shape: ZFS + ephemeral root, the local user, a Wayland
  # session (greetd -> dwl, home-manager as a NixOS module), Entra login,
  # CachyOS kernel with a stock-kernel "safe" boot entry.
  workstation =
    foundation
    ++ [
      p.layer-kernel
      p.storage-zfs
      p.storage-zfs-rollback
      # who logs in and with which roles (hive.accounts / hive.roleHolders)
      p.accounts
      # the local desktop user (break-glass next to Entra)
      p.layer-users-local
      # wheel + eval-time secrets cache for the account holding admin
      p.role-admin
      # Wayland session: seat/portal/greetd, then dwl + the user's home
      p.layer-session
      p.layer-compositor
      # Entra ID login via himmelblau
      p.auth-entra
      # the user's split keyboard follows them to every machine
      p.device-keyboard-ergohaven
      # firefox + Phoenix: system package (Entra users have no HM profile)
      p.browser-firefox
      # `vpn` over hive.tunnels; the tunnels come with their roles
      p.vpn
      # rootless docker for the accounts holding dev
      p.role-dev
      # vpn-w
      p.role-freelance
      # vpn-o, vpn-t
      p.role-employer
      # off-LAN ssh to the router over Yggdrasil, on demand via `vpn`
      p.ygg-client
      # 3 generations, weekly nh clean
      p.maintenance
      # pxpipe system unit + /etc/hosts alias, shared by every session's Hermes
      p.agent-proxy
      # /srv/the-hive: one checkout for both accounts, group hive via default ACL
      p.srv-the-hive
      # /srv/workspace: shared project clones (work/, projects/), both accounts write
      p.srv-workspace
      # /srv/agents: hermes skills + memories shared by both accounts, sessions stay per-user
      p.srv-agents
      # /srv/data: personal files (music/, documents/), not code
      p.srv-data
      # destyle: Qwen3-8B + LoRA на iGPU по требованию, 127.0.0.1:8080
      p.llm-destyle
      # `cpu-governor@<name>.service` for the powermenu's performance toggle
      p.cpu-governor
    ];

  # Hardware: exactly one per host.
  # Intel laptop, iGPU scanout (penrose's dGPU: render offload, gpu-intel).
  intelLaptop = [
    p.platform-baremetal
    p.gpu-intel
    p.laptop
    # the WD19TBS moves between both laptops: udev authorises it by
    # unique_id, kanshi `home` for the LG behind it
    p.device-dock-wd19tbs
  ];

  # HP ZBook Firefly 16 G10 (Raptor Lake, iGPU only, TB4 dock): the same
  # laptop shape plus what only this host needs (docker).
  raptorLaptop =
    intelLaptop
    ++ [
      p.host-elster
      p.device-dac-dawn-pro
      p.device-fingerprint-synaptics
      p.device-printer-office-hp
      p.device-dock-office-hp
    ];

  # Encryption + unlock; must match what the host's disk file created.
  zfsNative = [
    p.hardware-zfs-unlock # zfsUnlock: pre-unseal PCR 15 gate + anti-replay
    p.hardware-zfs-tpm # TPM2 initrd, mkzfscreds, zfs-key-sync
    p.hardware-secureboot # lanzaboote: signed UKIs, key auto-enrollment
    p.secrets # agenix: zfs-rpool-passphrase -> zfsUnlock.passphraseFile
  ];

  mkHost = {
    hostKey,
    base,
    hardware,
    encryption ? [],
    extraModules ? [],
  }: let
    host = globals.hosts.${hostKey};
  in
    utilsLib.mkSystem {
      ren = {
        inherit system pkgs disko;
      };

      imports = base ++ hardware ++ encryption ++ extraModules;

      # Lets every imported module read repo/host params without re-importing.
      # `host` is this host's entry only, so profiles cannot read another's.
      _module.args.globals = globals;
      _module.args.host = host;
      _module.args.inputs = inputs;

      disko.devices = utilsLib.collectDisks {${hostKey} = cell.disks.${hostKey};};

      networking.hostName = host.hostName;
      system.stateVersion = "24.11";
    };
in {
  # Dell Latitude 5580.
  penrose = mkHost {
    hostKey = "penrose";
    base = workstation;
    hardware = intelLaptop ++ [p.host-penrose p.device-battery-dell-ec p.device-gpu-quadro-m620 p.gaming-steam];
    encryption = zfsNative;
  };

  # HP ZBook Firefly 16 G10: the daily driver and the Entra machine. The whole
  # penrose config plus host-elster.
  elster = mkHost {
    hostKey = "elster";
    base = workstation;
    hardware = raptorLaptop;
    encryption = zfsNative;
  };
}
