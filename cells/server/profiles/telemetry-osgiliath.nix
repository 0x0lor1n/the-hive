# What osgiliath tells home, and the one way home reads from it.
#
# Metrics: the hisilome module's node + nginxlog exporters bound to the ygg
# address only (metrics.nix in the hisilome repo); ygg0 opens the two ports
# to the whole mesh. Deliberately no source filter: an allowlist would put
# the home ygg address on the VPS, and osgiliath must stay blind to home
# (same rule as 22 in ygg-osgiliath.nix). What leaks to a mesh stranger who
# finds the ports: load, status counts per page, listener counts. No
# addresses, no agents.
#
# Logs: raw access log on the box, rotated daily, 14 days (the colophon says
# so). minas-tirith PULLS it over ygg (log-pull-osgiliath.nix) as user
# `logpull` with one agenix-generated key whose forced command only ever
# serves `rsync --server --sender` of that directory: no shell, no pty, no
# forwarding, nothing writable. This is the "one read-only key" exception to
# "nothing on the mesh may log in".
{
  inputs,
  cell,
}: {
  config,
  lib,
  pkgs,
  ...
}: let
  yggAddr = "201:f885:7585:1739:35f4:1185:b21e:967d";
  logDir = "/var/log/nginx";
  pullKey = inputs.self.outPath + "/secrets/generated/minas-tirith/log-pull-ssh-key.pub";

  # rrsync in ten lines: the client's exact server command, or nothing.
  # The flag word varies with client options (-logDtpre.iLsfxCIvu and the
  # like), so the shape is checked, not the letters: four words, the second
  # a single dash-flag, the last two the directory.
  serveLogs = pkgs.writeShellScript "serve-hisilome-logs" ''
    set -eu
    # shellcheck disable=SC2086
    set -- ''${SSH_ORIGINAL_COMMAND:-}
    case "$#:''${1:-}:''${2:-}:''${3:-}:''${4:-}:''${5:-}" in
      "6:rsync:--server:--sender:-"[A-Za-z.]*":.")
        [ "''${6:-}" = "${logDir}/" ] || { echo "logpull: ${logDir}/ only" >&2; exit 1; }
        exec ${pkgs.rsync}/bin/rsync --server --sender "$4" . "${logDir}/" ;;
      *)
        echo "logpull: only rsync --server --sender of ${logDir}/ is allowed" >&2
        exit 1 ;;
    esac
  '';
in {
  services.hisilome = {
    accessLog.enable = true;
    metrics = {
      enable = true;
      listenAddress = "[${yggAddr}]";
    };
  };

  networking.firewall.interfaces.ygg0.allowedTCPPorts = [
    config.services.hisilome.metrics.nodePort
    config.services.hisilome.metrics.nginxlogPort
  ];

  # The nginx module's default is weekly x 26: half a year of raw addresses
  # on a public box. Daily, 14 kept, compressed from the second day; the
  # exporter follows the live file by name (ReOpen) so a rotation is a
  # moment of nothing, not a loss.
  services.logrotate.settings.nginx = {
    frequency = "daily";
    rotate = 14;
  };

  users.users.logpull = {
    isSystemUser = true;
    group = "logpull";
    shell = pkgs.bash;
    # Read access to the 0750 nginx:nginx log dir; nothing else is group nginx.
    extraGroups = [config.services.nginx.group];
    openssh.authorizedKeys.keys = [
      ''restrict,command="${serveLogs}" ${lib.fileContents pullKey}''
    ];
  };
  users.groups.logpull = {};
}
