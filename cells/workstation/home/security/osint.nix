# OSINT toolbelt. Personal-account only (see ./default.nix). `dig` is the
# bind client package in nixpkgs.
{pkgs, ...}: {
  home.packages = with pkgs; [
    whois
    dig
    fierce
  ];
}
