#!/usr/bin/env python3
"""Apply TRaSH custom formats + profiles to Sonarr/Radarr, with a Russian-audio preference.
Idempotent: CFs matched by name (update), profiles matched by name (update)."""
import json, glob, re, sys, urllib.request, urllib.error

TRASH = "/tmp/trash/docs/json"
APPS = {
    "sonarr": {"url": "http://127.0.0.1:18989", "profile_lang": None},
    "radarr": {"url": "http://127.0.0.1:17878"},
}

# ---- our own custom formats (not in TRaSH) ----------------------------------
RU_AUDIO_RE = (r"\b(RUS(SIAN)?|DUB|MVO|DVO|AVO|LostFilm|Lostfilm|NewStudio|Jaskier|HDRezka|Kuraj-Bambey|"
               r"Red ?Head ?Sound|RHS|TVShows|AlexFilm|Ideafilm|Amedia|Kinopoisk|Кинопоиск|Дубляж|Дублированный|"
               r"Многоголос|Двухголос|Одноголос|Профессиональный|Любительский|Озвуч|Перевод|AniLibria|AniDub|"
               r"AniStar|AniMedia|Dream ?Cast|Studio ?Band|Ancord|SHIZA|JAM|Персона99)\b")
RU_SUB_ONLY_RE = r"\b(Sub(s|titles)?)\b"

def own_cfs(app):
    lang_ru = 11  # Russian in Sonarr/Radarr Language enum
    ru_audio = {
        "name": "RU Audio",
        "includeCustomFormatWhenRenaming": False,
        "specifications": [
            {"name": "Russian language (parsed)", "implementation": "LanguageSpecification",
             "negate": False, "required": False, "fields": {"value": lang_ru}},
            {"name": "RU dub keywords in title", "implementation": "ReleaseTitleSpecification",
             "negate": False, "required": False, "fields": {"value": RU_AUDIO_RE}},
            {"name": "Not 'Sub' only (Kinozal/RuTracker style)", "implementation": "ReleaseTitleSpecification",
             "negate": True, "required": True,
             "fields": {"value": r"^(?!.*\b(DUB|MVO|DVO|AVO|Дубляж|Многоголос|Двухголос|Одноголос|Профессиональный|Любительский|Озвуч))(?=.*\bSub\b).*$"}},
        ],
    }
    return [ru_audio]

OWN_SCORES = {"RU Audio": 2500}

# TRaSH CF sets ---------------------------------------------------------------
COMMON_NEG = ["BR-DISK", "LQ", "LQ (Release Title)", "Extras", "Upscaled", "Obfuscated", "Retags", "Scene",
              "x265 (no HDR/DV)", "AV1", "DV (w/o HDR fallback)", "Bad Dual Groups"]
COMMON_POS = ["Repack/Proper", "Repack2", "Repack3", "HDR", "HDR10+ Boost", "DV Boost", "DV (Disk)"]
ANIME_TIERS = [f"Anime BD Tier 0{i}" for i in range(1, 9)] + [f"Anime Web Tier 0{i}" for i in range(1, 7)]
ANIME_EXTRA = ["Anime Raws", "Anime LQ Groups", "Uncensored", "v0", "v1", "v2", "v3", "v4", "VRV", "10bit", "Anime Dual Audio"]

PROFILES = {
    "sonarr": {
        "WEB-1080p RU": {
            "base": "web-1080p.json",
            "cfs": COMMON_NEG + COMMON_POS + ["WEB Tier 01", "WEB Tier 02", "WEB Tier 03", "WEB Scene",
                                              "HD Bluray Tier 01", "HD Bluray Tier 02", "RU Audio"],
            "qualities_allowed": ["Bluray-1080p", "WEB 1080p", "Bluray-720p", "WEB 720p", "HDTV-1080p"],
            "cutoff": "WEB 1080p",
        },
        "Anime RU": {
            "base": "anime-remux-1080p.json",
            "cfs": COMMON_NEG + ["Repack/Proper", "Repack2", "Repack3", "Remux Tier 01", "Remux Tier 02"]
                   + ANIME_TIERS + ANIME_EXTRA + ["RU Audio"],
            "qualities_allowed": ["Bluray-1080p Remux", "Bluray-1080p", "WEB 1080p", "Bluray-720p", "WEB 720p", "HDTV-1080p"],
            "cutoff": "Bluray-1080p",
        },
    },
    "radarr": {
        "UHD Bluray + WEB RU": {
            "base": "uhd-bluray-web.json",
            "cfs": COMMON_NEG + COMMON_POS + ["3D", "Generated Dynamic HDR", "Line/Mic Dubbed",
                                              "UHD Bluray Tier 01", "UHD Bluray Tier 02", "UHD Bluray Tier 03",
                                              "WEB Tier 01", "WEB Tier 02", "WEB Tier 03", "RU Audio"],
            "qualities_allowed": ["Bluray-2160p", "WEB 2160p", "Bluray-1080p", "WEB 1080p"],
            "cutoff": "Bluray-2160p",
        },
        "HD Bluray + WEB RU": {
            "base": "hd-bluray-web.json",
            "cfs": COMMON_NEG + COMMON_POS + ["3D", "Line/Mic Dubbed",
                                              "HD Bluray Tier 01", "HD Bluray Tier 02", "HD Bluray Tier 03",
                                              "WEB Tier 01", "WEB Tier 02", "WEB Tier 03", "RU Audio"],
            "qualities_allowed": ["Bluray-1080p", "WEB 1080p", "Bluray-720p", "WEB 720p"],
            "cutoff": "Bluray-1080p",
        },
        "Anime RU": {
            "base": "anime-remux-1080p.json",
            "cfs": COMMON_NEG + ["Repack/Proper", "Repack2", "Repack3", "Remux Tier 01", "Remux Tier 02", "Remux Tier 03"]
                   + ANIME_TIERS + ANIME_EXTRA + ["RU Audio"],
            "qualities_allowed": ["Remux-1080p", "Bluray-1080p", "WEB 1080p", "Bluray-720p", "WEB 720p"],
            "cutoff": "Bluray-1080p",
        },
    },
}
# TRaSH scores we override: don't nuke dubs (we WANT dubs), and penalize non-RU with 'Sub' only lightly
SCORE_OVERRIDE = {"Dubs Only": 0, "Anime Dual Audio": 150, "10bit": 10, "Uncensored": 20, "x265": 0, "x265 (no HDR/DV)": -500, "x265 (HD)": -500}


def api(app, method, path, body=None):
    cfg = APPS[app]
    key = re.search(r'"apiKey": *"([^"]*)', urllib.request.urlopen(cfg["url"] + "/initialize.json").read().decode()).group(1)
    req = urllib.request.Request(cfg["url"] + "/api/v3" + path, method=method,
                                 headers={"X-Api-Key": key, "Content-Type": "application/json"},
                                 data=json.dumps(body).encode() if body is not None else None)
    try:
        r = urllib.request.urlopen(req).read().decode()
    except urllib.error.HTTPError as e:
        print("  !! HTTP", e.code, method, path, e.read().decode()[:400]); raise
    return json.loads(r) if r else None


def load_trash_cfs(app):
    cfs = {}
    for f in glob.glob(f"{TRASH}/{app}/cf/*.json"):
        c = json.load(open(f)); cfs[c["name"]] = c
    return cfs


def strip_cf(c):
    """TRaSH json -> API body."""
    return {"name": c["name"],
            "includeCustomFormatWhenRenaming": c.get("includeCustomFormatWhenRenaming", False),
            "specifications": [
                {"name": s["name"], "implementation": s["implementation"], "negate": s["negate"],
                 "required": s["required"], "fields": [{"name": k, "value": v} for k, v in s["fields"].items()]}
                for s in c["specifications"]]}


def sync_cfs(app, wanted_names):
    trash = load_trash_cfs(app)
    own = {c["name"]: c for c in own_cfs(app)}
    existing = {c["name"]: c for c in api(app, "GET", "/customformat")}
    ids, scores = {}, {}
    for n in sorted(set(wanted_names)):
        src = own.get(n) or trash.get(n)
        if not src:
            print(f"  ?? no CF source for {n!r}"); continue
        body = strip_cf(src)
        if n in existing:
            body["id"] = existing[n]["id"]
            api(app, "PUT", f"/customformat/{body['id']}", body); ids[n] = body["id"]
        else:
            ids[n] = api(app, "POST", "/customformat", body)["id"]; print(f"  + CF {n}")
        if n in OWN_SCORES: scores[n] = OWN_SCORES[n]
        elif n in SCORE_OVERRIDE: scores[n] = SCORE_OVERRIDE[n]
        else: scores[n] = src.get("trash_scores", {}).get("default", 0)
    return ids, scores


def build_profile(app, name, spec, cf_ids, cf_scores, existing_profiles, schema):
    base = json.load(open(f"{TRASH}/{app}/quality-profiles/{spec['base']}"))
    # quality items: take the schema's full items list, then set allowed per base/override
    items = json.loads(json.dumps(schema["items"]))
    allowed = set(spec.get("qualities_allowed") or [(q.get("name") or q["quality"]["name"]) for q in base["items"] if q.get("allowed")])
    for it in items:
        nm = it.get("name") or it["quality"]["name"]
        it["allowed"] = nm in allowed
        for sub in it.get("items", []): sub["allowed"] = it["allowed"]
    # Sonarr/Radarr require cutoff to be an allowed item's id
    cutoff_name = spec["cutoff"]
    cutoff_id = None
    for it in items:
        nm = it.get("name") or it["quality"]["name"]
        if nm == cutoff_name: cutoff_id = it.get("id") or it["quality"]["id"]
    assert cutoff_id is not None, f"cutoff {cutoff_name} not found"
    # order: Sonarr wants best-quality last in list (items ordered worst->best); schema is already correct
    fmt_items = [{"format": cf_ids[n], "name": n, "score": cf_scores[n]} for n in spec["cfs"] if n in cf_ids]
    # every CF in the app must be present in formatItems (score 0 if not used)
    present = {f["name"] for f in fmt_items}
    for n, i in cf_ids.items():
        if n not in present: fmt_items.append({"format": i, "name": n, "score": 0})
    body = {
        "name": name, "upgradeAllowed": True, "cutoff": cutoff_id, "items": items,
        "minFormatScore": base.get("minFormatScore", 0),
        "cutoffFormatScore": base.get("cutoffFormatScore", 10000),
        "minUpgradeFormatScore": base.get("minUpgradeFormatScore", 1),
        "formatItems": fmt_items,
    }
    if app == "radarr":
        body["language"] = {"id": -1, "name": "Any"}   # language handled via RU Audio CF
    if name in existing_profiles:
        body["id"] = existing_profiles[name]["id"]
        api(app, "PUT", f"/qualityprofile/{body['id']}", body); print(f"  ~ profile {name} updated (id {body['id']})")
    else:
        r = api(app, "POST", "/qualityprofile", body); print(f"  + profile {name} created (id {r['id']})")


def main():
    for app in (sys.argv[1:] or APPS):
        print(f"== {app}")
        wanted = sorted({n for p in PROFILES[app].values() for n in p["cfs"]})
        cf_ids, cf_scores = sync_cfs(app, wanted)
        schema = api(app, "GET", "/qualityprofile/schema")
        existing = {p["name"]: p for p in api(app, "GET", "/qualityprofile")}
        for name, spec in PROFILES[app].items():
            build_profile(app, name, spec, cf_ids, cf_scores, existing, schema)
        print(f"  CFs: {len(cf_ids)}  (RU Audio id={cf_ids.get('RU Audio')})")

if __name__ == "__main__":
    main()
