{
  inputs,
  cell,
  ...
}: {
  globals,
  lib,
  ...
}: let
  # globals holds "a.b.c.d/24"; colmena wants the bare address. Derived, not
  # stored twice.
  addressOf = h: lib.head (lib.splitString "/" globals.hosts.${h}.ipv4.address);

  # Decrypted on the deploying workstation with its own TPM PIN identity
  # (same prompt as the deploy key). rage stops at the first TPM identity it
  # cannot open, so pick the one for this host instead of listing both.
  icecastKey = file: {
    keyCommand = [
      "bash"
      "-c"
      ''exec rage -d -i "${inputs.self}/secrets/$(uname -n)-nix-rage.pub" "$0"''
      "${inputs.self}/secrets/hisilome/${file}.age"
    ];
    destDir = "/run/keys";
    user = "hisilome";
    group = "hisilome";
    permissions = "0400";
    uploadAt = "pre-activation";
  };
in {
  # hive's colmena transformer added this; colmena's own evaluator does not.
  environment.etc."nixos/configuration.nix".text = ''
    throw '''
      This machine is not managed by nixos-rebuild, but by colmena.
    '''
  '';

  deployment = {
    targetHost = addressOf "osgiliath";
    targetUser = "root";
    # 1 vCPU / 1.9 GB / no swap cannot build a NixOS closure.
    buildOnTarget = false;
    tags = ["vps"];
    keys = {
      "icecast-source-password" = icecastKey "icecast-source-password";
      "icecast-admin-password" = icecastKey "icecast-admin-password";
    };
  };
}
