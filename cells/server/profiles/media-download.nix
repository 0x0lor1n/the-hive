# Download side of the media stack: qbittorrent-nox + Prowlarr (indexers)
# + Radarr/Sonarr/Lidarr (films/series/music). Web UIs are LAN only; the
# torrent peer port is open to the world and minas-tirith forwards it here
# (net-router-wan.nix, next to TorrServer's 42000).
#
# State: one dataset per service on `fast` (snapshotted hourly, copied to
# warm1). The user creates them once on the live host BEFORE the deploy:
#
#   for s in qbittorrent prowlarr radarr sonarr lidarr; do
#     sudo zfs create -o mountpoint=legacy fast/services/$s; done
#   sudo zfs create -o mountpoint=legacy -o recordsize=1M tank/media/downloads
#
# and once after the deploy (tmpfiles below fixes only the dataset roots,
# the existing library tree is uid 1000:users from the NTFS migration):
#
#   cd /tank/media && sudo chgrp -R media films anime cartoons music \
#     && sudo find films anime cartoons music -type d -exec chmod 2775 {} + \
#     && sudo find films anime cartoons music -type f -exec chmod 664 {} +
#
# Files: everything in /tank/media/* is group `media` (fixed gid 950, setgid
# dirs, group-writable) so the *arr can move what qbittorrent wrote. The
# library datasets and downloads are separate datasets: hardlinks are
# impossible, imports are copy+delete — turn "Use Hardlinks" off in the UIs.
#
# qbittorrent's config is seeded once (paths, LAN auth bypass, legal notice)
# and then owned by the web UI; the module's `serverConfig` would overwrite
# the file on every start, so it stays empty. The *arr keep their settings
# in their own DBs; tracker logins go into Prowlarr's UI, never into the repo.
{
  inputs,
  cell,
}: {
  pkgs,
  lib,
  host,
  ...
}: let
  lan = "192.168.10.0/24";
  mediaGid = 950;
  peerPort = 42001;
  downloads = "/tank/media/downloads";
  webPorts = {
    qbittorrent = 8080;
    prowlarr = 9696;
    radarr = 7878;
    sonarr = 8989;
    lidarr = 8686;
  };
  svcs = builtins.attrNames webPorts;
  lanRule = port: "iptables -A nixos-fw -p tcp -s ${lan} --dport ${toString port} -j nixos-fw-accept";
  lanUnrule = port: "iptables -D nixos-fw -p tcp -s ${lan} --dport ${toString port} -j nixos-fw-accept || true";

  noAuth = {
    method = "External";
    required = "DisabledForLocalAddresses";
  };

  qbitSeed = pkgs.writeText "qBittorrent.conf" ''
    [LegalNotice]
    Accepted=true

    [BitTorrent]
    Session\DefaultSavePath=${downloads}/complete
    Session\TempPath=${downloads}/incomplete
    Session\TempPathEnabled=true

    [Preferences]
    WebUI\Address=*
    WebUI\AuthSubnetWhitelistEnabled=true
    WebUI\AuthSubnetWhitelist=${lan}
  '';
  qbitConf = "/var/lib/qbittorrent/qBittorrent/config/qBittorrent.conf";
in {
  fileSystems =
    lib.listToAttrs (map (s:
      lib.nameValuePair "/var/lib/${s}" {
        device = "fast/services/${s}";
        fsType = "zfs";
      })
    svcs)
    // {
      ${downloads} = {
        device = "tank/media/downloads";
        fsType = "zfs";
      };
      # Sonarr's root folder. Created after the initial disko run:
      #   zfs create -o mountpoint=legacy -o recordsize=1M tank/media/series
      "/tank/media/series" = {
        device = "tank/media/series";
        fsType = "zfs";
      };
    };

  users.groups.media.gid = mediaGid;
  # The admin manages the library by hand too.
  users.users.${host.userName}.extraGroups = ["media"];

  # Dataset roots come root-owned from `zfs create`; `z` fixes mode/group
  # without recursing into the library. Owner stays as is (the admin's uid).
  # /tank/media itself must be root-owned: tmpfiles refuses to descend from a
  # non-root parent into a root-owned child ("unsafe path transition").
  systemd.tmpfiles.rules =
    ["z /tank/media 2775 root media -"]
    ++ map (d: "z /tank/media/${d} 2775 - media -") ["films" "series" "anime" "cartoons" "music"]
    ++ [
      "z ${downloads} 2775 qbittorrent media -"
      "d ${downloads}/complete 2775 qbittorrent media -"
      "d ${downloads}/incomplete 2775 qbittorrent media -"
    ];

  # ---- qbittorrent --------------------------------------------------------
  services.qbittorrent = {
    enable = true;
    group = "media";
    profileDir = "/var/lib/qbittorrent";
    webuiPort = webPorts.qbittorrent;
    torrentingPort = peerPort;
  };
  systemd.services.qbittorrent = {
    unitConfig.RequiresMountsFor = ["/var/lib/qbittorrent" downloads];
    serviceConfig = {
      # Chowns the root-owned dataset root on every start, after the mount.
      StateDirectory = "qbittorrent";
      StateDirectoryMode = "0750";
      # Group-writable downloads for the *arr moves.
      UMask = "0002";
      ExecStartPre = lib.mkAfter [
        (pkgs.writeShellScript "qbittorrent-seed-config" ''
          [ -e ${qbitConf} ] && exit 0
          ${pkgs.coreutils}/bin/install -Dm600 ${qbitSeed} ${qbitConf}
          echo "qbittorrent: seeded ${qbitConf}"
        '')
      ];
    };
  };

  # ---- *arr ---------------------------------------------------------------
  # LAN-only by firewall, home use: no login on any of them. `External` is
  # the *arr way to say "auth is handled upstream" — it skips the first-run
  # user wizard. API keys stay required for the cross-links (*arr <-> Prowlarr).
  services.prowlarr = {
    enable = true;
    settings.auth = noAuth;
  };
  # rutracker.org / .net sit behind a Cloudflare JS challenge (cf-mitigated:
  # challenge, 403 on GET and POST). FlareSolverr runs a headless Chromium
  # that solves it; Prowlarr is pointed at it via an Indexer Proxy
  # (Settings -> Indexers -> + -> FlareSolverr, host http://127.0.0.1:8191,
  # tag "cf") and the rutracker indexer gets the same tag. Localhost only.
  services.flaresolverr.enable = true;
  # The module runs it as DynamicUser, which turns /var/lib/prowlarr into a
  # symlink to /var/lib/private — but it is a dataset mountpoint. Static user
  # instead; StateDirectory stays and chowns the root on every start.
  users.users.prowlarr = {
    isSystemUser = true;
    group = "prowlarr";
    home = "/var/lib/prowlarr";
  };
  users.groups.prowlarr = {};
  systemd.services.prowlarr.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "prowlarr";
    Group = "prowlarr";
  };

  services.radarr = {
    enable = true;
    group = "media";
    settings.auth = noAuth;
  };
  services.sonarr = {
    enable = true;
    group = "media";
    settings.auth = noAuth;
  };
  services.lidarr = {
    enable = true;
    group = "media";
    settings.auth = noAuth;
  };
  # The modules create dataDir under /var/lib/<svc> with tmpfiles; the
  # dataset must be there first. Sonarr's module sets StateDirectory itself;
  # Radarr/Lidarr need it too, or the root-owned dataset root stays
  # unwritable and tmpfiles can't create `.config/<App>` (Permission denied).
  # UMask 0002: imported files/folders stay group-writable for the admin and
  # the other *arr (radarr/sonarr modules hard-set 0022, hence mkForce).
  systemd.services.radarr = {
    unitConfig.RequiresMountsFor = "/var/lib/radarr";
    serviceConfig = {
      StateDirectory = "radarr";
      StateDirectoryMode = "0750";
      UMask = lib.mkForce "0002";
    };
  };
  systemd.services.sonarr = {
    unitConfig.RequiresMountsFor = "/var/lib/sonarr";
    serviceConfig.UMask = lib.mkForce "0002";
  };
  systemd.services.lidarr = {
    unitConfig.RequiresMountsFor = "/var/lib/lidarr";
    serviceConfig = {
      StateDirectory = "lidarr";
      StateDirectoryMode = "0750";
      UMask = lib.mkForce "0002";
    };
  };

  # ---- firewall -----------------------------------------------------------
  networking.firewall = {
    # Torrent peers from anywhere; minas-tirith forwards peerPort here.
    allowedTCPPorts = [peerPort];
    allowedUDPPorts = [peerPort];
    # Web UIs: the LAN only.
    extraCommands = lib.concatMapStringsSep "\n" lanRule (builtins.attrValues webPorts);
    extraStopCommands = lib.concatMapStringsSep "\n" lanUnrule (builtins.attrValues webPorts);
  };
}
