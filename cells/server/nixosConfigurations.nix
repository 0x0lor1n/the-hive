# Headless server hosts.
#
# Ported from test-vm's mkHost. The shape is the same -- a base suite, hardware
# and host-specific modules -- but rensa has no bee module: `ren.system`,
# `ren.pkgs` and `ren.disko` replace `bee.system` / `bee.pkgs` / importing
# disko's nixosModule by hand.
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

  # Everything any installed host needs, regardless of machine class.
  foundation = [
    common.base
    common.storage-impermanence
    common.layer-users-root
  ];

  # Headless server: stock kernel, btrfs, root only, no desktop, no Entra.
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
          # colmena's modules, so `deployment.*` exists. Under hive these came
          # from the colmenaConfigurations transformer; here they are explicit,
          # which is easier to follow.
          colmena.nixosModules.deploymentOptions
          colmena.nixosModules.keyChownModule
          colmena.nixosModules.keyServiceModule
          colmena.nixosModules.assertionModule
        ]
        ++ base
        ++ hardware
        ++ extraModules;

      # Lets every imported module read user/host params without re-importing.
      _module.args.globals = globals;
      # colmena defaults `deployment.targetHost` to the node name, which its own
      # evaluator supplies via `_module.args.name`. Nothing sets that when its
      # modules are imported into a plain nixosSystem, so without this every
      # `config.deployment` read fails with "attribute 'name' missing".
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
