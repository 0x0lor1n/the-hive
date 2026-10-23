# imladris web UIs off-LAN for the phone: imladris has no yggdrasil node, so
# the router (already the ygg junction) relays ygg0:<port> -> imladris:<port>
# with systemd-socket-proxyd. Plain TCP relay, websockets included; the
# service sees every ygg client as 192.168.10.1. The WAN gets nothing: the
# ports open on ygg0 only (same shape as Grafana/ntfy in
# monitoring-server.nix). Each socket is activated on first connect, its proxy
# exits after 10 min idle.
{
  inputs,
  cell,
}: {
  pkgs,
  lib,
  ...
}: let
  upstream = "192.168.10.10";
  relays = {
    jellyfin = 8096;
    immich = 2283;
  };
in {
  systemd.sockets = lib.mapAttrs' (svc: port:
    lib.nameValuePair "${svc}-ygg-proxy" {
      description = "${svc} relay over yggdrasil (socket)";
      wantedBy = ["sockets.target"];
      listenStreams = ["[::]:${toString port}"];
      socketConfig = {
        BindIPv6Only = "both";
        NoDelay = true;
      };
    })
  relays;

  systemd.services = lib.mapAttrs' (svc: port:
    lib.nameValuePair "${svc}-ygg-proxy" {
      description = "${svc} relay over yggdrasil";
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
    })
  relays;

  networking.firewall.interfaces.ygg0.allowedTCPPorts = builtins.attrValues relays;
}
