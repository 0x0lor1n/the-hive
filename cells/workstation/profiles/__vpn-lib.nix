# Shared by role-freelance.nix and role-employer.nix: the agenix shape of a
# tunnel secret and an openvpn server reading two of them.
#
# Secret sources: secrets/vpn/<name>.age, rekeyed per host into
# secrets/rekeyed/<host>/ like the ssh identities. openvpn takes the .ovpn
# verbatim (inline ca/cert/key, so the file itself is the secret) plus a
# two-line auth-user-pass file. root 0400: the tunnels are system units.
{
  inputs,
  lib,
  config,
}: {
  secret = name: {
    rekeyFile = "${inputs.self.outPath}/secrets/vpn/${name}.age";
    mode = "0400";
  };
  ovpn = name: pushedDns: extra: {
    config = ''
      config ${config.age.secrets."vpn-${name}-ovpn".path}
      auth-user-pass ${config.age.secrets."vpn-${name}-auth".path}
      ${extra}
    '';
    autoStart = false;
    updateResolvConf = pushedDns;
  };
}
