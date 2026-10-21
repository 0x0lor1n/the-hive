# Jellyfin off-LAN for the phone: imladris has no yggdrasil node, so the
# router (already the ygg junction) relays ygg0:8096 -> imladris:8096 with
# systemd-socket-proxyd. Plain TCP relay, websockets included; Jellyfin sees
# every ygg client as 192.168.10.1. The WAN gets nothing: the port opens on
# ygg0 only (same shape as Grafana/ntfy in monitoring-server.nix). The socket
# is activated on first connect, the proxy exits after 10 min idle.
{
  inputs,
  cell,
}: {
  config,
  pkgs,
  ...
}: let
  port = 8096;
  upstream = "192.168.10.10";
in {
  systemd.sockets.jellyfin-ygg-proxy = {
    description = "Jellyfin relay over yggdrasil (socket)";
    wantedBy = ["sockets.target"];
    listenStreams = ["[::]:${toString port}"];
    socketConfig = {
      BindIPv6Only = "both";
      NoDelay = true;
    };
  };

  systemd.services.jellyfin-ygg-proxy = {
    description = "Jellyfin relay over yggdrasil";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig = {
      ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd --exit-idle-time=10min ${upstream}:${toString port}";
      DynamicUser = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
      RestrictAddressFamilies = ["AF_INET" "AF_INET6"];
    };
  };

  networking.firewall.interfaces.ygg0.allowedTCPPorts = [port];
}
