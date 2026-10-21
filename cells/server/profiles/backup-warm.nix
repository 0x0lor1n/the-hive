# Warm backup: sanoid snapshots tank, a nightly oneshot copies photos and
# archive to `warm1` (one Barracuda, created by hand like `fast`). warm1 is
# imported only for the run and exported afterwards, so a dead or missing
# disk never blocks boot and a stray `rm -rf` on the host can't reach it.
#
# media is snapshotted (short undo window) but never copied: it can be
# re-downloaded, photos and archive can't.
#
# The stamp is written inside the run, not in ExecStartPost: warm1 is
# exported by then and its size/free would be unreadable.
{
  inputs,
  cell,
}: {
  config,
  pkgs,
  lib,
  ...
}: let
  pool = "warm1";
  # source dataset -> target under warm1
  copies = {
    "tank/photos" = "${pool}/photos";
    "tank/archive" = "${pool}/archive";
    # Service state (DBs, configs) on the NVMe pool: small, but the only copy.
    "fast/services" = "${pool}/services";
    # Hot tier (backup-hot.nix): imladris rpool/safe + the router's push.
    "tank/backups" = "${pool}/backups";
  };

  syncoid = "${pkgs.sanoid}/bin/syncoid";
  zfs = config.boot.zfs.package;
  zpool = "${zfs}/bin/zpool";
  textfileDir = "/var/lib/node_exporter/textfile";

  run = pkgs.writeShellScript "warm-backup" ''
    set -euo pipefail
    start=$(date +%s)

    # Already imported (a manual session): use it, leave it imported.
    if ${zpool} list -H ${pool} >/dev/null 2>&1; then
      owned=0
    else
      ${zpool} import -N ${pool}
      owned=1
    fi
    cleanup() { if [ "$owned" = 1 ]; then ${zpool} export ${pool}; fi; }
    trap cleanup EXIT

    # --no-sync-snap: send sanoid's snapshots, don't litter tank with
    # syncoid_* ones. --delete-target-snapshots: warm1 keeps the same
    # snapshots as tank, so sanoid's pruning bounds warm1 too. -w: the
    # router's datasets under tank/backups are raw-encrypted, no key here.
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (src: dst: ''
        echo "warm-backup: ${src} -> ${dst}"
        ${syncoid} -r --no-sync-snap --delete-target-snapshots --sendoptions=w ${src} ${dst}
      '')
      copies)}

    if [ "$(date +%d)" = 01 ]; then
      echo "warm-backup: monthly scrub of ${pool}"
      ${zpool} scrub -w ${pool}
    fi
    ${zpool} status -x ${pool}

    read -r size free < <(${zpool} list -Hp -o size,free ${pool})
    end=$(date +%s)
    mkdir -p ${textfileDir}
    tmp=$(mktemp -p ${textfileDir})
    cat >"$tmp" <<EOF
    # TYPE backup_last_success_seconds gauge
    backup_last_success_seconds{tier="warm"} $end
    # TYPE backup_last_duration_seconds gauge
    backup_last_duration_seconds{tier="warm"} $((end - start))
    # TYPE warm_pool_size_bytes gauge
    warm_pool_size_bytes $size
    # TYPE warm_pool_free_bytes gauge
    warm_pool_free_bytes $free
    EOF
    chmod 0644 "$tmp"
    mv "$tmp" ${textfileDir}/warm-backup.prom
  '';
in {
  services.sanoid = {
    enable = true;
    templates = {
      keep-long = {
        hourly = 0;
        daily = 14;
        monthly = 6;
        autosnap = true;
        autoprune = true;
      };
      keep-short = {
        hourly = 0;
        daily = 3;
        monthly = 0;
        autosnap = true;
        autoprune = true;
      };
      # Service state changes all day (DBs); hourly gives a 1h RPO.
      keep-services = {
        hourly = 24;
        daily = 14;
        monthly = 3;
        autosnap = true;
        autoprune = true;
      };
    };
    datasets = {
      "fast/services" = {
        useTemplate = ["keep-services"];
        recursive = true;
      };
      "tank/photos" = {
        useTemplate = ["keep-long"];
        recursive = true;
      };
      "tank/archive" = {
        useTemplate = ["keep-long"];
        recursive = true;
      };
      "tank/media" = {
        useTemplate = ["keep-short"];
        recursive = true;
      };
    };
  };

  systemd.services.warm-backup = {
    description = "Copy tank photos/archive/backups + fast/services snapshots to ${pool}";
    after = ["zfs.target" "sanoid.service"];
    path = [zfs pkgs.mbuffer pkgs.pv pkgs.lzop pkgs.coreutils];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = run;
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };

  systemd.timers.warm-backup = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*-*-* 03:00";
      Persistent = true;
      RandomizedDelaySec = "10m";
    };
  };
}
