# Personal-account extras (home/default.nix imports this only with
# `personal = true`, i.e. for the local user): OSINT tools and tor with the
# user's obfs4 bridges.
#
# Not here: ssh matchBlocks + agent (home/default.nix, from the role's
# encrypted set) and the VPN profiles, which are system units with agenix
# runtime secrets in profiles/vpn.nix.
{...}: {
  imports = [
    ./osint.nix
    ./tor.nix
  ];
}
