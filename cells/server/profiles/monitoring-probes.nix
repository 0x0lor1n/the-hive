# Router-side probes that feed node_exporter's textfile dir
# (monitoring-server.nix): ONU temperatures/RX power over the stick's
# root-without-password ssh (same path as salt-status), and an hourly iperf3
# run against imladris over the 10G DAC.
{
  inputs,
  cell,
}: {
  pkgs,
  lib,
  ...
}: let
  textfileDir = "/var/lib/node_exporter/textfile";
  imladris = "192.168.10.10";
  eeprom = "/sys/devices/platform/18000000.ssx1_1/18100000.ponmbox/eeprom51";

  writeProm = ''
    write_prom() {
      mkdir -p ${textfileDir}
      tmp=$(mktemp -p ${textfileDir})
      cat >"$tmp"
      chmod 0644 "$tmp"
      mv "$tmp" ${textfileDir}/"$1".prom
    }
  '';

  # Busybox on the stick has hexdump, no usable od. Unreachable = only
  # onu_reachable 0: stale temperatures must vanish, not freeze.
  onuTemps = pkgs.writeShellScript "onu-temps" ''
    set -uo pipefail
    ${writeProm}
    raw=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@192.168.11.1 \
        'cat /sys/class/thermal/thermal_zone0/temp
         hexdump -v -s 96 -n 2 -e "2/1 \"%u \" \"\n\"" ${eeprom}
         hexdump -v -s 104 -n 2 -e "2/1 \"%u \" \"\n\"" ${eeprom}') || raw=
    if [ "$(wc -l <<<"$raw")" != 3 ]; then
      printf '# TYPE onu_reachable gauge\nonu_reachable 0\n' | write_prom onu
      exit 0
    fi
    # SFF-8472 A2h: temp = signed 16-bit / 256 °C; RX = u16 * 0.1 µW.
    awk 'NR == 1 { cpu = $1 / 1000 }
         NR == 2 { t = $1 * 256 + $2; if (t >= 32768) t -= 65536 }
         NR == 3 { p = $1 * 256 + $2 }
         END {
           print "# TYPE onu_reachable gauge"; print "onu_reachable 1"
           print "# TYPE onu_cpu_temp_celsius gauge"; printf "onu_cpu_temp_celsius %.3f\n", cpu
           print "# TYPE onu_sfp_temp_celsius gauge"; printf "onu_sfp_temp_celsius %.3f\n", t / 256
           if (p > 0) { print "# TYPE onu_rx_power_dbm gauge"; printf "onu_rx_power_dbm %.2f\n", 10 * log(p * 0.0001) / log(10) }
         }' <<<"$raw" | write_prom onu
  '';

  # Skips the backup window (hot 02:05/02:30, warm 03:00): the series goes
  # absent for that hour instead of reporting the backup's traffic as LAN speed.
  iperf3Probe = pkgs.writeShellScript "iperf3-probe" ''
    set -uo pipefail
    ${writeProm}
    case $(date -u +%H) in 02 | 03)
      : | write_prom iperf3
      exit 0
      ;;
    esac
    bps() { iperf3 -c ${imladris} -t 10 -P 4 -J "$@" | jq -e '.end.sum_received.bits_per_second'; }
    send=$(bps) || send=
    recv=$(bps -R) || recv=
    {
      echo '# TYPE lan_iperf3_bits_per_second gauge'
      [ -n "$send" ] && echo "lan_iperf3_bits_per_second{peer=\"imladris\",direction=\"send\"} $send"
      [ -n "$recv" ] && echo "lan_iperf3_bits_per_second{peer=\"imladris\",direction=\"recv\"} $recv"
      true
    } | write_prom iperf3
  '';
in {
  systemd.services.onu-temps = {
    description = "ONU stick temperatures and RX power, for node_exporter";
    path = [pkgs.openssh pkgs.coreutils pkgs.gawk];
    serviceConfig.Type = "oneshot";
    serviceConfig.ExecStart = onuTemps;
  };
  systemd.timers.onu-temps = {
    wantedBy = ["timers.target"];
    timerConfig.OnCalendar = "*:0/1";
  };

  systemd.services.iperf3-probe = {
    description = "iperf3 minas-tirith <-> imladris over the DAC, for node_exporter";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    path = [pkgs.iperf3 pkgs.jq pkgs.coreutils];
    serviceConfig.Type = "oneshot";
    serviceConfig.ExecStart = iperf3Probe;
  };
  systemd.timers.iperf3-probe = {
    wantedBy = ["timers.target"];
    timerConfig.OnCalendar = "*:07";
  };
}
