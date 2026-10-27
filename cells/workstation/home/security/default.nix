# OSINT tools, part of the dev role (home/roles/dev.nix, which also imports
# tor.nix next to it).
#
# Not here: ssh matchBlocks + agent (home/default.nix, from the role's
# encrypted set) and the VPN profiles, which are system units with agenix
# runtime secrets in profiles/vpn.nix.
{...}: {
  imports = [
    ./osint.nix
  ];
}
