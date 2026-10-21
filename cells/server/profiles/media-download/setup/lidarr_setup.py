import json, re, urllib.request, urllib.error
B = "http://127.0.0.1:18686"
key = re.search(r'"apiKey": *"([^"]*)', urllib.request.urlopen(B + "/initialize.json").read().decode()).group(1)
def api(m, p, body=None):
    req = urllib.request.Request(B + "/api/v1" + p, method=m, headers={"X-Api-Key": key, "Content-Type": "application/json"},
                                 data=json.dumps(body).encode() if body is not None else None)
    try: r = urllib.request.urlopen(req).read().decode()
    except urllib.error.HTTPError as e: print("!!", e.code, m, p, e.read().decode()[:300]); raise
    return json.loads(r) if r.strip() else None

# 1. quality profile: Lossless > High Quality Lossy, cutoff Lossless
schema = api("GET", "/qualityprofile/schema")
items = schema["items"]
for it in items:
    nm = it.get("name") or it["quality"]["name"]
    it["allowed"] = nm in ("Lossless", "High Quality Lossy")
    for s in it.get("items", []): s["allowed"] = it["allowed"]
prof = {"name": "FLAC > MP3-320", "upgradeAllowed": True, "cutoff": 1005, "items": items,
        "minFormatScore": 0, "cutoffFormatScore": 0, "formatItems": schema.get("formatItems", [])}
ex = {p["name"]: p for p in api("GET", "/qualityprofile")}
if prof["name"] in ex:
    prof["id"] = ex[prof["name"]]["id"]; api("PUT", f"/qualityprofile/{prof['id']}", prof)
else:
    prof["id"] = api("POST", "/qualityprofile", prof)["id"]
print("profile id", prof["id"])

# 2. root folder default profile
rf = api("GET", "/rootfolder/1"); rf["defaultQualityProfileId"] = prof["id"]; api("PUT", "/rootfolder/1", rf)

# 3. naming (TRaSH recommended), rename on
n = api("GET", "/config/naming")
n.update({"renameTracks": True, "replaceIllegalCharacters": True,
          "standardTrackFormat": "{Album Title} ({Release Year})/{Artist Name} - {Album Title} - {track:00} - {Track Title}",
          "multiDiscTrackFormat": "{Album Title} ({Release Year})/{Medium Format} {medium:00}/{Artist Name} - {Album Title} - {track:00} - {Track Title}",
          "artistFolderFormat": "{Artist Name}"})
api("PUT", "/config/naming", n)

# 4. media management: keep cue/log/covers, group-writable
mm = api("GET", "/config/mediamanagement")
mm.update({"importExtraFiles": True, "extraFileExtensions": "jpg,jpeg,png,cue,log",
           "setPermissionsLinux": True, "chmodFolder": "775",
           "autoUnmonitorPreviouslyDownloadedTracks": True})
api("PUT", "/config/mediamanagement", mm)

# 5. switch artists
arts = api("GET", "/artist")
ids = [a["id"] for a in arts if a["qualityProfileId"] != prof["id"]]
if ids:
    api("PUT", "/artist/editor", {"artistIds": ids, "qualityProfileId": prof["id"], "monitored": True,
                                  "monitorNewItems": "none"})
print("artists switched:", len(ids), "of", len(arts))
# metadata profile: Album + EP, Studio, Official
mp = api("GET", "/metadataprofile/1")
for t in mp["primaryAlbumTypes"]: t["allowed"] = t["albumType"]["name"] in ("Album", "EP")
api("PUT", "/metadataprofile/1", mp)
print("done")
