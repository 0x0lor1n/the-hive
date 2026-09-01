# Everything that evaluates `globals` runs from here: the encrypted half is
# decrypted at eval time by the nix-plugins extra-builtin, which NIX_CONFIG
# below loads.
{
  inputs,
  cell,
  ...
}: let
  pkgs = inputs.pkgs;

  # nix-plugins 16.0.1 does not build against nix 2.34's C++ API
  # (https://discourse.nixos.org/t/67426). Pin components to 2.31 and ship the
  # matching client; a mismatch fails to dlopen the plugin.
  nixPlugins = pkgs.nix-plugins.override {
    nixComponents = pkgs.nixVersions.nixComponents_2_31;
  };

  # One deploy key for the fleet. Encrypted to the PIN-protected identity, so
  # no unattended process can deploy. Do not "fix" the prompt.
  deploy-key = pkgs.writeShellApplication {
    name = "deploy-key";
    runtimeInputs = with pkgs; [git rage age-plugin-tpm openssh];
    text = ''
      root=$(git rev-parse --show-toplevel)

      if [ -z "''${SSH_AUTH_SOCK:-}" ]; then
        echo "deploy-key: no ssh-agent in this shell." >&2
        exit 1
      fi

      rage -d \
        -i "$root/secrets/jarvis-nix-rage.pub" \
        "$root/secrets/deploy.age" \
        | ssh-add -t 900 -

      echo "deploy-key: loaded, expires in 15 minutes."
    '';
  };

  dev = pkgs.writeShellApplication {
    name = "dev";
    runtimeInputs = with pkgs; [git direnv coreutils];
    text = builtins.readFile "${inputs.self.outPath}/nix/dev.sh";
  };
in {
  default = pkgs.mkShell {
    name = "nix-rensa";

    packages = [
      # Must match what nixPlugins is built against.
      pkgs.nixVersions.nix_2_31

      pkgs.rage
      pkgs.age-plugin-tpm

      # From the pinned input, not pkgs.colmena: the CLI asserts its __schema
      # equals the one colmenaHive read from this same source.
      inputs.colmena.packages.${pkgs.stdenv.hostPlatform.system}.colmena

      pkgs.nixos-anywhere
      deploy-key
      dev
      pkgs.direnv

      # From this cell's input, not the root's: see cells/repo/flake.nix.
      inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.hermes-agent

      pkgs.alejandra
    ];

    shellHook = ''
      # sudo does not inherit this; use --preserve-env=NIX_CONFIG.
      export NIX_CONFIG="
        plugin-files = ${nixPlugins}/lib/nix/plugins
        extra-builtins-file = ${inputs.self.outPath}/nix/extra-builtins.nix
      "
      echo "nix-rensa: colmena, nixos-anywhere, rage, extra-builtins loaded"
      echo "  deploy-key      load the fleet deploy key (TPM PIN, 15-min TTL)"
      echo "  dev <cell>      switch devshell; cd \"\$(dev <cell>)\" to also cd"
    '';
  };
}
