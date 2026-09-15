# Personal-account extras (home/default.nix imports this only with
# `personal = true`, i.e. for the local user): OSINT tools and tor with the
# user's obfs4 bridges. Ported from jarvis users/shared/security/.
#
# Not here any more: ssh matchBlocks + agent (home/default.nix, from the
# role's encrypted set) and the VPN profiles, which became system units with
# agenix runtime secrets in profiles/vpn.nix -- jarvis rendered wireguard and
# openvpn credentials into the nix store through xdg.configFile.text.
{...}: {
  imports = [
    ./osint.nix
    ./tor.nix
  ];
}
