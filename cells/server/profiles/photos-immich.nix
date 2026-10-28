# Immich on :2283, LAN only; datasets and backup tiers in photos-immich/README.md.
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
  # Regenerable, so outside fast/services; mounted into mediaLocation (Immich has one root).
  cacheMounts = {
    "${media}/thumbs" = "fast/services-cache/immich-thumbs";
    "${media}/encoded-video" = "fast/services-cache/immich-encoded";
    "/var/cache/immich" = "fast/services-cache/immich-ml";
  };
  # Dataset roots are root:root 755 and Immich runs with UMask 0077. ExecStartPre
  # runs after the mounts, so no tmpfiles-vs-mount race on the first switch.
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
    # Gen9 VAAPI decodes up to 4096x2304; Immich falls back to software for GoPro 5.3K.
    accelerationDevices = ["/dev/dri/renderD128"];
    # Rendered to a file, which makes the admin System Settings page read-only.
    settings = {
      server.externalDomain = "http://${lanIp}:${toString port}";
      ffmpeg = {
        accel = "vaapi";
        accelDecode = true;
        transcode = "optimal";
        targetResolution = "1080";
        targetVideoCodec = "h264";
        acceptedVideoCodecs = ["h264"];
      };
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

  # Job queue only; persisted so queued thumbnail/ML jobs survive the root rollback.
  environment.persistence."/state".directories = ["/var/lib/redis-immich"];

  networking.firewall = {
    extraCommands = "iptables -A nixos-fw -p tcp -s ${lan} --dport ${toString port} -j nixos-fw-accept";
    extraStopCommands = "iptables -D nixos-fw -p tcp -s ${lan} --dport ${toString port} -j nixos-fw-accept || true";
  };
}
