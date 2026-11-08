# The home end of osgiliath's telemetry (telemetry-osgiliath.nix holds the
# VPS end): the raw access log is pulled here nightly over ygg, and this is
# where it may be studied. The VPS keeps 14 days; this keeps everything,
# in rpool/logs/hisilome: no snapshots, no backup, quota-capped like the
# IDS output next to it. `zfs create -o mountpoint=legacy -o quota=20G
# rpool/logs/hisilome` once on the live host before deploying (same hand
# step as logs/prometheus).
#
# Pull, never push: home dials the VPS, the VPS holds no address of home.
# The key is agenix-generated; the .pub lands in secrets/generated/ and is
# what osgiliath authorises, forced to one rsync --sender. `agenix generate
# && agenix rekey` before the first eval of either host.
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
  osgiliathYgg = "201:f885:7585:1739:35f4:1185:b21e:967d";
  dest = "/var/log/hisilome";
  textfileDir = "/var/lib/node_exporter/textfile";

  pull = pkgs.writeShellScript "log-pull-osgiliath" ''
    set -euo pipefail
    start=$(date +%s)
    # The live file is appended to between runs; rotated files are immutable
    # once compressed. --no-perms etc.: the VPS's nginx:nginx 0640 means
    # nothing here. No --delete: the VPS forgets after 14 days, home does not.
    ${pkgs.rsync}/bin/rsync -rt --no-perms --no-owner --no-group --chmod=F0640 \
      -e "${pkgs.openssh}/bin/ssh -i ${config.age.secrets.log-pull-ssh-key.path} \
          -o IdentitiesOnly=yes -o BatchMode=yes" \
      "logpull@[${osgiliathYgg}]:/var/log/nginx/" "${dest}/"
    end=$(date +%s)
    mkdir -p ${textfileDir}
    tmp=$(mktemp -p ${textfileDir})
    cat >"$tmp" <<EOF
    # TYPE logpull_last_success_seconds gauge
    logpull_last_success_seconds{source="osgiliath"} $end
    # TYPE logpull_last_duration_seconds gauge
    logpull_last_duration_seconds{source="osgiliath"} $((end - start))
    EOF
    chmod 0644 "$tmp"
    mv "$tmp" ${textfileDir}/log-pull.prom
  '';
in {
  age.secrets.log-pull-ssh-key.generator.script = {
    pkgs,
    lib,
    file,
    ...
  }: ''
    tmp=$(${pkgs.coreutils}/bin/mktemp -d)
    trap "${pkgs.coreutils}/bin/rm -rf '$tmp'" EXIT
    ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -N "" \
      -C "minas-tirith log pull from osgiliath (agenix-generated)" -f "$tmp/key" >/dev/null
    ${pkgs.coreutils}/bin/cp "$tmp/key.pub" \
      ${lib.escapeShellArg (lib.removeSuffix ".age" file + ".pub")}
    ${pkgs.coreutils}/bin/cat "$tmp/key"
  '';

  programs.ssh.knownHosts.${osgiliathYgg}.publicKey = globals.hosts.osgiliath.sshHostPubkey;

  # nofail: a missing dataset must not drop the router into emergency mode;
  # RequiresMountsFor below then fails the pull instead of filling /.
  fileSystems.${dest} = {
    device = "rpool/logs/hisilome";
    fsType = "zfs";
    options = ["nofail"];
  };

  systemd.services.log-pull-osgiliath = {
    description = "Pull the hisilo.me access log from osgiliath over ygg";
    after = ["network-online.target" "yggdrasil.service"];
    wants = ["network-online.target"];
    unitConfig.RequiresMountsFor = [dest];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pull;
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };
  systemd.timers.log-pull-osgiliath = {
    wantedBy = ["timers.target"];
    # After the VPS's 00:00 logrotate and before the 02:30 hot backup.
    timerConfig = {
      OnCalendar = "*-*-* 01:30";
      RandomizedDelaySec = "10m";
      Persistent = true;
    };
  };
}
