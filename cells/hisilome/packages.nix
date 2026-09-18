# The rendered site, the station scripts, and the nginx location set shared by
# the NixOS module and the dev stack so the two cannot drift.
{
  inputs,
  cell,
  ...
}: let
  pkgs = inputs.pkgs;
  lib = pkgs.lib;

  # music/ (1.1 GB, gitignored) and radio/state/ (rewritten every second by a
  # running station) would otherwise churn the site derivation -- and through
  # it the host toplevel -- on every edit.
  src = builtins.path {
    path = ./.;
    name = "hisilome-src";
    filter = path: type: let
      rel = lib.removePrefix (toString ./. + "/") (toString path);
    in
      !(lib.hasPrefix "music" rel || lib.hasPrefix "radio/state" rel || lib.hasPrefix "diagrams/out" rel);
  };

  mkScript = name: runtimeInputs:
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      text = builtins.readFile "${src}/bin/${name}.sh";
    };

  # d2 takes .ttf only; the page ships Iosevka as woff2 subsets. Decompress
  # those rather than pulling iosevka-bin (a .ttc, which d2 also refuses), so
  # the diagrams use the exact glyph set the prose does.
  d2-fonts =
    pkgs.runCommand "hisilome-d2-fonts" {
      nativeBuildInputs = [(pkgs.python3.withPackages (p: [p.fonttools p.brotli]))];
    } ''
      mkdir -p $out
      for w in regular bold; do
        fonttools ttLib.woff2 decompress ${src}/static/fonts/iosevka-$w.woff2 -o $out/$w.ttf
      done
    '';

  # d2 -> svg next to each post's index.md before zola build; Zola copies
  # colocated assets into the page directory and the d2 shortcode inlines the
  # svg from there. --scale 1 writes width/height on the <svg>, so the browser
  # draws diagrams at native size instead of stretching a 360px chain to the
  # column width. classes.d2 is import-only, hence the numbered-file glob.
  # No italic subset is shipped, so italic falls back to regular.
  build-site = pkgs.writeShellApplication {
    name = "build-site";
    runtimeInputs = [pkgs.d2 pkgs.zola pkgs.coreutils pkgs.findutils];
    text = ''
      export D2_FONT_REGULAR=${d2-fonts}/regular.ttf
      export D2_FONT_ITALIC=${d2-fonts}/regular.ttf
      export D2_FONT_BOLD=${d2-fonts}/bold.ttf
      export D2_FONT_SEMIBOLD=${d2-fonts}/bold.ttf
      # Engine is per file: a leading "# layout: dagre" line overrides elk.
      find content -name '[0-9]*.d2' -print0 | while IFS= read -r -d "" f; do
        layout=$(sed -n '1,3s/^# layout: *//p' "$f" | head -1)
        d2 --layout "''${layout:-elk}" --theme 200 --pad 20 --scale 1 "$f" "''${f%.d2}.svg"
      done
      # Drafts are in unless SITE_DRAFTS=0: local builds are for reading what
      # is not published yet; the deploy derivation sets 0 explicitly.
      if [ "''${SITE_DRAFTS:-1}" != 0 ]; then set -- --drafts "$@"; fi
      zola build "$@"
    '';
  };

  # Fragments liquidsoap writes into radio/state, served outside the site root
  # so `zola build` cannot delete them.
  fragments = [
    {
      name = "console.html";
      file = "console.html";
      type = "text/html";
    }
    {
      name = "refresh.html";
      file = "refresh.html";
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
    {
      # Empty while liquidsoap runs; the station unit's ExecStopPost writes the
      # offline <style> into it. Missing (never started) falls to the SSI stub.
      name = "status.html";
      file = "status.html";
      type = "text/html";
    }
  ];

  # What the shell includes when the station is down. SSI cannot add a class
  # to <body>, so the fragment is a <style> that flips a custom property;
  # style.css keys the loader and the hidden player off it.
  offlineStyle = "<style>:root{--station-ui:none;--ld-image:var(--ld-loader);--ld-anim:ld-crawl 1.8s steps(14,end) infinite}</style>";

  # A top-level navigation to any page gets the shell, which frames the
  # original URL via SSI `request_uri` (never rewritten by nginx). The frame's
  # own request carries Sec-Fetch-Dest: iframe and falls through to the page.
  # Zola pages end in "/", so assets and streams are untouched. Clients without
  # Sec-Fetch-Dest (curl, crawlers, old Safari) get the bare page.
  nginxHttpConfig = ''
    map "$http_sec_fetch_dest$uri" $shell_page {
      ~^document.*/$  /listen/index.html;
      default         /__none;
    }

    # 1 vCPU, icecast <clients>100</clients>: without these one client holding
    # a few hundred /stream.* connections takes the station down.
    limit_conn_zone $binary_remote_addr zone=stream:1m;
    limit_req_zone  $binary_remote_addr zone=pages:1m rate=10r/s;
    limit_conn_status 429;
    limit_req_status  429;
  '';

  # A shell load is ~10 requests at once (page, css, fonts, two frames, their
  # fragments), then a fragment every 10s per listener.
  pageLimit = "limit_req zone=pages burst=40 nodelay;";

  # `stateDir` is where liquidsoap writes (absolute in prod, relative in dev).
  # `extraHeaders` is repeated in every location that adds its own header:
  # nginx `add_header` in a location discards the inherited set.
  nginxLocations = {
    stateDir,
    extraHeaders ? "",
  }:
    {
      "/".extraConfig = ''
        ${pageLimit}
        try_files $shell_page $uri $uri/ =404;
      '';

      "~ ^/stream\\.(mp3|opus)$".extraConfig = ''
        # Two mounts plus a reconnect in flight per household.
        limit_conn stream 6;
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_request_buffering off;
        chunked_transfer_encoding off;

        # Icecast answers "ICY 200 OK" instead of an HTTP status line when the
        # client sends Icy-MetaData: 1; nginx cannot parse that -> 502.
        proxy_set_header Icy-MetaData "";
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

        # default 60s trips on a liquidsoap restart
        proxy_read_timeout 24h;
        proxy_send_timeout 24h;

        gzip off;
      '';
    }
    // lib.listToAttrs (map (f:
      lib.nameValuePair "= /${f.name}" {
        extraConfig = ''
          ${pageLimit}
          alias ${stateDir}/${f.file};
          default_type ${f.type};
          add_header Cache-Control "no-store, no-cache, must-revalidate";
          ${extraHeaders}
          ssi off;
        '';
      })
    fragments);

  # Dev nginx: the same locations in a standalone config. Relative paths
  # resolve against `-p $PWD` (cells/hisilome).
  devNginxConf = let
    locs = nginxLocations {stateDir = "radio/state";};
    render = lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: ''
        location ${k} {
        ${v.extraConfig}
        }
      '')
      locs);
  in
    pkgs.writeText "nginx.dev.conf" ''
      daemon off;
      error_log radio/state/logs/nginx_error.log;
      pid radio/state/nginx.pid;
      worker_processes auto;

      events { worker_connections 1024; }

      http {
        include ${pkgs.nginx}/conf/mime.types;
        default_type application/octet-stream;
        access_log radio/state/logs/nginx_access.log;
        client_body_temp_path radio/state/nginx_client_body;
        proxy_temp_path radio/state/nginx_proxy;
        ${nginxHttpConfig}

        server {
          listen 8099;
          root public;
          ssi on;
          index index.html;
          ${render}
        }
      }
    '';
in {
  inherit nginxLocations nginxHttpConfig build-site;

  # Marks the station offline (see `fragments`). Run from the unit's
  # ExecStopPost, or by hand in dev. `station-online` clears it.
  station-offline = pkgs.writeShellApplication {
    name = "station-offline";
    text = ''
      printf '%s' '${offlineStyle}' > radio/state/status.html.tmp
      mv radio/state/status.html.tmp radio/state/status.html
    '';
  };
  station-online = pkgs.writeShellApplication {
    name = "station-online";
    text = ''
      : > radio/state/status.html.tmp
      mv radio/state/status.html.tmp radio/state/status.html
    '';
  };

  site = pkgs.runCommand "hisilome-site" {} ''
    set -e
    cp -r ${src} s
    chmod -R u+w s
    cd s
    export HOME=$TMPDIR
    SITE_DRAFTS=0 ${build-site}/bin/build-site --output-dir $out
  '';

  # Preview through the same nginx config as prod (SSI, fragments, headers).
  # `zola serve` does none of that: the SSI comments leak into the page as text.
  dev-site = pkgs.writeShellApplication {
    name = "dev-site";
    runtimeInputs = [build-site cell.packages.dev-nginx pkgs.watchexec pkgs.coreutils];
    text = ''
      build-site
      dev-nginx &
      trap 'kill $!' EXIT
      echo "site: http://localhost:8099 (stream/console 502 unless the station is up)"
      exec watchexec \
        --watch content --watch templates --watch static --watch syntaxes --watch config.toml \
        --ignore 'content/**/*.svg' \
        --debounce 300ms --on-busy-update=queue \
        -- build-site
    '';
  };

  dev-nginx = pkgs.writeShellApplication {
    name = "dev-nginx";
    runtimeInputs = [pkgs.nginx pkgs.coreutils];
    text = ''
      mkdir -p radio/state/logs
      exec nginx -c ${devNginxConf} -p "$PWD" "$@"
    '';
  };

  tag-replaygain = mkScript "tag-replaygain" (
    with pkgs; [
      ffmpeg
      flac
      python3Packages.mutagen
      coreutils
      findutils
      gawk
    ]
  );

  # Not in process-compose: albums change with the library, not the station,
  # and a boot-time rewrite would remux the m4a tracks every run.
  tag-album = mkScript "tag-album" (
    with pkgs; [
      ffmpeg
      flac
      python3Packages.mutagen
      coreutils
      findutils
      gawk
    ]
  );

  build-queue = mkScript "build-queue" (
    with pkgs; [
      ffmpeg
      coreutils
      findutils
      gawk
    ]
  );

  listener-count = mkScript "listener-count" (
    with pkgs; [
      curl
      coreutils
      gnused
      gawk
    ]
  );
}
