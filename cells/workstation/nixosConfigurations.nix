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
    ((inputs.pkgs.extend inputs.chaotic.overlays.default).extend inputs.phoenix.overlays.default).extend evdiOverlay;

  # evdi (DisplayLink DRM shim, host-elster) at the nixpkgs pin is 1.14.15 and
  # does not compile against 7.x: DRM renamed `drm_atomic_state` to
  # `drm_atomic_commit` in the plane helpers. Upstream fixed it in v1.15.1
  # (2026-09-15). Overriding the package inside both kernel sets keeps the
  # kernels themselves untouched (same drvs, nyx cache hits); only elster's
  # closure pulls evdi in. Drop once nixpkgs carries >= 1.15.1.
  evdiOverlay = final: prev: let
    bump = kp:
      kp.extend (_: kprev: {
        evdi = kprev.evdi.overrideAttrs (_old: rec {
          version = "1.15.1";
          src = final.fetchFromGitHub {
            owner = "DisplayLink";
            repo = "evdi";
            tag = "v${version}";
            hash = "sha256-3g6OETXJSf6AScJ2K9F67mPlh3Wpi20Yq+f+xe78p9Y=";
          };
          # nixpkgs' prePatch stubs out the Makefile's /etc/os-release read;
          # 1.15.x no longer has it, and --replace-fail aborts on a miss.
          prePatch = "";
        });
      });
  in {
    linuxPackages_cachyos = bump prev.linuxPackages_cachyos;
    linuxPackages = bump prev.linuxPackages;
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
      # the local desktop user (break-glass next to Entra)
      p.layer-users-local
      # Wayland session: seat/portal/greetd, then dwl + the user's home
      p.layer-session
      p.layer-compositor
      # Entra ID login via himmelblau
      p.auth-entra
      # the user's split keyboard follows them to every machine
      p.input-vial
      # firefox + Phoenix: system package (Entra users have no HM profile)
      p.browser-firefox
      # the three VPN tunnels as system units, secrets in /run/agenix
      p.vpn
      # 3 generations, weekly nh clean
      p.maintenance
      # pxpipe system unit + /etc/hosts alias, shared by every session's Hermes
      p.agent-proxy
      # /srv/the-hive: one checkout for both accounts, dotfiles/ group-writable
      p.srv-the-hive
      # /srv/workspace: shared project clones (work/, projects/), both accounts write
      p.srv-workspace
      # destyle: Qwen3-8B + LoRA на iGPU по требованию, 127.0.0.1:8080
      p.llm-destyle
      # `cpu-governor@<name>.service` for the powermenu's performance toggle
      p.cpu-governor
    ];

  # Hardware: exactly one per host. The playground VMs mount the host's flake
  # at /mnt/share over 9p, a real machine has no such thing.
  vmGuest = [
    p.platform-virtio
    p.gpu-virtio
    p.dev-9p-share
  ];

  # Intel laptop, iGPU only (the dGPU is powered down in gpu-intel).
  intelLaptop = [
    p.platform-baremetal
    p.gpu-intel
    p.laptop
  ];

  # HP ZBook Firefly 16 G10 (Raptor Lake, iGPU only, TB4 dock): the same
  # laptop shape plus what only this host needs (docker, DisplayLink).
  raptorLaptop = intelLaptop ++ [p.host-elster];

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
      # Only consumed by the disko image builder.
      disko.memSize = 4096;
      # nixpkgs >= 2026-08 vmTools requires `kernel.target`, but disko (through
      # master ff8702b) passes an aggregateModules buildEnv as `kernel`, which
      # has none. The buildEnv still symlinks bzImage from the real kernel, so
      # naming the image explicitly restores the old behaviour. Drop once disko
      # passes `kernelModules` instead.
      disko.imageBuilder.pkgs =
        pkgs
        // {
          vmTools = pkgs.vmTools.override {kernelImage = "bzImage";};
        };

      networking.hostName = host.hostName;
      system.stateVersion = "24.11";
    };
in {
  # QEMU rehearsal: native ZFS encryption behind a pre-unseal PCR 15 gate with
  # anti-replay, Secure Boot, impermanence.
  sevastopol = mkHost {
    hostKey = "sevastopol";
    base = workstation;
    hardware = vmGuest;
    encryption = zfsNative;
  };

  # Dell Latitude 5580: what sevastopol rehearsed, on the real disk. Same base
  # and encryption stack, only the hardware list differs.
  penrose = mkHost {
    hostKey = "penrose";
    base = workstation;
    hardware = intelLaptop;
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
