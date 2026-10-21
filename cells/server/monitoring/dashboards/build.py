#!/usr/bin/env python3
"""Generate the Grafana dashboards in this directory.

    python3 build.py          write hive.json, imladris.json, minas-tirith.json
    python3 build.py --check  exit 1 if any file differs from what would be written

The JSON is provisioned read-only (monitoring-server.nix); change this file,
not the JSON. Panels are placed left to right in rows of 24 columns: each
helper takes its width and height, `row()` starts a new band.
"""

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
DS = {"type": "prometheus", "uid": "prometheus"}
SCHEMA_VERSION = 42  # Grafana 13.1 new-dashboard default

H = 3600
UP_DOWN = [{"type": "value", "options": {
    "0": {"text": "DOWN", "color": "red", "index": 0},
    "1": {"text": "UP", "color": "green", "index": 1},
}}]
# zfs_exporter encodes pool health as the index of the zpool state.
POOL_HEALTH = [{"type": "value", "options": {
    str(i): {"text": t, "color": c, "index": i}
    for i, (t, c) in enumerate([
        ("ONLINE", "green"), ("DEGRADED", "orange"), ("FAULTED", "red"),
        ("OFFLINE", "red"), ("UNAVAIL", "red"), ("REMOVED", "red"),
        ("SUSPENDED", "red"),
    ])
}}]

# Non-HTTP helpers shown in the collapsed "Auxiliary" table. Oneshot jobs are
# listed by their timer: the service is inactive between runs by design, a
# failed run shows up in "Failed units" instead.
AUX_UNITS = [
    "atx-watchdog-heartbeat.service", "smartd.service",
    "flaresolverr.service", "anilibria-torznab.service", "iperf3.service",
    "prometheus.service", "alertmanager.service", "alertmanager-ntfy.service",
    "prometheus-node-exporter.service", "prometheus-zfs-exporter.service",
    "prometheus-smartctl-exporter.service",
    "prometheus-blackbox-exporter.service", "yggdrasil.service",
    "sanoid.timer", "hot-backup.timer", "warm-backup.timer",
    "snapshot-age.timer", "iperf3-probe.timer", "onu-temps.timer",
]

# Datasets whose newest snapshot matters: every backup source and target
# root, not each child.
SNAPSHOT_DATASETS = (
    "fast/services|rpool/safe|tank/(photos|archive|media|backups)"
    "|tank/backups/(imladris|minas-tirith)/(safe|logs)"
)


def thresholds(*steps):
    """thresholds("green", 55, "orange", 65, "red") -> Grafana steps."""
    out = [{"color": steps[0], "value": None}]
    for value, color in zip(steps[1::2], steps[2::2]):
        out.append({"color": color, "value": value})
    return {"mode": "absolute", "steps": out}


def target(expr, legend="", ref="A", instant=False, table=False):
    t = {"refId": ref, "datasource": DS, "expr": expr, "legendFormat": legend}
    if instant:
        t["instant"] = True
        t["range"] = False
    if table:
        t["format"] = "table"
    return t


def targets(*specs, **kw):
    """targets((expr, legend), ...) -> refIds A, B, ..."""
    return [target(e, l, chr(ord("A") + i), **kw) for i, (e, l) in enumerate(specs)]


def panel(kind, title, w, h, tgts, defaults=None, options=None, overrides=None,
          **extra):
    p = {
        "type": kind,
        "title": title,
        "_w": w,
        "_h": h,
        "datasource": DS,
        "targets": tgts,
        "fieldConfig": {"defaults": defaults or {}, "overrides": overrides or []},
        "options": options or {},
    }
    p.update(extra)
    return p


def stat(title, w, h, tgts, unit=None, steps=None, mappings=None, color="background",
         text="auto", links=None, decimals=None, no_value=None, **extra):
    d = {}
    if unit:
        d["unit"] = unit
    if decimals is not None:
        d["decimals"] = decimals
    if steps:
        d["thresholds"] = steps
    else:
        d["color"] = {"mode": "fixed", "fixedColor": "blue"}
    if mappings:
        d["mappings"] = mappings
    if links:
        d["links"] = links
    if no_value:
        d["noValue"] = no_value
    return panel("stat", title, w, h, tgts, d, {
        "colorMode": color if steps else "none",
        "graphMode": "none",
        "textMode": text,
        "justifyMode": "auto",
        "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
    }, **extra)


def ts(title, w, h, tgts, unit=None, steps=None, line_steps=False, min_=None,
       max_=None, decimals=None, legend_table=False, overrides=None, **extra):
    d = {"custom": {"lineWidth": 1, "fillOpacity": 0, "spanNulls": False}}
    if unit:
        d["unit"] = unit
    if min_ is not None:
        d["min"] = min_
    if max_ is not None:
        d["max"] = max_
    if decimals is not None:
        d["decimals"] = decimals
    if steps:
        d["thresholds"] = steps
        if line_steps:
            d["custom"]["thresholdsStyle"] = {"mode": "line"}
    legend = {"displayMode": "list", "placement": "bottom", "calcs": []}
    if legend_table:
        # A list legend truncates past ~3 rows in h=8; the sorted table keeps
        # the worst series on top.
        legend = {"displayMode": "table", "placement": "bottom",
                  "calcs": ["lastNotNull", "max"], "sortBy": "Last *",
                  "sortDesc": True}
    return panel("timeseries", title, w, h, tgts, d, {
        "legend": legend,
        "tooltip": {"mode": "multi", "sort": "desc"},
    }, overrides, **extra)


def gauge(title, w, h, tgts, unit, steps, min_=0, max_=1):
    return panel("gauge", title, w, h, tgts,
                 {"unit": unit, "min": min_, "max": max_, "thresholds": steps},
                 {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
                  "showThresholdMarkers": True})


def bargauge(title, w, h, tgts, unit, steps, min_=0, max_=None, **extra):
    d = {"unit": unit, "min": min_, "thresholds": steps}
    if max_ is not None:
        d["max"] = max_
    return panel("bargauge", title, w, h, tgts, d, {
        "orientation": "horizontal",
        "displayMode": "basic",
        "showUnfilled": True,
        "valueMode": "color",
        "namePlacement": "left",
        "sizing": "auto",
        "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
    }, **extra)


def table(title, w, h, tgts, exclude=(), rename=None, order=(), overrides=None,
          no_value=None, merge=False, sort=None):
    org = {"excludeByName": {k: True for k in exclude},
           "renameByName": rename or {},
           "indexByName": {k: i for i, k in enumerate(order)}}
    tr = ([{"id": "merge", "options": {}}] if merge else [])
    tr.append({"id": "organize", "options": org})
    d = {"custom": {"align": "auto", "cellOptions": {"type": "auto"}}}
    if no_value:
        d["noValue"] = no_value
    opts = {"showHeader": True, "cellHeight": "sm"}
    if sort:
        opts["sortBy"] = [{"displayName": sort, "desc": False}]
    return panel("table", title, w, h, tgts, d, opts, overrides,
                 transformations=tr)


def state_timeline(title, w, h, tgts, mappings, **extra):
    return panel("state-timeline", title, w, h, tgts,
                 {"mappings": mappings, "custom": {"fillOpacity": 80, "lineWidth": 0},
                  "color": {"mode": "thresholds"},
                  "thresholds": thresholds("red", 1, "green")},
                 {"showValue": "never", "mergeValues": True, "rowHeight": 0.8,
                  "alignValue": "left",
                  "legend": {"displayMode": "list", "placement": "bottom", "showLegend": False},
                  "tooltip": {"mode": "single"}}, **extra)


def by_name(name, **props):
    return {"matcher": {"id": "byName", "options": name},
            "properties": [{"id": k, "value": v} for k, v in props.items()]}


def status_cell(field, mappings=UP_DOWN):
    return {"matcher": {"id": "byName", "options": field}, "properties": [
        {"id": "mappings", "value": mappings},
        {"id": "custom.cellOptions", "value": {"type": "color-background"}},
        {"id": "custom.width", "value": 90},
    ]}


def row(title, panels, collapsed=False):
    return {"title": title, "panels": panels, "collapsed": collapsed}


def layout(rows):
    """Assign ids and gridPos; rows of panels wrap at 24 columns."""
    out, pid, y = [], 1, 0

    def place(panels, y):
        nonlocal pid
        placed, x, band = [], 0, 0
        for p in panels:
            w, h = p.pop("_w"), p.pop("_h")
            if x + w > 24:
                x, y, band = 0, y + band, 0
            placed.append({"id": pid, **p, "gridPos": {"x": x, "y": y, "w": w, "h": h}})
            pid += 1
            x += w
            band = max(band, h)
        return placed, y + band

    for r in rows:
        head = {"id": pid, "type": "row", "title": r["title"],
                "collapsed": r["collapsed"],
                "gridPos": {"x": 0, "y": y, "w": 24, "h": 1}}
        pid += 1
        y += 1
        placed, end = place(r["panels"], y)
        if r["collapsed"]:
            # Collapsed panels live inside the row and take no grid height.
            head["panels"] = placed
            out.append(head)
        else:
            head["panels"] = []
            out.append(head)
            out.extend(placed)
            y = end
    return out


def dashboard(uid, title, rows, description):
    return {
        "uid": uid,
        "title": title,
        "description": description,
        "tags": ["hive"],
        "timezone": "utc",
        "schemaVersion": SCHEMA_VERSION,
        "version": 1,
        "editable": False,
        "graphTooltip": 1,
        "refresh": "30s",
        "time": {"from": "now-24h", "to": "now"},
        "links": [{"type": "dashboards", "tags": ["hive"], "asDropdown": False,
                   "includeVars": False, "keepTime": True, "title": "hive",
                   "targetBlank": False, "icon": "external link", "tooltip": "",
                   "url": ""}],
        "panels": layout(rows),
        "templating": {"list": []},
        "annotations": {"list": []},
    }


def host_link(host):
    return [{"title": f"{host} dashboard", "url": f"/d/{host}"}]


def bps(expr):
    return f"rate({expr}[1m]) * 8"


# ---------------------------------------------------------------- hive ----
def hive():
    hosts = [
        ("imladris", 'probe_success{job="icmp-lan",host="imladris"}', True),
        ("minas-tirith", 'up{job="node-minas-tirith"}', True),
        ("osgiliath", 'probe_success{job="probe-osgiliath"}', False),
        ("vontar", 'probe_success{job="icmp-lan",host="vontar"}', False),
        ("asus-ap", 'probe_success{job="icmp-lan",host="asus-ap"}', False),
    ]
    host_panels = [
        # No series at all (exporter gone, probe target dropped) reads as DOWN.
        stat(name, 4, 4, [target(expr, name)], links=host_link(name) if link else None,
             steps=thresholds("red", 1, "green"), mappings=UP_DOWN, no_value="DOWN")
        for name, expr, link in hosts
    ]
    host_panels.append(stat(
        "imladris boot", 4, 4, [target("atx_watchdog_unclean_boot", "imladris")],
        steps=thresholds("green", 1, "red"),
        mappings=[{"type": "value", "options": {
            "0": {"text": "clean", "color": "green", "index": 0},
            "1": {"text": "UNCLEAN", "color": "red", "index": 1}}}]))
    host_panels.append(state_timeline("Up/down, 24 h", 24, 6, targets(
        ('probe_success{job=~"icmp-lan|probe-osgiliath"}', "{{host}}"),
        ('up{job="node-minas-tirith"}', "minas-tirith"),
    ), UP_DOWN))

    iperf = 'lan_iperf3_bits_per_second{peer="imladris"}'
    vontar_port = 'node_network_{d}_bytes_total{{host="minas-tirith",device="enp3s0"}}'
    lan = [
        stat("iperf3 minas-tirith ↔ imladris", 6, 8, [target(iperf, "{{direction}}")],
             unit="bps", text="value_and_name",
             steps=thresholds("red", 5e9, "orange", 9e9, "green"),
             description="Hourly at :07, 10 s, 4 streams. send = router → imladris. "
                         "Skipped 02:00–03:59 UTC (backups)."),
        stat("imladris link", 4, 8,
             [target('node_network_speed_bytes{host="imladris",device="enp7s0"} * 8', "enp7s0")],
             unit="bps", steps=thresholds("red", 1e10, "green")),
        ts("iperf3, 7 d", 14, 8, [target(iperf, "{{direction}}")], unit="bps", min_=0,
           steps=thresholds("red", 5e9, "orange", 9e9, "green"), line_steps=True,
           timeFrom="7d"),
        ts("Router port → Vontar X5 (enp3s0)", 18, 8, targets(
            (bps(vontar_port.format(d="transmit")), "to Vontar"),
            (bps(vontar_port.format(d="receive")), "from Vontar"),
        ), unit="bps", min_=0,
           description="Passive: everything the Vontar pulls (imladris and internet) "
                       "crosses this router port."),
        stat("To Vontar, max 7 d", 6, 8, [target(
            f'max_over_time(({bps(vontar_port.format(d="transmit"))})[7d:5m])', "max")],
            unit="bps"),
    ]

    age = thresholds("green", 26 * H, "orange", 36 * H, "red")
    backups = [
        stat("Since last backup", 10, 5,
             [target("time() - backup_last_success_seconds", "{{tier}} {{host}}")],
             unit="s", steps=age, text="value_and_name",
             description="hot = nightly copy while the system runs (imladris local, "
                         "router push); warm = warm1, imported only for the run."),
        stat("Last run took", 6, 5,
             [target("backup_last_duration_seconds", "{{tier}} {{host}}")],
             unit="s", text="value_and_name"),
        stat("warm1 free", 4, 5, [target("warm_pool_free_bytes", "warm1")], unit="bytes"),
        stat("warm1 free %", 4, 5,
             [target("warm_pool_free_bytes / warm_pool_size_bytes", "warm1")],
             unit="percentunit", steps=thresholds("red", 0.1, "green")),
        bargauge("Newest snapshot age", 24, 9, [target(
            f'time() - zfs_snapshot_latest_seconds{{dataset=~"{SNAPSHOT_DATASETS}"}}',
            "{{dataset}}")], "s", thresholds("green", 26 * H, "red")),
    ]

    pools = [
        bargauge("Pool used", 10, 7, targets(
            ("zfs_pool_allocated_bytes / zfs_pool_size_bytes", "{{host}} {{pool}}"),
            ("1 - warm_pool_free_bytes / warm_pool_size_bytes", "imladris warm1"),
        ), "percentunit", thresholds("green", 0.8, "red"), max_=1),
        bargauge("Pool free", 10, 7, targets(
            ("zfs_pool_free_bytes", "{{host}} {{pool}}"),
            ("warm_pool_free_bytes", "imladris warm1"),
        ), "bytes", thresholds("blue")),
        stat("Pool health", 4, 7, [target("zfs_pool_health", "{{host}} {{pool}}")],
             steps=thresholds("green", 1, "red"), mappings=POOL_HEALTH,
             text="value_and_name"),
    ]

    # The probe url is the health endpoint; the link opens the app root.
    svc_expr = ('label_replace(probe_success{job="http-services",tier="main"}, '
                '"link", "$1", "url", "(https?://[^/]+).*")')
    services = [
        table("Services", 12, 10, [target(svc_expr, ref="A", instant=True, table=True)],
              exclude=["Time", "__name__", "instance", "job", "tier", "url"],
              rename={"Value": "status"}, order=["service", "host", "status", "link"],
              sort="service",
              overrides=[status_cell("status"),
                         by_name("link", **{"custom.hidden": True}),
                         by_name("service", links=[{
                             "title": "open", "url": "${__data.fields.link}",
                             "targetBlank": True}])]),
        table("Failed units", 12, 10,
              [target('node_systemd_unit_state{state="failed"} == 1', instant=True, table=True)],
              exclude=["Time", "__name__", "instance", "job", "state", "type", "Value"],
              order=["host", "name"], no_value="none"),
    ]
    aux_rx = "|".join(u.replace(".", "\\\\.") for u in AUX_UNITS)
    aux = [
        table("Auxiliary units", 24, 12, [target(
            f'node_systemd_unit_state{{name=~"{aux_rx}",state="active"}}',
            instant=True, table=True)],
            exclude=["Time", "__name__", "instance", "job", "state", "type"],
            rename={"Value": "status"}, order=["host", "name", "status"], sort="name",
            overrides=[status_cell("status", [{"type": "value", "options": {
                "0": {"text": "inactive", "color": "red", "index": 0},
                "1": {"text": "active", "color": "green", "index": 1}}}])]),
    ]

    alerts = [
        table("Firing alerts", 24, 8, [target(
            'ALERTS{alertstate="firing",severity!="info"}', instant=True, table=True)],
            exclude=["Time", "__name__", "alertstate", "instance", "job", "Value"],
            order=["alertname", "severity", "host"], no_value="none"),
    ]

    return dashboard("hive", "hive", [
        row("Hosts", host_panels),
        row("LAN", lan),
        row("Backups", backups),
        row("Pools", pools),
        row("Services", services),
        row("Auxiliary", aux, collapsed=True),
        row("Alerts", alerts),
    ], "Home: hosts, LAN, backups, pools, services. Per-host detail: imladris, minas-tirith.")


# ------------------------------------------------------------ imladris ----
def imladris():
    h = 'host="imladris"'
    with_serial = (" * on (host, device) group_left (model_name, serial_number) "
                   f"smartctl_device{{{h}}}")
    realloc = f'smartctl_device_attribute{{{h},attribute_id="5",attribute_value_type="raw"}}'
    hdd = [
        ts("HDD temperature (SMART)", 12, 8, [target(
            f'smartctl_device_temperature{{{h},temperature_type="current",device=~"sd.*"}}'
            + with_serial, "{{device}} {{serial_number}}")],
           unit="celsius", steps=thresholds("green", 55, "orange", 65, "red"),
           line_steps=True, legend_table=True,
           description="IronWolf/Barracuda operating max 65 °C."),
        ts("Reallocated sectors (SMART 5 raw)", 12, 8,
           [target(realloc + with_serial, "{{device}} {{serial_number}}")],
           unit="short", min_=0, legend_table=True, decimals=0),
        table("Reallocated now", 8, 8, targets(
            (realloc, ""), (f"increase({realloc}[24h])", ""), instant=True, table=True),
            exclude=["Time", "__name__", "instance", "job", "host", "attribute_flags_long",
                     "attribute_flags_short", "attribute_id", "attribute_name",
                     "attribute_value_type"],
            rename={"Value #A": "reallocated", "Value #B": "Δ 24 h"},
            order=["device", "reallocated", "Δ 24 h"], merge=True, sort="device",
            overrides=[by_name("Δ 24 h", **{
                "thresholds": thresholds("green", 1, "red"),
                "custom.cellOptions": {"type": "color-text"},
                "decimals": 0})]),
        ts("Pending / offline-uncorrectable (SMART 197/198 raw)", 8, 8, [target(
            f'smartctl_device_attribute{{{h},attribute_id=~"197|198",attribute_value_type="raw"}}',
            "{{device}} {{attribute_name}}")],
           unit="short", min_=0, steps=thresholds("green", 1, "red"), legend_table=True,
           decimals=0),
        stat("Power-on hours", 4, 8, [target(
            f"smartctl_device_power_on_seconds{{{h}}} / 3600", "{{device}}")],
             unit="h", decimals=0, text="value_and_name"),
        stat("SMART status", 4, 8,
             [target(f"smartctl_device_smart_status{{{h}}}", "{{device}}")],
             steps=thresholds("red", 1, "green"), text="value_and_name",
             mappings=[{"type": "value", "options": {
                 "0": {"text": "FAILED", "color": "red", "index": 0},
                 "1": {"text": "PASSED", "color": "green", "index": 1}}}]),
    ]

    nvme_expr = (f'smartctl_device_temperature{{{h},temperature_type="current",'
                 f'device=~"nvme.*"}}' + with_serial)
    nvme_steps = thresholds("green", 70, "orange", 82, "red")
    nvme = [
        ts("NVMe temperature", 16, 8, [target(nvme_expr, "{{device}} {{model_name}}")],
           unit="celsius", steps=nvme_steps, line_steps=True, legend_table=True,
           description="nvme0 PM9B1 = OS (rpool); the three 1 TB = fast raidz1. "
                       "Samsung spec max 82 °C."),
        stat("NVMe now", 8, 8, [target(nvme_expr, "{{device}}")], unit="celsius",
             steps=nvme_steps, text="value_and_name"),
    ]

    system = host_system(h, cores=4) + [
        stat("ZFS ARC", 6, 4, [target(f"node_zfs_arc_size{{{h}}}", "ARC")], unit="bytes"),
        stat("Page cache", 6, 4, [target(f"node_memory_Cached_bytes{{{h}}}", "cached")],
             unit="bytes"),
        cpu_busy(h, 24),
    ]

    net = [
        ts("NIC throughput", 24, 8, targets(
            (bps(f'node_network_receive_bytes_total{{{h},device=~"enp.*"}}'), "{{device}} rx"),
            (bps(f'node_network_transmit_bytes_total{{{h},device=~"enp.*"}}'), "{{device}} tx"),
        ), unit="bps", min_=0, description="enp7s0 = 10G DAC to the router; enp8s0 = 1G spare."),
    ]

    space = [
        bargauge("Pool free", 8, 8, [target(f"zfs_pool_free_bytes{{{h}}}", "{{pool}}")],
                 "bytes", thresholds("blue")),
        bargauge("Dataset used", 8, 8, [target(
            f'zfs_dataset_used_bytes{{{h},name=~"tank/(photos|archive|media|backups)|fast/services"}}',
            "{{name}}")], "bytes", thresholds("blue")),
        bargauge("Filesystem free", 8, 8, [target(
            f'node_filesystem_avail_bytes{{{h},mountpoint=~"/|/boot"}}', "{{mountpoint}}")],
                 "bytes", thresholds("blue")),
        ts("Pool used", 24, 8, [target(
            f"zfs_pool_allocated_bytes{{{h}}} / zfs_pool_size_bytes{{{h}}}", "{{pool}}")],
           unit="percentunit", min_=0, steps=thresholds("green", 0.8, "red"),
           line_steps=True, max_=1),
    ]

    return dashboard("imladris", "imladris", [
        row("Disks (HDD)", hdd),
        row("NVMe", nvme),
        row("System", system),
        row("Network", net),
        row("Space", space),
    ], "NAS: disk health and temperature, system, space.")


def host_system(h, cores):
    return [
        gauge("RAM used", 4, 4, [target(
            f"1 - node_memory_MemAvailable_bytes{{{h}}} / node_memory_MemTotal_bytes{{{h}}}",
            "RAM")], "percentunit", thresholds("green", 0.85, "orange", 0.95, "red")),
        stat("Load / core", 4, 4, [target(f"node_load1{{{h}}} / {cores}", "load1")],
             unit="percentunit", steps=thresholds("green", 0.8, "orange", 1.5, "red")),
        stat("CPU temp", 4, 4, [target(
            f'node_hwmon_temp_celsius{{{h},chip="platform_coretemp_0",sensor="temp1"}}', "cpu")],
             unit="celsius", steps=thresholds("green", 80, "orange", 95, "red")),
    ]


def cpu_busy(h, w):
    return ts("CPU busy", w, 8, [target(
        f'1 - avg(rate(node_cpu_seconds_total{{{h},mode="idle"}}[5m]))', "busy")],
              unit="percentunit", min_=0, max_=1)


# -------------------------------------------------------- minas-tirith ----
def minas_tirith():
    h = 'host="minas-tirith"'

    def hw(chip):
        return f'node_hwmon_temp_celsius{{{h},chip="{chip}",sensor="temp1"}}'

    # ONU limits are provisional (baseline + 10 °C): OnuHot gets its threshold
    # from the measured 24 h curve in Phase 5, these follow it then.
    sensors = [
        ("NVMe", hw("nvme_nvme0"), thresholds("green", 70, "orange", 82, "red")),
        ("CPU N305", hw("platform_coretemp_0"), thresholds("green", 85, "orange", 95, "red")),
        ("DIMM", hw("i2c_0_0_0050"), thresholds("green", 70, "orange", 85, "red")),
        ("ONU CPU", "onu_cpu_temp_celsius", thresholds("green", 82, "orange", 90, "red")),
        ("ONU SFP", "onu_sfp_temp_celsius", thresholds("green", 75, "orange", 85, "red")),
    ]
    thermal = [
        stat(name, w, 4, [target(expr, name)], unit="celsius", steps=steps)
        for (name, expr, steps), w in zip(sensors, [5, 5, 5, 5, 4])
    ] + [
        ts("Temperatures", 24, 8, targets(*[(expr, name) for name, expr, _ in sensors]),
           unit="celsius", legend_table=True),
    ]

    rx_steps = thresholds("red", -28, "orange", -27, "green", -8, "red")
    onu = [
        stat("ONU RX power", 6, 6, [target("onu_rx_power_dbm", "rx")], unit="dBm",
             steps=rx_steps, decimals=2,
             description="GPON class B+: below −28 dBm the link drops (salt-status)."),
        stat("ONU reachable", 6, 6, [target("onu_reachable", "onu")],
             steps=thresholds("red", 1, "green"), mappings=UP_DOWN),
        ts("ONU RX power, 24 h", 12, 6, [target("onu_rx_power_dbm", "rx")], unit="dBm",
           steps=rx_steps, line_steps=True),
    ]

    system = host_system(h, cores=8) + [
        bargauge("Free space", 4, 4, targets(
            (f'node_filesystem_avail_bytes{{{h},mountpoint="/"}}', "/"),
            (f"zfs_pool_free_bytes{{{h}}}", "{{pool}}"),
        ), "bytes", thresholds("blue")),
        bargauge("rpool/logs vs quota", 8, 4, [target(
            f'zfs_dataset_used_bytes{{{h},name=~"rpool/logs/.*"}} '
            f'/ zfs_dataset_quota_bytes{{{h},name=~"rpool/logs/.*"}}', "{{name}}")],
                 "percentunit", thresholds("green", 0.8, "red"), max_=1),
        cpu_busy(h, 24),
    ]

    devs = "enp1s0f0|br-lan|enp1s0f1|enp2s0|enp3s0"

    def port(direction):
        return [target(
            f'label_replace(label_replace(label_replace(label_replace('
            f'{bps(f"node_network_{direction}_bytes_total{{{h},device=~\"{devs}\"}}")}, '
            f'"role", "WAN", "device", "enp1s0f0"), '
            f'"role", "imladris 10G", "device", "enp1s0f1"), '
            f'"role", "Asus AP", "device", "enp2s0"), '
            f'"role", "Vontar X5", "device", "enp3s0")',
            "{{device}} {{role}}")]

    net = [
        ts("Received (bit/s)", 12, 9, port("receive"), unit="bps", min_=0,
           description="Per port, not stacked: br-lan is the sum of its members."),
        ts("Transmitted (bit/s)", 12, 9, port("transmit"), unit="bps", min_=0),
    ]

    return dashboard("minas-tirith", "minas-tirith", [
        row("Thermal", thermal),
        row("ONU", onu),
        row("System", system),
        row("WAN/LAN", net),
    ], "Router: thermal, ONU stick, system, per-port traffic.")


DASHBOARDS = {"hive.json": hive, "imladris.json": imladris, "minas-tirith.json": minas_tirith}


def render(fn):
    return json.dumps(fn(), indent=2, ensure_ascii=False) + "\n"


def main(argv):
    check = argv[1:] == ["--check"]
    if argv[1:] and not check:
        sys.exit(__doc__)
    drift = []
    for name, fn in DASHBOARDS.items():
        path, text = HERE / name, render(fn)
        if check:
            if not path.exists() or path.read_text() != text:
                drift.append(name)
        else:
            path.write_text(text)
    if drift:
        print("out of date: " + ", ".join(drift) + " (run python3 build.py)", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
