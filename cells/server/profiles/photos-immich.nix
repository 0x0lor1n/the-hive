# Immich: photo/video library with face/object search. Web UI and API on
# :2283, LAN only; shared links point at the LAN IP (server.externalDomain).
#
# Storage, three tiers by what losing it costs:
#   tank/photos/immich                  -> /tank/photos/immich (mediaLocation:
#       phone uploads, profile pics, Immich's own nightly DB dumps). Under
#       tank/photos, so sanoid keep-long + the warm1 copy cover it.
#   fast/services/postgresql            -> /var/lib/postgresql (the DB; hourly
#       snapshots + warm1 like every fast/services/*).
#   fast/services-cache/immich-{thumbs,encoded} -> thumbs/ and encoded-video/
#       inside mediaLocation; fast/services-cache/immich-ml -> /var/cache/immich
#       (ML models). All regenerable, so outside fast/services: no snapshots,
#       not copied to warm1.
# The existing library (tank/photos/{personal,camera,wedding}) is NOT moved:
# it is added in the web UI as an external library, read-only to Immich
# (files are o+r, Immich never writes there).
#
# The user creates the datasets once on the live host BEFORE the deploy:
#
#   sudo zfs create -o mountpoint=legacy tank/photos/immich
#   sudo zfs create -o mountpoint=legacy -o recordsize=16k fast/services/postgresql
#   sudo zfs create -o mountpoint=none fast/services-cache
#   for d in thumbs encoded ml; do
#     sudo zfs create -o mountpoint=legacy fast/services-cache/immich-$d; done
#
# Settings: `settings` below is rendered to a config file, which makes the
# admin "System Settings" page read-only; the keys not listed keep Immich's
# defaults. Users, albums, libraries and API keys stay in the UI/DB.
{
  inputs,
  cell,
}: {
  pkgs,
  lib,
  ...
}: let
  lan = "192.168.10.0/24";
  lanIp = "192.168.10.10";
  port = 2283;
  media = "/tank/photos/immich";
  # Regenerable caches mounted into mediaLocation (Immich has one root only).
  cacheMounts = {
    "${media}/thumbs" = "fast/services-cache/immich-thumbs";
    "${media}/encoded-video" = "fast/services-cache/immich-encoded";
    "/var/cache/immich" = "fast/services-cache/immich-ml";
  };
  # `zfs create` leaves dataset roots root:root 755; Immich runs as `immich`
  # with UMask 0077 and must own them. Runs as root ("+") before every start,
  # after the mounts, so no tmpfiles-vs-mount race on the first switch.
  ownDirs = pkgs.writeShellScript "immich-own-dirs" ''
    set -eu
    for d in ${media} ${lib.concatStringsSep " " (builtins.attrNames cacheMounts)}; do
      ${pkgs.coreutils}/bin/chown immich:immich "$d"
      ${pkgs.coreutils}/bin/chmod 0700 "$d"
    done
  '';
in {
  fileSystems =
    {
      ${media} = {
        device = "tank/photos/immich";
        fsType = "zfs";
      };
      "/var/lib/postgresql" = {
        device = "fast/services/postgresql";
        fsType = "zfs";
      };
    }
    // lib.mapAttrs (_: device: {
      inherit device;
      fsType = "zfs";
    })
    cacheMounts;

  services.immich = {
    enable = true;
    host = "";
    inherit port;
    mediaLocation = media;
    # i5-6600T iGPU (Gen9, VAAPI): HW h264 encode and HW decode up to 4096x2304.
    # GoPro 5.3K HEVC is over that limit; Immich then retries with software
    # decoding by itself (media.service "Retrying with ... software decoding").
    accelerationDevices = ["/dev/dri/renderD128"];
    settings = {
      server.externalDomain = "http://${lanIp}:${toString port}";
      ffmpeg = {
        accel = "vaapi";
        accelDecode = true;
        # Browser playback copy: h264 1080p for anything not already h264 or
        # above 1080p (GoPro 5.3K/4K HEVC, phone HEVC). Originals untouched;
        # download in the UI and shared links give the original file.
        transcode = "optimal";
        targetResolution = "1080";
        targetVideoCodec = "h264";
        acceptedVideoCodecs = ["h264"];
      };
      # Map tiles and reverse geocoding: the defaults call tiles.immich.cloud
      # from the browser, nothing to pin. No version check against GitHub.
      newVersionCheck.enabled = false;
    };
  };
  users.users.immich.extraGroups = ["render" "video"];

  systemd.services = {
    immich-server = {
      unitConfig.RequiresMountsFor = [media "${media}/thumbs" "${media}/encoded-video"];
      serviceConfig.ExecStartPre = ["+${ownDirs}"];
    };
    immich-machine-learning.unitConfig.RequiresMountsFor = ["/var/cache/immich"];
    # StateDirectory=postgresql (upstream) chowns the dataset root after the mount.
    postgresql.unitConfig.RequiresMountsFor = ["/var/lib/postgresql"];
  };

  # Redis holds only the job queue; persisted so queued thumbnail/ML jobs
  # survive a reboot (root is rolled back).
  environment.persistence."/state".directories = ["/var/lib/redis-immich"];

  networking.firewall = {
    extraCommands = "iptables -A nixos-fw -p tcp -s ${lan} --dport ${toString port} -j nixos-fw-accept";
    extraStopCommands = "iptables -D nixos-fw -p tcp -s ${lan} --dport ${toString port} -j nixos-fw-accept || true";
  };
}
