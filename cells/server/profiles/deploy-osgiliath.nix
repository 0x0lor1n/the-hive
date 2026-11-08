{
  inputs,
  cell,
  ...
}: {lib, ...}: let
  # Same literal as ygg-osgiliath.nix / workstation ssh config: derived from
  # the pinned key, public, not a secret.
  yggAddr = "201:f885:7585:1739:35f4:1185:b21e:967d";

  # Decrypted on the deploying workstation with its own TPM PIN identity
  # (same prompt as the deploy key). rage stops at the first TPM identity it
  # cannot open, so pick the one for this host instead of listing both.
  # The PIN prompt is drawn on the tty and colmena's progress bar overwrites
  # it, so "Uploading key" looks hung. Deploy with `colmena apply --verbose`
  # (disables the bar) or type the PIN blind.
  hisilomeKey = file: {
    user,
    group,
  }: {
    keyCommand = [
      "bash"
      "-c"
      ''exec rage -d -i "${inputs.self}/secrets/$(uname -n)-nix-rage.pub" "$0"''
      "${inputs.self}/secrets/hisilome/${file}.age"
    ];
    destDir = "/run/keys";
    inherit user group;
    permissions = "0400";
    uploadAt = "pre-activation";
  };
  icecastKey = file:
    hisilomeKey file {
      user = "hisilome";
      group = "hisilome";
    };
in {
  # hive's colmena transformer added this; colmena's own evaluator does not.
  environment.etc."nixos/configuration.nix".text = ''
    throw '''
      This machine is not managed by nixos-rebuild, but by colmena.
    '''
  '';

  deployment = {
    # Over the mesh, not the WAN: 22 is closed there (net-osgiliath.nix), so
    # the encrypted globals are no longer needed to reach the box. Bare v6,
    # no brackets: colmena builds `user@host` for ssh and nix-copy-closure
    # alike and ssh takes it as is.
    targetHost = yggAddr;
    targetUser = "root";
    # The workstation's own ygg tunnel is off by default (`vpn up yggdrasil`);
    # the router always sits on the mesh, so jump through it.
    sshOptions = ["-o" "ProxyJump=minas-tirith"];
    # 1 vCPU / 1.9 GB / no swap cannot build a NixOS closure.
    buildOnTarget = false;
    tags = ["vps"];
    keys = {
      "icecast-source-password" = icecastKey "icecast-source-password";
      "icecast-admin-password" = icecastKey "icecast-admin-password";
      # yggdrasil runs as a DynamicUser and gets the file via LoadCredential,
      # which systemd reads as root: root-owned 0400 is the right shape.
      "yggdrasil-private.pem" =
        hisilomeKey "yggdrasil-private.pem" {
          user = "root";
          group = "root";
        }
        // {
          name = "private.pem";
          destDir = "/persist/var/lib/yggdrasil";
        };
      # tor's root ExecStartPre installs it into /run/tor/onion/ as tor:tor.
      "onion-hs_ed25519_secret_key" = hisilomeKey "onion-hs_ed25519_secret_key" {
        user = "root";
        group = "root";
      };
    };
  };
}
