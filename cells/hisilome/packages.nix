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
      !(lib.hasPrefix "music" rel || lib.hasPrefix "radio/state" rel);
  };

  mkScript = name: runtimeInputs:
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      text = builtins.readFile "${src}/bin/${name}.sh";
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
  ];

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
  inherit nginxLocations nginxHttpConfig;

  site = pkgs.runCommand "hisilome-site" {} ''
    cp -r ${src} s
    chmod -R u+w s
    cd s
    ${pkgs.zola}/bin/zola build --output-dir $out
  '';

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
