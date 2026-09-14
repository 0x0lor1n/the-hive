# Everything that evaluates `globals` runs from here: the encrypted half is
# decrypted at eval time by the nix-plugins extra-builtin, which NIX_CONFIG
# below loads.
{
  inputs,
  cell,
  ...
}: let
  inherit (inputs) pkgs dslib devtools-lib treefmt;

  # Formatters for what is actually in tree: nix, go, sh. deadnix is a
  # formatter here too -- it edits unused bindings out, not just reports.
  treefmtWrapper = treefmt.mkWrapper pkgs {
    projectRootFile = "flake.nix";
    programs = {
      alejandra.enable = true;
      deadnix.enable = true;
      gofumpt.enable = true;
      shfmt.enable = true;
    };
    # `cell`/`inputs` are the rensa block signature; deadnix must not strip
    # them or the block stops matching. Underscore-prefixed names it ignores.
    settings.formatter.deadnix.options = ["--no-lambda-pattern-names"];
    settings.formatter.shfmt.options = ["-i" "2" "-s"];
    settings.global.excludes = [
      "*.age"
      "*.patch"
      "*.pub"
      "*.lock"
      "cells/hisilome/**"
    ];
  };

  # go test for every go.mod in tree. Nix-free on purpose: pre-push should not
  # wait on an evaluation. Binaries are still built by buildGoModule in
  # packages.nix; this is the fast path for the human/agent loop.
  go-test-all = pkgs.writeShellApplication {
    name = "go-test-all";
    runtimeInputs = [pkgs.go pkgs.git];
    text = ''
      # pkgs.go defaults to CGO_ENABLED=1, and `net` then wants a C compiler
      # for runtime/cgo. No gcc on the workstation PATH by design; the
      # binaries are pure Go and buildGoModule builds them the same way.
      export CGO_ENABLED=0
      root=$(git rev-parse --show-toplevel)
      status=0
      while IFS= read -r mod; do
        dir=$(dirname "$mod")
        echo "==> $dir"
        (cd "$root/$dir" && go test ./...) || status=1
      done < <(cd "$root" && git ls-files '*/go.mod' 'go.mod')
      exit $status
    '';
  };

  # pkgs.nix and pkgs.nix-plugins are pinned to one version by the overlay in
  # flake.nix (transformInputs) — same nix here and as every host's
  # nix.package, so the plugin dlopens under nixos-rebuild too.
  nixPlugins = pkgs.nix-plugins;

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

  # Prime the eval-time secrets cache with this host's PIN-protected TPM
  # identity. Not required: on a cache miss eval itself prompts for the PIN
  # (age-plugin-tpm talks to /dev/tty). This exists for the cases without a
  # tty - agents, CI, sudo without a terminal - and to decrypt on purpose.
  # Cache lives in /var/tmp/nix-import-encrypted/$UID, keyed by ciphertext
  # hash, and is persisted (layer-users-local): a PIN is needed once per change
  # of an .age file, not once per boot.
  #
  # Covers every eval-time file: globals.nix.age and the per-role
  # secrets/user-*.nix.age (cells/workstation/home/secrets.nix). One PIN
  # session, all misses; files already cached are skipped.
  unlock-secrets = pkgs.writeShellApplication {
    name = "unlock-secrets";
    runtimeInputs = with pkgs; [git rage age-plugin-tpm coreutils];
    text = ''
      # Same cache, same key as eval (see nix/rageImportEncrypted.sh).
      root=$(git rev-parse --show-toplevel)
      case "''${1:-$(hostname)}" in
        penrose) identity=dellvis-nix-rage ;;
        *)       identity=jarvis-nix-rage ;;
      esac
      cache="/var/tmp/nix-import-encrypted/$UID"
      umask 077; mkdir -p "$cache"
      missed=0
      for file in "$root/secrets/globals.nix.age" "$root"/secrets/user-*.nix.age; do
        [[ -e $file ]] || continue
        name=$(basename "''${file%.age}")
        out="$cache/$(sha512sum "$file" | cut -c1-32)-$name"
        if [[ -e $out ]]; then
          echo "unlock-secrets: $name.age already cached for UID $UID." >&2
          continue
        fi
        missed=1
        echo "unlock-secrets: decrypting secrets/$name.age with $identity (TPM PIN)" >&2
        rage --decrypt --identity "$root/secrets/$identity.pub" --output "$out" "$file"
      done
      if [[ $missed == 1 ]]; then
        echo "unlock-secrets: cached for UID $UID; eval will not touch the TPM until one of these files changes." >&2
      fi
    '';
  };

  dev = pkgs.writeShellApplication {
    name = "dev";
    runtimeInputs = with pkgs; [git direnv coreutils];
    text = builtins.readFile "${inputs.self.outPath}/nix/dev.sh";
  };
in {
  # rensa devshell module, not pkgs.mkShell: the lefthook module needs
  # enterShellCommands to (re)install git hooks on every shell entry.
  default = dslib.mkShell {
    imports = [devtools-lib.devshellModule];
    name = "nix-rensa";

    packages = [
      # Agent-facing `nix`. The real client is NOT in packages: buildEnv
      # rejects two bin/nix. NIXQ_REAL_NIX below pins it by store path.
      cell.packages.nixq

      pkgs.rage
      pkgs.age-plugin-tpm

      # From the pinned input, not pkgs.colmena: the CLI asserts its __schema
      # equals the one colmenaHive read from this same source.
      inputs.colmena.packages.${pkgs.stdenv.hostPlatform.system}.colmena

      pkgs.nixos-anywhere
      # Workstation secrets (generated/ + rekeyed/<host>). agenix-rekey is a
      # workstation-cell input; that cell re-exports the CLI.
      inputs.cells.workstation.packages.agenix
      deploy-key
      unlock-secrets
      dev
      cell.packages.rtk
      pkgs.direnv

      # Same pin the workstation installs system-wide (agent-proxy.nix).
      cell.packages.hermes-agent

      treefmtWrapper
      go-test-all
      pkgs.go
      pkgs.gitleaks
    ];

    env = {
      # sudo does not inherit this; use --preserve-env=NIX_CONFIG.
      NIX_CONFIG.value = ''
        plugin-files = ${nixPlugins}/lib/nix/plugins
        extra-builtins-file = ${inputs.self.outPath}/nix/extra-builtins.nix
      '';
      # nixq must wrap exactly the client nix-plugins was built against.
      NIXQ_REAL_NIX.value = "${pkgs.nix}/bin/nix";
      # rtk: local filters only. `rtk nix` does not exist and must not: nix
      # errors go through nixq, whose contract is "verbatim after error".
      RTK_TELEMETRY_DISABLED.value = "1";
    };

    lefthook.config = {
      pre-commit = {
        parallel = true;
        jobs = [
          {
            # Staged-only: history is scanned by hand (skill pii-scan). Rules
            # incl. PII in .gitleaks.toml.
            name = "gitleaks";
            run = "${pkgs.gitleaks}/bin/gitleaks protect --staged --no-banner --redact";
          }
          {
            # Formats the staged files and re-stages them (stage_fixed).
            name = "treefmt";
            run = "${treefmtWrapper}/bin/treefmt {staged_files}";
            stage_fixed = true;
            env.TERM = "dumb";
          }
        ];
      };
      pre-push.jobs = [
        {
          name = "go-test";
          run = "${go-test-all}/bin/go-test-all";
        }
      ];
    };

    enterShellCommands.motd.text = ''
      echo "nix-rensa: colmena, nixos-anywhere, rage, extra-builtins loaded"
      echo "  deploy-key      load the fleet deploy key (TPM PIN, 15-min TTL)"
      echo "  unlock-secrets  decrypt globals.nix.age + secrets/user-*.nix.age with this host's TPM (PIN); eval prompts itself when it has a tty"
      echo "  agenix edit|generate|rekey|view   workstation secrets (generated/ + rekeyed/<host>)"
      echo "  dev <cell>      switch devshell; cd \"\$(dev <cell>)\" to also cd"
      echo "  nix             = nixq shim (quiet progress; NIXQ=off to bypass); rtk <cmd> for compact git/ls/…"
      echo "  treefmt         alejandra + deadnix + gofumpt + shfmt; runs on pre-commit (LEFTHOOK=0 to skip)"
      echo "  go-test-all     go test every module; runs on pre-push"
    '';
  };
}
