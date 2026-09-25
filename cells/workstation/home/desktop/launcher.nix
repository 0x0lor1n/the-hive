# fuzzel — wlroots-native (layer-shell) app launcher.
# Same author as foot, same minimal aesthetic.
# HM module programs.fuzzel exists in release-25.05.
{
  pkgs,
  theme,
  ...
}: let
  k = theme.roles;
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
        background = "${k.bg}ff";
        text = "${k.fg}ff";
        match = "${k.highlight}ff";
        selection = "${k.selection}ff";
        selection-text = "${k.fg}ff";
        selection-match = "${k.highlight}ff";
        border = "${k.focus}ff";
      };
    };
  };
}
