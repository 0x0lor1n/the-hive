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
        routes = [
          {
            matchers = ["severity = critical"];
            repeat_interval = "1h";
          }
        ];
      };
      receivers = [
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
    ruleFiles = [../monitoring/alerts.yml];
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
    settings = {
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
