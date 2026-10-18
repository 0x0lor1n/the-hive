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
    ];
  };

  # go test for every go.mod in tree. Nix-free: pre-push should not wait on an
  # evaluation. Binaries are still built by buildGoModule in packages.nix.
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

  # One deploy key for the fleet, encrypted to the PIN-protected identity so
  # no unattended process can deploy. The prompt is the point.
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
        -i "$root/secrets/$(uname -n)-nix-rage.pub" \
        "$root/secrets/deploy.age" \
        | ssh-add -t 900 -

      echo "deploy-key: loaded, expires in 15 minutes."
    '';
  };

  # Prime the eval-time secrets cache with this host's PIN-protected TPM
  # identity. Not required: on a cache miss eval itself prompts for the PIN
  # (age-plugin-tpm talks to /dev/tty). This is for the cases without a tty --
  # agents, CI, sudo without a terminal. Cache lives in
  # /var/tmp/nix-import-encrypted/$UID, keyed by ciphertext hash, and is
  # persisted (layer-users-local): one PIN per change of an .age file, not per
  # boot. Covers globals.nix.age and the per-role secrets/user-*.nix.age
  # (cells/workstation/home/secrets.nix) in one session.
  unlock-secrets = pkgs.writeShellApplication {
    name = "unlock-secrets";
    runtimeInputs = with pkgs; [git rage age-plugin-tpm coreutils];
    text = ''
      # Same cache, same key as eval (see nix/rageImportEncrypted.sh).
      root=$(git rev-parse --show-toplevel)
      case "''${1:-$(hostname)}" in
        penrose) identity=penrose-nix-rage ;;
        elster)  identity=elster-nix-rage ;;
        *)       echo "unlock-secrets: no PIN identity for host $1" >&2; exit 1 ;;
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

  # Moves llm-agents (hermes, claude, opencode) to numtide's main and herdr to
  # its newest tag, builds agents-check and this host's toplevel, shows the
  # nvd diff. Green: snapshots persist + srv/agents (hermes state, shared
  # skills/memories) and prints the switch; red: restores the four files.
  # Restore hermes after a bad bump, then roll the generation back:
  #   rsync -a --delete /persist/.zfs/snapshot/pre-agents-<ts>/home/<user>/.hermes/ ~/.hermes/
  #   rsync -a --delete /srv/agents/.zfs/snapshot/pre-agents-<ts>/ /srv/agents/
  agents-bump = pkgs.writeShellApplication {
    name = "agents-bump";
    # No `nix`: the shell's pkgs.nix must stay first on PATH (nix-plugins).
    runtimeInputs = with pkgs; [git coreutils gnused gnugrep nvd hostname];
    text = ''
      root=$(git rev-parse --show-toplevel)
      host=$(hostname)
      files=(cells/repo/flake.nix cells/repo/flake.lock cells/workstation/flake.nix cells/workstation/flake.lock)
      if ! git -C "$root" diff --quiet HEAD -- "''${files[@]}"; then
        echo "agents-bump: uncommitted changes in ''${files[*]}; commit or stash first." >&2
        exit 1
      fi
      restore() { git -C "$root" checkout HEAD -- "''${files[@]}"; }
      trap 'echo "agents-bump: failed, inputs restored, no snapshot." >&2; restore' ERR

      rev=$(git ls-remote https://github.com/numtide/llm-agents.nix refs/heads/main | cut -f1)
      tag=$(git ls-remote --tags --refs https://github.com/herdrdev/herdr 'v*' | sed 's|.*/||' | sort -V | tail -1)
      sed -i "s|numtide/llm-agents.nix/[0-9a-f]\{40\}\"|numtide/llm-agents.nix/$rev\"|" "$root/cells/repo/flake.nix"
      sed -i "s|herdrdev/herdr/v[0-9.]*\"|herdrdev/herdr/$tag\"|" "$root/cells/workstation/flake.nix"
      nix flake update llm-agents --flake "$root/cells/repo"
      nix flake update herdr --flake "$root/cells/workstation"
      if git -C "$root" diff --quiet HEAD -- "''${files[@]}"; then
        echo "agents-bump: already at llm-agents $rev, herdr $tag."
        exit 0
      fi

      nix build --no-link -L "$root#x86_64-linux.workstation.packages.agents-check"
      top=$(nix build --no-link --print-out-paths "$root#nixosConfigurations.$host.config.system.build.toplevel")
      nvd diff /run/current-system "$top"
      trap - ERR

      ts=$(date +%Y%m%d-%H%M%S)
      datasets=()
      for ds in rpool/safe/persist rpool/safe/srv/agents; do
        zfs list -H -o name "$ds" >/dev/null 2>&1 && datasets+=("$ds@pre-agents-$ts")
      done
      sudo zfs snapshot "''${datasets[@]}"
      for snap in "''${datasets[@]}"; do
        # Keep the five newest pre-agents-* per dataset.
        zfs list -H -t snapshot -o name -s creation -d 1 "''${snap%@*}" \
          | grep '@pre-agents-' | head -n -5 \
          | while read -r old; do sudo zfs destroy "$old"; done
      done

      echo
      echo "agents-bump: snapshot pre-agents-$ts on ''${datasets[*]%@*}"
      echo "  llm-agents $rev, herdr $tag; commit ''${files[*]} after the switch."
      echo "  sudo nix-env -p /nix/var/nix/profiles/system --set $top"
      echo "  sudo $top/bin/switch-to-configuration switch"
    '';
  };
in {
  # rensa devshell module, not pkgs.mkShell: the lefthook module needs
  # enterShellCommands to (re)install git hooks on every shell entry.
  default = dslib.mkShell {
    imports = [devtools-lib.devshellModule];
    name = "nix-rensa";

    packages = [
      # The client nix-plugins is built against. Agents started here put nixq
      # in front of it themselves (withNixq); NIXQ_REAL_NIX pins it for them.
      pkgs.nix

      pkgs.rage
      pkgs.age-plugin-tpm

      # From the pinned input, not pkgs.colmena: the CLI asserts its __schema
      # equals the one colmenaHive read from this same source.
      inputs.colmena.packages.${pkgs.stdenv.hostPlatform.system}.colmena

      pkgs.nixos-anywhere
      cell.packages.agenix
      deploy-key
      unlock-secrets
      agents-bump
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

    enterShellCommands.agenix-primary.text = ''
      # shellcheck disable=SC1091
      . ${inputs.self.outPath}/nix/agenix-primary.sh
    '';
    enterShellCommands.motd.text = ''
      echo "nix-rensa: colmena, nixos-anywhere, rage, extra-builtins loaded"
      echo "  deploy-key      load the fleet deploy key (TPM PIN, 15-min TTL)"
      echo "  unlock-secrets  decrypt globals.nix.age + secrets/user-*.nix.age with this host's TPM (PIN); eval prompts itself when it has a tty"
      echo "  agenix edit|generate|rekey|view   host secrets (generated/ + rekeyed/<host>)"
      echo "  agents-bump     bump hermes/claude/opencode/herdr, check, snapshot hermes state; prints the switch"
      echo "  dev <cell>      switch devshell; cd \"\$(dev <cell>)\" to also cd"
      echo "  rtk <cmd>        compact git/ls/…; agents get nixq as nix (NIXQ=off to bypass)"
      echo "  treefmt         alejandra + deadnix + gofumpt + shfmt; runs on pre-commit (LEFTHOOK=0 to skip)"
      echo "  go-test-all     go test every module; runs on pre-push"
    '';
  };
}
