#!/usr/bin/env python3
"""media-configure: push the media stack's in-app settings (what the *arr,
Prowlarr, qbittorrent and Jellyfin keep in their own SQLite/XML) from the
NixOS config. Idempotent: every resource is matched by name and PUT in place.

Runs as a systemd oneshot on imladris (media-download.nix) after the services
are up; `media-configure` on the host re-runs it by hand. Everything talks to
127.0.0.1 — LAN auth is disabled on the *arr, qbittorrent is reached via the
host's LAN address (its auth bypass is a subnet whitelist).

Environment:
  TRASH                  TRaSH-Guides docs/json (CFs + quality profiles)
  LAN_IP                 this host's LAN address (qbittorrent auth bypass)
  CREDENTIALS_DIRECTORY  systemd LoadCredential: rutracker, kinozal,
                         jellyfin-admin, jellyfin-tv (KEY=VALUE lines)
"""
import glob
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

TRASH = os.environ.get("TRASH", "/tmp/trash/docs/json")
LAN_IP = os.environ.get("LAN_IP", "192.168.10.10")
PORTS = {"prowlarr": 9696, "anilibria": 9697, "radarr": 7878, "sonarr": 8989, "lidarr": 8686, "jellyfin": 8096, "qbittorrent": 8080}
FLARESOLVERR = "http://127.0.0.1:8191"
LIBRARY = {"series": "/tank/media/series", "films": "/tank/media/films", "music": "/tank/media/music",
           "anime": "/tank/media/anime"}
DOWNLOADS = "/tank/media/downloads/complete"
READY_TIMEOUT = 300


def log(*a):
    print(*a, flush=True)


def credential(name):
    """KEY=VALUE lines from $CREDENTIALS_DIRECTORY/media-<name>; {} if absent."""
    d = os.environ.get("CREDENTIALS_DIRECTORY")
    p = os.path.join(d, "media-" + name) if d else None
    if not p or not os.path.exists(p):
        return {}
    out = {}
    for line in open(p):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def http(method, url, body=None, headers=None, timeout=120, raw=False) -> Any:
    data = None
    h = dict(headers or {})
    if body is not None:
        data = json.dumps(body).encode()
        h.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(url, method=method, headers=h, data=data)
    r = urllib.request.urlopen(req, timeout=timeout).read().decode()
    if raw:
        return r
    return json.loads(r) if r.strip() else None


def wait_for(what, probe):
    t0 = time.time()
    while True:
        try:
            v = probe()
            if v:
                return v
        except Exception as e:  # noqa: BLE001 - any failure means "not yet"
            err = e
        else:
            err = "empty"
        if time.time() - t0 > READY_TIMEOUT:
            raise SystemExit(f"{what}: not ready after {READY_TIMEOUT}s ({err})")
        time.sleep(3)


# ---- *arr (Sonarr/Radarr/Lidarr/Prowlarr) ---------------------------------
class Arr:
    def __init__(self, name, api):
        self.name = name
        self.base = f"http://127.0.0.1:{PORTS[name]}"
        self.api = api
        self.key = wait_for(f"{name} api key", self._read_key)
        wait_for(f"{name} api", lambda: self("GET", "/system/status"))

    def _read_key(self):
        txt = http("GET", f"{self.base}/initialize.json", raw=True, timeout=10)
        m = re.search(r'"apiKey": *"([^"]*)', txt)
        return m.group(1) if m else None

    def __call__(self, method, path, body=None):
        try:
            return http(method, f"{self.base}/api/{self.api}{path}", body, {"X-Api-Key": self.key})
        except urllib.error.HTTPError as e:
            msg = e.read().decode()[:600]
            log(f"  !! {self.name} {e.code} {method} {path}: {msg}")
            raise

    def upsert(self, resource, name, pick, fields, extra=None, force=False):
        """Provider-style resource (indexer, downloadclient, notification,
        applications, indexerproxy): template from /<resource>/schema, fields
        by name, matched to the existing item by its name."""
        existing = {r["name"]: r for r in self("GET", f"/{resource}")}
        tpl = next((s for s in self("GET", f"/{resource}/schema") if pick(s)), None)
        if tpl is None:
            log(f"  ?? {self.name}: no schema template for {resource} {name!r}")
            return None
        body = json.loads(json.dumps(tpl))
        body["name"] = name
        body.update(extra or {})
        known = {f["name"] for f in body["fields"]}
        for f in body["fields"]:
            if f["name"] in fields:
                f["value"] = fields[f["name"]]
        for k in set(fields) - known:
            log(f"  ?? {self.name} {resource} {name}: unknown field {k}")
        q = "?forceSave=true" if force else ""
        if name in existing:
            body["id"] = existing[name]["id"]
            r = self("PUT", f"/{resource}/{body['id']}{q}", body)
            log(f"  = {resource} {name}")
        else:
            r = self("POST", f"/{resource}{q}", body)
            log(f"  + {resource} {name}")
        return r

    def upsert_tested(self, *a, **kw):
        """Save with the app's connection test; on failure (tracker down,
        Cloudflare) save anyway so one bad indexer does not block the rest."""
        try:
            return self.upsert(*a, **kw)
        except urllib.error.HTTPError as e:
            if e.code != 400:
                raise
            log("     test failed, saving with forceSave")
            return self.upsert(*a, **kw, force=True)

    def tag(self, label):
        for t in self("GET", "/tag"):
            if t["label"] == label:
                return t["id"]
        return self("POST", "/tag", {"label": label})["id"]

    def patch(self, path, changes):
        cur = self("GET", path)
        if all(cur.get(k) == v for k, v in changes.items()):
            return
        cur.update(changes)
        self("PUT", path, cur)
        log(f"  ~ {path} {sorted(changes)}")

    def root_folder(self, path, **extra):
        for r in self("GET", "/rootfolder"):
            if r["path"].rstrip("/") == path.rstrip("/"):
                if extra and any(r.get(k) != v for k, v in extra.items()):
                    r.update(extra)
                    self("PUT", f"/rootfolder/{r['id']}", r)
                return r["id"]
        log(f"  + rootfolder {path}")
        return self("POST", "/rootfolder", {"path": path, **extra})["id"]


# ---- TRaSH custom formats + quality profiles --------------------------------
RU_AUDIO_RE = (r"\b(RUS(SIAN)?|DUB|MVO|DVO|AVO|LostFilm|Lostfilm|NewStudio|Jaskier|HDRezka|Kuraj-Bambey|"
               r"Red ?Head ?Sound|RHS|TVShows|AlexFilm|Ideafilm|Amedia|Kinopoisk|Кинопоиск|Дубляж|Дублированный|"
               r"Многоголос|Двухголос|Одноголос|Профессиональный|Любительский|Озвуч|Перевод|AniLibria|AniDub|"
               r"AniStar|AniMedia|Dream ?Cast|Studio ?Band|Ancord|SHIZA|JAM|Персона99)\b")
RU_SUB_ONLY_RE = (r"^(?!.*\b(DUB|MVO|DVO|AVO|Дубляж|Многоголос|Двухголос|Одноголос|Профессиональный|"
                  r"Любительский|Озвуч))(?=.*\bSub\b).*$")
LANG_RU = 11  # Sonarr/Radarr Language enum

OWN_CFS = {
    "RU Audio": {
        "name": "RU Audio",
        "includeCustomFormatWhenRenaming": False,
        "specifications": [
            {"name": "Russian language (parsed)", "implementation": "LanguageSpecification",
             "negate": False, "required": False, "fields": {"value": LANG_RU}},
            {"name": "RU dub keywords in title", "implementation": "ReleaseTitleSpecification",
             "negate": False, "required": False, "fields": {"value": RU_AUDIO_RE}},
            {"name": "Not 'Sub' only (Kinozal/RuTracker style)", "implementation": "ReleaseTitleSpecification",
             "negate": True, "required": True, "fields": {"value": RU_SUB_ONLY_RE}},
        ],
    },
}
OWN_SCORES = {"RU Audio": 2500}
# TRaSH scores we override: dubs are wanted, x265 only softly penalised.
SCORE_OVERRIDE = {"Dubs Only": 0, "Anime Dual Audio": 150, "10bit": 10, "Uncensored": 20,
                  "x265": 0, "x265 (no HDR/DV)": -500, "x265 (HD)": -500}

COMMON_NEG = ["BR-DISK", "LQ", "LQ (Release Title)", "Extras", "Upscaled", "Obfuscated", "Retags", "Scene",
              "x265 (no HDR/DV)", "AV1", "DV (w/o HDR fallback)", "Bad Dual Groups"]
COMMON_POS = ["Repack/Proper", "Repack2", "Repack3", "HDR", "HDR10+ Boost", "DV Boost", "DV (Disk)"]
ANIME_TIERS = [f"Anime BD Tier 0{i}" for i in range(1, 9)] + [f"Anime Web Tier 0{i}" for i in range(1, 7)]
ANIME_EXTRA = ["Anime Raws", "Anime LQ Groups", "Uncensored", "v0", "v1", "v2", "v3", "v4", "VRV", "10bit",
               "Anime Dual Audio"]

PROFILES = {
    "sonarr": {
        "WEB-1080p RU": {
            "base": "web-1080p.json",
            "cfs": COMMON_NEG + COMMON_POS + ["WEB Tier 01", "WEB Tier 02", "WEB Tier 03", "WEB Scene",
                                              "HD Bluray Tier 01", "HD Bluray Tier 02", "RU Audio"],
            "qualities": ["Bluray-1080p", "WEB 1080p", "Bluray-720p", "WEB 720p", "HDTV-1080p"],
            "cutoff": "WEB 1080p",
        },
        "Anime RU": {
            "base": "anime-remux-1080p.json",
            "cfs": COMMON_NEG + ["Repack/Proper", "Repack2", "Repack3", "Remux Tier 01", "Remux Tier 02"]
                   + ANIME_TIERS + ANIME_EXTRA + ["RU Audio"],
            "qualities": ["Bluray-1080p Remux", "Bluray-1080p", "WEB 1080p", "Bluray-720p", "WEB 720p",
                          "HDTV-1080p",
                          # pre-BD era titles (Texhnolyze, Lain): AniLiberty's "DVDRip 1080p"
                          # upscales parse as DVD; lowest allowed, any WEB/BD upgrades over it.
                          "DVD"],
            "cutoff": "Bluray-1080p",
        },
        # Native-4K titles only (Netflix originals: Edgerunners, Devilman Crybaby...).
        # Assign per series; default stays Anime RU because most "2160p" anime is upscale.
        "Anime UHD RU": {
            "base": "anime-remux-1080p.json",
            "cfs": COMMON_NEG + COMMON_POS + ["Remux Tier 01", "Remux Tier 02"]
                   + ANIME_TIERS + ANIME_EXTRA + ["RU Audio"],
            "qualities": ["Bluray-2160p Remux", "Bluray-2160p", "WEB 2160p",
                          "Bluray-1080p Remux", "Bluray-1080p", "WEB 1080p"],
            "cutoff": "WEB 2160p",
        },
    },
    "radarr": {
        "UHD Bluray + WEB RU": {
            "base": "uhd-bluray-web.json",
            "cfs": COMMON_NEG + COMMON_POS + ["3D", "Generated Dynamic HDR", "Line/Mic Dubbed",
                                              "UHD Bluray Tier 01", "UHD Bluray Tier 02", "UHD Bluray Tier 03",
                                              "WEB Tier 01", "WEB Tier 02", "WEB Tier 03", "RU Audio"],
            "qualities": ["Bluray-2160p", "WEB 2160p", "Bluray-1080p", "WEB 1080p"],
            "cutoff": "Bluray-2160p",
        },
        "HD Bluray + WEB RU": {
            "base": "hd-bluray-web.json",
            "cfs": COMMON_NEG + COMMON_POS + ["3D", "Line/Mic Dubbed",
                                              "HD Bluray Tier 01", "HD Bluray Tier 02", "HD Bluray Tier 03",
                                              "WEB Tier 01", "WEB Tier 02", "WEB Tier 03", "RU Audio"],
            "qualities": ["Bluray-1080p", "WEB 1080p", "Bluray-720p", "WEB 720p"],
            "cutoff": "Bluray-1080p",
        },
        "Anime RU": {
            "base": "anime-remux-1080p.json",
            "cfs": COMMON_NEG + ["Repack/Proper", "Repack2", "Repack3", "Remux Tier 01", "Remux Tier 02",
                                 "Remux Tier 03"] + ANIME_TIERS + ANIME_EXTRA + ["RU Audio"],
            "qualities": ["Remux-1080p", "Bluray-1080p", "WEB 1080p", "Bluray-720p", "WEB 720p"],
            "cutoff": "Bluray-1080p",
        },
    },
}


def trash_cfs(app):
    cfs = {}
    for f in glob.glob(f"{TRASH}/{app}/cf/*.json"):
        c = json.load(open(f))
        cfs[c["name"]] = c
    return cfs


def cf_body(c):
    return {"name": c["name"],
            "includeCustomFormatWhenRenaming": c.get("includeCustomFormatWhenRenaming", False),
            "specifications": [
                {"name": s["name"], "implementation": s["implementation"], "negate": s["negate"],
                 "required": s["required"], "fields": [{"name": k, "value": v} for k, v in s["fields"].items()]}
                for s in c["specifications"]]}


def sync_cfs(app, wanted):
    trash = trash_cfs(app.name)
    existing = {c["name"]: c for c in app("GET", "/customformat")}
    ids, scores = {}, {}
    for n in sorted(set(wanted)):
        src = OWN_CFS.get(n) or trash.get(n)
        if not src:
            log(f"  ?? no CF source for {n!r}")
            continue
        body = cf_body(src)
        if n in existing:
            body["id"] = existing[n]["id"]
            app("PUT", f"/customformat/{body['id']}", body)
            ids[n] = body["id"]
        else:
            ids[n] = app("POST", "/customformat", body)["id"]
            log(f"  + CF {n}")
        if n in OWN_SCORES:
            scores[n] = OWN_SCORES[n]
        elif n in SCORE_OVERRIDE:
            scores[n] = SCORE_OVERRIDE[n]
        else:
            scores[n] = src.get("trash_scores", {}).get("default", 0)
    return ids, scores


def item_name(it):
    return it.get("name") or it["quality"]["name"]


def item_id(it):
    return it.get("id") or it["quality"]["id"]


def quality_profile(app, name, spec, cf_ids, cf_scores, schema):
    base = json.load(open(f"{TRASH}/{app.name}/quality-profiles/{spec['base']}"))
    items = json.loads(json.dumps(schema["items"]))
    allowed = set(spec["qualities"])
    for it in items:
        it["allowed"] = item_name(it) in allowed
        for sub in it.get("items", []):
            sub["allowed"] = it["allowed"]
    cutoff = next(item_id(it) for it in items if item_name(it) == spec["cutoff"])
    fmt = [{"format": cf_ids[n], "name": n, "score": cf_scores[n]} for n in spec["cfs"] if n in cf_ids]
    present = {f["name"] for f in fmt}
    # every CF in the app must appear in formatItems (score 0 if unused)
    for c in app("GET", "/customformat"):
        if c["name"] not in present:
            fmt.append({"format": c["id"], "name": c["name"], "score": 0})
    body = {
        "name": name, "upgradeAllowed": True, "cutoff": cutoff, "items": items,
        "minFormatScore": base.get("minFormatScore", 0),
        "cutoffFormatScore": base.get("cutoffFormatScore", 10000),
        "minUpgradeFormatScore": base.get("minUpgradeFormatScore", 1),
        "formatItems": fmt,
    }
    if app.name == "radarr":
        body["language"] = {"id": -1, "name": "Any"}  # language is scored by the RU Audio CF
    existing = {p["name"]: p for p in app("GET", "/qualityprofile")}
    if name in existing:
        body["id"] = existing[name]["id"]
        app("PUT", f"/qualityprofile/{body['id']}", body)
        log(f"  = profile {name}")
    else:
        app("POST", "/qualityprofile", body)
        log(f"  + profile {name}")


def trash_profiles(app):
    wanted = {n for p in PROFILES[app.name].values() for n in p["cfs"]}
    cf_ids, cf_scores = sync_cfs(app, wanted)
    schema = app("GET", "/qualityprofile/schema")
    for name, spec in PROFILES[app.name].items():
        quality_profile(app, name, spec, cf_ids, cf_scores, schema)
    log(f"  CFs: {len(cf_ids)}")


# ---- per-app configuration --------------------------------------------------
def jellyfin_notification(app, jf_key, flags):
    app.upsert("notification", "Jellyfin", lambda s: s["implementation"] == "MediaBrowser",
               {"host": "127.0.0.1", "port": PORTS["jellyfin"], "useSsl": False, "apiKey": jf_key,
                "notify": False, "updateLibrary": True},
               {f: True for f in flags})


def qbit_client(app, category_field, category):
    app.upsert("downloadclient", "qBittorrent", lambda s: s["implementation"] == "QBittorrent",
               {"host": LAN_IP, "port": PORTS["qbittorrent"], "useSsl": False, "username": "", "password": "",
                category_field: category},
               {"enable": True, "priority": 1, "removeCompletedDownloads": True, "removeFailedDownloads": True})


def configure_sonarr(jf_key):
    log("== sonarr")
    s = Arr("sonarr", "v3")
    s.root_folder(LIBRARY["series"])
    qbit_client(s, "tvCategory", "tv")
    # Imports copy between datasets (hardlinks fall back); folders 755, files
    # group-writable via the unit's UMask. No rename: Jellyfin reads the
    # release names fine and RU groups' names carry the dub info.
    s.patch("/config/mediamanagement", {"copyUsingHardlinks": True, "chmodFolder": "755",
                                        "setPermissionsLinux": False, "importExtraFiles": False,
                                        "extraFileExtensions": "srt", "enableMediaInfo": True,
                                        "downloadPropersAndRepacks": "preferAndUpgrade"})
    s.patch("/config/naming", {"renameEpisodes": False})
    jellyfin_notification(s, jf_key, ["onDownload", "onUpgrade", "onRename", "onSeriesDelete",
                                      "onEpisodeFileDelete"])
    s.tag("anime")
    trash_profiles(s)
    # Everything is fetched as season packs. Series type "anime" exists for
    # per-episode absolute numbering and makes a season search fan out per
    # episode (Texhnolyze: 380 Prowlarr queries, 4.5 min); "standard" is one
    # query per indexer (9 s) and parses the same E1-22 / S01 packs.
    for sr in s("GET", "/series"):
        if sr["seriesType"] != "standard":
            sr["seriesType"] = "standard"
            s("PUT", f"/series/{sr['id']}", sr)
            log(f"  = series {sr['title']}: standard")
    return s


def configure_radarr(jf_key):
    log("== radarr")
    r = Arr("radarr", "v3")
    r.root_folder(LIBRARY["films"])
    qbit_client(r, "movieCategory", "movies")
    r.patch("/config/mediamanagement", {"copyUsingHardlinks": True, "chmodFolder": "755",
                                        "setPermissionsLinux": False, "importExtraFiles": False,
                                        "extraFileExtensions": "srt", "enableMediaInfo": True,
                                        "downloadPropersAndRepacks": "preferAndUpgrade"})
    r.patch("/config/naming", {"renameMovies": False})
    jellyfin_notification(r, jf_key, ["onDownload", "onUpgrade", "onRename", "onMovieDelete",
                                      "onMovieFileDelete"])
    trash_profiles(r)
    return r


def configure_lidarr(jf_key):
    log("== lidarr")
    ld = Arr("lidarr", "v1")
    qbit_client(ld, "musicCategory", "music")
    # quality profile: Lossless > High Quality Lossy, cutoff Lossless
    schema = ld("GET", "/qualityprofile/schema")
    items = schema["items"]
    for it in items:
        it["allowed"] = item_name(it) in ("Lossless", "High Quality Lossy")
        for sub in it.get("items", []):
            sub["allowed"] = it["allowed"]
    cutoff = next(item_id(it) for it in items if item_name(it) == "Lossless")
    prof = {"name": "FLAC > MP3-320", "upgradeAllowed": True, "cutoff": cutoff, "items": items,
            "minFormatScore": 0, "cutoffFormatScore": 0, "formatItems": schema.get("formatItems", [])}
    existing = {p["name"]: p for p in ld("GET", "/qualityprofile")}
    if prof["name"] in existing:
        prof["id"] = existing[prof["name"]]["id"]
        ld("PUT", f"/qualityprofile/{prof['id']}", prof)
        log(f"  = profile {prof['name']}")
    else:
        prof["id"] = ld("POST", "/qualityprofile", prof)["id"]
        log(f"  + profile {prof['name']}")
    # metadata profile 1: albums + EPs only
    mp = ld("GET", "/metadataprofile/1")
    for t in mp["primaryAlbumTypes"]:
        t["allowed"] = t["albumType"]["name"] in ("Album", "EP")
    ld("PUT", "/metadataprofile/1", mp)
    ld.root_folder(LIBRARY["music"], defaultQualityProfileId=prof["id"], defaultMetadataProfileId=1)
    ld.patch("/config/naming", {
        "renameTracks": True, "replaceIllegalCharacters": True,
        "standardTrackFormat": "{Album Title} ({Release Year})/{Artist Name} - {Album Title} - {track:00} - {Track Title}",
        "multiDiscTrackFormat": "{Album Title} ({Release Year})/{Medium Format} {medium:00}/{Artist Name} - {Album Title} - {track:00} - {Track Title}",
        "artistFolderFormat": "{Artist Name}"})
    ld.patch("/config/mediamanagement", {"importExtraFiles": True, "extraFileExtensions": "jpg,jpeg,png,cue,log",
                                         "setPermissionsLinux": True, "chmodFolder": "775",
                                         "autoUnmonitorPreviouslyDownloadedTracks": True})
    jellyfin_notification(ld, jf_key, ["onReleaseImport", "onUpgrade", "onRename", "onArtistDelete",
                                       "onAlbumDelete", "onTrackRetag"])
    # artists added before the profile existed
    arts = ld("GET", "/artist")
    ids = [a["id"] for a in arts if a["qualityProfileId"] != prof["id"]]
    if ids:
        ld("PUT", "/artist/editor", {"artistIds": ids, "qualityProfileId": prof["id"]})
        log(f"  ~ {len(ids)} artists -> {prof['name']}")
    return ld


def configure_prowlarr(apps):
    log("== prowlarr")
    p = Arr("prowlarr", "v1")
    cf = p.tag("cf")
    p.upsert("indexerproxy", "FlareSolverr", lambda s: s["implementation"] == "FlareSolverr",
             {"host": FLARESOLVERR, "requestTimeout": 60}, {"tags": [cf]})

    def cardigann(definition):
        return lambda s: s["implementation"] == "Cardigann" and s.get("definitionName") == definition

    # Semi-private, behind Cloudflare -> FlareSolverr via the `cf` tag. Titles
    # keep their Cyrillic and get a RUS marker: both feed the RU Audio CF.
    rt = credential("rutracker")
    if rt:
        p.upsert_tested("indexer", "RuTracker.org", lambda s: s["implementation"] == "RuTracker",
                        {"baseUrl": "https://rutracker.org/", "username": rt["USERNAME"],
                         "password": rt["PASSWORD"], "russianLetters": True, "addRussianToTitle": True,
                         "useMagnetLinks": False, "moveAllTagsToEndOfReleaseTitle": True},
                        {"tags": [cf], "enable": True, "priority": 25, "appProfileId": 1})
    else:
        log("  -- no rutracker credential, skipped")
    kz = credential("kinozal")
    if kz:
        p.upsert_tested("indexer", "Kinozal", cardigann("kinozal"),
                        {"baseUrl": "https://kinozal.me/", "username": kz["USERNAME"], "password": kz["PASSWORD"],
                         "stripcyrillic": True, "addrussian": True},
                        {"tags": [cf], "enable": True, "priority": 25, "appProfileId": 1})
    else:
        log("  -- no kinozal credential, skipped")
    p.upsert_tested("indexer", "RuTor", cardigann("rutor"),
                    {"baseUrl": "https://rutor.info/", "stripcyrillic": True, "addrussiantotitle": True},
                    {"enable": True, "priority": 25, "appProfileId": 1})
    p.upsert_tested("indexer", "Nyaa.si", cardigann("nyaasi"),
                    {"prefer_magnet_links": True, "type": 1},
                    {"enable": True, "priority": 25, "appProfileId": 1})
    p.upsert_tested("indexer", "Anime Tosho", cardigann("animetosho-xyz"),
                    {}, {"enable": True, "priority": 25, "appProfileId": 1})
    # AniLiberty via the local anilibria-torznab bridge (media-download.nix).
    # RU dub, 1080p WEB-DL; titles carry RUS so the RU Audio CF scores them.
    # Priority 10 (lower = preferred) so it wins ties against raw Nyaa.
    al = credential("anilibria")
    if al.get("API_KEY"):
        p.upsert_tested("indexer", "AniLiberty",
                        lambda s: s["implementation"] == "Torznab" and s["name"] == "Generic Torznab",
                        {"baseUrl": f"http://127.0.0.1:{PORTS['anilibria']}", "apiPath": "/api",
                         "apiKey": al["API_KEY"], "torrentBaseSettings.preferMagnetUrl": True},
                        {"enable": True, "priority": 10, "appProfileId": 1})
    else:
        log("  -- no anilibria api key (bridge not up yet?), skipped")

    # Apps: full sync. RuTor returns no categories, so 8000 (Other) is synced too.
    tv = [5000, 5010, 5020, 5030, 5040, 5045, 5050, 5060, 5070, 5080, 5090, 8000]
    movies = [2000, 2010, 2020, 2030, 2040, 2045, 2050, 2060, 2070, 2080, 2090, 8000]
    audio = [3000, 3010, 3020, 3030, 3040, 3050, 3060]
    me = f"http://127.0.0.1:{PORTS['prowlarr']}"
    # Sonarr is addOnly: Prowlarr adds new indexers but does not overwrite
    # them, so tune_sonarr_indexers() below owns the per-indexer anime flags.
    for impl, cats, level, extra in (
            ("Sonarr", tv, "addOnly", {"animeSyncCategories": [5070], "syncAnimeStandardFormatSearch": False}),
            ("Radarr", movies, "fullSync", {}), ("Lidarr", audio, "fullSync", {})):
        a = apps[impl.lower()]
        p.upsert_tested("applications", impl, lambda s, i=impl: s["implementation"] == i,
                        {"prowlarrUrl": me, "baseUrl": a.base, "apiKey": a.key, "syncCategories": cats, **extra},
                        {"syncLevel": level, "enable": True})
    p("POST", "/command", {"name": "ApplicationIndexerSync"})
    return p


# Sonarr indexers synced from Prowlarr. A season search on an anime series
# fans out per episode; the "standard format" duplicate doubled it and
# Kinozal has nothing for anime -- 380 queries / 4.5 min on Texhnolyze.
NO_ANIME_INDEXERS = {"Kinozal"}


def tune_sonarr_indexers(s, p):
    log("== sonarr indexers")
    want = {f"{i['name']} (Prowlarr)" for i in p("GET", "/indexer") if i.get("enable")}
    wait_for("prowlarr -> sonarr sync", lambda: want <= {i["name"] for i in s("GET", "/indexer")} or None)
    for i in s("GET", "/indexer"):
        f = {x["name"]: x for x in i["fields"]}
        anime = [] if i["name"].replace(" (Prowlarr)", "") in NO_ANIME_INDEXERS else [5070]
        changes = {"animeStandardFormatSearch": False, "animeCategories": anime}
        if all(f[k]["value"] == v for k, v in changes.items() if k in f):
            continue
        for k, v in changes.items():
            if k in f:
                f[k]["value"] = v
        s("PUT", f"/indexer/{i['id']}", i)
        log(f"  = {i['name']}: anime={'off' if not anime else 'on'}, stdFormat=off")


def configure_qbittorrent():
    log("== qbittorrent")
    base = f"http://{LAN_IP}:{PORTS['qbittorrent']}/api/v2"
    cats = wait_for("qbittorrent", lambda: http("GET", f"{base}/torrents/categories") or {})
    for c in ("tv", "movies", "music"):
        path = f"{DOWNLOADS}/{c}"
        form = urllib.parse.urlencode({"category": c, "savePath": path}).encode()
        hdr = {"Content-Type": "application/x-www-form-urlencoded"}
        if c not in cats:
            urllib.request.urlopen(urllib.request.Request(f"{base}/torrents/createCategory", data=form, headers=hdr))
            log(f"  + category {c}")
        elif cats[c].get("savePath") != path:
            urllib.request.urlopen(urllib.request.Request(f"{base}/torrents/editCategory", data=form, headers=hdr))
            log(f"  ~ category {c} -> {path}")

    # No seeding: stop the torrent the moment it completes (ratio 0, action
    # Stop). The *arr import from a stopped torrent, then remove it.
    want = {"max_ratio_enabled": True, "max_ratio": 0, "max_ratio_act": 0}
    prefs = http("GET", f"{base}/app/preferences")
    if any(prefs.get(k) != v for k, v in want.items()):
        form = urllib.parse.urlencode({"json": json.dumps(want)}).encode()
        urllib.request.urlopen(urllib.request.Request(f"{base}/app/setPreferences", data=form, headers=hdr))
        log("  ~ share limit: stop at ratio 0")


# ---- Jellyfin ----------------------------------------------------------------
class Jellyfin:
    LIBS = [  # (name, type, path)
        ("Фильмы", "movies", LIBRARY["films"]),
        ("Сериалы", "tvshows", LIBRARY["series"]),
        ("Аниме", "tvshows", LIBRARY["anime"]),
        ("Музыка", "music", LIBRARY["music"]),
    ]
    # libraries that used to exist and must go (cartoons folded into films/series)
    RETIRED = ["Мультфильмы"]

    def __init__(self):
        self.base = f"http://127.0.0.1:{PORTS['jellyfin']}"
        self.auth = 'MediaBrowser Client="media-configure", Device="imladris", DeviceId="media-configure", Version="1"'
        self.token = None

    def __call__(self, method, path, body=None, raw=False):
        h = {"Authorization": self.auth + (f', Token="{self.token}"' if self.token else "")}
        try:
            return http(method, self.base + path, body, h, raw=raw)
        except urllib.error.HTTPError as e:
            log(f"  !! jellyfin {e.code} {method} {path}: {e.read().decode()[:300]}")
            raise

    def login(self, user, pw):
        r = http("POST", f"{self.base}/Users/AuthenticateByName", {"Username": user, "Pw": pw},
                 {"Authorization": self.auth})
        return r["AccessToken"]


def configure_jellyfin():
    log("== jellyfin")
    jf = Jellyfin()
    pub = wait_for("jellyfin", lambda: jf("GET", "/System/Info/Public"))
    admin = credential("jellyfin-admin")
    if not admin:
        log("  -- no jellyfin-admin credential: wizard/libraries/users skipped")
        return None
    if not pub["StartupWizardCompleted"]:
        cfg = jf("GET", "/Startup/Configuration")
        cfg.update({"UICulture": "ru", "MetadataCountryCode": "RU", "PreferredMetadataLanguage": "ru"})
        jf("POST", "/Startup/Configuration", cfg)
        jf("GET", "/Startup/User")
        jf("POST", "/Startup/User", {"Name": admin["USERNAME"], "Password": admin["PASSWORD"]})
        jf("POST", "/Startup/RemoteAccess", {"EnableRemoteAccess": False, "EnableAutomaticPortMapping": False})
        jf("POST", "/Startup/Complete")
        log("  + wizard done")
    jf.token = jf.login(admin["USERNAME"], admin["PASSWORD"])

    existing = {v["Name"]: v for v in jf("GET", "/Library/VirtualFolders")}
    for name in jf.RETIRED:
        if name in existing:
            q = urllib.parse.urlencode({"name": name, "refreshLibrary": "true"})
            jf("DELETE", f"/Library/VirtualFolders?{q}", raw=True)
            log(f"  - library {name}")
    for name, typ, path in jf.LIBS:
        if name in existing:
            continue
        opts = {"LibraryOptions": {
            "EnableRealtimeMonitor": True, "EnablePhotos": False,
            "PreferredMetadataLanguage": "ru", "MetadataCountryCode": "RU",
            "SaveLocalMetadata": False, "EnableChapterImageExtraction": False,
            "PathInfos": [{"Path": path}],
        }}
        q = urllib.parse.urlencode({"name": name, "collectionType": typ, "refreshLibrary": "true"})
        jf("POST", f"/Library/VirtualFolders?{q}", opts, raw=True)
        log(f"  + library {name} ({typ}) {path}")

    sc = jf("GET", "/System/Configuration")
    if sc.get("EnableMetrics"):
        sc["EnableMetrics"] = False
        jf("POST", "/System/Configuration", sc, raw=True)

    # viewer account (TV box, phone): no admin, no deletion, Russian audio/subs
    tv = credential("jellyfin-tv")
    if tv:
        users = {u["Name"]: u for u in jf("GET", "/Users")}
        if tv["USERNAME"] not in users:
            u = jf("POST", "/Users/New", {"Name": tv["USERNAME"], "Password": tv["PASSWORD"]})
            users[tv["USERNAME"]] = u
            log(f"  + user {tv['USERNAME']}")
        u = users[tv["USERNAME"]]
        try:
            jf.login(tv["USERNAME"], tv["PASSWORD"])
        except urllib.error.HTTPError:
            jf("POST", f"/Users/{u['Id']}/Password", {"NewPw": tv["PASSWORD"]}, raw=True)
            log(f"  ~ user {tv['USERNAME']} password")
        pol = dict(u["Policy"])
        pol.update({"IsAdministrator": False, "EnableContentDeletion": False, "EnableRemoteAccess": True,
                    "EnableMediaPlayback": True, "EnableAllFolders": True, "EnableAllDevices": True})
        if pol != u["Policy"]:
            jf("POST", f"/Users/{u['Id']}/Policy", pol, raw=True)
            log(f"  ~ user {tv['USERNAME']} policy")
        conf = dict(u["Configuration"])
        conf.update({"AudioLanguagePreference": "rus", "SubtitleLanguagePreference": "rus",
                     "PlayDefaultAudioTrack": False, "SubtitleMode": "Smart",
                     "RememberAudioSelections": True, "RememberSubtitleSelections": True})
        if conf != u["Configuration"]:
            jf("POST", f"/Users/{u['Id']}/Configuration", conf, raw=True)
            log(f"  ~ user {tv['USERNAME']} configuration")

    # API key for the *arr "Jellyfin" notification (library refresh on import)
    keys = jf("GET", "/Auth/Keys")["Items"]
    key = next((k["AccessToken"] for k in keys if k["AppName"] == "arr-stack"), None)
    if not key:
        jf("POST", "/Auth/Keys?app=arr-stack", raw=True)
        keys = jf("GET", "/Auth/Keys")["Items"]
        key = next(k["AccessToken"] for k in keys if k["AppName"] == "arr-stack")
        log("  + api key arr-stack")
    return key


# ---- debugging helper --------------------------------------------------------
def search(app_name, query, n=14):
    """media-configure search sonarr 'seriesId=1&seasonNumber=1' [n]:
    top releases with CF scores, to sanity-check a profile."""
    app = Arr(app_name, "v3")
    rs = app("GET", f"/release?{query}")
    rs.sort(key=lambda r: (-r.get("customFormatScore", 0), -r.get("seeders", 0)))
    print(len(rs), "releases")
    for r in rs[:n]:
        cfs = [c["name"] for c in r.get("customFormats", [])]
        rej = r.get("rejections", [])
        print(f'{r["customFormatScore"]:>7} ok={str(r["approved"])[0]} '
              f'{r["indexer"].replace(" (Prowlarr)", "")[:9]:9} {r["quality"]["quality"]["name"]:13} '
              f's={r["seeders"]:<5} {cfs} | {r["title"][:60]} {("REJ:" + rej[0][:40]) if rej else ""}')


def main(argv):
    if argv[1:2] == ["search"]:
        return search(argv[2], argv[3], int(argv[4]) if len(argv) > 4 else 14)
    jf_key = configure_jellyfin()
    configure_qbittorrent()
    apps = {
        "sonarr": configure_sonarr(jf_key),
        "radarr": configure_radarr(jf_key),
        "lidarr": configure_lidarr(jf_key),
    }
    p = configure_prowlarr(apps)
    tune_sonarr_indexers(apps["sonarr"], p)
    log("done")


if __name__ == "__main__":
    main(sys.argv)
