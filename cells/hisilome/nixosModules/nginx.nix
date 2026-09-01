{
  inputs,
  cell,
}: {
  config,
  lib,
  ...
}: let
  cfg = config.services.hisilome;
  radioState = "${cfg.stateDir}/radio/state";

  # 'unsafe-inline' on style-src only: liquidsoap's fragments and the tag cloud
  # use style attributes.
  securityHeaders = ''
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;
    add_header Content-Security-Policy "default-src 'none'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; media-src 'self'; frame-src 'self'; frame-ancestors 'self'; base-uri 'none'; form-action 'none'" always;
    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;
    add_header Alt-Svc 'h3=":443"; ma=86400' always;
  '';
in {
  config = lib.mkIf cfg.enable {
    services.nginx = {
      enable = true;

      # Reload, not restart: listeners hold /stream.* open for hours and a blog
      # post must not cut the radio. Only nginx.service changes on a template
      # edit; liquidsoap and icecast are untouched (measured).
      enableReload = true;

      recommendedProxySettings = false; # would override the Icy-MetaData fix
      recommendedGzipSettings = true;
      recommendedOptimisation = true;

      virtualHosts.${cfg.domain} = {
        enableACME = cfg.enableACME;
        forceSSL = cfg.enableACME;
        quic = cfg.enableACME;
        http3 = cfg.enableACME;
        root = "${cfg.site}";

        # live.html and schedule.html include fragments liquidsoap writes;
        # without ssi they render an empty hole and still return 200.
        extraConfig = ''
          ssi on;
          ${securityHeaders}
        '';

        locations = cell.packages.nginxLocations {
          stateDir = radioState;
          extraHeaders = securityHeaders;
        };
      };
    };

    users.users.${config.services.nginx.user}.extraGroups = [cfg.group];
  };
}
