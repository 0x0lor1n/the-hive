# Off-LAN ssh to minas-tirith over Yggdrasil, and through it to the LAN hosts,
# plus the web UIs the router serves on ygg0 (webPorts, on localhost).
# yggstack is userspace: no TUN, so the laptop gets no routable ygg address and
# accepts nothing inbound. No key configured: a fresh node identity per start.
# The router's address lives only in the encrypted globals. Off by default:
# `vpn up yggdrasil` / vpnmenu (vpn.nix), no peers contacted until then.
{
  pkgs,
  lib,
  globals,
  host,
  ...
}: let
  router = globals.hosts.minas-tirith.yggAddress;
  port = 2201;
  # localhost:<port> -> the router's ygg0:<port>: Grafana is served there, Jellyfin
  # and Immich are relayed on to imladris (server ygg-relay.nix). Same port on
  # both ends, so the LAN and ygg URLs differ only in the host.
  webPorts = {
    grafana = 3000;
    immich = 2283;
    jellyfin = 8096;
  };
  forwards =
    ["127.0.0.1:${toString port}:[${router}]:22"]
    ++ map (p: "127.0.0.1:${toString p}:[${router}]:${toString p}") (builtins.attrValues webPorts);
  conf = pkgs.writeText "yggstack.json" (builtins.toJSON {
    Peers = import ../../common/__yggdrasil-peers.nix;
    MulticastInterfaces = [];
    AdminListen = "none";
    NodeInfoPrivacy = true;
  });
in
  # The VM has no user-ssh-key and no `vpn` to start it with.
  lib.mkIf (router != null && !host.isVm) {
    hive.tunnels.yggdrasil = "yggstack.service";

    systemd.services.yggstack = {
      description = "Yggdrasil userspace tunnel to minas-tirith ssh";
      wants = ["network-online.target"];
      after = ["network-online.target"];
      serviceConfig = {
        ExecStart = "${lib.getExe' pkgs.yggstack "yggstack"} -useconffile ${conf} ${lib.concatMapStringsSep " " (f: "-local-tcp ${f}") forwards}";
        DynamicUser = true;
        Restart = "always";
        RestartSec = 10;
      };
    };

    # zsh completes ssh hosts from ~/.ssh/config and known_hosts, never from
    # /etc/ssh/ssh_config; listing the aliases on the existing pins makes them
    # completable. Verification still goes through HostKeyAlias.
    programs.ssh.knownHosts = {
      minas-tirith.hostNames = ["minas-tirith-ygg"];
      imladris.hostNames = ["imladris-ygg"];
    };

    programs.ssh.extraConfig = ''
      Host minas-tirith-ygg imladris-ygg
        User ${host.userName}
        IdentityFile /run/agenix/user-ssh-key
        IdentitiesOnly yes
      Host minas-tirith-ygg
        HostName 127.0.0.1
        Port ${toString port}
        HostKeyAlias minas-tirith
      Host imladris-ygg
        HostName 192.168.10.10
        HostKeyAlias imladris
        ProxyJump minas-tirith-ygg
    '';
  }
