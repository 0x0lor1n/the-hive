# Hísilómë on osgiliath: the host-facing half of the deployment.
#
# The service itself is defined in the blog's own repo and imported below --
# the same pattern auth-entra.nix uses for himmelblau and layer-compositor.nix
# for home-manager. That split is deliberate (iteration 12 §1.1): the systemd
# units must stay in lockstep with radio.liq and icecast.xml, so they live
# beside them; the domain, certificate, secrets and firewall are facts about
# THIS host, so they live here.
{
  inputs,
  cell,
}: {
  lib,
  pkgs,
  globals,
  ...
}: {
  # Cross-cell reference, verified to work in this hive version by probe: a
  # cell block receives `inputs.cells`, so cells/nixos can reach cells/hisilome
  # without either becoming a flake input of the other.
  imports = [inputs.cells.hisilome.nixosModules.default];

  services.hisilome = {
    enable = true;
    domain = "hisilo.me";

    # INSIDE the persistent subvolume, not a bind-mount.
    #
    # `/persist` is never rolled back, so a path used directly under it needs no
    # `environment.persistence` entry -- that list is for state which must
    # *appear* at a conventional location (/etc/ssh, /var/lib/...). The music
    # library is 1.1 GB rsynced out of band; restoring it through a bind-mount
    # would be pointless indirection.
    #
    # globals.persistence.dataPath is documented as the "kept-forever data
    # root" (globals-options.nix) and had no consumer until now.
    stateDir = "${globals.persistence.dataPath}/radio";

    # Delivered by colmena at deploy time (see colmenaConfigurations.nix).
    # /run/keys, never the Nix store, never git.
    sourcePasswordFile = "/run/keys/icecast-source-password";
    adminPasswordFile = "/run/keys/icecast-admin-password";
  };

  # ---------------------------------------------------------------------
  # TLS
  # ---------------------------------------------------------------------
  security.acme = {
    acceptTerms = true;
    defaults.email = globals.acme.email;

    # PRODUCTION. Staging did its job: it absorbed the failed attempts while
    # the webroot bug (iteration 12.3) was found, then issued cleanly --
    # "(STAGING) Artificial Amaranth YE1", valid 90 days, served by nginx --
    # which is what proved the whole HTTP-01 path before spending any of the
    # real quota.
    #
    # Left explicit rather than removed: Let's Encrypt allows only 5 duplicate
    # certificates per domain per week, so anyone debugging issuance here
    # should point this back at staging FIRST rather than iterating against
    # production and locking themselves out for days.
    #   https://acme-staging-v02.api.letsencrypt.org/directory
    defaults.server = "https://acme-v02.api.letsencrypt.org/directory";
  };

  # WITHOUT THIS, EVERY REBOOT RE-REQUESTS THE CERTIFICATE.
  #
  # /var/lib/acme holds the account key and the issued certs, and it lives on
  # `/`, which storage-btrfs-rollback.nix resets to @root-blank on every boot.
  # Three or four reboots during a debugging session would exhaust Let's
  # Encrypt's duplicate-certificate limit and lock out issuance for days -- a
  # failure that surfaces long after its cause.
  #
  # Declared here rather than in storage-impermanence.nix for the same reason
  # sbctl and himmelblau are: the profile that owns the state owns its
  # persistence (iteration 11 §3.3).
  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/acme";
      user = "acme";
      group = "acme";
      mode = "0755";
    }
  ];

  # THE BIND MOUNT CAN SHADOW THE ACME CHALLENGE DIRECTORY.
  #
  # The webroot is /var/lib/acme/acme-challenge, created by nixpkgs'
  # `systemd.tmpfiles.settings."10-acme"` rule. Persisting /var/lib/acme turns
  # it into a bind mount from /persist, and during ACTIVATION (unlike boot)
  # NixOS runs `systemd-tmpfiles --create` and only then starts new units. So
  # tmpfiles created the directory on the root filesystem and the mount was
  # then laid over the top of it, hiding it -- lego reported
  # "webroot path does not exist" and the order failed.
  #
  # Two belts, because the failure mode is a certificate that silently never
  # issues:
  #   - order acme-setup after the mount, so this cannot recur on activation
  #   - create the tree in ExecStartPre regardless, which is correct even if
  #     the ordering analysis above is wrong
  systemd.services.acme-setup = {
    after = ["var-lib-acme.mount"];
    requires = ["var-lib-acme.mount"];
  };

  systemd.services."acme-order-renew-hisilo.me".serviceConfig.ExecStartPre = [
    "+${pkgs.coreutils}/bin/install -d -o acme -g acme -m 0755 /var/lib/acme/acme-challenge/.well-known/acme-challenge"
  ];

  # ---------------------------------------------------------------------
  # Exposure
  # ---------------------------------------------------------------------
  #
  # 80 is not just a redirect: ACME's HTTP-01 challenge needs it. net-osgiliath
  # opens 22 only, so without this the certificate can never be issued.
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  # www.hisilo.me has an A record too. Without an alias it would resolve, hit
  # this host, match no server_name, and be served the default vhost with a
  # certificate that is not valid for it.
  services.nginx.virtualHosts."hisilo.me".serverAliases = ["www.hisilo.me"];
}
