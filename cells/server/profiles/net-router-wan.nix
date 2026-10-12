# Line-specific addressing (BNG, alias, announces) is in fiber-bypass.nix.
{
  inputs,
  cell,
}: {
  lib,
  config,
  pkgs,
  site,
  ...
}: let
  wan = config.router.ports.wan;
  lan = config.router.lanBridge;

  netStatus = pkgs.writeShellApplication {
    name = "net-status";
    runtimeInputs = with pkgs; [iproute2 gnugrep gawk curl coreutils];
    text = ''
      echo "== links =="
      ip -br link | grep -v '^lo'
      echo
      echo "== tether =="
      tether=""
      for d in /sys/class/net/*; do
        drv=$(basename "$(readlink -f "$d/device/driver" 2>/dev/null)" 2>/dev/null || true)
        case "$drv" in
          rndis_host|cdc_ether|cdc_ncm|cdc_mbim) tether=$(basename "$d") ;;
        esac
      done
      if [ -n "$tether" ]; then
        echo "tether up on $tether"
        ip -4 addr show "$tether" | grep inet || true
      else
        echo "no tether (plug the phone in, then enable USB tethering on it)"
      fi
      echo
      echo "== default routes, lowest metric wins =="
      ip -4 route show default || true
      ip -6 route show default || true
      echo
      echo "== egress =="
      v4=$(curl -4 -s --max-time 8 https://ifconfig.co || echo FAILED)
      echo "v4: $v4"
      v4dev=$(ip -4 route show default | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1); exit}')
      case "$v4" in
        FAILED)        echo "     -> no v4 egress" ;;
        ${site.wan.ip4}) echo "     -> static IP, out through the stick" ;;
        *)             echo "     -> out via $v4dev" ;;
      esac
      echo "v6: $(curl -6 -s --max-time 8 https://ifconfig.co || echo FAILED)"
    '';
  };
in {
  options.router.ports = {
    wan = lib.mkOption {type = lib.types.str;};
    lan = lib.mkOption {type = lib.types.listOf lib.types.str;};
  };

  config = {
    networking.useNetworkd = true;
    networking.useDHCP = false;
    networking.nftables.enable = true;
    # Dark interfaces are normal here (no fiber in the stick = no carrier).
    systemd.network.wait-online.enable = false;

    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
      # Multi-homed (stick 100, tether 2048): strict drops tether replies.
      "net.ipv4.conf.all.rp_filter" = 2;
      "net.ipv4.conf.default.rp_filter" = 2;
    };

    systemd.network.links."10-wan" = {
      matchConfig.OriginalName = wan;
      linkConfig.MACAddress = site.wan.mac;
    };

    systemd.services.wan-ring-buffers = {
      description = "Raise ring buffers on ${wan} (ixgbe default is 512)";
      after = ["sys-subsystem-net-devices-${wan}.device"];
      wantedBy = ["sys-subsystem-net-devices-${wan}.device"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.ethtool}/bin/ethtool -G ${wan} rx 4096 tx 4096";
      };
    };

    # Phone tether, matched by driver: USB NIC names follow the physical port.
    systemd.network.networks."40-tether" = {
      matchConfig = {
        Driver = ["rndis_host" "cdc_ether" "cdc_ncm" "cdc_mbim"];
        Type = "ether";
      };
      networkConfig.DHCP = "yes";
      dhcpV4Config.RouteMetric = 2048;
      ipv6AcceptRAConfig.RouteMetric = 2048;
      linkConfig.RequiredForOnline = false;
    };
    # Loaded up front: a cold plug must work with no other uplink.
    boot.kernelModules = ["usbnet" "rndis_host" "cdc_ether" "cdc_ncm"];

    services.resolved = {
      enable = true;
      settings.Resolve = {
        FallbackDNS = site.wan.dns6 ++ site.wan.dns4;
        LLMNR = "no";
        MulticastDNS = "no";
      };
    };

    networking.nat = {
      enable = true;
      externalInterface = wan;
      internalInterfaces = [lan];
    };

    # Else 22 opens on the WAN (public v6); br-lan is trusted, ygg0 opens it.
    services.openssh.openFirewall = false;

    networking.firewall = {
      enable = true;
      trustedInterfaces = [lan];
      # LAN clients hold public v6 addresses: drop unsolicited inbound.
      filterForward = true;
      # nftables rpfilter ignores the rp_filter sysctls.
      checkReversePath = "loose";

      # TorrServe on the Vontar: by port, its v6 privacy address rotates.
      extraForwardRules = ''
        iifname "${wan}" tcp dport 51413 accept comment "TorrServe BT peer port"
        iifname "${wan}" udp dport 51413 accept comment "TorrServe BT peer port (uTP/DHT)"
      '';
      # ONU management net.
      extraInputRules = ''iifname "${wan}" ip saddr 192.168.11.0/24 accept'';
    };

    environment.systemPackages = with pkgs; [
      netStatus
      mosh
      tcpdump
      ethtool
      iperf3
      inetutils
      mtr
      dnsutils
      curl
      tmux
      htop
      pciutils
      usbutils
    ];
  };
}
