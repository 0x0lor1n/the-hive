# OSINT toolbelt, ported from jarvis users/shared/security/osint.nix
# (2026-09-15). Personal-account only (see ./default.nix). `dig` is the
# bind client package in nixpkgs; whois and fierce as before.
{pkgs, ...}: {
  home.packages = with pkgs; [
    whois
    dig
    fierce
  ];
}
