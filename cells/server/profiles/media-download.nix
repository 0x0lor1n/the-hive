# Download side of the media stack: qbittorrent-nox + Prowlarr (indexers)
# + Radarr/Sonarr/Lidarr (films/series/music) + Jellyfin (playback). Web UIs are LAN only; the
# torrent peer port is open to the world and minas-tirith forwards it here
# (net-router-wan.nix, next to TorrServer's 42000).
#
# State: one dataset per service on `fast` (snapshotted hourly, copied to
# warm1). The user creates them once on the live host BEFORE the deploy:
#
#   for s in qbittorrent prowlarr radarr sonarr lidarr jellyfin; do
#     sudo zfs create -o mountpoint=legacy fast/services/$s; done
#   sudo zfs create -o mountpoint=legacy -o recordsize=1M tank/media/downloads
#
# and once after the deploy (tmpfiles below fixes only the dataset roots,
# the existing library tree is uid 1000:users from the NTFS migration):
#
#   cd /tank/media && sudo chgrp -R media films anime music \
#     && sudo find films anime music -type d -exec chmod 2775 {} + \
#     && sudo find films anime music -type f -exec chmod 664 {} +
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
  lanIp = "192.168.10.10";
  mediaGid = 950;
  peerPort = 42001;
  downloads = "/tank/media/downloads";
  webPorts = {
    qbittorrent = 8080;
    prowlarr = 9696;
    radarr = 7878;
    sonarr = 8989;
    lidarr = 8686;
    jellyfin = 8096;
  };
  # Jellyfin client auto-discovery (UDP broadcast from the apps).
  jellyfinDiscovery = 7359;
  # Jellyfin transcoder config, written over config/encoding.xml at every start.
  # VAAPI on the i5-6600T iGPU (Gen9): HW decode h264/hevc8/mpeg2/vc1/vp8 + HW
  # h264 encode; no 10-bit decode, no vp9/av1, no tone-mapping (needs OpenCL
  # which was crashing the QSV path -> "Unable to find a valid media source").
  jellyfinEncodingXml = pkgs.writeText "jellyfin-encoding.xml" ''
    <?xml version="1.0" encoding="utf-8"?>
    <EncodingOptions xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
      <EncodingThreadCount>-1</EncodingThreadCount>
      <EnableFallbackFont>false</EnableFallbackFont>
      <EnableAudioVbr>false</EnableAudioVbr>
      <DownMixAudioBoost>2</DownMixAudioBoost>
      <DownMixStereoAlgorithm>None</DownMixStereoAlgorithm>
      <MaxMuxingQueueSize>2048</MaxMuxingQueueSize>
      <EnableThrottling>false</EnableThrottling>
      <ThrottleDelaySeconds>180</ThrottleDelaySeconds>
      <EnableSegmentDeletion>false</EnableSegmentDeletion>
      <SegmentKeepSeconds>720</SegmentKeepSeconds>
      <HardwareAccelerationType>vaapi</HardwareAccelerationType>
      <VaapiDevice>/dev/dri/renderD128</VaapiDevice>
      <QsvDevice />
      <EnableTonemapping>false</EnableTonemapping>
      <EnableVppTonemapping>false</EnableVppTonemapping>
      <EnableVideoToolboxTonemapping>false</EnableVideoToolboxTonemapping>
      <TonemappingAlgorithm>bt2390</TonemappingAlgorithm>
      <TonemappingMode>auto</TonemappingMode>
      <TonemappingRange>auto</TonemappingRange>
      <TonemappingDesat>0</TonemappingDesat>
      <TonemappingPeak>100</TonemappingPeak>
      <TonemappingParam>0</TonemappingParam>
      <VppTonemappingBrightness>16</VppTonemappingBrightness>
      <VppTonemappingContrast>1</VppTonemappingContrast>
      <H264Crf>23</H264Crf>
      <H265Crf>28</H265Crf>
      <EncoderPreset xsi:nil="true" />
      <DeinterlaceDoubleRate>false</DeinterlaceDoubleRate>
      <DeinterlaceMethod>yadif</DeinterlaceMethod>
      <EnableDecodingColorDepth10Hevc>false</EnableDecodingColorDepth10Hevc>
      <EnableDecodingColorDepth10Vp9>false</EnableDecodingColorDepth10Vp9>
      <EnableDecodingColorDepth10HevcRext>false</EnableDecodingColorDepth10HevcRext>
      <EnableDecodingColorDepth12HevcRext>false</EnableDecodingColorDepth12HevcRext>
      <EnableEnhancedNvdecDecoder>false</EnableEnhancedNvdecDecoder>
      <PreferSystemNativeHwDecoder>true</PreferSystemNativeHwDecoder>
      <EnableIntelLowPowerH264HwEncoder>false</EnableIntelLowPowerH264HwEncoder>
      <EnableIntelLowPowerHevcHwEncoder>false</EnableIntelLowPowerHevcHwEncoder>
      <EnableHardwareEncoding>true</EnableHardwareEncoding>
      <AllowHevcEncoding>false</AllowHevcEncoding>
      <AllowAv1Encoding>false</AllowAv1Encoding>
      <EnableSubtitleExtraction>true</EnableSubtitleExtraction>
      <HardwareDecodingCodecs>
        <string>h264</string>
        <string>hevc</string>
        <string>mpeg2video</string>
        <string>vc1</string>
        <string>vp8</string>
      </HardwareDecodingCodecs>
      <AllowOnDemandMetadataBasedKeyframeExtractionForExtensions>
        <string>mkv</string>
      </AllowOnDemandMetadataBasedKeyframeExtractionForExtensions>
    </EncodingOptions>
  '';
  svcs = builtins.attrNames webPorts;
  lanRule = port: "iptables -A nixos-fw -p tcp -s ${lan} --dport ${toString port} -j nixos-fw-accept";
  lanUnrule = port: "iptables -D nixos-fw -p tcp -s ${lan} --dport ${toString port} -j nixos-fw-accept || true";
  lanRuleUdp = port: "iptables -A nixos-fw -p udp -s ${lan} --dport ${toString port} -j nixos-fw-accept";
  lanUnruleUdp = port: "iptables -D nixos-fw -p udp -s ${lan} --dport ${toString port} -j nixos-fw-accept || true";

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

  # In-app settings pusher (see the media-configure unit below).
  # AniLiberty (anilibria.top) has no Torznab/RSS search; its API v1 separates
  # release search from torrent lookup and Prowlarr has no native definition
  # yet (upstream PR #2730). This Go bridge fans that out into a Generic
  # Torznab endpoint (categories 5000/5070, titles "<label> SxxEyy RUS / <rus>
  # / <orig>" — Sonarr parses them, RUS feeds the RU Audio CF). Stdlib only.
  anilibriaTorznab = pkgs.buildGoModule {
    pname = "anilibria-torznab";
    version = "1.0.3";
    src = pkgs.fetchFromGitHub {
      owner = "Zenderg";
      repo = "anilibria-torznab";
      rev = "8fab6dddbd54d5a60766009b6bc61a792c1660b1";
      hash = "sha256-s6UpWf8g7bq15z6ODAyYmHDPaYpALePKZBoPfHFn5Go=";
    };
    vendorHash = null;
    subPackages = ["cmd/server"];
    env.CGO_ENABLED = 0;
    ldflags = ["-s" "-w" "-X main.version=1.0.3"];
    postInstall = "mv $out/bin/server $out/bin/anilibria-torznab";
    meta.mainProgram = "anilibria-torznab";
  };
  anilibriaPort = 9697;
  mediaKeys = ["rutracker" "kinozal" "jellyfin-admin" "jellyfin-tv"];
  mediaConfigure = pkgs.writeShellScriptBin "media-configure" ''
    export TRASH="''${TRASH:-${inputs.trash-guides}/docs/json}" LAN_IP="''${LAN_IP:-${lanIp}}"
    # By hand (no systemd credentials): run inside the unit's sandbox instead,
    # then show its log.
    if [ -z "''${CREDENTIALS_DIRECTORY:-}" ] && [ "''${1:-}" != search ]; then
      systemctl restart media-configure.service
      exec journalctl -u media-configure.service --no-pager -o cat --since -20min
    fi
    exec ${pkgs.python3}/bin/python3 ${./media-download/configure.py} "$@"
  '';
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
    ++ map (d: "z /tank/media/${d} 2775 - media -") ["films" "series" "anime" "music"]
    ++ [
      "z ${downloads} 2775 qbittorrent media -"
      "d ${downloads}/complete 2775 qbittorrent media -"
      "d ${downloads}/incomplete 2775 qbittorrent media -"
    ]
    # qbittorrent categories (tv/movies/music) -> per-*arr subdirs under complete/
    ++ map (c: "d ${downloads}/complete/${c} 2775 qbittorrent media -") ["tv" "movies" "music"];

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
  # AniLiberty -> Torznab bridge (see anilibriaTorznab above). Localhost only;
  # Prowlarr talks to it as a Generic Torznab indexer with a per-host API key
  # generated once into its state dir. media-configure reads the same file
  # (ImportCredential media-anilibria) to register the indexer.
  systemd.services.anilibria-torznab = {
    description = "AniLiberty -> Torznab bridge for Prowlarr";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target"];
    wants = ["network-online.target"];
    environment = {
      LISTEN_ADDR = "127.0.0.1:${toString anilibriaPort}";
      REQUEST_INTERVAL = "1s";
      LOG_LEVEL = "info";
    };
    script = ''
      # KEY=VALUE so media-configure's credential() reads the same file.
      [ -s api-key ] || (umask 077; printf 'API_KEY=%s\n' "$(tr -dc 'a-f0-9' </dev/urandom | head -c 48)" > api-key)
      set -a; . ./api-key; set +a
      exec ${lib.getExe anilibriaTorznab}
    '';
    serviceConfig = {
      DynamicUser = true;
      StateDirectory = "anilibria-torznab";
      WorkingDirectory = "/var/lib/anilibria-torznab";
      Restart = "on-failure";
      RestartSec = 5;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
    };
  };
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

  # ---- jellyfin -----------------------------------------------------------
  # Media server over the same /tank/media library the *arr stack fills.
  # Libraries (films/series/anime/music) are added in the web UI.
  # State on fast/services/jellyfin (same pattern as the *arr):
  #   zfs create -o mountpoint=legacy fast/services/jellyfin
  services.jellyfin = {
    enable = true;
    group = "media";
    openFirewall = false;
  };
  systemd.services.jellyfin = {
    unitConfig.RequiresMountsFor = ["/var/lib/jellyfin" "/tank/media/series"];
    serviceConfig = {
      StateDirectory = "jellyfin";
      StateDirectoryMode = "0750";
      UMask = lib.mkForce "0002";
    };
    # encoding.xml is owned by nix: Dashboard -> Playback -> Transcoding edits
    # are overwritten on every (re)start. Change it here, redeploy.
    preStart = ''
      install -m 0640 ${jellyfinEncodingXml} /var/lib/jellyfin/config/encoding.xml
    '';
  };
  # Intel VAAPI (i5-6600T, Skylake/Gen9) for transcoding. Not QSV: jellyfin-ffmpeg
  # 7.x drives QSV via libvpl whose runtime (vpl-gpu-rt) is Gen12+ only; Gen9 would
  # need the deprecated intel-media-sdk, and QSV buys nothing over VAAPI here
  # (no HW HEVC 10-bit decode on Skylake anyway).
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [intel-media-driver intel-compute-runtime];
  };
  users.users.jellyfin.extraGroups = ["render" "video"];

  # ---- in-app settings ----------------------------------------------------
  # What the *arr/Prowlarr/qbittorrent/Jellyfin keep in their own SQLite/XML:
  # root folders, download client, qbittorrent categories, Prowlarr indexers
  # + proxies + app links, TRaSH custom formats and the RU quality profiles,
  # Jellyfin wizard/libraries/users. media-download/configure.py pushes it
  # all over the local APIs, idempotently; it runs after every deploy and by
  # hand as `media-configure`. Tracker logins and the Jellyfin passwords are
  # colmena deployment.keys (secrets/imladris/*.age, decrypted with this
  # workstation's TPM identity at deploy time, never in the store).
  #
  #   agenix-style edit:  rage -d -i secrets/$(uname -n)-nix-rage.pub secrets/imladris/rutracker.age
  #   format:             USERNAME=...\nPASSWORD=...   (one file per credential)
  # ---------------------------------------------------------------------------
  systemd.services.media-configure = {
    description = "media stack in-app settings (idempotent)";
    wantedBy = ["multi-user.target"];
    after = ["qbittorrent.service" "prowlarr.service" "radarr.service" "sonarr.service" "lidarr.service" "jellyfin.service" "flaresolverr.service" "anilibria-torznab.service"];
    wants = ["qbittorrent.service" "prowlarr.service" "radarr.service" "sonarr.service" "lidarr.service" "jellyfin.service" "anilibria-torznab.service"];
    # Re-run when the script, the TRaSH pin or the service closure changes.
    restartTriggers = [mediaConfigure inputs.trash-guides.outPath];
    environment = {
      TRASH = "${inputs.trash-guides}/docs/json";
      LAN_IP = lanIp;
    };
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      # ImportCredential (not LoadCredential): a key missing on the host
      # (deploy without secrets, reboot — /run is tmpfs) is skipped by the
      # script, not fatal for the unit. The manager reads /run/credstore as
      # root; the DynamicUser only sees $CREDENTIALS_DIRECTORY.
      ImportCredential = "media-*";
      # The bridge's self-generated key lives in its state dir, not credstore.
      LoadCredential = "media-anilibria:/var/lib/anilibria-torznab/api-key";
      ExecStart = "${mediaConfigure}/bin/media-configure";
      TimeoutStartSec = "20min";
    };
  };
  environment.systemPackages = [mediaConfigure];

  deployment.keys = lib.listToAttrs (map (k:
    lib.nameValuePair "media-${k}" {
      keyCommand = [
        "bash"
        "-c"
        ''exec rage -d -i "${inputs.self}/secrets/$(uname -n)-nix-rage.pub" "$0"''
        "${inputs.self}/secrets/imladris/${k}.age"
      ];
      destDir = "/run/credstore";
      user = "root";
      group = "root";
      permissions = "0400";
      uploadAt = "pre-activation";
    })
  mediaKeys);

  # ---- firewall -----------------------------------------------------------
  networking.firewall = {
    # Torrent peers from anywhere; minas-tirith forwards peerPort here.
    allowedTCPPorts = [peerPort];
    allowedUDPPorts = [peerPort];
    # Web UIs: the LAN only.
    extraCommands =
      lib.concatMapStringsSep "\n" lanRule (builtins.attrValues webPorts)
      + "\n"
      + lanRuleUdp jellyfinDiscovery;
    extraStopCommands =
      lib.concatMapStringsSep "\n" lanUnrule (builtins.attrValues webPorts)
      + "\n"
      + lanUnruleUdp jellyfinDiscovery;
  };
}
