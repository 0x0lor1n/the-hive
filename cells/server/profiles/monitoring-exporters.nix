# Scrape targets for the Prometheus on minas-tirith (monitoring-server.nix).
# LAN-only: the firewall opens the ports on the single NIC, which sits on
# br-lan behind the router; nothing here is reachable from outside.
#
# boot-marker: the ATX watchdog has no journal hook, so a oneshot on every
# boot looks at the previous journal for "Reached target Shutdown" and writes
# the verdict into node_exporter's textfile dir. The dir is persisted in
# /state so the backup stamps survive a reboot (the boot marker is
# rewritten every boot regardless).
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
  bootMarker = pkgs.writeShellScript "boot-marker" ''
    set -euo pipefail
    prev=$(${pkgs.systemd}/bin/journalctl -b -1 -q -o cat 2>/dev/null || true)
    if [ -z "$prev" ]; then
      # First boot ever or journal lost: nothing to judge.
      unclean=0
    elif grep -q 'Reached target.*Shutdown' <<<"$prev"; then
      unclean=0
    else
      unclean=1
    fi
    # Don't rely on tmpfiles ordering: on a live switch tmpfiles-setup is not
    # re-run, so the dir may not exist yet.
    mkdir -p ${textfileDir}
    tmp=$(mktemp -p ${textfileDir})
    {
      echo '# HELP atx_watchdog_unclean_boot 1 if the previous boot ended without a clean shutdown.'
      echo '# TYPE atx_watchdog_unclean_boot gauge'
      echo "atx_watchdog_unclean_boot $unclean"
    } >"$tmp"
    chmod 0644 "$tmp"
    mv "$tmp" ${textfileDir}/boot-marker.prom
  '';
in {
  services.prometheus.exporters = {
    node = {
      enable = true;
      listenAddress = "0.0.0.0";
      enabledCollectors = [
        "systemd"
        "textfile"
      ];
      extraFlags = ["--collector.textfile.directory=${textfileDir}"];
      openFirewall = true;
    };

    # Pool capacity/health; node's zfs collector only gives ARC stats.
    zfs = {
      enable = true;
      listenAddress = "0.0.0.0";
      pools = [
        "tank"
        "fast"
        "rpool"
      ];
      openFirewall = true;
    };

    # SMART attributes (reallocated sectors, power-on hours, NVMe wear).
    # drivetemp in hwmon already covers temperature. The exporter's default
    # powermode-check=standby skips spun-down disks, same as smartd.
    smartctl = {
      enable = true;
      listenAddress = "0.0.0.0";
      maxInterval = "5m";
      openFirewall = true;
    };
  };

  environment.persistence."/state".directories = ["/var/lib/node_exporter"];
  systemd.tmpfiles.rules = ["d ${textfileDir} 0755 root root -"];

  systemd.services.boot-marker = {
    description = "Record whether the previous boot shut down cleanly";
    wantedBy = ["multi-user.target"];
    after = ["systemd-tmpfiles-setup.service"];
    before = ["prometheus-node-exporter.service"];
    path = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = bootMarker;
    };
  };
}
