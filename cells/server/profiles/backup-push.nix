# Hot backup tier, router side: sanoid snapshots rpool/{safe,logs}, a nightly
# oneshot pushes them raw (`-w`, still encrypted, no key on the far side) to
# imladris tank/backups/minas-tirith as user `backup` (backup-hot.nix holds
# that end: account, `restrict`ed key, `zfs allow`).
#
# Key: agenix-rekey generator; the .pub lands in secrets/generated/ and is
# what imladris authorises. `agenix generate && agenix rekey` before the
# first eval of either host.
{
  inputs,
  cell,
}: {
  config,
  pkgs,
  lib,
  globals,
  ...
}: let
  imladris = "192.168.10.10";
  textfileDir = "/var/lib/node_exporter/textfile";
  zfs = config.boot.zfs.package;
  syncoid = "${pkgs.sanoid}/bin/syncoid";
  copies = {
    "rpool/safe" = "tank/backups/minas-tirith/safe";
    "rpool/logs" = "tank/backups/minas-tirith/logs";
  };

  push = pkgs.writeShellScript "hot-backup" ''
    set -euo pipefail
    start=$(date +%s)
    # --no-privilege-elevation: `backup` has no sudo, `zfs allow` covers it.
    # --compress=none: 10G LAN, and imladris's `backup` has no lzop/mbuffer.
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (src: dst: ''
        echo "hot-backup: ${src} -> ${imladris}:${dst}"
        ${syncoid} -r --no-sync-snap --delete-target-snapshots --sendoptions=w \
          --no-privilege-elevation --compress=none \
          --sshkey ${config.age.secrets.push-backup-ssh-key.path} \
          ${src} backup@${imladris}:${dst}
      '')
      copies)}
    end=$(date +%s)
    mkdir -p ${textfileDir}
    tmp=$(mktemp -p ${textfileDir})
    cat >"$tmp" <<EOF
    # TYPE backup_last_success_seconds gauge
    backup_last_success_seconds{tier="hot"} $end
    # TYPE backup_last_duration_seconds gauge
    backup_last_duration_seconds{tier="hot"} $((end - start))
    EOF
    chmod 0644 "$tmp"
    mv "$tmp" ${textfileDir}/hot-backup.prom
  '';
in {
  # Custom generator: agenix's built-in ssh-ed25519 writes no .pub
  # (same as user-ssh-key in cells/workstation/profiles/secrets.nix).
  age.secrets.push-backup-ssh-key.generator.script = {
    pkgs,
    lib,
    file,
    ...
  }: ''
    tmp=$(${pkgs.coreutils}/bin/mktemp -d)
    trap "${pkgs.coreutils}/bin/rm -rf '$tmp'" EXIT
    ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -N "" \
      -C "minas-tirith hot-backup push (agenix-generated)" -f "$tmp/key" >/dev/null
    ${pkgs.coreutils}/bin/cp "$tmp/key.pub" \
      ${lib.escapeShellArg (lib.removeSuffix ".age" file + ".pub")}
    ${pkgs.coreutils}/bin/cat "$tmp/key"
  '';

  programs.ssh.knownHosts.${imladris}.publicKey = globals.hosts.imladris.sshHostPubkey;

  services.sanoid = {
    enable = true;
    templates = {
      keep-services = {
        hourly = 24;
        daily = 14;
        monthly = 3;
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
    };
    datasets = {
      "rpool/safe" = {
        useTemplate = ["keep-services"];
        recursive = true;
      };
      "rpool/logs" = {
        useTemplate = ["keep-short"];
        recursive = true;
      };
    };
  };

  systemd.services.hot-backup = {
    description = "Push rpool/{safe,logs} snapshots to imladris";
    after = ["zfs.target" "sanoid.service" "network-online.target"];
    wants = ["network-online.target"];
    path = [zfs pkgs.openssh pkgs.coreutils];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = push;
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };
  systemd.timers.hot-backup = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*-*-* 02:30";
      Persistent = true;
    };
  };
}
