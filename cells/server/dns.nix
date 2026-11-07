# Public DNS of the site as code: terranix renders dns/*.nix to config.tf.json,
# opentofu (with the Njalla provider baked in) applies it. Not a host, so not
# a nixosConfiguration; the devshell exposes it as `dns <tofu args>`.
#
# State: records carry the public IP, which the repo keeps encrypted (globals),
# so the tfstate is NOT committed -- it lives under the user's XDG state dir.
# Losing it costs one `dns import` per record (ids from Njalla's list-records).
{
  inputs,
  cell,
  system,
  ...
}: let
  inherit (inputs) pkgs terranix;
  globals = inputs.cells.common.globals;

  # Not in nixpkgs. Abandoned upstream (2022) but the API has not moved;
  # Resources: A/AAAA/CAA/CNAME/MX/NS/PTR/TLSA/TXT. Token via NJALLA_API_TOKEN.
  njalla = pkgs.terraform-providers.mkProvider {
    owner = "Sighery";
    repo = "terraform-provider-njalla";
    rev = "v0.10.0";
    spdx = "MIT";
    homepage = "https://registry.terraform.io/providers/Sighery/njalla";
    hash = "sha256-I8aIOr97TDxf6h3eMXZQLAIj8b8YNcHpaRBbb6KcdL0=";
    vendorHash = "sha256-VFqtMLv6pDzHIgxckjolvWiI81IIjzjqbkMNRBy9hpA=";
  };

  tofu = pkgs.opentofu.withPlugins (_: [njalla]);

  hisilomeConfig = terranix.lib.terranixConfiguration {
    inherit system pkgs;
    modules = [./dns/hisilome.nix];
    extraArgs = {host = globals.hosts.osgiliath;};
  };
in {
  inherit njalla tofu;
  hisilome = hisilomeConfig;

  # `dns ids|plan|apply|import ...`: a scratch dir per run with the rendered
  # config, state pinned outside the repo, token decrypted with this host's
  # TPM PIN identity (same prompt as deploy-key) and handed over as env.
  #
  # The config is built at run time, not baked in: it reads globals, which
  # need the extra-builtins plugin that only the devshell's NIX_CONFIG
  # provides. Baking it would make direnv's (outer) devshell eval fail.
  cli = pkgs.writeShellApplication {
    name = "dns";
    runtimeInputs = [tofu pkgs.nix pkgs.rage pkgs.age-plugin-tpm pkgs.git pkgs.coreutils pkgs.curl pkgs.jq];
    text = ''
      root=$(git rev-parse --show-toplevel)
      state="''${XDG_STATE_HOME:-$HOME/.local/state}/the-hive/dns/hisilome"
      mkdir -p "$state"
      work=$(mktemp -d)
      trap 'rm -rf "$work"' EXIT
      config=$(nix build --no-link --print-out-paths "$root#x86_64-linux.server.dns.hisilome")
      cp "$config" "$work/config.tf.json"
      cd "$work"

      if [ -z "''${NJALLA_API_TOKEN:-}" ]; then
        token="$root/secrets/hisilome/njalla-api-token.age"
        if [ ! -f "$token" ]; then
          echo "dns: $token is missing. Njalla panel → API token, then:" >&2
          echo "  rage -e -r <penrose> -r <elster> -o $token   (recipients from secrets/*-nix-rage.pub)" >&2
          exit 1
        fi
        NJALLA_API_TOKEN=$(rage -d \
          -i "$root/secrets/$(uname -n)-nix-rage.pub" \
          "$token")
        export NJALLA_API_TOKEN
      fi

      # `dns ids`: record ids for `dns import <addr> hisilo.me:<id>`.
      if [ "''${1:-}" = "ids" ]; then
        curl -fsS https://njal.la/api/1/ \
          -H "Authorization: Njalla $NJALLA_API_TOKEN" \
          -H 'Content-Type: application/json' \
          --data '{"jsonrpc":"2.0","id":1,"method":"list-records","params":{"domain":"hisilo.me"}}' \
          | jq -r '.result.records[] | [.id, .type, .name, .content, .ttl] | @tsv'
        exit
      fi

      # withPlugins pre-seeds the provider dir; init stays offline. The local
      # backend gets its path here, so every later command finds the state.
      tofu init -input=false -no-color -backend-config="path=$state/terraform.tfstate" >/dev/null
      exec tofu "$@"
    '';
  };
}
