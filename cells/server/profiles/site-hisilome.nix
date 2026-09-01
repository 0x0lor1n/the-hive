# Host-facing half of Hísilómë: domain, cert, secrets, firewall. The service
# itself is cells/hisilome/nixosModules.nix.
{
  inputs,
  cell,
}: {
  pkgs,
  globals,
  ...
}: {
  imports = [inputs.cells.hisilome.nixosModules.default];

  services.hisilome = {
    enable = true;
    domain = "hisilo.me";
    # Directly under /persist (never rolled back), so no persistence entry.
    stateDir = "${globals.persistence.dataPath}/radio";
    # Delivered by colmena (deploy-osgiliath.nix); never in the store.
    sourcePasswordFile = "/run/keys/icecast-source-password";
    adminPasswordFile = "/run/keys/icecast-admin-password";
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = globals.acme.email;
    # Point at staging FIRST when debugging issuance: 5 duplicate certs per
    # domain per week, then locked out for days.
    #   https://acme-staging-v02.api.letsencrypt.org/directory
    defaults.server = "https://acme-v02.api.letsencrypt.org/directory";
  };

  # /var/lib/acme is on /, which is rolled back every boot. Without this every
  # reboot re-requests the certificate and burns the rate limit.
  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/acme";
      user = "acme";
      group = "acme";
      mode = "0755";
    }
  ];

  # On activation, tmpfiles creates the challenge webroot on / and the bind
  # mount is then laid over it -> lego "webroot path does not exist". Order
  # after the mount, and create the tree regardless.
  systemd.services.acme-setup = {
    after = ["var-lib-acme.mount"];
    requires = ["var-lib-acme.mount"];
  };
  systemd.services."acme-order-renew-hisilo.me".serviceConfig.ExecStartPre = [
    "+${pkgs.coreutils}/bin/install -d -o acme -g acme -m 0755 /var/lib/acme/acme-challenge/.well-known/acme-challenge"
  ];

  # 80 is needed for HTTP-01, not just the redirect. UDP 443 is QUIC.
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
  networking.firewall.allowedUDPPorts = [443];

  services.nginx.virtualHosts."hisilo.me".serverAliases = ["www.hisilo.me"];
}
