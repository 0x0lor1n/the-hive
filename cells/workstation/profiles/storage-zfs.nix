# ZFS support profile: enables ZFS, sets a stable per-host hostId, and
# creates any disko-declared dataset that is missing on an installed host.
{
  lib,
  config,
  host,
  pkgs,
  ...
}: let
  # Every zfs_fs dataset disko knows about, across all pools. disko itself only
  # runs at install time, so a dataset added to disks/<host>.nix later never
  # gets created -- but its fileSystems entry does, and the resulting failed
  # .mount drops the host into emergency mode (penrose, safe/srv/agents).
  # disko adds a pseudo dataset "__root" (the pool itself, _createFilesystem =
  # false) to every zpool -- it is not a child dataset and must be skipped.
  datasets = lib.concatMap (
    pool:
      map (d: {
        dataset = "${pool.name}/${d.name}";
        inherit (d) options;
      }) (lib.filter (d: d.type == "zfs_fs" && d.name != "__root") (lib.attrValues pool.datasets))
  ) (lib.attrValues config.disko.devices.zpool);

  mkCreate = d: let
    opts = lib.concatStringsSep " " (lib.mapAttrsToList (k: v: "-o ${lib.escapeShellArg "${k}=${v}"}") d.options);
  in ''
    if ! zfs list -H -o name ${lib.escapeShellArg d.dataset} >/dev/null 2>&1; then
      echo "creating missing dataset ${d.dataset}"
      zfs create -p ${opts} ${lib.escapeShellArg d.dataset}
    fi
  '';
in {
  # Create-only reconciliation: existing datasets and their properties are
  # never touched (no `zfs set`), so a pool whose keylocation was rotated to
  # prompt/TPM by zfs-key-sync is left alone. Runs after the pools are imported
  # (root pool: already in initrd) and before any local mount, which is where
  # the new dataset's legacy mount would otherwise fail.
  systemd.services.zfs-ensure-datasets = lib.mkIf (datasets != []) {
    description = "Create disko-declared ZFS datasets that are missing";
    wantedBy = ["local-fs-pre.target"];
    before = ["local-fs-pre.target"];
    after = ["zfs-import.target"];
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [pkgs.zfs];
    # `lib.attrValues` sorts by attr name, so a parent (safe/srv) always
    # precedes its children (safe/srv/agents); -p covers the rest.
    script = lib.concatMapStringsSep "\n" mkCreate datasets;
  };

  boot.supportedFilesystems = ["zfs"];

  # ZFS requires a stable 8-hex hostId. Derived from the host's own hostName,
  # so the disko-created pool's hostid matches at import time and no two hosts
  # share one -- that collision is exactly what ZFS multihost protection exists
  # to detect. Consequence: renaming a host orphans its pool (forceImportRoot).
  networking.hostId = lib.substring 0 8 (builtins.hashString "sha256" config.networking.hostName);

  # Default /dev/disk/by-id doesn't populate for virtio disks (no hardware
  # serial); the disko-created pool's vdev label uses by-partlabel, which
  # udev does populate. GPT partlabels exist on bare metal too, so this is
  # correct for both.
  boot.zfs.devNodes = "/dev/disk/by-partlabel";

  # VM only: disko's image builder leaves a mismatched /etc/hostid. On hardware
  # this disables the guard against a pool open elsewhere.
  boot.zfs.forceImportRoot = host.isVm;
  boot.kernelParams = lib.optionals host.isVm ["zfs_force=1"];

  # No autoScrub on the VMs (ephemeral, scrubs are noise). Real hardware
  # gets it -- a laptop pool that is never scrubbed silently rots.
  services.zfs.autoScrub = lib.mkIf (!host.isVm) {
    enable = true;
    interval = "monthly";
  };
}
