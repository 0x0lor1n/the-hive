# Media stack: the imperative part

Everything in `media-download.nix` is declarative (services, firewall, datasets,
Jellyfin `encoding.xml`). What the *arr/qbittorrent/Jellyfin keep in their own
SQLite/XML is NOT, and this file is the full list of what was done by hand or
via API on 2026-10-21 so it can be replayed on a fresh state dataset.

Scripts here are idempotent (match by name/id, PUT in place). Run from the
laptop with SSH port forwards:

    ssh -N -L 18989:127.0.0.1:8989 -L 17878:127.0.0.1:7878 \
           -L 18686:127.0.0.1:8686 -L 19696:127.0.0.1:9696 imladris &

API keys are read from each app's `/initialize.json` (LAN auth is disabled).

## Order

1. qbittorrent  (manual, Web UI http://imladris:8080)
2. Prowlarr     (manual — credentials)
3. Sonarr / Radarr / Lidarr  (manual root+client, then scripts)
4. Jellyfin     (`jellyfin_setup.py`)
5. Vontar X5    (adb)

## 1. qbittorrent

Config seeded once by nix (`qbittorrent-seed`), then owned by the UI.
Done in UI / API (`/api/v2/torrents/createCategory`):

| category | save path |
|---|---|
| `tv`     | `/tank/media/downloads/complete/tv` |
| `movies` | `/tank/media/downloads/complete/movies` |
| `music`  | `/tank/media/downloads/complete/music` |

Everything else (save/temp paths, port 42001, LAN auth bypass, legal notice)
is in the nix seed — see `qbittorrent-seed` in `media-download.nix`.

## 2. Prowlarr

Indexers (Settings → Indexers, credentials are the user's, never here):

| name | type | notes |
|---|---|---|
| RuTracker.org | Cardigann, semi-private, `https://rutracker.org/` | tag `cf` (FlareSolverr); `Strip Russian letters` off, `Add RUS to titles` off |
| Kinozal | Cardigann, semi-private, `https://kinozal.me/` | tag `cf`, same |
| RuTor | public, `https://rutor.info/` | |
| Nyaa.si | public | anime |
| Anime Tosho | public | anime, aggregator of Nyaa/AniDex/TokyoTosho |

Settings → Indexers → Indexer Proxies: FlareSolverr, host `http://127.0.0.1:8191`,
tag `cf`; the two semi-private indexers carry the `cf` tag.

Settings → Apps: Sonarr/Radarr/Lidarr with Prowlarr server `http://127.0.0.1:9696`,
app servers `http://127.0.0.1:<port>`, sync level *Full Sync*. Sync categories:

- Sonarr: TV (5000-5090) + Anime (5070)
- Radarr: Movies (2000-2090)
- Lidarr: Audio (3000-3060)

## 3. Sonarr / Radarr / Lidarr

Manual (Settings → Media Management / Download Clients). Actual state on host:

| | Sonarr | Radarr | Lidarr |
|---|---|---|---|
| root folder | `/tank/media/series` | `/tank/media/films` | `/tank/media/music` |
| download client | qBittorrent `192.168.10.10:8080`, cat `tv` | same, cat `movies` | same, cat `music` |
| hardlinks | on (falls back to copy — separate datasets) | on | on |
| chmod folder | 755 | 755 | 775 |
| rename | on | **off** | on |

Anime and cartoons are NOT separate roots: anime series live in Sonarr under
`/tank/media/series` with the `Anime RU` profile, cartoons in Radarr under
`/tank/media/films`. The existing `/tank/media/anime` and `/tank/media/cartoons`
trees are legacy (NTFS migration) and only Jellyfin reads them.

Then:

    git clone --depth 1 https://github.com/TRaSH-Guides/Guides /tmp/trash
    python3 apply_trash.py            # sonarr + radarr
    python3 lidarr_setup.py

`apply_trash.py` — ~60 TRaSH custom formats + own `RU Audio` (+2500: parsed
Russian language OR RU dub keywords MVO/DVO/DUB/LostFilm/AniLibria/…, NOT
Sub-only Kinozal/RuTracker titles). TRaSH `Dubs Only` neutralised to 0, x265
softened to -500. Profiles: Sonarr `WEB-1080p RU`, `Anime RU`; Radarr
`UHD Bluray + WEB RU`, `HD Bluray + WEB RU`, `Anime RU`. Languages: Original+Russian.
`upgradeAllowed=true`, cutoffs WEB 1080p / Bluray-1080p (anime) / Bluray-2160p (UHD).

`lidarr_setup.py` — quality profile `Lossless > High Quality Lossy` (FLAC/ALAC/APE/
24bit + MP3-320/OGG Vorbis Q9-10/AAC-320, cutoff Lossless), metadata profile
albums/EPs/singles only, standard track naming.

`search_test.py <port> '<query>' [n]` — print top releases with CF scores to
check a profile, e.g. `search_test.py 18989 'seriesId=1&seasonNumber=1'`.

## 4. Jellyfin

    python3 jellyfin_setup.py admin '<admin-pw>'       # wizard + libs + network
    # then in Dashboard → Users: user `tv` (dumb password, no admin, no delete,
    # no remote control; libraries: all)

Script does: wizard (ru UI/metadata, no remote access/UPnP), admin user,
5 libraries (Фильмы `/tank/media/films`, Сериалы `/tank/media/series`,
Аниме `/tank/media/anime`, Мультфильмы `/tank/media/cartoons`, Музыка
`/tank/media/music`), `EnableRemoteAccess=false`, metrics off, an `arr-stack`
API key (printed; paste into Sonarr/Radarr/Lidarr → Connect → Jellyfin).
Network: nothing set in UI — ygg access goes through `jellyfin-ygg-proxy` (nix).
`encoding.xml` is nix-owned — do not touch in UI.

Library scan after: Dashboard → Libraries → Scan All.

## 5. Vontar X5 (Android TV, 192.168.10.55)

    adb connect 192.168.10.55:5555
    adb install -r jellyfin-androidtv-v0.19.x-libre.apk   # from GitHub releases
    adb shell monkey -p org.jellyfin.androidtv 1

Then in the app: server `http://192.168.10.10:8096`, user `tv`. Playback →
*Exoplayer*, passthrough audio on.

Also present on the box (not ours): Kodi, NUM, TorrServer client.

## Still open

- **Phone over ygg: "Unable to find a valid media source" on transcoded
  anime** (Ergo Proxy: h264 + AC3/TrueHD + ASS subs; Texhnolyze: HEVC 10-bit +
  FLAC). Atlantis (h264 + EAC3, direct play) works, so it is not bandwidth.
  Server side the VAAPI transcode starts and produces segments fine (verified
  with a synthetic PlaybackInfo + HLS fetch from the LAN: 3.8 MB segment in
  1.3 s, ffmpeg exits 0 on kill). The phone client never even calls
  PlaybackInfo for these items in the journal — so the failure is on the
  Android client side (device profile / subtitle burn-in / ygg relay) and
  needs client logs. Not touched yet.
- Lidarr `Lossless > HQ Lossy` never got a successful auto-grab verified.
- Jellyfin user `tv` creation is manual; fold into `jellyfin_setup.py`.
- Wrap all of this into a `media-stack-configure` oneshot once the scripts read
  the API keys on the host instead of over SSH.
