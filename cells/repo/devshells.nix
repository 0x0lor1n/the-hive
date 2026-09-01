# The repo's devshell.
#
# Everything that evaluates `globals` must run from inside this shell: the
# encrypted half of globals is decrypted at EVAL time by
# `builtins.extraBuiltins.rageImportEncrypted`, which only exists when
# nix-plugins is loaded. Outside the shell the failure is
# `attribute 'extraBuiltins' missing`, which is why globals.nix carries an
# assertMsg naming this shell.
#
# That covers `nix build .#nixosConfigurations...`, `nix eval .#colmenaHive...`
# and `colmena build/apply` alike.
{
  inputs,
  cell,
  ...
}: let
  pkgs = inputs.pkgs;

  # nix-plugins 16.0.1 does not build against nix 2.34's C++ API (mkString /
  # RegisterPrimOp signatures changed). Pin the components to 2.31 --
  # https://discourse.nixos.org/t/67426 -- and ship a matching nix_2_31 on PATH
  # so the client and the plugin agree. A mismatch fails to load the plugin.
  nixPlugins = pkgs.nix-plugins.override {
    nixComponents = pkgs.nixVersions.nixComponents_2_31;
  };
in {
  default = pkgs.mkShell {
    name = "nix-rensa";

    packages = [
      # MUST match the nix that nix-plugins is built against.
      pkgs.nixVersions.nix_2_31

      # Decrypts globals and the deploy keys; age-plugin-tpm handles the
      # TPM-sealed master identities.
      pkgs.rage
      pkgs.age-plugin-tpm

      # Deployment CLI. Taken from the PINNED input rather than pkgs.colmena:
      # the root flake's `colmenaHive` reads `__schema` out of this exact
      # colmena, and the CLI asserts the schema matches its own. nixpkgs ships
      # an older colmena, which would reject our output. Sourcing both halves
      # from one pin makes that mismatch impossible rather than merely unlikely.
      inputs.colmena.packages.${pkgs.stdenv.hostPlatform.system}.colmena

      # Installs a fresh machine; reads nixosConfigurations.<name>.
      pkgs.nixos-anywhere

      pkgs.alejandra
    ];

    shellHook = ''
      # `sudo` does not inherit this. Use `sudo --preserve-env=NIX_CONFIG`, or
      # put the two settings in the host's /etc/nix/nix.conf.
      export NIX_CONFIG="
        plugin-files = ${nixPlugins}/lib/nix/plugins
        extra-builtins-file = ${inputs.self.outPath}/nix/extra-builtins.nix
      "
      echo "nix-rensa devshell — colmena, nixos-anywhere, rage, extra-builtins loaded"
    '';
  };
}
