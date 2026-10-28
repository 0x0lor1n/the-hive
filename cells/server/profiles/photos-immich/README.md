# Immich: datasets

Created by hand on imladris before the first deploy:

```bash
sudo zfs create -o mountpoint=legacy tank/photos/immich
sudo zfs create -o mountpoint=legacy -o recordsize=16k fast/services/postgresql
sudo zfs create -o mountpoint=none fast/services-cache
for d in thumbs encoded ml; do
  sudo zfs create -o mountpoint=legacy fast/services-cache/immich-$d; done
```

| dataset | mounted at | backup |
|---|---|---|
| `tank/photos/immich` | `mediaLocation`: uploads, profile pics, Immich's nightly DB dumps | sanoid keep-long + warm1 (under `tank/photos`) |
| `fast/services/postgresql` | `/var/lib/postgresql` | hourly + warm1, like every `fast/services/*` |
| `fast/services-cache/immich-{thumbs,encoded}` | `thumbs/`, `encoded-video/` in `mediaLocation` | none, regenerable |
| `fast/services-cache/immich-ml` | `/var/cache/immich` (ML models) | none, regenerable |

The existing library (`tank/photos/{personal,camera,wedding}`) stays in place
and is added in the web UI as a read-only external library (files are o+r).
