# Off-LAN ssh to minas-tirith over Yggdrasil, and through it to the LAN hosts.
# yggstack is userspace: no TUN, so the laptop gets no routable ygg address and
# accepts nothing inbound. No key configured: a fresh node identity per start.
# The router's address lives only in the encrypted globals.
{
  pkgs,
  lib,
  globals,
  host,
  ...
}: let
  router = globals.hosts.minas-tirith.yggAddress;
  port = 2201;
  conf = pkgs.writeText "yggstack.json" (builtins.toJSON {
    Peers = import ../../common/__yggdrasil-peers.nix;
    MulticastInterfaces = [];
    AdminListen = "none";
    NodeInfoPrivacy = true;
  });
in
  lib.mkIf (router != null) {
    systemd.services.yggstack = {
      description = "Yggdrasil userspace tunnel to minas-tirith ssh";
      wantedBy = ["multi-user.target"];
      wants = ["network-online.target"];
      after = ["network-online.target"];
      serviceConfig = {
        ExecStart = "${lib.getExe' pkgs.yggstack "yggstack"} -useconffile ${conf} -local-tcp 127.0.0.1:${toString port}:[${router}]:22";
        DynamicUser = true;
        Restart = "always";
        RestartSec = 10;
      };
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
