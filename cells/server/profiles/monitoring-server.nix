# Prometheus + Alertmanager + Grafana + ntfy on the router: the one host that
# is always up and is already the LAN/yggdrasil junction. Scrapes the
# exporters from monitoring-exporters.nix (imladris) and its own; osgiliath is
# only probed (tcp :22) -- a public box gets no new open port.
#
# Reachability: Prometheus/Alertmanager/bridge bind loopback; Grafana and ntfy
# bind everything and the firewall decides -- br-lan is trusted
# (net-router-wan.nix), ygg0 gets the two ports here, the WAN gets nothing.
# The phone subscribes over its own yggdrasil peering (its key goes into
# site.yggdrasil.allowedPublicKeys), so alerts arrive off-LAN too.
#
# State: three `rpool/logs/*` datasets (disks/minas-tirith.nix), created by
# hand on the live host before the first apply:
#   zfs create -o mountpoint=legacy -o quota=20G rpool/logs/prometheus
#   zfs create -o mountpoint=legacy -o quota=5G  rpool/logs/grafana
#   zfs create -o mountpoint=legacy -o quota=2G  rpool/logs/ntfy-sh
#
# Secrets (agenix-rekey generators, `agenix generate && agenix rekey`): one
# publisher password; ntfy gets it as a bcrypt hash (declarative auth-users
# through the env file), the bridge gets it in clear (extra config file).
{
  inputs,
  cell,
}: {
  config,
  pkgs,
  lib,
  globals,
  ...
}: let
  imladris = "192.168.10.10";
  # Same split as deploy-osgiliath.nix: the encrypted half stores it with a
  # prefix length.
  osgiliath = lib.head (lib.splitString "/" globals.hosts.osgiliath.ipv4.address);

  ntfyPort = 2586;
  grafanaPort = 3000;
  promPort = 9090;
  amPort = 9093;
  bridgePort = 8000;
  ntfyUser = "alertmanager";
  topic = "hive-alerts";

  # Up/down per box on the LAN; vontar is a DHCP lease (.103), not static.
  icmpTargets = {
    imladris = imladris;
    vontar = "192.168.10.103";
    asus-ap = "192.168.10.2";
  };
  # User-facing web UIs, one row each on the dashboard. flaresolverr and
  # anilibria-torznab listen on imladris loopback only: their status comes
  # from node_exporter's systemd collector, not from here.
  httpServices = {
    jellyfin = "http://${imladris}:8096/health";
    torrserver = "http://${imladris}:8090/";
    qbittorrent = "http://${imladris}:8080/";
    prowlarr = "http://${imladris}:9696/";
    radarr = "http://${imladris}:7878/";
    sonarr = "http://${imladris}:8989/";
    lidarr = "http://${imladris}:8686/";
    grafana = "http://192.168.10.1:${toString grafanaPort}/api/health";
    ntfy = "http://192.168.10.1:${toString ntfyPort}/v1/health";
  };
  hostOf = url:
    if lib.hasPrefix "http://${imladris}:" url
    then "imladris"
    else "minas-tirith";

  # Blackbox jobs: the target becomes ?target=, the scrape goes to blackbox.
  probeJob = name: module: staticConfigs: {
    job_name = name;
    metrics_path = "/probe";
    params.module = [module];
    static_configs = staticConfigs;
    relabel_configs = [
      {
        source_labels = ["__address__"];
        target_label = "__param_target";
      }
      {
        target_label = "__address__";
        replacement = "127.0.0.1:9115";
      }
    ];
  };

  # 3D "city" panel (dashboards/build.py → city.json). Not on grafana.com;
  # unsigned, hence allow_loading_unsigned_plugins. Built from git main, not
  # the v1.1.0 release zip: the release only matches field.name, so columns
  # renamed by the organize transformation (config.displayName) are never
  # found and every building renders offline. Fixed upstream in ed78c95
  # (2026-08-24), no release cut since. Pinned commit also needs Grafana
  # >= 13.1.4 (plugin.json grafanaDependency). The bundle makes no requests
  # of its own (no fetch/XHR/backendSrv) -- re-check on every bump, it runs
  # with the viewer's Grafana session.
  neonCityPanel = let
    # Tweaks with no panel option:
    # - light cycles only, no floating "data packet" orbs;
    # - at a dead end (the 1G spurs) generateRandomPath backtracks without
    #   recording the cells it steps over, so the cycle cut straight through
    #   buildings to the next waypoint; record them, it U-turns on the road;
    # - a trail ribbon joins its newest point to the next one, so when a
    #   cycle jumps (new path from a random cell every ~5 s, a long frame)
    #   it drew a streak across the map; restart the trail on jumps > half a
    #   cell (a normal per-frame step is < 0.1).
    sourcePatches =
      ''
        substituteInPlace src/engine/traffic/TrafficConfig.ts \
          --replace-fail "lightCycleRatio: 0.6," "lightCycleRatio: 1,"
        substituteInPlace src/engine/traffic/PathGenerator.ts \
          --replace-fail "          current = escapeCell;" "          path.push(escapeCell); current = escapeCell;"
        substituteInPlace src/engine/traffic/TrailSystem.ts \
          --replace-fail "addPoint(position: THREE.Vector3, direction: THREE.Vector3): void {" \
            "addPoint(position: THREE.Vector3, direction: THREE.Vector3): void { if (this.count > 0 && this.points[this.head].position.distanceTo(position) > 0.5) { this.count = 0; }"
      ''
      + recolor;

    # Repaint the panel in the repo theme (cells/common/theme.nix). It has no
    # palette option; ~80 colours are literals across prefabs, shaders and the
    # tooltip CSS, as 0xRRGGBB / #RRGGBB(AA) / rgba(r, g, b / vec3(r, g, b.
    # Neon -> brightest Kanagawa hue of the same role; bodies/ground -> sumiInk.
    # Greys, black and white stay. The build fails if a mapped neon survives.
    k = inputs.cells.common.theme.colors;
    toTheme = with k; {
      # cyan: roads, edges, trails, holograms
      "00ffff" = springBlue;
      "00e5ff" = springBlue;
      "66ffff" = lightBlue;
      "88ffff" = lightBlue;
      "aaffff" = lightBlue;
      "4fc3f7" = crystalBlue;
      "00aaff" = crystalBlue;
      "0088ff" = crystalBlue;
      "44aaff" = crystalBlue;
      "4488ff" = crystalBlue;
      "448aff" = crystalBlue;
      "2979ff" = crystalBlue;
      "88aaff" = crystalBlue;
      # magenta / violet
      "ff00ff" = sakuraPink;
      "ff66cc" = sakuraPink;
      "ff0088" = sakuraPink;
      "ff4081" = sakuraPink;
      "ff0080" = sakuraPink;
      "ff00c8" = sakuraPink;
      "e040fb" = oniViolet;
      "ea80fc" = oniViolet2;
      "ce93d8" = oniViolet2;
      "aa00ff" = oniViolet;
      "7c4dff" = oniViolet;
      # status: online / warning / critical
      "00ff88" = springGreen;
      "00e676" = springGreen;
      "00ffaa" = springGreen;
      "33ff66" = springGreen;
      "aeea00" = springGreen;
      "ffaa00" = roninYellow;
      "ffab00" = roninYellow;
      "ff8800" = surimiOrange;
      "ff6600" = surimiOrange;
      "cc6600" = surimiOrange;
      "ff6400" = surimiOrange;
      "ffd700" = carpYellow;
      "ffd740" = carpYellow;
      "ffdd00" = carpYellow;
      "ffcc44" = carpYellow;
      "ffff00" = carpYellow;
      "ffffcc" = carpYellow;
      "ff4444" = peachRed;
      "ff4041" = peachRed;
      "ff4400" = peachRed;
      "ff6666" = waveRed;
      "ff8888" = waveRed;
      "ff0000" = samuraiRed;
      "ff3232" = peachRed;
      "ff6464" = waveRed;
      "640000" = winterRed;
      "cc2222" = autumnRed;
      "331a00" = winterYellow;
      "330000" = winterRed;
      "0d0800" = winterYellow;
      "0d0004" = winterRed;
      # offline, bodies, ground
      "666688" = sumiInk6;
      "666680" = sumiInk6;
      "e0e0e0" = fujiWhite;
      "1a1a2e" = sumiInk3;
      "1a1a2a" = sumiInk3;
      "0a0a12" = sumiInk0;
      "0a0a1a" = sumiInk0;
      "050510" = sumiInk0;
      "111122" = sumiInk1;
      "222233" = sumiInk4;
      "2a2a4a" = sumiInk5;
      "333344" = sumiInk5;
      "001a33" = waveBlue1;
      "000a28" = waveBlue1;
      "000d1a" = sumiInk0;
      "001428" = waveBlue1;
      "c8e6ff" = lightBlue;
      "334455" = waveBlue1;
      "445566" = waveBlue2;
      "556677" = dragonBlue;
      "667788" = dragonBlue;
      "8899aa" = springViolet1;
      "8899bb" = springViolet1;
      "aabbcc" = oniViolet2;
    };
    rgbOf = hex: map (i: (builtins.fromTOML "v = 0x${builtins.substring i 2 hex}").v) [0 2 4];
    csv = sep: hex: lib.concatMapStringsSep sep toString (rgbOf hex);
    glsl = hex: lib.concatMapStringsSep ", " (c: toString (c / 255.0)) (rgbOf hex);
    sedRules = lib.concatStrings (lib.mapAttrsToList (from: to: ''
        s/0x${from}\b/0x${to}/Ig
        s/#${from}/#${to}/Ig
        s/rgba\?(${csv ", *" from}\b/rgba(${csv ", " to}/g
      '')
      toTheme);
    recolor = ''
      cat > recolor.sed <<'EOF'
      ${sedRules}
      s/vec3(1\.0, 0\.0, 1\.0)/vec3(${glsl k.sakuraPink})/g
      s/vec3(0\.08, 0\.08, 0\.12)/vec3(${glsl k.sumiInk1})/g
      EOF
      find src -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.css' \) \
        -not -path '*__mocks__*' -exec sed -i -f recolor.sed {} +
      if grep -rniE '(0x|#)(00ffff|ff00ff|00ff88|ffaa00|ff4444)' src --include='*.ts' --include='*.tsx' \
        | grep -v '__mocks__\|\.test\.'; then
        echo "recolor: neon left over" >&2; exit 1
      fi
    '';
    # Grafana busts its browser cache for plugin assets with ?_cache=<plugin.json
    # version>, served max-age=3600: a rebuild that keeps "1.1.1" is invisible
    # to browsers that already loaded it. Tag the version with the patch set.
    patchTag = builtins.substring 0 8 (builtins.hashString "sha256" sourcePatches);
  in
    pkgs.buildNpmPackage {
      pname = "whooktown-neoncity-panel";
      version = "1.1.1-unstable-2026-09-07";
      src = pkgs.fetchFromGitHub {
        owner = "fredericalix";
        repo = "grafana-neon-city-panel";
        rev = "8c5fff0d784caeb0645fc5c05e581e9cff507788";
        hash = "sha256-SI7hvy7nNH27HcaQMdMeq3GPPtjfw9D2LPXWqbKftws=";
      };
      npmDepsHash = "sha256-B/kh43x51Xxw2yLn9PU2x1czHEwzNOgO2EOo4lKb+Jo=";
      nodejs = pkgs.nodejs_22;
      # playwright/@swc pull browser/native binaries we don't need for a build.
      npmFlags = ["--ignore-scripts"];
      makeCacheWritable = true; # npm ci writes to the cache for the git dep below
      forceGitDeps = true; # @grafana/ui pulls react-data-grid from git; npm wants its devDeps (biome) to "prepare" it, which aren't in the lock
      env.PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
      postPatch =
        sourcePatches
        + ''
          substituteInPlace package.json \
            --replace-fail '"version": "1.1.1",' '"version": "1.1.1-${patchTag}",'
        '';
      npmBuildScript = "build";
      installPhase = ''
        runHook preInstall
        cp -r dist $out
        runHook postInstall
      '';
      doCheck = false;
    };

  passwordOf = {
    decrypt,
    deps,
    lib,
    ...
  }: ''pw=$(${decrypt} ${lib.escapeShellArg (lib.head deps).file})'';
in {
  # ---- secrets ----------------------------------------------------------
  age.secrets = {
    # Repo-only: never reaches the host, the two below derive from it.
    ntfy-publisher-password = {
      generator.script = "alnum";
      intermediary = true;
    };

    # NTFY_AUTH_USERS=<user>:<bcrypt>:<role>. systemd EnvironmentFile does
    # not expand `$`, so the hash goes in as is.
    ntfy-env.generator = {
      dependencies = [config.age.secrets.ntfy-publisher-password];
      script = args @ {pkgs, ...}: ''
        ${passwordOf args}
        hash=$(${pkgs.coreutils}/bin/printf '%s\n' "$pw" \
          | ${pkgs.mkpasswd}/bin/mkpasswd -m bcrypt -R 10 --stdin)
        ${pkgs.coreutils}/bin/printf "NTFY_AUTH_USERS='%s:%s:user'\n" ${ntfyUser} "$hash"
      '';
    };

    # Merged over the module-generated settings.yml by alertmanager-ntfy.
    alertmanager-ntfy-auth.generator = {
      dependencies = [config.age.secrets.ntfy-publisher-password];
      script = args @ {pkgs, ...}: ''
        ${passwordOf args}
        ${pkgs.coreutils}/bin/printf 'ntfy:\n  auth:\n    basic:\n      username: "%s"\n      password: "%s"\n' ${ntfyUser} "$pw"
      '';
    };

    grafana-admin-password = {
      generator.script = "alnum";
      owner = "grafana";
    };
    grafana-secret-key = {
      generator.script = "hex";
      owner = "grafana";
    };
  };

  # ---- ntfy -------------------------------------------------------------
  services.ntfy-sh = {
    enable = true;
    settings = {
      # Only used for links inside notifications; subscribe by whatever
      # address reaches the router (LAN or ygg0).
      base-url = "http://192.168.10.1:${toString ntfyPort}";
      listen-http = ":${toString ntfyPort}";
      auth-default-access = "deny-all";
      # The phone subscribes anonymously; only the bridge publishes.
      auth-access = [
        "everyone:hive-*:read-only"
        "${ntfyUser}:hive-*:write-only"
      ];
      cache-duration = "72h";
    };
    environmentFile = config.age.secrets.ntfy-env.path;
  };
  # DynamicUser + StateDirectory would turn /var/lib/ntfy-sh into a symlink
  # to /var/lib/private, but it is a dataset mountpoint. Static user instead
  # (the module declares `ntfy-sh` already); StateDirectory stays and chowns
  # the root-owned dataset root on every start.
  systemd.services.ntfy-sh = {
    unitConfig.RequiresMountsFor = "/var/lib/ntfy-sh";
    serviceConfig.DynamicUser = lib.mkForce false;
  };

  # ---- alertmanager -> ntfy ---------------------------------------------
  services.prometheus.alertmanager-ntfy = {
    enable = true;
    settings = {
      http.addr = "127.0.0.1:${toString bridgePort}";
      ntfy = {
        baseurl = "http://127.0.0.1:${toString ntfyPort}";
        notification = {
          inherit topic;
          priority = ''status == "firing" ? "high" : "default"'';
          templates = {
            title = ''
              {{ if eq .Status "resolved" }}Resolved: {{ end }}{{ index .Labels "alertname" }}{{ with index .Labels "host" }} @ {{ . }}{{ end }}
            '';
            description = ''
              {{ index .Annotations "summary" }}
            '';
          };
        };
      };
    };
    extraConfigFiles = [config.age.secrets.alertmanager-ntfy-auth.path];
  };

  services.prometheus.alertmanager = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = amPort;
    configuration = {
      route = {
        receiver = "ntfy";
        group_by = ["alertname" "host"];
        group_wait = "30s";
        group_interval = "5m";
        repeat_interval = "12h";
        # A critical that is still firing is worth a nudge every hour; the
        # 12 h default is for "yes, I know the pool is 80 % full".
        # DiskReallocatingGrowing fires for the 6 h after each growth step
        # by design (alerts.yml): one push per wave, no hourly repeats.
        # info = dashboard only.
        routes = [
          {
            matchers = ["severity = info"];
            receiver = "null";
          }
          {
            matchers = ["alertname = DiskReallocatingGrowing"];
            repeat_interval = "12h";
          }
          {
            matchers = ["severity = critical"];
            repeat_interval = "1h";
          }
        ];
      };
      # A host that is down takes its scrapes, services, backups and
      # snapshot stamps with it: HostDown is the one push. Needs `host` on
      # both sides; the scrape/probe job labels give it.
      inhibit_rules = [
        {
          source_matchers = ["alertname =~ HostDown|HostUnresponsive"];
          target_matchers = ["alertname =~ ExporterDown|ServiceDown|BackupStale|SnapshotStale|SystemdUnitFailed"];
          equal = ["host"];
        }
        # Critical temperature replaces the warning for the same sensor.
        {
          source_matchers = ["severity = critical"];
          target_matchers = ["severity = warning"];
          equal = ["alertname" "host" "device" "chip"];
        }
      ];
      receivers = [
        {name = "null";}
        {
          name = "ntfy";
          webhook_configs = [
            {
              url = "http://127.0.0.1:${toString bridgePort}/hook";
              send_resolved = true;
            }
          ];
        }
      ];
    };
  };

  # ---- prometheus -------------------------------------------------------
  services.prometheus = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = promPort;
    retentionTime = "30d";
    globalConfig = {
      scrape_interval = "15s";
      evaluation_interval = "15s";
    };
    # Unit tests (alerts_test.yml) run at build time: a rule change that
    # breaks them does not reach the router.
    ruleFiles = [
      (pkgs.runCommand "alerts.yml" {nativeBuildInputs = [pkgs.prometheus.cli];} ''
        cp ${../monitoring/alerts.yml} alerts.yml
        cp ${../monitoring/alerts_test.yml} alerts_test.yml
        promtool test rules alerts_test.yml
        cp alerts.yml $out
      '')
    ];
    alertmanagers = [{static_configs = [{targets = ["127.0.0.1:${toString amPort}"];}];}];

    exporters = {
      node = {
        enable = true;
        listenAddress = "127.0.0.1";
        enabledCollectors = [
          "systemd"
          "textfile"
        ];
        # hot-backup stamp (backup-push.nix); persisted so it survives a reboot.
        extraFlags = ["--collector.textfile.directory=/var/lib/node_exporter/textfile"];
      };
      zfs = {
        enable = true;
        listenAddress = "127.0.0.1";
        pools = ["rpool"];
      };
      blackbox = {
        enable = true;
        listenAddress = "127.0.0.1";
        configFile = pkgs.writeText "blackbox.yml" (builtins.toJSON {
          modules = {
            tcp_connect = {
              prober = "tcp";
              timeout = "5s";
            };
            icmp = {
              prober = "icmp";
              timeout = "5s";
              icmp.preferred_ip_protocol = "ip4";
            };
            http_2xx = {
              prober = "http";
              timeout = "5s";
              http = {
                preferred_ip_protocol = "ip4";
                follow_redirects = true;
              };
            };
          };
        });
      };
    };

    scrapeConfigs = let
      job = name: host: targets: {
        job_name = "${name}-${host}";
        static_configs = [
          {
            inherit targets;
            labels = {inherit host;};
          }
        ];
      };
    in [
      (job "node" "imladris" ["${imladris}:9100"])
      (job "zfs" "imladris" ["${imladris}:9134"])
      (job "smartctl" "imladris" ["${imladris}:9633"])
      (job "node" "minas-tirith" ["127.0.0.1:9100"])
      (job "zfs" "minas-tirith" ["127.0.0.1:9134"])
      # No exporter on the public VPS: is ssh reachable from here.
      (probeJob "probe-osgiliath" "tcp_connect" [
        {
          targets = ["${osgiliath}:22"];
          labels.host = "osgiliath";
        }
      ])
      (probeJob "icmp-lan" "icmp" (lib.mapAttrsToList (host: ip: {
          targets = [ip];
          labels.host = host;
        })
        icmpTargets))
      (probeJob "http-services" "http_2xx" (lib.mapAttrsToList (service: url: {
          targets = [url];
          labels = {
            inherit service url;
            host = hostOf url;
            tier = "main";
          };
        })
        httpServices))
    ];
  };
  environment.persistence."/state".directories = ["/var/lib/node_exporter"];
  systemd.tmpfiles.rules = ["d /var/lib/node_exporter/textfile 0755 root root -"];

  # Module sets StateDirectory=prometheus2 (0700): chowns the dataset root.
  systemd.services.prometheus.unitConfig.RequiresMountsFor = "/var/lib/prometheus2";

  # ---- grafana ----------------------------------------------------------
  services.grafana = {
    enable = true;
    # Plugins come from the store only; nothing is installed from the UI.
    declarativePlugins = [neonCityPanel];
    settings = {
      plugins.allow_loading_unsigned_plugins = neonCityPanel.pname;
      server = {
        http_addr = "0.0.0.0";
        http_port = grafanaPort;
        domain = "192.168.10.1";
      };
      security = {
        admin_user = "admin";
        admin_password = "$__file{${config.age.secrets.grafana-admin-password.path}}";
        secret_key = "$__file{${config.age.secrets.grafana-secret-key.path}}";
      };
      analytics = {
        reporting_enabled = false;
        check_for_updates = false;
      };
      users.allow_sign_up = false;
      # Servers run UTC and so does every journal line; Grafana defaults to
      # the browser's zone, which makes panels disagree with journalctl.
      date_formats.default_timezone = "utc";
      # Generated by monitoring/dashboards/build.py, provisioned below.
      dashboards.default_home_dashboard_path = "${../monitoring/dashboards/hive.json}";
    };
    provision = {
      enable = true;
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          uid = "prometheus";
          url = "http://127.0.0.1:${toString promPort}";
          isDefault = true;
        }
      ];
      dashboards.settings.providers = [
        {
          name = "hive";
          options.path = ../monitoring/dashboards;
        }
      ];
    };
  };
  # Dataset root is root-owned from `zfs create`; StateDirectory chowns it on
  # every start, after RequiresMountsFor (torrserver precedent).
  systemd.services.grafana = {
    unitConfig.RequiresMountsFor = "/var/lib/grafana";
    serviceConfig = {
      StateDirectory = "grafana";
      StateDirectoryMode = "0750";
    };
  };

  # ---- reachability -----------------------------------------------------
  networking.firewall.interfaces.ygg0.allowedTCPPorts = [
    ntfyPort
    grafanaPort
  ];
}
