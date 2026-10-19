# TorrServer (MatriX): streams torrents to the TV boxes' TorrServe/NUM/Kodi,
# fetching only the pieces being played. Web UI and API on :8090, LAN only.
#
# State (settings + torrent list, a few MB) sits on its own dataset
# (disks/imladris.nix) so it moves to another pool with one zfs send.
# The piece cache is RAM: CacheSize below, nothing written to disk.
#
# Settings live in TorrServer's own DB and stay editable in the web UI; the
# keys in `pinned` are re-applied on every start, everything else is the UI's.
{
  inputs,
  cell,
}: {
  pkgs,
  lib,
  ...
}: let
  webPort = 8090;
  peerPort = 42000;
  stateDir = "/var/lib/torrserver";
  pinned = {
    CacheSize = 4 * 1024 * 1024 * 1024;
    PeersListenPort = peerPort;
    UseDisk = false;
  };
  api = "http://127.0.0.1:${toString webPort}/settings";
  applyPinned = pkgs.writeShellScript "torrserver-pin-settings" ''
    set -eu
    PATH=${lib.makeBinPath [pkgs.curl pkgs.jq pkgs.coreutils]}
    for _ in $(seq 30); do
      cur=$(curl -fsS -X POST -d '{"action":"get"}' ${api}) && break
      sleep 1
    done
    [ -n "''${cur:-}" ] || { echo "torrserver API not up" >&2; exit 1; }
    want=$(jq -c --argjson p '${builtins.toJSON pinned}' '. + $p' <<< "$cur")
    [ "$want" = "$(jq -c . <<< "$cur")" ] && exit 0
    curl -fsS -X POST -d "{\"action\":\"set\",\"sets\":$want}" ${api}
    echo "torrserver: pinned settings re-applied"
  '';
in {
  users.users.torrserver = {
    isSystemUser = true;
    group = "torrserver";
    home = stateDir;
  };
  users.groups.torrserver = {};

  systemd.services.torrserver = {
    description = "TorrServer";
    wantedBy = ["multi-user.target"];
    wants = ["network-online.target"];
    after = ["network-online.target"];
    unitConfig.RequiresMountsFor = stateDir;
    # Upstream unit: return freed heap to the kernel promptly.
    environment.GODEBUG = "madvdontneed=1";
    serviceConfig = {
      ExecStart = "${lib.getExe' pkgs.torrserver "torrserver"} --port ${toString webPort} --path ${stateDir}";
      ExecStartPost = applyPinned;
      User = "torrserver";
      Group = "torrserver";
      Restart = "on-failure";
      LimitNOFILE = 65536;
      # The dataset root is the mountpoint, root-owned from `zfs create`.
      # StateDirectory chowns it on every start, after RequiresMountsFor.
      StateDirectory = "torrserver";
      StateDirectoryMode = "0750";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
  };

  networking.firewall = {
    # Peers from anywhere; minas-tirith forwards 42000 here (net-router-wan.nix).
    allowedTCPPorts = [peerPort];
    allowedUDPPorts = [peerPort];
    # Web UI/API: the LAN only.
    extraCommands = ''
      iptables -A nixos-fw -p tcp -s 192.168.10.0/24 --dport ${toString webPort} -j nixos-fw-accept
    '';
    extraStopCommands = ''
      iptables -D nixos-fw -p tcp -s 192.168.10.0/24 --dport ${toString webPort} -j nixos-fw-accept || true
    '';
  };
}
