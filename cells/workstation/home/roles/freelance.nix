# freelance: client work done under the user's own name. The home side is
# git includeIf + ssh matchBlocks only, and both still come through the
# account's whole encrypted set (home/secrets.nix -> `secrets` in
# ../default.nix) until it is cut per role. vpn-w is a system unit
# (profiles/vpn.nix).
{...}: {}
