# Router-side probes into the textfile dir: ONU temperatures/RX power, daily
# speed test (docs/monitoring.md).
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
  vontar = "192.168.10.103";
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

  # Ookla to 16522: Salt's 41691 drops Ookla, speedtest-go caps at 0.8 of 8
  # Gbit/s. A run moves ~35 GB, so once a day.
  speedProbe = pkgs.writeShellScript "net-speed-probe" ''
    set -uo pipefail
    ${writeProm}
    state=$STATE_DIRECTORY
    # keep <peer> <download bps> <upload bps>: both or nothing
    keep() {
      [ -n "$2" ] && [ -n "$3" ] || return 0
      printf 'net_speed_bits_per_second{peer="%s",direction="download"} %s\n' "$1" "$2" >"$state/$1.prom"
      printf 'net_speed_bits_per_second{peer="%s",direction="upload"} %s\n' "$1" "$3" >>"$state/$1.prom"
      printf 'net_speed_timestamp_seconds{peer="%s"} %s\n' "$1" "$(date +%s)" >>"$state/$1.prom"
    }
    iperf() {
      iperf3 -c "$@" -J | jq -er '.end.sum_received.bits_per_second // empty' || true
    }

    keep imladris "$(iperf ${imladris} -t 10 -P 4)" "$(iperf ${imladris} -t 10 -P 4 -R)"
    keep vontar "$(iperf ${vontar} -t 5 -P 1)" "$(iperf ${vontar} -t 5 -P 1 -R)"
    wan=$(HOME=$state speedtest --accept-license --accept-gdpr -s 16522 -f json 2>/dev/null \
      | jq -er '"\(.download.bandwidth * 8) \(.upload.bandwidth * 8)"') || wan=
    # shellcheck disable=SC2086 # two words on purpose
    [ -n "$wan" ] && keep salt $wan

    {
      for m in net_speed_bits_per_second net_speed_timestamp_seconds; do
        echo "# TYPE $m gauge"
        cat "$state"/*.prom 2>/dev/null | grep "^$m{" | sort
      done
      true
    } | write_prom net-speed
    # The hourly iperf3-probe's file, gone with the unit that wrote it.
    rm -f ${textfileDir}/iperf3.prom
  '';
  ookla =
    (import pkgs.path {
      inherit (pkgs.stdenv.hostPlatform) system;
      config.allowUnfreePredicate = p: lib.getName p == "ookla-speedtest";
    }).ookla-speedtest;
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

  systemd.services.net-speed-probe = {
    description = "Daily iperf3 to imladris and the Vontar, Ookla to Lausanne, for node_exporter";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    path = [pkgs.iperf3 pkgs.jq pkgs.coreutils pkgs.gnugrep ookla];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = speedProbe;
      StateDirectory = "net-speed-probe";
    };
  };
  systemd.timers.net-speed-probe = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "05:17";
      # Router was down at 05:17: run at boot instead of skipping a day.
      Persistent = true;
    };
  };
  # Last good results survive a reboot (root rolls back to @blank).
  environment.persistence."/state".directories = ["/var/lib/net-speed-probe"];
}
