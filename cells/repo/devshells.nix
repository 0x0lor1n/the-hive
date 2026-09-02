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

  # Not a Nix module: the pxpipe user service is installed imperatively so it
  # works on non-NixOS hosts. Re-run after the package
  # changes: the unit pins the store path it was generated from.
  pxpipe-install = pkgs.writeShellApplication {
    name = "pxpipe-install";
    runtimeInputs = with pkgs; [coreutils systemd];
    text = ''
      port="''${PXPIPE_PORT:-47821}"
      unit="$HOME/.config/systemd/user/pxpipe.service"
      mkdir -p "$(dirname "$unit")"
      cat > "$unit" <<EOF
      [Unit]
      Description=pxpipe: Anthropic loopback proxy (images system prompt/tool docs)
      After=network-online.target

      [Service]
      ExecStart=${pkgs.lib.getExe cell.packages.pxpipe} -port $port
      Restart=on-failure
      RestartSec=2

      [Install]
      WantedBy=default.target
      EOF
      systemctl --user daemon-reload
      systemctl --user enable pxpipe.service
      systemctl --user restart pxpipe.service
      echo "pxpipe-install: listening on 127.0.0.1:$port; log: journalctl --user -fu pxpipe"
    '';
  };
in {
  default = pkgs.mkShell {
    name = "nix-rensa";

    packages = [
      # Agent-facing `nix`: shadows the real client below (mkShell prepends in
      # list order). NIXQ_REAL_NIX in shellHook pins the target so a stray
      # system nix 2.34 can never be picked — that would break the plugin.
      cell.packages.nixq

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
      pxpipe-install
      cell.packages.pxpipe
      cell.packages.rtk
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
      # nixq must wrap exactly the client nix-plugins was built against.
      export NIXQ_REAL_NIX=${pkgs.nixVersions.nix_2_31}/bin/nix
      # rtk: local filters only. `rtk nix` does not exist and must not: nix
      # errors go through nixq, whose contract is "verbatim after error".
      export RTK_TELEMETRY_DISABLED=1
      echo "nix-rensa: colmena, nixos-anywhere, rage, extra-builtins loaded"
      echo "  deploy-key      load the fleet deploy key (TPM PIN, 15-min TTL)"
      echo "  dev <cell>      switch devshell; cd \"\$(dev <cell>)\" to also cd"
      echo "  pxpipe-install  (re)install the pxpipe user service; needs pxpipe.anthropic.com in /etc/hosts"
      echo "  nix             = nixq shim (quiet progress; NIXQ=off to bypass); rtk <cmd> for compact git/ls/…"
    '';
  };
}
