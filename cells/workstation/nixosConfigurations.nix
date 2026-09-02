# Workstation hosts. Isolated from cells/server: a different cell flake with its
# own inputs (lanzaboote, mkcreds), never part of colmenaHive.
#
# test-vm port (.hermes/state/port-test-vm.md), phases 1-4: storage + boot,
# secrets, auth, desktop; phase 5: CachyOS kernel + "safe" fallback entry.
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
  # our nixpkgs pin equals nyx's lock.
  pkgs = inputs.pkgs.extend inputs.chaotic.overlays.default;
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
    ];

  # Hardware: exactly one per host. The playground VMs mount the host's flake
  # at /mnt/share over 9p, a real machine has no such thing.
  vmGuest = [
    p.platform-virtio
    p.gpu-virtio
    p.dev-9p-share
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
  # Native ZFS encryption behind a pre-unseal PCR 15 gate with anti-replay.
  # The rehearsal for dellvis.
  sevastopol = mkHost {
    hostKey = "sevastopol";
    base = workstation;
    hardware = vmGuest;
    encryption = zfsNative;
  };
}
