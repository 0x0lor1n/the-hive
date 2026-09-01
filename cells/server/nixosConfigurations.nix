{
  inputs,
  cell,
  system,
  ...
}: let
  inherit (inputs) utilsLib pkgs disko colmena;
  globals = inputs.cells.common.globals;
  common = inputs.cells.common.profiles;
  p = cell.profiles;

  foundation = [
    common.base
    common.storage-impermanence
    common.layer-users-root
  ];

  server =
    foundation
    ++ [
      p.storage-btrfs
      p.storage-btrfs-rollback
      p.layer-server-hardening
    ];

  kvmGuest = [p.platform-virtio];

  mkHost = {
    hostKey,
    base,
    hardware,
    extraModules ? [],
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
        ++ base
        ++ hardware
        ++ extraModules;

      _module.args.globals = globals;
      # colmena's own evaluator supplies `name`; deployment.targetHost defaults
      # from it and every config.deployment read fails without it.
      _module.args.name = hostKey;
      _module.args.host = host;
      _module.args.inputs = inputs;

      disko.devices = utilsLib.collectDisks cell.disks;

      networking.hostName = host.hostName;
      system.stateVersion = "24.11";
    };
in {
  osgiliath = mkHost {
    hostKey = "osgiliath";
    base = server;
    hardware = kvmGuest;
    extraModules = [
      p.net-osgiliath
      p.site-hisilome
      p.deploy-osgiliath
    ];
  };
}
