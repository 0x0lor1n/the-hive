# Off-LAN access over Yggdrasil: ssh to minas-tirith and through it to the LAN
# hosts, the router's web UIs on ygg0, and anything else on the mesh (osgiliath's
# site at its ygg address) straight from the browser/curl. Real yggdrasil with a
# TUN, so the laptop gets a routable 2xx: address; the firewall accepts nothing
# inbound on it. No key configured: a fresh node identity per start. The
# router's address lives only in the encrypted globals. Off by default:
# `vpn up yggdrasil` / vpnmenu (vpn.nix), no peers contacted until then.
{
  lib,
  globals,
  host,
  ...
}: let
  router = globals.hosts.minas-tirith.yggAddress;
in
  lib.mkIf (router != null) {
    hive.tunnels.yggdrasil = "yggdrasil.service";

    services.yggdrasil = {
      enable = true;
      settings = {
        IfName = "ygg0";
        # Same as the router: big segments fragment into many QUIC packets on
        # the mobile path.
        IfMTU = 1280;
        NodeInfoPrivacy = true;
        # Public peers only; never announce on the local LAN/WiFi.
        MulticastInterfaces = [];
        Peers = import ../../common/__yggdrasil-peers.nix;
      };
    };

    # The module wires the unit into multi-user.target; it's a tunnel here,
    # flipped on demand.
    systemd.services.yggdrasil.wantedBy = lib.mkForce [];

    # Nothing listens for the mesh; keep the default-deny on ygg0 explicit.
    networking.firewall.interfaces.ygg0 = {
      allowedTCPPorts = [];
      allowedUDPPorts = [];
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
        HostName ${router}
        HostKeyAlias minas-tirith
      Host imladris-ygg
        HostName 192.168.10.10
        HostKeyAlias imladris
        ProxyJump minas-tirith-ygg
    '';
  }
