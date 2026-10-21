# Hot backup tier on imladris: `tank/backups` is the landing zone for every
# copy that is not media. Nightly, rpool/safe is copied there locally; the
# router pushes its own rpool/{safe,logs} as user `backup` (backup-push.nix).
# warm-backup then carries tank/backups to warm1 with the rest.
#
# Datasets and the push user's rights, by hand on the live host (not disko,
# same as `fast`/`warm1`):
#
#   sudo zfs create -o mountpoint=none tank/backups
#   sudo zfs create -o mountpoint=none tank/backups/imladris
#   sudo zfs create -o mountpoint=none tank/backups/minas-tirith
#   sudo zfs allow -u backup create,mount,receive,destroy,rollback,snapshot,hold tank/backups/minas-tirith
#
# snapshot-age: newest sanoid snapshot per dataset, for SnapshotStale and
# the dashboard; received copies under tank/backups are listed too.
{
  inputs,
  cell,
}: {
  config,
  pkgs,
  lib,
  ...
}: let
  textfileDir = "/var/lib/node_exporter/textfile";
  zfs = config.boot.zfs.package;
  syncoid = "${pkgs.sanoid}/bin/syncoid";
  pushKey = inputs.self.outPath + "/secrets/generated/minas-tirith/push-backup-ssh-key.pub";

  writeProm = ''
    write_prom() {
      mkdir -p ${textfileDir}
      tmp=$(mktemp -p ${textfileDir})
      cat >"$tmp"
      chmod 0644 "$tmp"
      mv "$tmp" ${textfileDir}/"$1".prom
    }
  '';

  hotBackup = pkgs.writeShellScript "hot-backup" ''
    set -euo pipefail
    ${writeProm}
    start=$(date +%s)
    # Same flags as the push and warm tiers: sanoid's snapshots only, target
    # pruned along with the source.
    ${syncoid} -r --no-sync-snap --delete-target-snapshots --sendoptions=w \
      rpool/safe tank/backups/imladris/safe
    end=$(date +%s)
    write_prom hot-backup <<EOF
    # TYPE backup_last_success_seconds gauge
    backup_last_success_seconds{tier="hot"} $end
    # TYPE backup_last_duration_seconds gauge
    backup_last_duration_seconds{tier="hot"} $((end - start))
    EOF
  '';

  snapshotAge = pkgs.writeShellScript "snapshot-age" ''
    set -euo pipefail
    ${writeProm}
    ${zfs}/bin/zfs list -H -p -t snapshot -o name,creation -r \
        fast/services tank/photos tank/archive tank/media rpool/safe tank/backups \
      | awk -F'\t' '
          $1 ~ /@autosnap_/ {
            split($1, p, "@")
            if ($2 > max[p[1]]) max[p[1]] = $2
          }
          END {
            print "# TYPE zfs_snapshot_latest_seconds gauge"
            for (d in max) printf "zfs_snapshot_latest_seconds{dataset=\"%s\"} %d\n", d, max[d]
          }' \
      | write_prom snapshot-age
  '';
in {
  users.users.backup = {
    isSystemUser = true;
    group = "backup";
    # Needs a real shell for syncoid's remote commands; `zfs allow` above is
    # the boundary, `restrict` drops pty/forwarding.
    shell = pkgs.bash;
    openssh.authorizedKeys.keys = ["restrict ${lib.fileContents pushKey}"];
  };
  users.groups.backup = {};

  services.sanoid.datasets =
    {
      "rpool/safe" = {
        useTemplate = ["keep-services"];
        recursive = true;
      };
    }
    # Empty containers: warm-backup's `syncoid -r --no-sync-snap` fails on a
    # dataset with no snapshots. Not recursive: the received leaves below keep
    # their source's snapshots only.
    // lib.genAttrs ["tank/backups" "tank/backups/imladris" "tank/backups/minas-tirith"] (_: {
      useTemplate = ["keep-short"];
    });

  systemd.services.hot-backup = {
    description = "Copy rpool/safe snapshots to tank/backups";
    after = ["zfs.target" "sanoid.service"];
    path = [zfs pkgs.mbuffer pkgs.pv pkgs.lzop pkgs.coreutils];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = hotBackup;
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };
  # Off the hour: sanoid's hourly run would race it, and timers don't order.
  systemd.timers.hot-backup = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*-*-* 02:05";
      Persistent = true;
    };
  };

  systemd.services.snapshot-age = {
    description = "Newest sanoid snapshot per dataset, for node_exporter";
    path = [pkgs.coreutils pkgs.gawk];
    serviceConfig.Type = "oneshot";
    serviceConfig.ExecStart = snapshotAge;
  };
  systemd.timers.snapshot-age = {
    wantedBy = ["timers.target"];
    timerConfig.OnCalendar = "*:0/15";
  };
}
