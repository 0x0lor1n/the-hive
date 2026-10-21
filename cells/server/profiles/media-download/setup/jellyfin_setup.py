import json, sys, urllib.request, urllib.parse, urllib.error, time
J = "http://192.168.10.10:8096"
H = {"Content-Type": "application/json",
     "Authorization": 'MediaBrowser Client="hermes", Device="setup", DeviceId="hermes-setup", Version="1"'}
TOKEN = None

def call(method, path, body=None, raw=False):
    h = dict(H)
    if TOKEN: h["Authorization"] += f', Token="{TOKEN}"'
    req = urllib.request.Request(J + path, method=method, headers=h,
                                 data=json.dumps(body).encode() if body is not None else None)
    try:
        r = urllib.request.urlopen(req, timeout=60).read().decode()
    except urllib.error.HTTPError as e:
        print("  !!", e.code, method, path, e.read().decode()[:300]); raise
    return r if raw else (json.loads(r) if r.strip() else None)

user, pw = sys.argv[1], sys.argv[2]
pub = call("GET", "/System/Info/Public")
print("Jellyfin", pub["Version"], "wizard completed:", pub["StartupWizardCompleted"])

if not pub["StartupWizardCompleted"]:
    cfg = call("GET", "/Startup/Configuration")
    cfg.update({"UICulture": "ru", "MetadataCountryCode": "RU", "PreferredMetadataLanguage": "ru"})
    call("POST", "/Startup/Configuration", cfg)
    call("GET", "/Startup/User")
    call("POST", "/Startup/User", {"Name": user, "Password": pw})
    call("POST", "/Startup/RemoteAccess", {"EnableRemoteAccess": False, "EnableAutomaticPortMapping": False})
    call("POST", "/Startup/Complete")
    print("wizard done")

auth = call("POST", "/Users/AuthenticateByName", {"Username": user, "Pw": pw})
TOKEN = auth["AccessToken"]; print("auth ok, user", auth["User"]["Name"])

LIBS = [  # (name, type, path)
    ("Фильмы", "movies", "/tank/media/films"),
    ("Сериалы", "tvshows", "/tank/media/series"),
    ("Аниме", "tvshows", "/tank/media/anime"),
    ("Мультфильмы", "movies", "/tank/media/cartoons"),
    ("Музыка", "music", "/tank/media/music"),
]
existing = {v["Name"]: v for v in call("GET", "/Library/VirtualFolders")}
for name, typ, path in LIBS:
    if name in existing:
        print("  = lib", name, "exists"); continue
    opts = {"LibraryOptions": {
        "EnableRealtimeMonitor": True, "EnablePhotos": False,
        "PreferredMetadataLanguage": "ru", "MetadataCountryCode": "RU",
        "SaveLocalMetadata": False, "EnableChapterImageExtraction": False,
        "PathInfos": [{"Path": path}],
    }}
    q = urllib.parse.urlencode({"name": name, "collectionType": typ, "refreshLibrary": "false"})
    call("POST", f"/Library/VirtualFolders?{q}", opts, raw=True)
    print("  + lib", name, typ, path)

# transcoding: encoding.xml is nix-owned (media-download.nix), not touched here.

# server: LAN-only, no UPnP
sc = call("GET", "/System/Configuration")
sc["EnableMetrics"] = False
call("POST", "/System/Configuration", sc, raw=True)
call("POST", "/Library/Refresh", raw=True)
print("library scan started; apiKey for *arr:")
call("POST", "/Auth/Keys?app=arr-stack", raw=True)
keys = call("GET", "/Auth/Keys")
print([k["AccessToken"] for k in keys["Items"] if k["AppName"] == "arr-stack"][0])
