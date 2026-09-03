# fuzzel — wlroots-native (layer-shell) app launcher.
# Same author as foot, same minimal aesthetic.
# HM module programs.fuzzel exists in release-25.05.
{pkgs, ...}: let
  k = import ./kanagawa.nix;
in {
  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        font = "monospace:size=11";
        terminal = "${pkgs.foot}/bin/foot";
        layer = "overlay";
        width = 40;
        lines = 12;
      };
      border = {
        width = 2;
        radius = 0;
      };
      # fuzzel wants rrggbbaa.
      colors = {
        background = "${k.sumiInk3}ff";
        text = "${k.fujiWhite}ff";
        match = "${k.carpYellow}ff";
        selection = "${k.waveBlue2}ff";
        selection-text = "${k.fujiWhite}ff";
        selection-match = "${k.carpYellow}ff";
        border = "${k.crystalBlue}ff";
      };
    };
  };
}
