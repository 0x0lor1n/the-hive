# What the Salt Fiber Box would do: WAN addressing + the two BNG announcements
# (salt-fiber-bypass post, SALT-WAS110-NOTES).
{
  inputs,
  cell,
}: {
  config,
  pkgs,
  site,
  ...
}: let
  wan = config.router.ports.wan;
  w = site.wan;
  onuIp = "192.168.11.2";

  py = name: let
    src = pkgs.writeText "${name}.py" (builtins.readFile ./fiber-bypass/${name}.py);
  in
    pkgs.writeShellScriptBin name ''exec ${pkgs.python3}/bin/python3 ${src} "$@"'';
  ndAnnounce = py "salt-nd-announce";
  ripAnnounce = py "salt-rip-announce";

  saltStatus = pkgs.writeShellScriptBin "salt-status" ''
    echo "== PON =="
    ${pkgs.openssh}/bin/ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
      root@192.168.11.1 'pon psg; echo -n "mib: "; cat /tmp/8311-mib-file' 2>/dev/null \
      || echo "stick unreachable"
    echo "== RX power =="
    ${pkgs.openssh}/bin/ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@192.168.11.1 \
      'dd if=/sys/devices/platform/18000000.ssx1_1/18100000.ponmbox/eeprom51 bs=1 skip=104 count=2 2>/dev/null' \
      2>/dev/null | ${pkgs.coreutils}/bin/od -An -tu1 \
      | ${pkgs.gawk}/bin/awk '{p=$1*256+$2; print p ? sprintf("RX %.2f dBm", 10*log(p*0.0001)/log(10)) : "NO LIGHT"}'
    echo "== routes =="; ${pkgs.iproute2}/bin/ip route | grep -E '^default' || echo "no default route"
    echo "== v4 =="; ${pkgs.curl}/bin/curl -4 -s --max-time 8 https://ifconfig.co || echo "v4 FAILED"
    echo "== v6 =="; ${pkgs.curl}/bin/curl -6 -s --max-time 8 https://ifconfig.co || echo "v6 FAILED"
  '';

  every30s = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "20s";
      OnUnitActiveSec = "30s";
      AccuracySec = "1s";
    };
  };
in {
  systemd.network.networks."10-wan" = {
    matchConfig.Name = wan;
    address = [
      "${onuIp}/24"
      "${w.ip4}/32"
      # Makes the /20 on-link; the gateway ARPs only from this source.
      "${w.alias4.address}/${toString w.alias4.prefixLength}"
      # /128: Salt routes the /64 to ::1, the prefix itself goes to the LAN.
      "${w.ip6}/128"
    ];
    networkConfig = {
      IPv6AcceptRA = false;
      LinkLocalAddressing = "ipv6";
      DNS = w.dns6 ++ w.dns4;
    };
    routes = [
      {
        Gateway = w.gw4;
        # Valid only while salt-rip-announce runs, else CGNAT.
        PreferredSource = w.ip4;
        Metric = 100;
      }
      # No static neighbour entry for it; see salt-nd-announce.
      {
        Gateway = w.gw6;
        Metric = 100;
      }
    ];
    linkConfig.RequiredForOnline = false;
  };

  # The BNG re-resolves us via tagged multicast the host drops; announce first.
  systemd.services.salt-nd-announce = {
    description = "Announce our IPv6 address to the Salt BNG";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${ndAnnounce}/bin/salt-nd-announce ${wan} ${w.ip6} ${w.bngMac} ${w.gw6}";
    };
  };
  systemd.timers.salt-nd-announce = every30s // {description = "Periodic IPv6 NA to the Salt BNG";};

  # Registers the public /32 with the BNG's source guard, as the box does.
  systemd.services.salt-rip-announce = {
    description = "Announce routes to the Salt BNG via RIPv2";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${ripAnnounce}/bin/salt-rip-announce ${wan} ${w.alias4.address} ${w.ip4} ${w.alias4.network} ${w.alias4.netmask}";
    };
  };
  systemd.timers.salt-rip-announce = every30s // {description = "Periodic RIPv2 announce to the Salt BNG";};

  environment.systemPackages = [saltStatus ndAnnounce ripAnnounce];
}
