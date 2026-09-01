# The Zola site and the radio station as a NixOS module. Host-agnostic; the
# consumer sets domain, secrets and firewall.
#
# radio.liq and the scripts address everything relative to the working
# directory (`radio/state/...`, `music`, `public`). Rather than rewrite tuned
# audio code, the module reproduces that directory shape under stateDir and
# runs every unit with WorkingDirectory there. radio.liq is used verbatim.
{
  inputs,
  cell,
  ...
}: {
  default = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.services.hisilome;

    # Each file gets its own store path. Referencing `inputs.self + "/cells/..."`
    # instead would make the toplevel depend on the whole flake source and
    # re-push a 4 GiB closure on every unrelated edit (measured).
    radioLiq = builtins.path {
      path = ./radio/radio.liq;
      name = "radio.liq";
    };
    icecastXml = builtins.path {
      path = ./radio/icecast.xml;
      name = "icecast.xml";
    };
    inherit
      (lib)
      mkOption
      mkEnableOption
      mkIf
      types
      ;

    # The layout every unit runs inside.
    #   ${stateDir}/public      -> the built site (store symlink)
    #   ${stateDir}/music/      -> the library (real dir; rsync target)
    #   ${stateDir}/radio/state -> the only writable path
    runtime = cfg.stateDir;
    radioState = "${runtime}/radio/state";

    # "liquidsoap cannot write outside its state dir" -- what a container would
    # buy, at no closure cost.
    hardening = {
      ReadWritePaths = [radioState];
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      ProtectKernelTunables = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
    };

    buildQueue = cell.packages.build-queue;

    # build-queue exits 1 on an empty library, which failed the first
    # activation before the library was rsynced. Empty is valid: serve the
    # site, no station.
    emptyTolerantQueue = pkgs.writeShellApplication {
      name = "build-queue-if-music";
      runtimeInputs = [
        buildQueue
        pkgs.findutils
        pkgs.coreutils
      ];
      text = ''
        if [ -z "$(find music -type f \
              \( -iname "*.flac" -o -iname "*.mp3" -o -iname "*.m4a" -o -iname "*.opus" \
                 -o -iname "*.ogg" -o -iname "*.wav" \) -print -quit 2>/dev/null)" ]; then
          echo "build-queue-if-music: no playable files under $PWD/music -- skipping."
          echo "  the site is served regardless; the station starts once the library is synced."
          exit 0
        fi
        exec build-queue --rounds ${toString cfg.queueRounds} music
      '';
    };

    listenerCount = cell.packages.listener-count;

    # Repeated in every location that adds its own header: nginx `add_header`
    # in a location discards the server-level set. 'unsafe-inline' on style-src
    # only: liquidsoap's fragments and the tag cloud use style attributes.
    securityHeaders = ''
      add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;
      add_header Content-Security-Policy "default-src 'none'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; media-src 'self'; frame-src 'self'; frame-ancestors 'self'; base-uri 'none'; form-action 'none'" always;
      add_header X-Content-Type-Options nosniff always;
      add_header Referrer-Policy strict-origin-when-cross-origin always;
      add_header Alt-Svc 'h3=":443"; ma=86400' always;
    '';
  in {
    options.services.hisilome = {
      enable = mkEnableOption "the Hísilómë site and radio station";

      domain = mkOption {
        type = types.str;
        description = "Public hostname. Also the nginx virtualHost name.";
        example = "hisilo.me";
      };

      enableACME = mkOption {
        type = types.bool;
        default = true;
        description = "Request a Let's Encrypt certificate and force HTTPS.";
      };

      stateDir = mkOption {
        type = types.path;
        default = "/var/lib/hisilome";
        description = ''
          Runtime root. Must be writable and persistent: it holds the music
          library and the queue. On an impermanent host, point this INSIDE the
          persistent subvolume rather than adding a bind-mount -- the paths below
          are used directly, not restored into place.
        '';
      };

      site = mkOption {
        type = types.package;
        default = cell.packages.site;
        defaultText = "cell.packages.site";
        description = "The built Zola site. Overridable for testing.";
      };

      user = mkOption {
        type = types.str;
        default = "hisilome";
      };
      group = mkOption {
        type = types.str;
        default = "hisilome";
      };

      sourcePasswordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          File containing the icecast SOURCE password. Read at unit start, never
          copied into the Nix store. null keeps radio/icecast.xml's committed dev
          value, which is safe ONLY because icecast binds 127.0.0.1.
        '';
      };

      adminPasswordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "File containing the icecast ADMIN password. Same handling as sourcePasswordFile.";
      };

      queueRounds = mkOption {
        type = types.int;
        default = 8;
        description = "Shuffled passes concatenated into the play queue (process-compose.yaml:13).";
      };
    };

    config = mkIf cfg.enable {
      users.users.${cfg.user} = {
        isSystemUser = true;
        group = cfg.group;
        home = runtime;
        description = "Hísilómë radio";
      };
      users.groups.${cfg.group} = {};

      # public/ is a store symlink: publishing is an atomic swap and zola never
      # runs on the target.
      systemd.services.hisilome-setup = {
        description = "Assemble the Hísilómë runtime directory";
        wantedBy = ["multi-user.target"];
        before = [
          "icecast.service"
          "liquidsoap.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          set -eu
          install -d -o ${cfg.user} -g ${cfg.group} -m 0755 "${runtime}" "${runtime}/radio"
          install -d -o ${cfg.user} -g ${cfg.group} -m 0755 "${radioState}" "${radioState}/logs"
          install -d -o ${cfg.user} -g ${cfg.group} -m 0750 "${runtime}/music"

          ln -sfn ${cfg.site} "${runtime}/public"
          ln -sfn ${radioLiq} "${runtime}/radio/radio.liq"

          # icecast.xml is rendered, not linked: it carries passwords, and store
          # files are world-readable. <webroot>/<adminroot> are re-pointed too;
          # the committed file pins a stale store path.
          #
          # Password resolution order. colmena's deployment.keys land in /run/keys
          # (tmpfs) and are gone after a reboot until the next apply, so a value
          # resolved on a previous boot is kept on the persistent volume:
          #   1. the delivered key file
          #   2. the value from a previous boot
          #   3. the committed dev value (loopback-only icecast; nginx proxies
          #      only /stream.mp3, so not reachable from outside)
          umask 077

          resolve() {  # $1 = key file or empty, $2 = env file, $3 = var name
            if [ -n "$1" ] && [ -r "$1" ]; then
              tr -d '\n' < "$1"
            elif [ -r "$2" ]; then
              sed -n "s/^$3=//p" "$2"
            else
              echo ""
            fi
          }

          SRC=$(resolve "${lib.optionalString (cfg.sourcePasswordFile != null) cfg.sourcePasswordFile}" \
                        "${radioState}/source.env" ICECAST_SOURCE_PASSWORD)
          ADM=$(resolve "${lib.optionalString (cfg.adminPasswordFile != null) cfg.adminPasswordFile}" \
                        "${radioState}/admin.env" ADMIN_PASSWORD)

          if [ -z "$SRC" ] || [ -z "$ADM" ]; then
            echo "hisilome-setup: WARNING - falling back to the committed dev password." >&2
            echo "  icecast is loopback-only so this is not remotely reachable, but run" >&2
            echo "  'colmena apply' to deliver the real credentials." >&2
          fi

          sed \
            -e "s#<webroot>.*</webroot>#<webroot>${pkgs.icecast}/share/icecast/web</webroot>#" \
            -e "s#<adminroot>.*</adminroot>#<adminroot>${pkgs.icecast}/share/icecast/admin</adminroot>#" \
            ${icecastXml} > "${runtime}/radio/icecast.xml"

          if [ -n "$SRC" ]; then
            sed -i \
              -e "s#<source-password>.*</source-password>#<source-password>$SRC</source-password>#" \
              -e "s#<relay-password>.*</relay-password>#<relay-password>$SRC</relay-password>#" \
              "${runtime}/radio/icecast.xml"
          else
            SRC=hackme
          fi
          if [ -n "$ADM" ]; then
            sed -i \
              -e "s#<admin-password>.*</admin-password>#<admin-password>$ADM</admin-password>#" \
              "${runtime}/radio/icecast.xml"
          else
            ADM=hackme
          fi

          # Persistent volume, 0400: not in the store, not in git. icecast
          # cannot read a password from a descriptor, so on-disk it is.
          printf 'ICECAST_SOURCE_PASSWORD=%s\n' "$SRC" > "${radioState}/source.env"
          printf 'ADMIN_PASSWORD=%s\nADMIN=admin:%s\n' "$ADM" "$ADM" > "${radioState}/admin.env"

          chown ${cfg.user}:${cfg.group} "${runtime}/radio/icecast.xml" \
            "${radioState}/source.env" "${radioState}/admin.env"
          chmod 0400 "${radioState}/source.env" "${radioState}/admin.env"
          chmod 0400 "${runtime}/radio/icecast.xml"
        '';
      };

      # process-compose.yaml's graph, translated. Absent on purpose: build-site
      # (a derivation, built off-host) and tag-music (run on the workstation
      # before rsync; ReplayGain tags travel inside the files).

      systemd.services.icecast = {
        description = "Icecast stream server";
        wantedBy = ["multi-user.target"];
        after = ["hisilome-setup.service"];
        requires = ["hisilome-setup.service"];
        serviceConfig =
          {
            ExecStart = "${pkgs.icecast}/bin/icecast -c ${runtime}/radio/icecast.xml";
            User = cfg.user;
            Group = cfg.group;
            WorkingDirectory = runtime;
            Restart = "on-failure";
            RestartSec = 2;
          }
          // hardening;
      };

      # Must finish before liquidsoap: reload_mode="watch" on a missing playlist
      # is not recoverable (process-compose.yaml:11-16).
      systemd.services.hisilome-build-queue = {
        description = "Rebuild the Hísilómë play queue";
        after = ["hisilome-setup.service"];
        requires = ["hisilome-setup.service"];
        wantedBy = ["multi-user.target"];
        before = ["liquidsoap.service"];
        environment = {
          DIR = "music";
          OUT = "radio/state";
        };
        serviceConfig =
          {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${emptyTolerantQueue}/bin/build-queue-if-music";
            User = cfg.user;
            Group = cfg.group;
            WorkingDirectory = runtime;
          }
          // hardening;
      };

      # A timer, not process-compose.yaml:21's `while true; sleep 86400` loop:
      # under systemd that would restart its countdown on every reboot and drift.
      systemd.timers.hisilome-build-queue = {
        description = "Reshuffle the Hísilómë queue daily";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
          RandomizedDelaySec = "30m";
        };
      };

      systemd.services.liquidsoap = {
        description = "Liquidsoap encoder for Hísilómë";
        wantedBy = ["multi-user.target"];
        after = [
          "hisilome-setup.service"
          "icecast.service"
          "hisilome-build-queue.service"
        ];
        requires = [
          "hisilome-setup.service"
          "hisilome-build-queue.service"
        ];
        # After icecast but not bound to it: liquidsoap retries the source.
        # Condition, not failure, on a missing queue: an unsynced library serves
        # the site with no station instead of crash-looping.
        unitConfig.ConditionPathExists = "${radioState}/queue.m3u";
        serviceConfig =
          {
            ExecStart = "${pkgs.liquidsoap}/bin/liquidsoap ${runtime}/radio/radio.liq";
            EnvironmentFile = "${radioState}/source.env";
            User = cfg.user;
            Group = cfg.group;
            WorkingDirectory = runtime;
            Restart = "always";
            RestartSec = 5;
          }
          // hardening;
      };

      systemd.services.hisilome-listeners = {
        description = "Poll icecast for the listener count";
        wantedBy = ["multi-user.target"];
        after = ["icecast.service"];
        environment.OUT = "radio/state/listeners.txt";
        serviceConfig =
          {
            ExecStart = "${listenerCount}/bin/listener-count";
            EnvironmentFile = "${radioState}/admin.env";
            User = cfg.user;
            Group = cfg.group;
            WorkingDirectory = runtime;
            Restart = "always";
            RestartSec = 10;
          }
          // hardening;
      };

      # Translated from radio/nginx.conf: that file pins a store path for
      # mime.types and carries no TLS. Locations are app knowledge; domain and
      # ACME come from the consumer.
      services.nginx = {
        enable = true;

        # Reload, not restart: listeners hold /stream.mp3 open for hours and a
        # blog post must not cut the radio. A template edit changes only
        # nginx.service; liquidsoap and icecast are untouched (measured).
        enableReload = true;

        recommendedProxySettings = false; # would override the Icy-MetaData fix below
        recommendedGzipSettings = true;
        recommendedOptimisation = true;

        virtualHosts.${cfg.domain} = {
          enableACME = cfg.enableACME;
          forceSSL = cfg.enableACME;
          quic = cfg.enableACME;
          http3 = cfg.enableACME;
          root = "${cfg.site}";

          # ssi on is REQUIRED: static/live.html:129 and static/schedule.html:16
          # include fragments liquidsoap writes at runtime. Without it both pages
          # render with a silent empty hole and still return 200.
          extraConfig = ''
            ssi on;
            ${securityHeaders}
          '';

          locations =
            {
              # radio/nginx.conf:17-20,39-41. The shell's own frame also requests
              # "/", but carries Sec-Fetch-Dest: iframe - which is what stops the
              # shell framing itself forever.
              "= /".extraConfig = ''
                if ($http_sec_fetch_dest = iframe) { rewrite ^ /index.html last; }
                rewrite ^ /listen.html last;
              '';

              "/".extraConfig = ''
                try_files $uri $uri/ =404;
              '';

              # radio/nginx.conf:52-72, header-for-header.
              "~ ^/stream\\.(mp3|opus)$".extraConfig = ''
                proxy_pass http://127.0.0.1:8000;
                proxy_http_version 1.1;
                proxy_buffering off;
                proxy_request_buffering off;
                chunked_transfer_encoding off;

                # Icecast answers "ICY 200 OK" rather than an HTTP status line when
                # the client sends Icy-MetaData: 1; nginx cannot parse that -> 502.
                proxy_set_header Icy-MetaData "";
                proxy_set_header Host $host;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

                # default 60s trips on a liquidsoap restart
                proxy_read_timeout 24h;
                proxy_send_timeout 24h;

                gzip off;
              '';
            }
            # Live fragments, written by liquidsoap into radio/state/. Outside the
            # site root so `zola build` cannot delete them (nginx.conf:61-62).
            // lib.listToAttrs (
              map
              (
                f:
                  lib.nameValuePair "= /${f.name}" {
                    extraConfig = ''
                      alias ${radioState}/${f.file};
                      default_type ${f.type};
                      add_header Cache-Control "no-store, no-cache, must-revalidate";
                      ${securityHeaders}
                      ssi off;
                    '';
                  }
              )
              [
                {
                  name = "console.html";
                  file = "console.html";
                  type = "text/html";
                }
                {
                  name = "schedule-body.html";
                  file = "schedule.html";
                  type = "text/html";
                }
                {
                  name = "listeners.txt";
                  file = "listeners.txt";
                  type = "text/plain";
                }
                {
                  name = "now-playing.txt";
                  file = "now-playing.txt";
                  type = "text/plain";
                }
              ]
            );
        };
      };

      # nginx must be able to traverse into the state dir to serve the fragments.
      users.users.${config.services.nginx.user}.extraGroups = [cfg.group];
    };
  };
}
