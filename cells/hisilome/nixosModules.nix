# NixOS module for Hísilómë: the Zola site and the radio station.
#
# Deliberately knows nothing about any particular host. Everything
# osgiliath-specific -- which domain, which secrets, which firewall -- is set by
# the consumer (test-vm's cells/nixos/profiles/site-hisilome.nix).
#
# THE CENTRAL DESIGN CONSTRAINT: radio.liq and the shell scripts address
# everything RELATIVE to the working directory -- `radio/state/...`, `music`,
# `public` (radio.liq:3-5,52,116,124,212,225,303). Rather than rewrite tuned
# audio code to use absolute paths, this module reproduces the directory shape
# that code already expects and sets WorkingDirectory to it. radio.liq is used
# verbatim.
# rensa passes `system` as well as `inputs` and `cell`, so block files need an
# ellipsis. hive's signature was exactly `{ inputs, cell }`.
{
  inputs,
  cell,
  ...
}: {
  # A `functions` cell block must evaluate to an ATTRSET of instances, not to
  # a bare module lambda -- paisano rejects the latter with
  # "expected type 'attrs<any>' ... is of type 'lambda'".
  default = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.services.hisilome;

    # The two files the units read at start, each given its OWN store path.
    #
    # NOT `inputs.self + "/cells/hisilome"`: that makes the setup script
    # depend on the entire flake source, so osgiliath's toplevel changes on
    # every unrelated repo edit and `colmena apply` re-pushes a 4.2 GiB
    # closure for nothing. Measured -- folding the blog in this way changed
    # the toplevel while the package set stayed identical, and the only diff
    # was this script's hash.
    #
    # builtins.path copies each file alone, so the units change only when
    # radio.liq or icecast.xml actually change.
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

    # Shared systemd confinement. This is what makes NixOS containers unnecessary
    # here (see iteration-12 plan §10): the boundary wanted is "liquidsoap cannot
    # write outside its own state dir", and that is exactly this, at no closure
    # cost.
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

    # From the cell's packages block, so the units and the devshell can never
    # run different builds of the same script.
    buildQueue = cell.packages.build-queue;

    # build-queue exits 1 on an empty library ("no playable files in music"),
    # which failed the whole activation on the first deploy -- before the 1.1 GB
    # library had been rsynced, which cannot happen until the host exists. An
    # empty library is a valid state: serve the site, no station.
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

      # ---------------------------------------------------------------------
      # Runtime directory assembly
      # ---------------------------------------------------------------------
      #
      # public/ is a SYMLINK into the store, so publishing a new site is an atomic
      # swap and `zola build` never runs on the target.
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
          # Not created if absent-and-empty would be wrong: the library is rsynced
          # in out of band, and an empty dir is a valid (silent) station.
          install -d -o ${cfg.user} -g ${cfg.group} -m 0750 "${runtime}/music"

          ln -sfn ${cfg.site} "${runtime}/public"
          ln -sfn ${radioLiq} "${runtime}/radio/radio.liq"

          # icecast.xml is RENDERED, not linked: it carries passwords, and store
          # files are world-readable. The same pass re-points <webroot>/
          # <adminroot>, which icecast.xml:37-38 pins to a store path from
          # whenever it was last edited -- stale after any icecast bump.
          #
          # PASSWORD RESOLUTION, in order. This ordering exists because
          # colmena's deployment.keys land in /run/keys, which is a TMPFS: after
          # a reboot they are gone until the next `colmena apply`. Reading them
          # unconditionally under `set -eu` would leave the station dead on every
          # boot. So a previously-resolved value on the persistent volume is
          # preferred over the committed default, and a freshly delivered key
          # over both:
          #
          #   1. the key file, if colmena has delivered it       (best)
          #   2. the value resolved on a previous boot           (survives reboot)
          #   3. the committed dev value in icecast.xml          (last resort)
          #
          # (3) is not a silent downgrade: icecast binds 127.0.0.1 and nginx
          # proxies only /stream.mp3, so neither password is reachable from
          # outside. It is defence in depth, and the warning says so.
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

          # Written to the PERSISTENT volume, which is what makes step (2) above
          # work on the next boot. The password is on disk either way -- icecast
          # has no way to read it from a descriptor -- so the property held here
          # is "not in the Nix store and not in git", at mode 0400.
          printf 'ICECAST_SOURCE_PASSWORD=%s\n' "$SRC" > "${radioState}/source.env"
          printf 'ADMIN_PASSWORD=%s\nADMIN=admin:%s\n' "$ADM" "$ADM" > "${radioState}/admin.env"

          chown ${cfg.user}:${cfg.group} "${runtime}/radio/icecast.xml" \
            "${radioState}/source.env" "${radioState}/admin.env"
          chmod 0400 "${radioState}/source.env" "${radioState}/admin.env"
          chmod 0400 "${runtime}/radio/icecast.xml"
        '';
      };

      # ---------------------------------------------------------------------
      # The station
      # ---------------------------------------------------------------------
      #
      # process-compose.yaml's dependency graph, translated. Two processes are
      # deliberately absent: `build-site` (a derivation now, built off-host) and
      # `tag-music` (a full decode pass over the library -- run on the workstation
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
        # Ordered after icecast but NOT bound to it: liquidsoap retries the
        # source connection, so a brief icecast restart should not take the
        # encoder down with it.
        # Skipped, not failed, when there is no queue yet -- a host whose library
        # has not been synced should come up serving the site, with the station
        # simply absent. Without this liquidsoap crash-loops on a missing
        # playlist.
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

      # ---------------------------------------------------------------------
      # nginx
      # ---------------------------------------------------------------------
      #
      # Translated from radio/nginx.conf rather than used as-is: that file pins a
      # store path for mime.types (:12), which goes stale on any nginx bump, and
      # carries no TLS. The locations below are app knowledge and belong with the
      # app; the domain and ACME toggle come from the consumer.
      services.nginx = {
        enable = true;

        # RELOAD on config change rather than restart. The default is false,
        # which is the wrong default for THIS host: a restart drops every
        # in-flight connection, and the connections here are listeners
        # holding /stream.mp3 open for hours. Publishing a blog post must not
        # cut the radio off mid-track.
        #
        # Measured: a template edit changes nginx.service (new config store
        # path) but leaves liquidsoap and icecast untouched, so the encoder
        # never skips. This closes the remaining gap on the listener side.
        enableReload = true;

        recommendedProxySettings = false; # would override the Icy-MetaData fix below
        recommendedGzipSettings = true;
        recommendedOptimisation = true;

        virtualHosts.${cfg.domain} = {
          enableACME = cfg.enableACME;
          forceSSL = cfg.enableACME;
          root = "${cfg.site}";

          # ssi on is REQUIRED: static/live.html:129 and static/schedule.html:16
          # include fragments liquidsoap writes at runtime. Without it both pages
          # render with a silent empty hole and still return 200.
          extraConfig = ''
            ssi on;
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
              "= /stream.mp3".extraConfig = ''
                proxy_pass http://127.0.0.1:8000/stream.mp3;
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
