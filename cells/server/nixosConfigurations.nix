{
  inputs,
  cell,
  system,
  ...
}: let
  inherit (inputs) utilsLib pkgs disko colmena;
  globals = inputs.cells.common.globals;
  common = inputs.cells.common.profiles;
  ws = inputs.cells.workstation.profiles;
  p = cell.profiles;

  flakeRoot = /. + builtins.unsafeDiscardStringContext inputs.self.outPath;
  # Same recipients as globals.nix.age.
  siteOf = hostKey:
    builtins.extraBuiltins.rageImportEncrypted [
      (flakeRoot + "/secrets/penrose-nix-rage.pub")
      (flakeRoot + "/secrets/elster-nix-rage.pub")
    ] (flakeRoot + "/secrets/${hostKey}-site.nix.age");

  foundation = [
    common.base
    common.storage-impermanence
    common.layer-users-root
  ];

  btrfs = [
    p.storage-btrfs
    p.storage-btrfs-rollback
  ];

  # Shared with the workstations.
  zfsTpm = [
    ws.storage-zfs
    ws.storage-zfs-rollback
    ws.hardware-zfs-unlock
    ws.hardware-zfs-tpm
    p.secrets-agenix-zfs
  ];

  router = [
    p.layer-users-admin
    p.net-router-wan
    p.net-router-lan
    p.yggdrasil
    p.initrd-ssh
  ];

  mkHost = {
    hostKey,
    modules,
    stateVersion,
    site ? false,
  }: let
    host = globals.hosts.${hostKey};
  in
    utilsLib.mkSystem {
      ren = {
        inherit system pkgs disko;
      };

      imports =
        [
          colmena.nixosModules.deploymentOptions
          colmena.nixosModules.keyChownModule
          colmena.nixosModules.keyServiceModule
          colmena.nixosModules.assertionModule
        ]
        ++ foundation
        ++ modules;

      _module.args.globals = globals;
      # colmena's own evaluator supplies `name`; deployment.targetHost defaults
      # from it and every config.deployment read fails without it.
      _module.args.name = hostKey;
      _module.args.host = host;
      _module.args.inputs = inputs;
      _module.args.site =
        if site
        then siteOf hostKey
        else null;

      disko.devices = utilsLib.collectDisks {${hostKey} = cell.disks.${hostKey};};

      networking.hostName = host.hostName;
      system.stateVersion = stateVersion;
    };
in {
  osgiliath = mkHost {
    hostKey = "osgiliath";
    stateVersion = "24.11";
    modules =
      btrfs
      ++ [
        p.layer-server-hardening
        p.platform-virtio
        p.net-osgiliath
        p.site-hisilome
        p.deploy-osgiliath
      ];
  };

  minas-tirith = mkHost {
    hostKey = "minas-tirith";
    stateVersion = "26.05";
    site = true;
    modules =
      zfsTpm
      ++ router
      ++ [
        p.layer-server-hardening
        p.platform-minas-tirith
        p.fiber-bypass
        p.deploy-minas-tirith
      ];
  };

  # No TPM, no encryption: zfsTpm minus the unlock half.
  imladris = mkHost {
    hostKey = "imladris";
    stateVersion = "26.11";
    modules = [
      ws.storage-zfs
      ws.storage-zfs-rollback
      p.layer-users-admin
      p.layer-server-hardening
      p.platform-imladris
      p.storage-fast
      p.backup-warm
      p.atx-watchdog
      p.monitoring-exporters
      p.deploy-imladris
      # streaming torrents to the TV boxes, LAN :8090
      p.torrserver
    ];
  };
}
