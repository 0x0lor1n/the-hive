# TRaSH profiles (Sonarr/Radarr) with Russian-audio preference

Not declarative (Sonarr/Radarr keep profiles in SQLite). Re-apply after a fresh DB:

    git clone --depth 1 https://github.com/TRaSH-Guides/Guides /tmp/trash
    ssh -N -L 18989:127.0.0.1:8989 -L 17878:127.0.0.1:7878 imladris &
    python3 apply_trash.py            # both apps; or: apply_trash.py sonarr

Profiles created: Sonarr `WEB-1080p RU`, `Anime RU`; Radarr `UHD Bluray + WEB RU`, `HD Bluray + WEB RU`, `Anime RU`.
Own CF `RU Audio` (+2500) = parsed Russian language OR RU dub keywords (MVO/DVO/DUB/LostFilm/AniLibria/...)
and NOT "Sub"-only Kinozal/RuTracker titles. TRaSH `Dubs Only` neutralised (0), x265 softened to -500.
Idempotent: CFs/profiles matched by name and updated in place.
