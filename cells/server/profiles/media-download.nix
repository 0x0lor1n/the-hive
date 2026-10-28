# Download and playback side of the media stack; in-app settings are pushed by
# media-download/configure.py (see its README).
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
  incomplete = "/fast/downloads";
  webPorts = {
    qbittorrent = 8080;
    prowlarr = 9696;
    radarr = 7878;
    sonarr = 8989;
    lidarr = 8686;
    jellyfin = 8096;
  };
  jellyfinDiscovery = 7359;
  # i5-6600T (Gen9): no 10-bit/vp9/av1 HW decode; tone-mapping needs OpenCL,
  # which broke playback with "Unable to find a valid media source".
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

  # LAN-only by firewall. `External` skips the first-run login wizard; API keys
  # still guard the *arr <-> Prowlarr links.
  noAuth = {
    method = "External";
    required = "DisabledForLocalAddresses";
  };

  qbitSeed = pkgs.writeText "qBittorrent.conf" ''
    [LegalNotice]
    Accepted=true

    [BitTorrent]
    Session\DefaultSavePath=${downloads}/complete
    Session\TempPath=${incomplete}/incomplete
    Session\TempPathEnabled=true

    [Preferences]
    WebUI\Address=*
    WebUI\AuthSubnetWhitelistEnabled=true
    WebUI\AuthSubnetWhitelist=${lan}
  '';
  qbitConf = "/var/lib/qbittorrent/qBittorrent/config/qBittorrent.conf";

  # AniLiberty has no Torznab API and Prowlarr no definition for it yet
  # (Prowlarr PR #2730); this bridge exposes it as a Generic Torznab indexer.
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
  # RuTracker anime season packs; drop once nixpkgs' Prowlarr includes it.
  prowlarr = pkgs.prowlarr.overrideAttrs (old: {
    patches = (old.patches or []) ++ [./media-download/prowlarr-rutracker-anime.patch];
  });
  mediaKeys = ["rutracker" "kinozal" "jellyfin-admin" "jellyfin-tv"];
  mediaConfigure = pkgs.writeShellScriptBin "media-configure" ''
    export TRASH="''${TRASH:-${inputs.trash-guides}/docs/json}" LAN_IP="''${LAN_IP:-${lanIp}}"
    # By hand (no systemd credentials): run inside the unit's sandbox instead,
    # then show its log.
    if [ -z "''${CREDENTIALS_DIRECTORY:-}" ] && [ "''${1:-}" != search ]; then
      systemctl restart media-configure.service
      exec journalctl --no-pager -o cat _SYSTEMD_INVOCATION_ID="$(systemctl show -p InvocationID --value media-configure.service)"
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
      ${incomplete} = {
        device = "fast/downloads";
        fsType = "zfs";
      };
      "/tank/media/series" = {
        device = "tank/media/series";
        fsType = "zfs";
      };
    };

  users.groups.media.gid = mediaGid;
  users.users.${host.userName}.extraGroups = ["media"];

  # /tank/media stays root-owned: tmpfiles refuses an "unsafe path transition"
  # from a non-root parent into the root-owned dataset roots.
  systemd.tmpfiles.rules =
    ["z /tank/media 2775 root media -"]
    ++ map (d: "z /tank/media/${d} 2775 - media -") ["films" "series" "anime" "music"]
    ++ [
      "z ${downloads} 2775 qbittorrent media -"
      "d ${downloads}/complete 2775 qbittorrent media -"
      "z ${incomplete} 2775 qbittorrent media -"
      "d ${incomplete}/incomplete 2775 qbittorrent media -"
    ]
    # save paths of the qbittorrent categories set by configure.py
    ++ map (c: "d ${downloads}/complete/${c} 2775 qbittorrent media -") ["tv" "movies" "music"];

  # serverConfig stays empty: it would rewrite the seeded config on every start.
  services.qbittorrent = {
    enable = true;
    group = "media";
    profileDir = "/var/lib/qbittorrent";
    webuiPort = webPorts.qbittorrent;
    torrentingPort = peerPort;
  };
  systemd.services.qbittorrent = {
    unitConfig.RequiresMountsFor = ["/var/lib/qbittorrent" downloads incomplete];
    serviceConfig = {
      # Chowns the root-owned dataset root after the mount.
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

  services.prowlarr = {
    enable = true;
    package = prowlarr;
    settings.auth = noAuth;
  };
  # RuTracker and Kinozal sit behind a Cloudflare JS challenge; configure.py
  # wires this in as Prowlarr's `cf` indexer proxy.
  services.flaresolverr.enable = true;
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
    # preStart, not script: media-configure loads the key once this unit is
    # active, which for Type=simple is before the script runs (243/CREDENTIALS).
    preStart = ''
      # KEY=VALUE so media-configure's credential() reads the same file.
      [ -s api-key ] || (umask 077; printf 'API_KEY=%s\n' "$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')" > api-key)
    '';
    script = ''
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
  # The module's DynamicUser makes /var/lib/prowlarr a symlink into
  # /var/lib/private, which cannot be a dataset mountpoint.
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
  # StateDirectory chowns the dataset root (Sonarr's module sets it already).
  # UMask keeps imports group-writable; the modules hard-set 0022.
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
    # Overwrites Dashboard -> Transcoding edits on every start.
    preStart = ''
      install -m 0640 ${jellyfinEncodingXml} /var/lib/jellyfin/config/encoding.xml
    '';
  };
  # VAAPI, not QSV: jellyfin-ffmpeg's libvpl runtime is Gen12+ only.
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [intel-media-driver intel-compute-runtime];
  };
  users.users.jellyfin.extraGroups = ["render" "video"];

  systemd.services.media-configure = {
    description = "media stack in-app settings (idempotent)";
    wantedBy = ["multi-user.target"];
    after = ["qbittorrent.service" "prowlarr.service" "radarr.service" "sonarr.service" "lidarr.service" "jellyfin.service" "flaresolverr.service" "anilibria-torznab.service"];
    wants = ["qbittorrent.service" "prowlarr.service" "radarr.service" "sonarr.service" "lidarr.service" "jellyfin.service" "anilibria-torznab.service"];
    restartTriggers = [mediaConfigure inputs.trash-guides.outPath];
    environment = {
      TRASH = "${inputs.trash-guides}/docs/json";
      LAN_IP = lanIp;
    };
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      # ImportCredential: a key missing from /run/credstore (tmpfs) is
      # skipped by the script instead of failing the unit.
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

  networking.firewall = {
    # Torrent peers from anywhere; minas-tirith forwards peerPort here.
    allowedTCPPorts = [peerPort];
    allowedUDPPorts = [peerPort];
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
