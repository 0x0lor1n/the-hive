# Monitoring

Prometheus, Alertmanager, Grafana and ntfy run on minas-tirith (router, always
up). They scrape exporters on imladris (NAS) and on the router itself, and
probe the rest. Alerts go to ntfy and from there to the phone, over yggdrasil
when it is off the LAN.

| piece | file |
|---|---|
| Prometheus, Alertmanager, Grafana, ntfy, blackbox, scrape jobs | `cells/server/profiles/monitoring-server.nix` |
| imladris exporters (node, zfs, smartctl), iperf3 server, boot-marker | `cells/server/profiles/monitoring-exporters.nix` |
| router probes: ONU, daily speed test | `cells/server/profiles/monitoring-probes.nix` |
| backup tiers and their stamps | `cells/server/profiles/backup-{hot,push,warm}.nix` |
| alert rules and their unit tests | `cells/server/monitoring/alerts{,_test}.yml` |
| dashboards (generated) | `cells/server/monitoring/dashboards/build.py` |

Grafana: `http://192.168.10.1:3000` (home = `hive`). Prometheus and
Alertmanager listen on the router's loopback only:

```bash
ssh -L 9090:127.0.0.1:9090 -L 9093:127.0.0.1:9093 minas-tirith
```

## Topology

```
WAN (Salt XGS-PON, ONU stick 192.168.11.1)
 |
 enp1s0f0
minas-tirith 192.168.10.1 -- br-lan --+-- enp1s0f1 ==10G DAC== enp7s0  imladris 192.168.10.10
                                      +-- enp2s0   --1G------- Asus AP 192.168.10.2 (+ wifi clients)
                                      +-- enp3s0   --1G------- Vontar X5 192.168.10.103 (DHCP)
```

imladris `enp8s0` (1G) is the spare: `net-imladris.nix` keeps it configured
without an address, the cable is out. Rollback to 1G = swap the match names in
`net-imladris.nix` and plug it back in. Both 82599 cards sit on PCIe 2.0 x4
(16 Gb/s), enough for one 10G port each; iperf3 measures 9.41 Gbit/s both ways.

## Dashboards

Generated, never hand-edited:

```bash
cd cells/server/monitoring/dashboards
python3 build.py           # rewrite the JSON
python3 build.py --check   # exit 1 if any JSON differs from build.py
```

Colours come from `cells/common/theme.nix`. Every dashboard carries the `hive`
tag, which gives the cross-links in the header.

| uid | answers |
|---|---|
| `hive` (home) | **The-Hive**: is every box up (hosts table, up/down timeline), are the pools healthy and how full, when did each backup tier last succeed and how long it took. **Newest snapshots** (collapsed): snapshot age per dataset. **Network**: last daily speed test per link and traffic over each router port (WAN, DAC, Vontar). **Services**: the 9 web UIs, up/down with links, plus failed units on both hosts. **Auxiliary** (collapsed): helper units (exporters, timers, watchdog, FlareSolverr, torznab) by systemd state. Firing alerts are not on a dashboard: ntfy, or Alertmanager `:9093`. |
| `imladris` | HDD temperatures and SMART 5/197/198 (with a "growing in 24 h" column), power-on hours, SMART status; NVMe temperatures; RAM/ARC/load/CPU temp; NIC throughput; pool, dataset and filesystem space. |
| `minas-tirith` | NVMe, CPU, DIMM, ONU CPU and SFP temperatures; ONU RX power and reachability; load, RAM, free space, `rpool/logs/*` vs quota; per-port traffic. |
| `city` | The same state drawn as a neon city (unsigned plugin `neon-city-panel`, built from git and recoloured from the palette in `monitoring-server.nix`). |

## Textfile metrics

Written to `/var/lib/node_exporter/textfile/<file>.prom` (mktemp + mv; the dir
is persisted in `/state` on both hosts) and exported by node_exporter.

| metric | file | written by | host | when |
|---|---|---|---|---|
| `backup_last_success_seconds{tier="hot"}`, `backup_last_duration_seconds{tier="hot"}` | `hot-backup` | `hot-backup.service` | imladris | 02:05 |
| same, `tier="hot"` | `hot-backup` | `hot-backup.service` (push) | minas-tirith | 02:30 |
| `backup_last_success_seconds{tier="warm"}`, `backup_last_duration_seconds{tier="warm"}`, `warm_pool_size_bytes`, `warm_pool_free_bytes` | `warm-backup` | `warm-backup.service` | imladris | 03:00-03:10 |
| `zfs_snapshot_latest_seconds{dataset}` (newest `@autosnap_*`) | `snapshot-age` | `snapshot-age.service` | imladris | every 15 min |
| `atx_watchdog_unclean_boot` | `boot-marker` | `boot-marker.service` | imladris | every boot |
| `onu_reachable`, `onu_cpu_temp_celsius`, `onu_sfp_temp_celsius`, `onu_rx_power_dbm` | `onu` | `onu-temps.service` | minas-tirith | every minute |
| `net_speed_bits_per_second{peer,direction}`, `net_speed_timestamp_seconds{peer}` | `net-speed` | `net-speed-probe.service` | minas-tirith | 05:17 daily |

Times are UTC. The two hot stamps share a name; `host` tells them apart. A
backup stamp only moves on success, so a failed run shows as an old stamp.
`onu-temps` writes only `onu_reachable 0` when the stick does not answer:
stale temperatures disappear instead of freezing. `net-speed-probe` keeps the
last good result per peer in `/var/lib/net-speed-probe`; the dashboard hides
results older than two days. Peers: imladris (iperf3 over the DAC), Vontar
(static iperf3 on the box itself, outside this repo, see the header of
`monitoring-probes.nix`), `salt` (Ookla to Wingo Lausanne).

## Alerts

Severity decides the push: `critical` = ntfy high priority, repeated hourly
while firing; `warning` = ntfy default, repeated every 12 h; `info` = dashboard
only (routed to the `null` receiver). Grouping is `alertname` x `host`,
`group_wait` 10 s, `group_interval` 1 m (a resolve arrives within about a
minute). Alertmanager state (nflog, silences) is persisted, so a router
reboot or deploy neither re-sends active alerts nor loses their resolve.

| alert | severity | fires when | what to do |
|---|---|---|---|
| `HostDown` | critical | a LAN box (imladris, vontar, asus-ap) misses ping for 2 m | power, cable, console |
| `HostUnresponsive` | critical | a host pings but none of its exporters answer for 5 m | boot stuck: console (2026-10-22: ZFS key prompt) |
| `OsgiliathUnreachable` | critical | osgiliath ssh port closed from the router for 5 m | VPS provider console |
| `ExporterDown` | warning | one exporter silent for 1 m, host otherwise fine | `systemctl status prometheus-<x>-exporter` |
| `BlackboxDown` | warning | the blackbox exporter is down for 5 m: host and service probes are blind | restart it on minas-tirith |
| `ImladrisUncleanBoot` | warning | imladris came up without a clean shutdown | journal of the previous boot; ATX watchdog or power |
| `HostRebooted` | warning | any node host up < 15 min (2 m `for`); one push, no resolve | nothing if planned |
| `SystemdUnitFailed` | warning | a unit failed for 10 m (backups excluded) | `journalctl -u <unit>` |
| `ServiceDown` | warning | a web UI fails its HTTP probe for 2 m | `systemctl status <service>` |
| `PoolCapacity80` | warning | pool > 80 % for 1 h | prune or grow |
| `PoolDegraded` | critical | pool not ONLINE for 2 m | `zpool status` |
| `HddTempHigh` | warning >= 55 C 10 m, critical >= 65 C 2 m | IronWolf/Barracuda max is 65 C; held 1 h so a 54/55 walk is one push | airflow |
| `NvmeTempHigh` | warning >= 70 C 10 m, critical >= 82 C 2 m | Samsung spec max 82 C | airflow |
| `DiskSmartFailed` | critical | SMART overall FAILED | replace the disk |
| `DiskPendingSectors` | critical | SMART 197 > 0, immediately | `zpool offline` the disk now |
| `DiskReallocatingGrowing` | critical | SMART 5 or 198 moved in the last 6 h; one push per wave | plan a replacement |
| `DiskReallocatedBaseline` | info | SMART 5 or 198 > 0 but flat (sdd: 1152) | dashboard only |
| `BackupFailed` | critical | `hot-backup` or `warm-backup` unit failed | `journalctl -u <unit>`; rerun by hand |
| `BackupStale` | critical | a tier's last success is > 36 h old | check the timer and the last run |
| `SnapshotStale` | warning | newest sanoid snapshot of a dataset > 26 h old | `systemctl status sanoid` |
| `LanSlow` | warning | daily test: imladris < 5 Gbit/s or Vontar < 500 Mbit/s | cable, NIC, port speed |
| `OnuHot` | warning | ONU CPU >= 80 C or SFP >= 75 C for 10 m (idle 72/65) | airflow at the router |
| `OnuSignalLow` | warning | RX power < -27 dBm for 10 m (normal -14.8) | fibre, connector; `salt-status` |
| `OnuUnreachable` | warning | ONU ssh not answering for 10 m | `salt-status` |
| `WanSlow`, `NetSpeedProbeStale` | info | WAN < 2 Gbit/s; no good speed test for 2 days | dashboard only |

Inhibitions (one push per incident):

- `HostDown` or `HostUnresponsive` mutes `ExporterDown`, `ServiceDown`,
  `BackupStale`, `SnapshotStale`, `SystemdUnitFailed` of the same host. The
  rules also carry `unless` host-down / all-exporters-down, so a pending `for`
  does not fire the moment the host is back.
- A critical mutes the warning of the same alert, host, device and chip.
- `ImladrisUncleanBoot` mutes `HostRebooted`.

Measured on 2026-10-22: an imladris reboot = one `HostRebooted` push and
nothing else; pulling the DAC = one `HostDown` + one resolve; stopping
node_exporter = `ExporterDown` about 1.5 min later, resolve about 40 s after
the start.

Checks (the unit tests also run inside the router's build; a rule change that
breaks them does not deploy):

```bash
promtool check rules cells/server/monitoring/alerts.yml
promtool test rules cells/server/monitoring/alerts_test.yml
```

minas-tirith itself cannot report its own death: `HostRebooted` tells
afterwards that it was gone.

## Backups

```
minas-tirith rpool/{safe,logs} --push 02:30, raw, user backup--+
                                                               v
imladris     rpool/safe -------local 02:05--------------> tank/backups/{imladris,minas-tirith}
                                                               |
             tank/photos, tank/archive, fast/services ---------+--03:00--> warm1 (imported for the run only)
```

| tier | from | to | unit, host |
|---|---|---|---|
| hot | imladris `rpool/safe` | `tank/backups/imladris/safe` | `hot-backup`, imladris |
| hot (push) | minas-tirith `rpool/safe`, `rpool/logs` | `tank/backups/minas-tirith/{safe,logs}` | `hot-backup`, minas-tirith |
| warm | `tank/{photos,archive,backups}`, `fast/services` | `warm1/*` | `warm-backup`, imladris |

All three use `syncoid -r --no-sync-snap --delete-target-snapshots
--sendoptions=w`: only sanoid's snapshots travel, and the target is pruned
with the source. `tank/media` is snapshotted (keep-short) but never copied.
`warm-backup` scrubs `warm1` on the 1st of the month.

The router's datasets arrive raw and stay encrypted on imladris (no key
there). Hence `boot.zfs.requestEncryptionCredentials = false` in
`backup-hot.nix`: with the default, `zfs-import-tank` waits on the console for
their passphrase and the whole boot hangs. If a key ever gets loaded on
imladris by hand, unload it again (`zfs unload-key -r
tank/backups/minas-tirith`).

The push user `backup` on imladris has a `restrict`ed key (no pty, no
forwarding) and `zfs allow` on `tank/backups/minas-tirith` only; see the
header of `backup-hot.nix` for the hand-made datasets and the `zfs allow`
line.

## Storage

Prometheus: 30 d retention on `rpool/logs/prometheus` (quota 20 G). After two
days it holds 84 MB for about 7700 series, so 30 d lands near 1.3 G.
