# pxpipe: loopback proxy that images the bulky parts of each Anthropic
# request before it leaves the machine (cells/repo/packages.nix). One system
# instance, not a user unit: the port is shared, two logged-in users (Entra
# on seat0, the local user over ssh) would fight over it. Stateless -- the
# API key travels in each request -- so sharing the instance leaks nothing.
#
# Hermes itself is installed here too, system-wide: the Entra user is an
# NSS-only account (no users.users, no home-manager), so systemPackages is
# the only PATH both sessions share. State stays per-user in ~/.hermes
# (persisted for both: layer-users-local.nix, auth-entra.nix).
{
  inputs,
  cell,
}: {lib, ...}: let
  inherit (inputs.cells.repo.packages) pxpipe hermes-agent;
  port = 47821;
in {
  environment.systemPackages = [hermes-agent];

  systemd.services.pxpipe = {
    description = "pxpipe: Anthropic loopback proxy";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig = {
      ExecStart = "${lib.getExe pxpipe} -port ${toString port}";
      Restart = "on-failure";
      RestartSec = 2;
      DynamicUser = true;
      # Nothing on disk, nothing to reach but the loopback listener and
      # api.anthropic.com.
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
      RestrictAddressFamilies = ["AF_INET" "AF_INET6"];
      CapabilityBoundingSet = "";
    };
  };

  # Hermes (hermes_cli/runtime_provider.py) takes the endpoint for
  # `provider: anthropic` from model.base_url in config.yaml only -- not from
  # ANTHROPIC_BASE_URL -- and only when the hostname ends in .anthropic.com.
  networking.hosts."127.0.0.1" = ["pxpipe.anthropic.com"];
}
