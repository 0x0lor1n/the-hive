# osgiliath's colmena deployment.
#
# In test-vm this was a separate `colmenaConfigurations` cell block whose node
# imported the nixosConfigurations one VERBATIM and added only `deployment` --
# because hive harvests the two into different flake outputs and a host managed
# by both must not drift.
#
# rensa needs no such duplication. There is one host module; the root flake's
# `colmenaHive` reads `config.deployment` off the same evaluated system that
# `nixosConfigurations.osgiliath` exposes. One definition, structurally.
{
  inputs,
  cell,
  ...
}: {
  globals,
  lib,
  ...
}: let
  # Derived from the address rather than stored twice: globals holds
  # "a.b.c.d/24" and colmena wants the bare address. Storing both would let them
  # disagree, and the failure mode is deploying to the wrong machine.
  addressOf = h: lib.head (lib.splitString "/" globals.hosts.${h}.ipv4.address);

  # `inputs.self` is sourceInfo under rensa, but outPath survives -- which is
  # all keyCommand needs.
  self = inputs.self;

  icecastKey = file: {
    # ciphertext committed, plaintext never written to disk on the workstation,
    # no new tooling. Encrypted to the PIN-LESS identity on purpose: the deploy
    # is already gated by the PIN-protected deploy key, and demanding a second
    # PIN for a loopback-only daemon's service password adds friction without
    # adding a boundary.
    keyCommand = [
      "rage"
      "-d"
      "-i"
      "${self}/secrets/jarvis-nopin-rage.pub"
      "${self}/secrets/deploy/${file}.age"
    ];
    destDir = "/run/keys";
    user = "hisilome";
    group = "hisilome";
    permissions = "0400";
    uploadAt = "pre-activation";
  };
in {
  # hive's colmenaConfigurations transformer adds this itself
  # (src/transformers/colmenaConfigurations.nix); colmena's own evaluator does
  # NOT. Ported explicitly so a machine deployed from here behaves the same as
  # one deployed from test-vm: running nixos-rebuild on it fails loudly instead
  # of silently building whatever /etc/nixos happens to contain.
  environment.etc."nixos/configuration.nix".text = ''
    throw '''
      This machine is not managed by nixos-rebuild, but by colmena.
    '''
  '';

  deployment = {
    # ENCRYPTED: IPs resolve from secrets/globals.nix.age at eval time, so
    # `colmena build/apply` must run inside the devshell that supplies the
    # nix-plugins extra-builtin.
    targetHost = addressOf "osgiliath";
    targetUser = "root";
    # targetPort omitted deliberately: null means 22 to colmena, and restating
    # it adds a second place to be wrong.

    # 1 vCPU / 1.9 GB / no swap cannot build a NixOS closure.
    buildOnTarget = false;

    tags = ["vps"];

    # Icecast credentials delivered at deploy time rather than through agenix:
    # colmena's own mechanism, values never enter the Nix store.
    keys = {
      "icecast-source-password" = icecastKey "icecast-source-password";
      "icecast-admin-password" = icecastKey "icecast-admin-password";
    };
  };
}
