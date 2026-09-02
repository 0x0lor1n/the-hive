# fuzzel — wlroots-native (layer-shell) app launcher.
# Same author as foot, same minimal aesthetic.
# HM module programs.fuzzel exists in release-25.05.
{pkgs, ...}: {
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
    };
  };
}
