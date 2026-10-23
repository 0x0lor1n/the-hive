#!/usr/bin/env python3
"""Generate the Grafana dashboards in this directory.

    python3 build.py          write hive.json, imladris.json, minas-tirith.json
    python3 build.py --check  exit 1 if any file differs from what would be written

The JSON is provisioned read-only (monitoring-server.nix); change this file,
not the JSON. Panels are placed left to right in rows of 24 columns: each
helper takes its width and height, `row()` starts a new band.
"""

import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
DS = {"type": "prometheus", "uid": "prometheus"}
SCHEMA_VERSION = 42  # Grafana 13.1 new-dashboard default


def theme_roles():
    """Semantic roles of cells/common/theme.nix as #rrggbb (the repo palette)."""
    text = (HERE.parents[2] / "common" / "theme.nix").read_text()
    colors = dict(re.findall(r'^\s*(\w+) = "([0-9a-f]{6})";', text, re.M))
    block = text.split("roles = with colors; {", 1)[1].split("};", 1)[0]
    return {k: "#" + colors[v] for k, v in re.findall(r"^\s*(\w+) = (\w+);", block, re.M)}


ROLES = theme_roles()
# Grafana's named colours -> theme roles; every colour below goes through it.
COLOR = {"green": ROLES["success"], "orange": ROLES["warning"],
         "red": ROLES["urgent"], "blue": ROLES["info"]}

H = 3600


def value_map(*entries):
    """value_map((0, "DOWN", "red"), (1, "UP", "green")) -> Grafana value mappings."""
    return [{"type": "value", "options": {
        str(v): {"text": t, "color": COLOR[c], "index": i}
        for i, (v, t, c) in enumerate(entries)}}]


UP_DOWN = value_map((0, "DOWN", "red"), (1, "UP", "green"))
# zfs_exporter encodes pool health as the index of the zpool state.
POOL_HEALTH = value_map(*((i, t, c) for i, (t, c) in enumerate([
    ("ONLINE", "green"), ("DEGRADED", "orange"), ("FAULTED", "red"),
    ("OFFLINE", "red"), ("UNAVAIL", "red"), ("REMOVED", "red"),
    ("SUSPENDED", "red"),
])))

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
    "snapshot-age.timer", "net-speed-probe.timer", "onu-temps.timer",
]

# Datasets whose newest snapshot matters: every backup source and target
# root, not each child.
SNAPSHOT_DATASETS = (
    "fast/services|rpool/safe|tank/(photos|archive|media|backups)"
    "|tank/backups/(imladris|minas-tirith)/(safe|logs)"
)


def thresholds(*steps):
    """thresholds("green", 55, "orange", 65, "red") -> Grafana steps."""
    out = [{"color": COLOR[steps[0]], "value": None}]
    for value, color in zip(steps[1::2], steps[2::2]):
        out.append({"color": COLOR[color], "value": value})
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
        d["color"] = {"mode": "fixed", "fixedColor": COLOR["blue"]}
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
          no_value=None, merge=False, sort=None, **extra):
    # organize orders by the field's name BEFORE renaming; `order` is written
    # in display names, so map them back.
    original = {v: k for k, v in (rename or {}).items()}
    org = {"excludeByName": {k: True for k in exclude},
           "renameByName": rename or {},
           "indexByName": {original.get(k, k): i for i, k in enumerate(order)}}
    # merge joins the queries' rows on their shared label columns; Time differs
    # per query by a few ms and would split every row, so it goes first.
    tr = ([{"id": "filterFieldsByName",
            "options": {"exclude": {"pattern": "^(Time|__name__)$"}}},
           {"id": "merge", "options": {}}] if merge else [])
    tr.append({"id": "organize", "options": org})
    d = {"custom": {"align": "auto", "cellOptions": {"type": "auto"}}}
    if no_value:
        d["noValue"] = no_value
    opts = {"showHeader": True, "cellHeight": "sm"}
    if sort:
        opts["sortBy"] = [{"displayName": sort, "desc": False}]
    return panel("table", title, w, h, tgts, d, opts, overrides,
                 transformations=tr, **extra)


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


def status_cell(field, mappings=UP_DOWN, no_value=None, width=90):
    props = [
        {"id": "mappings", "value": mappings},
        {"id": "custom.cellOptions", "value": {"type": "color-background"}},
        {"id": "custom.width", "value": width},
    ]
    if no_value:
        # Shown, uncoloured, for a row with no sample in this column.
        props.append({"id": "noValue", "value": no_value})
    return {"matcher": {"id": "byName", "options": field}, "properties": props}


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
        if r["title"] is None:
            # Bare panels, no row header (a single-panel dashboard).
            placed, y = place(r["panels"], y)
            out.extend(placed)
            continue
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


def bps(expr):
    return f"rate({expr}[1m]) * 8"


def static_rows(rows):
    """[{"host": "x", "lan": "y"}, ...] -> one 0-valued series per dict, its
    keys as labels. Lets a table join constant columns onto live ones."""
    def series(labels):
        out = "vector(0)"
        for k, v in labels.items():
            out = f'label_replace({out}, "{k}", "{v}", "", "")'
        return out
    return " or ".join(series(r) for r in rows)


# ---------------------------------------------------------------- hive ----
def hive():
    # Box, LAN address, how it is reached off the LAN (the address itself is
    # in the encrypted globals, never in this public repo). osgiliath is the
    # VPS: no LAN address, reached over its WAN IP. "-", not "": label_replace
    # with an empty value deletes the label, and the cell with it.
    hosts = [
        ("imladris", "192.168.10.10", "-"),
        ("minas-tirith", "192.168.10.1", "Yggdrasil"),
        ("osgiliath", "-", "WAN"),
        ("vontar", "192.168.10.103", "-"),
        ("asus-ap", "192.168.10.2", "-"),
    ]
    # A host without a dashboard of its own links back to this one.
    dash_hosts = ("imladris", "minas-tirith")
    facts = static_rows({"host": n, "lan": ip, "other": o,
                         "dash": f"/d/{n}" if n in dash_hosts else "/d/hive"}
                        for n, ip, o in hosts)

    def per_host(expr):
        # Same label set on every query, so merge folds them into one row per
        # host; a host with no sample keeps its row through `facts` (ref C).
        return f"max by (host) ({expr}) + on (host) group_left (lan, other, dash) ({facts})"
    host_status = ('max by (host) (probe_success{job=~"icmp-lan|probe-osgiliath"}) '
                   'or max by (host) (up{job="node-minas-tirith"})')
    host_table = table("Hosts", 13, 8, targets(
        (per_host(host_status), ""),
        (per_host("time() - node_boot_time_seconds"), ""),
        (facts, ""),
        instant=True, table=True),
        exclude=["Value #C", "dash"], merge=True, sort="host",
        rename={"Value #A": "UP", "Value #B": "uptime",
                "lan": "LAN IP"},
        order=["host", "LAN IP", "UP", "other", "uptime"],
        overrides=[
            # No series at all (exporter gone, probe target dropped) reads as DOWN.
            status_cell("UP", no_value="DOWN"),
            by_name("uptime", unit="dtdurations", decimals=0),
            by_name("host", links=[{"title": "host dashboard",
                                    "url": "${__data.fields.dash}"}]),
        ],
        description=f"Host name opens its dashboard ({', '.join(dash_hosts)}).")

    # Usable space, not raw: zpool's size/free count raidz1 parity (tank shows
    # ~1.5x what fits), the root dataset's used/available do not. warm1 is a
    # single disk and exported between runs: its numbers come from the
    # warm-backup stamp (zpool free, no parity to subtract); health only
    # exists while it is imported.
    def root(m):
        return (f'max by (host, pool) (label_replace({m}{{name=~"[^/]+"}}, '
                '"pool", "$1", "name", "(.*)"))')

    def warm(m):
        return f'max by (host, pool) (label_replace({m}, "pool", "warm1", "", ""))'
    used, avail = root("zfs_dataset_used_bytes"), root("zfs_dataset_available_bytes")
    pool_table = table("Pools", 11, 8, targets(
        (f"{used} / ({used} + {avail}) or "
         + warm("1 - warm_pool_free_bytes / warm_pool_size_bytes"), ""),
        (f"{avail} or " + warm("warm_pool_free_bytes"), ""),
        ("max by (host, pool) (zfs_pool_health)", ""),
        instant=True, table=True),
        merge=True, sort="pool",
        rename={"Value #A": "used", "Value #B": "free", "Value #C": "health"},
        order=["host", "pool", "used", "free", "health"],
        overrides=[
            by_name("used", unit="percentunit", min=0, max=1,
                    thresholds=thresholds("green", 0.8, "red"),
                    **{"custom.cellOptions": {"type": "gauge", "mode": "basic",
                                              "valueDisplayMode": "text"}}),
            by_name("free", unit="bytes", decimals=1),
            status_cell("health", POOL_HEALTH, no_value="exported"),
        ],
        description="warm1 health reads \"exported\" outside its 03:00 run.")

    age = thresholds("green", 26 * H, "orange", 36 * H, "red")
    backups = table("Backups", 10, 6, targets(
        ("time() - backup_last_success_seconds", ""),
        ("backup_last_duration_seconds", ""),
        instant=True, table=True),
        exclude=["instance", "job"], merge=True, sort="tier",
        rename={"Value #A": "since last", "Value #B": "last run took"},
        order=["tier", "host", "since last", "last run took"],
        overrides=[
            by_name("since last", unit="s", decimals=1, thresholds=age,
                    **{"custom.cellOptions": {"type": "color-background"}}),
            by_name("last run took", unit="s", decimals=0),
        ],
        description="hot = nightly copy while the system runs (imladris local, "
                    "router push); warm = warm1, imported only for the run.")

    host_panels = [host_table, pool_table,
                   state_timeline("Up/down, 24 h", 14, 6, targets(
                       ('probe_success{job=~"icmp-lan|probe-osgiliath"}', "{{host}}"),
                       ('up{job="node-minas-tirith"}', "minas-tirith"),
                   ), UP_DOWN),
                   backups]
    snapshots = [
        bargauge("Newest snapshot age", 24, 9, [target(
            f'time() - zfs_snapshot_latest_seconds{{dataset=~"{SNAPSHOT_DATASETS}"}}',
            "{{dataset}}")], "s", thresholds("green", 26 * H, "red")),
    ]

    # Speed = the daily net-speed-probe (monitoring-probes.nix), last good
    # run, dropped after 2 days. Transferred = the router port's rx+tx over
    # the window, the probe's own run included (once a day, ~35 GB total).
    # The arrow is the download direction: towards the box further from the
    # internet.
    routes = {"salt": ("Salt OLT -> minas-tirith", "enp1s0f0", "SM fiber, XGS-PON"),
              "imladris": ("minas-tirith -> imladris", "enp1s0f1", "SFP+ DAC"),
              "vontar": ("minas-tirith -> vontar", "enp3s0", "RJ45 Cat6a")}
    # Speed colour as a share of the link's own ceiling: (bps, green from,
    # red below) per direction. The WAN gets less: Ookla also measures Wingo
    # and Salt's backbone (~80 % down, ~30 % up on a healthy line).
    ceilings = {
        "salt": {"download": (1e10, 0.6, 0.3), "upload": (1e10, 0.2, 0.1)},
        "imladris": {d: (1e10, 0.8, 0.5) for d in ("download", "upload")},
        "vontar": {d: (1e9, 0.8, 0.5) for d in ("download", "upload")},
    }
    devs = "|".join(dev for _, dev, _ in routes.values())

    def by_route(expr, label, extra=""):
        out = expr
        for key, (route, dev, cable) in routes.items():
            match = key if label == "peer" else dev
            out = f'label_replace({out}, "route", "{route}", "{label}", "{match}")'
            out = f'label_replace({out}, "cable", "{cable}", "{label}", "{match}")'
        return f'max by (route, cable{extra}) ({out})'

    fresh = "(time() - net_speed_timestamp_seconds) < 2 * 86400"

    def speed_of(direction):
        return by_route(f'net_speed_bits_per_second{{direction="{direction}"}} '
                        f'and on (peer) {fresh}', "peer")

    # A hidden column per speed column holding the cell's CSS (Grafana's
    # "styling from field"): one colour bucket per `or` branch.
    def speed_style(direction, field):
        buckets = []
        for peer, by_dir in ceilings.items():
            bps_max, green, red = by_dir[direction]
            share = (f'net_speed_bits_per_second{{peer="{peer}",direction="{direction}"}} '
                     f'/ {bps_max:g}')
            for cond, color in ((f">= {green}", "green"),
                                (f"< {green} >= {red}", "orange"),
                                (f"< {red}", "red")):
                css = '{\\"color\\":\\"' + COLOR[color] + '\\"}'
                buckets.append(f'label_replace({share} {cond}, "{field}", "{css}", "", "")')
        return by_route(f"({' or '.join(buckets)}) and on (peer) {fresh}", "peer",
                        extra=f", {field}")

    # ONU receive power as signal bars (fibre only). XGS-PON N1 class: the
    # receiver gives up near -28 dBm and overloads above -7.
    signal_map = [{"type": "range", "options": {
        "from": lo, "to": hi, "result": {"text": text, "color": COLOR[c], "index": i}}}
        for i, (lo, hi, text, c) in enumerate([
            (-7, 10, "▂▄▆█ overload", "red"),
            (-18, -7, "▂▄▆█", "green"),
            (-22, -18, "▂▄▆_", "green"),
            (-25, -22, "▂▄__", "orange"),
            (-28, -25, "▂___", "red"),
            (-60, -28, "____", "red"),
        ])]
    signal = 'label_replace(onu_rx_power_dbm, "peer", "salt", "", "")'

    def moved(window):
        port = (f'increase(node_network_receive_bytes_total{{host="minas-tirith",device=~"{devs}"}}[{window}]) '
                f'+ increase(node_network_transmit_bytes_total{{host="minas-tirith",device=~"{devs}"}}[{window}])')
        return by_route(port, "device")

    # Header -> PromQL range. "1m" = 30d = Prometheus retention
    # (monitoring-server.nix): any longer would just repeat it.
    windows = {"1h": "1h", "1d": "1d", "3d": "3d", "1w": "1w", "1m": "30d"}
    port_ts = 'node_network_{d}_bytes_total{{host="minas-tirith",device="{dev}"}}'
    # The style queries' own values are 1/0 noise; only their label is used.
    win_refs = {f"Value #{chr(ord('C') + i)}": w for i, w in enumerate(windows)}
    sig_ref = f"Value #{chr(ord('C') + len(windows))}"
    style_refs = [f"Value #{chr(ord('C') + len(windows) + i)}" for i in (1, 2)]
    lan = [
        # h=6: title + header + 3 rows without a scrollbar (h=5 scrolled).
        table("Network speed", 24, 6, targets(
            (speed_of("download"), ""), (speed_of("upload"), ""),
            *[(moved(r), "") for r in windows.values()],
            (by_route(signal, "peer"), ""),
            (speed_style("download", "download_style"), ""),
            (speed_style("upload", "upload_style"), ""),
            instant=True, table=True),
            merge=True, sort="route", exclude=style_refs,
            rename={"Value #A": "download speed", "Value #B": "upload speed",
                    sig_ref: "signal", **win_refs},
            order=["route", "signal", "cable", "download speed", "upload speed", *windows],
            overrides=[
                *[by_name(c, unit="bps", decimals=2, noValue="-",
                          **{"custom.styleField": f"{c.split()[0]}_style"})
                  for c in ("download speed", "upload speed")],
                *[by_name(f, **{"custom.hideFrom.viz": True})
                  for f in ("download_style", "upload_style")],
                by_name("signal", mappings=signal_map, noValue=" ", decimals=1,
                        **{"custom.cellOptions": {"type": "color-text"},
                           "custom.width": 110}),
                *[by_name(w, unit="decbytes", decimals=1) for w in windows],
            ],
            description="Speed: once a day at 05:17 UTC, in the arrow's direction "
                        "(download) and back (upload). iperf3 for the LAN cables, "
                        "Ookla to Wingo Lausanne for the WAN. Colour = share of the "
                        "link's ceiling (10G / 10G / 1G): green from 80 %, red below "
                        "50 %; WAN download 60 / 30 %, upload 20 / 10 %. signal = ONU "
                        "receive power, bars for XGS-PON (-28 dBm = receiver limit). "
                        "A failed run keeps the previous result; \"-\" = no good "
                        "result in 2 days. 1h ... 1m "
                        "= bytes through the router port both ways over that window "
                        "(1m = 30 d, the Prometheus retention; less right after a "
                        "router reboot)."),
        # Two shelves: outside links (internet, Yggdrasil) above, the
        # router's two LAN cables below.
        ts("Salt OLT -> minas-tirith (enp1s0f0, XGS-PON)", 12, 8, targets(
            (bps(port_ts.format(d="receive", dev="enp1s0f0")), "download"),
            (bps(port_ts.format(d="transmit", dev="enp1s0f0")), "upload"),
        ), unit="bps", min_=0,
           description="All internet traffic. Includes the daily Ookla run at 05:17 UTC."),
        ts("Yggdrasil -> minas-tirith (ygg0)", 12, 8, targets(
            (bps(port_ts.format(d="receive", dev="ygg0")), "download"),
            (bps(port_ts.format(d="transmit", dev="ygg0")), "upload"),
        ), unit="bps", min_=0,
           description="Overlay traffic: Jellyfin relay, Grafana and ntfy for remote "
                       "devices (a remote stream shows as upload). Rides on the Salt "
                       "link, so it is also counted there."),
        ts("minas-tirith -> imladris (enp1s0f1, 10G DAC)", 12, 8, targets(
            (bps(port_ts.format(d="transmit", dev="enp1s0f1")), "to imladris"),
            (bps(port_ts.format(d="receive", dev="enp1s0f1")), "from imladris"),
        ), unit="bps", min_=0,
           description="Includes the daily iperf3 spike at 05:17 UTC."),
        ts("minas-tirith -> Vontar X5 (enp3s0)", 12, 8, targets(
            (bps(port_ts.format(d="transmit", dev="enp3s0")), "to Vontar"),
            (bps(port_ts.format(d="receive", dev="enp3s0")), "from Vontar"),
        ), unit="bps", min_=0,
           description="Passive: everything the Vontar pulls (imladris and internet) "
                       "crosses this router port."),
    ]

    # The probe url is the health endpoint; the link opens the app root, the
    # LAN column shows host:port. Off-LAN, the router relays Jellyfin/Immich and
    # serves Grafana/ntfy on ygg0 (ygg-relay.nix, monitoring-server.nix);
    # the address stays out of this public repo.
    ygg_services = "jellyfin|immich|grafana|ntfy"
    # label_replace writes only where the source regex matches: "Yggdrasil"
    # for those four, then "-" wherever `other` is still empty.
    svc_expr = ('label_replace(label_replace(label_replace(label_replace('
                'probe_success{job="http-services",tier="main"}, '
                '"link", "$1", "url", "(https?://[^/]+).*"), '
                '"lan", "$1", "url", "https?://([^/]+).*"), '
                f'"other", "Yggdrasil", "service", "{ygg_services}"), '
                '"other", "-", "other", "")')
    services = [
        table("Services", 16, 13, [target(svc_expr, instant=True, table=True)],
              exclude=["Time", "__name__", "instance", "job", "tier", "url"],
              rename={"Value": "up/down", "lan": "LAN:PORT"},
              order=["service", "LAN:PORT", "other", "host", "up/down"],
              sort="service",
              overrides=[status_cell("up/down"),
                         by_name("link", **{"custom.hidden": True}),
                         by_name("service", links=[{
                             "title": "open", "url": "${__data.fields.link}",
                             "targetBlank": True}])]),
        table("Failed units", 8, 13,
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
            overrides=[status_cell("status", value_map(
                (0, "inactive", "red"), (1, "active", "green")))]),
    ]

    return dashboard("hive", "hive", [
        row("The-Hive", host_panels),
        row("Newest snapshots", snapshots, collapsed=True),
        row("Network", lan),
        row("Services", services),
        row("Auxiliary", aux, collapsed=True),
    ], "Home: hosts, pools, backups, network, services. Per-host detail: imladris, minas-tirith.")


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
             mappings=value_map((0, "FAILED", "red"), (1, "PASSED", "green"))),
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

    # Usable space (root dataset), not zpool's raw size/free with parity.
    pool_used = f'zfs_dataset_used_bytes{{{h},name=~"tank|fast|rpool"}}'
    pool_avail = f'zfs_dataset_available_bytes{{{h},name=~"tank|fast|rpool"}}'
    dl = f'{{{h},name="fast/downloads"}}'
    space = [
        bargauge("Pool free", 6, 8, [target(pool_avail, "{{name}}")],
                 "bytes", thresholds("blue")),
        bargauge("Dataset used", 6, 8, [target(
            f'zfs_dataset_used_bytes{{{h},name=~"tank/(photos|archive|media|backups)|fast/(services|downloads)"}}',
            "{{name}}")], "bytes", thresholds("blue")),
        gauge("Incomplete downloads", 6, 8, [target(
            f"zfs_dataset_used_bytes{dl} / (zfs_dataset_quota_bytes{dl} > 0)")],
              "percentunit", thresholds("green", 0.75, "orange", 0.9, "red")),
        bargauge("Filesystem free", 6, 8, [target(
            f'node_filesystem_avail_bytes{{{h},mountpoint=~"/|/boot"}}', "{{mountpoint}}")],
                 "bytes", thresholds("blue")),
        ts("Pool used", 24, 8, [target(
            f"{pool_used} / ({pool_used} + {pool_avail})", "{{name}}")],
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


# ---------------------------------------------------------------- city ----
# Two host blocks joined by the 10G DAC "highway"; each block is ringed by
# the services that run on it, imladris also by its pools. Thin 1G spurs lead
# from the router block to the AP and the Vontar box. Status (colour) is 1 / 0.5 / 0
# (whooktown-neoncity-panel: value ≥ 1 online, ≥ 0.5 warning, else critical),
# a missing sample (NaN) is "offline".

def city():
    def named(expr, name_from=None, name=None, **labels):
        """Collapse to one series per building, labelled `name` (+ static labels)."""
        src, rx, repl = ("", "", name) if name is not None else (name_from, "(.*)", "$1")
        out = f'max by (name) (label_replace({expr}, "name", "{repl}", "{src}", "{rx}"))'
        for k, v in labels.items():
            out = f'label_replace({out}, "{k}", "{v}", "", "")'
        return out

    def grade(x, ok, warn, lower_is_better=True):
        """1 / 0.5 / 0 by two cut-offs."""
        op = "<" if lower_is_better else ">"
        return f"(0.5 * ({x} {op} bool {warn}) + 0.5 * ({x} {op} bool {ok}))"

    def busy(host):
        return f'100 * (1 - avg(rate(node_cpu_seconds_total{{host="{host}",mode="idle"}}[5m])))'

    def ram(host):
        return (f'100 * (1 - node_memory_MemAvailable_bytes{{host="{host}"}} '
                f'/ node_memory_MemTotal_bytes{{host="{host}"}})')

    hosts = ("imladris", "minas-tirith")
    def pools(expr):
        """imladris tank / fast, renamed to the building names hot-slow / hot-fast."""
        return ('label_replace(label_replace(' + expr + ', "pool", "hot-slow", "pool", "tank"), '
                '"pool", "hot-fast", "pool", "fast")')

    imladris_pools = pools('zfs_pool_health{host="imladris",pool=~"tank|fast"}')
    warm = "warm_pool_free_bytes / warm_pool_size_bytes"
    # The textfile stamp survives unplugging; multiply by the physical disk
    # (BarraCuda ZR15YL21): absent -> scalar() is NaN -> the silo goes dark.
    warm_present = 'scalar(count(node_disk_info{host="imladris",serial="ZR15YL21"}))'

    # (name, type, x, z, facade label). Two blocks stacked along z, the 10G
    # highway between them. As the user looks at it (router block on top):
    # +z = up, +x = left. Each host is ringed by its services; imladris has
    # its pools along the bottom, the router its 1G spurs on the left.
    zi, zm = -9, 9            # host centres (x = 0)
    slots = [
        ("imladris", "tower_a", 0, zi, "NAS"),
        ("qbittorrent", "led_facade", 8, zi + 4, None),
        ("radarr", "display_a", 4, zi + 4, "RADARR"),
        ("lidarr", "display_a", 0, zi + 4, "LIDARR"),
        ("sonarr", "display_a", -4, zi + 4, "SONARR"),
        ("torrserver", "led_facade", -8, zi + 4, None),
        ("jellyfin", "pyramid", 5, zi, None),
        ("prowlarr", "display_a", -5, zi, "PROWLARR"),
        ("hot-fast", "farm_silo", 4, zi - 4, None),
        ("hot-slow", "farm_silo", 0, zi - 4, None),
        ("warm", "farm_silo", -4, zi - 4, None),
        ("minas-tirith", "tower_a", 0, zm, "ROUTER"),
        ("alertmanager", "display_a", 3, zm + 4, "ALERTS"),
        ("prometheus", "farm_silo", -3, zm + 4, None),
        ("grafana", "tower_b", 3, zm - 4, "GRAFANA"),
        ("ntfy", "tower_b", -3, zm - 4, "NTFY"),
        ("vontar", "pyramid", 9, zm + 3, None),
        ("asus-ap", "windmill", 9, zm - 3, None),
    ]

    # text1 is not just the tooltip "Info": towers and displays paint it over
    # their facade label (text2/text3 add lines under it). So a labelled
    # building gets its label as text1; the rest get a tooltip description.
    facade = {n: label for n, _, _, _, label in slots if label}
    info = {
        "asus-ap": ("Wi-Fi AP", "1G · ETH2"),
        "prometheus": ("metrics", "fill = TSDB volume used %"),
        "vontar": ("Vontar X5 · TV box", "1G · ETH1"),
        "jellyfin": ("media server", "via ygg proxy on minas-tirith"),
        "torrserver": ("streaming", None),
        "qbittorrent": ("downloads", None),
        "hot-slow": ("HDD pool tank", "fill = allocated %"),
        "hot-fast": ("NVMe pool fast", "fill = allocated %"),
        "warm": ("warm backup disk warm1", "dark = not plugged in"),
    }
    assert not facade.keys() & info.keys()

    def desc(name):
        if name in facade:
            return {"text1": facade[name]}
        t1, t2 = info[name]
        return {k: v for k, v in (("text1", t1), ("text2", t2)) if v}

    status = " or ".join(
        [named('probe_success{job="icmp-lan"}', "host"),  # imladris, asus-ap, vontar
         named('up{job="node-minas-tirith"}', name="minas-tirith"),
         named('probe_success{job="http-services"}', "service"),
         named('node_systemd_unit_state{host="minas-tirith",name="prometheus.service",state="active"}',
               name="prometheus"),
         named('node_systemd_unit_state{host="minas-tirith",name="alertmanager.service",state="active"}',
               name="alertmanager"),
         named(f"1 - clamp_max({imladris_pools}, 1)", "pool"),
         named(f"{grade(warm, 0.2, 0.1, lower_is_better=False)} * {warm_present}", name="warm")])
    # Static texts ride along as labels on a 0-valued series that is merged
    # into the same row by name.
    text = " or ".join(named("vector(0)", name=n, **desc(n)) for n in sorted(facade | info))

    # Activity (slow / normal / fast) = CPU busy, so a loaded host visibly
    # speeds up; the same series carries the CPU % for the tooltip.
    def with_activity(expr):
        return " or ".join([
            named(f"({expr}) > 60", name_from="name", activity="fast"),
            named(f"({expr}) > 15 <= 60", name_from="name", activity="normal"),
            named(f"({expr}) <= 15", name_from="name", activity="slow")])

    cpu = with_activity(" or ".join(named(busy(h), name=h) for h in hosts))
    mem = " or ".join(named(ram(h), name=h) for h in hosts)
    fill = " or ".join([
        named(pools('100 * zfs_pool_allocated_bytes{host="imladris",pool=~"tank|fast"} '
                    '/ zfs_pool_size_bytes{host="imladris",pool=~"tank|fast"}'), "pool"),
        named(f"100 * (1 - ({warm}))", name="warm"),
        named('100 * (1 - node_filesystem_avail_bytes{host="minas-tirith",mountpoint="/var/lib/prometheus2"} '
              '/ node_filesystem_size_bytes{host="minas-tirith",mountpoint="/var/lib/prometheus2"})',
              name="prometheus")])
    # Traffic on the roads = DAC load. A floor of 15 keeps a few cycles
    # moving on an idle LAN; 1 Gbit/s over the DAC saturates the streets.
    # The column is read from its last row, so every row carries the value.
    dac = ('max(rate(node_network_receive_bytes_total{host="minas-tirith",device="enp1s0f1"}[1m]) '
           'or rate(node_network_transmit_bytes_total{host="minas-tirith",device="enp1s0f1"}[1m])) * 8')
    traffic = f"0 * ({status}) + scalar(clamp_max(15 + 85 * {dac} / 1e9, 100))"

    columns = [("value", status), ("cpu", cpu), ("ram", mem), ("fill", fill),
               ("info", text), ("traffic", traffic)]
    tgts = [target(e, ref=chr(ord("A") + i), instant=True, table=True)
            for i, (_, e) in enumerate(columns)]
    rename = {f"Value #{t['refId']}": col for t, (col, _) in zip(tgts, columns)}
    info_ref = tgts[[c for c, _ in columns].index("info")]["refId"]   # labels only

    buildings = []
    for name, kind, x, z, label in slots:
        b = {"id": name, "name": name, "type": kind, "x": x, "z": z, "rotation": 0}
        if label:
            b["defaultText"] = label
        buildings.append(b)

    # Roads: a ring around each block (the router's is narrower), a 3-lane
    # 10G highway joining the two rings at x=0, and 1-lane 1G spurs from the
    # router ring to the AP / Vontar.
    rz = 6                                         # ring half-depth
    rings = ((zi, 10), (zm, 6))                    # (centre z, half-width)
    x0, z0, width, depth = -10, -15, 21, 31
    cells = set()
    for cz, rx in rings:
        for x in range(-rx, rx + 1):
            cells.update({(x, cz - rz), (x, cz + rz)})
        for z in range(cz - rz, cz + rz + 1):
            cells.update({(-rx, z), (rx, z)})
    for z in range(zi + rz, zm - rz + 1):          # 10G highway
        cells.update({(-1, z), (0, z), (1, z)})
    for x in range(rings[1][1], 9):                # 1G spurs, end next to the box
        cells.update({(x, zm - 3), (x, zm + 3)})
    roads = ["".join("1" if (x0 + i, z0 + j) in cells else "0" for i in range(width))
             for j in range(depth)]

    # The only panel: no row, no title. h=46 = two 1080p screens (23 rows =
    # 866 px fit under Grafana's top bar); the page scrolls.
    panel_ = panel("whooktown-neoncity-panel", "", 24, 46, tgts,
                   options={
                       "nameField": "name",
                       "statusField": "status",
                       "valueField": "value",
                       "thresholds": {"online": 1, "warning": 0.5, "critical": 0},
                       "trafficDensityField": "traffic",
                       "trafficSpeedField": "",
                       "enableTraffic": True,
                       "enableInteraction": True,
                       "showLabels": True,
                       "layout": {"gridSize": 2, "buildings": buildings, "roads": roads,
                                  "roadOrigin": {"x": x0, "z": z0}},
                   },
                   transformations=[
                       {"id": "filterFieldsByName",
                        "options": {"exclude": {"pattern": "^(__name__|Time)$"}}},
                       {"id": "merge", "options": {}},
                       {"id": "organize", "options": {"excludeByName": {f"Value #{info_ref}": True},
                                                      "indexByName": {},
                                                      "renameByName": rename}},
                   ])
    return dashboard("city", "hive city", [row(None, [panel_])],
                     "The hive as a neon city. One block = imladris (NAS) with its "
                     "services and pools (hot-fast = fast, hot-slow = tank, warm = warm1), "
                     "the other = minas-tirith (router) with its services and the 1G spurs "
                     "to the AP and the Vontar box; the 3-lane highway = 10G DAC (traffic "
                     "= its load). Colour = status, speed = CPU, silos = pool fill.")


DASHBOARDS = {"hive.json": hive, "imladris.json": imladris, "minas-tirith.json": minas_tirith,
              "city.json": city}


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
