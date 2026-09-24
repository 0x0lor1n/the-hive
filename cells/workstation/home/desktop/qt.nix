# Qt palette for every Qt app (qBittorrent, KeePassXC), from common/theme.nix.
# QT_QPA_PLATFORMTHEME and the plugins come from qt.* in layer-session.nix;
# this writes the configs both plugins read. Unlike an app's own palette,
# a qtct scheme fills the Inactive group too, so windows stay dark while a
# layer surface (slurp, fuzzel) holds keyboard focus.
{
  config,
  lib,
  theme,
  ...
}: let
  k = theme.roles;
  c = theme.colors;

  # QPalette::ColorRole order; qt6ct appends Accent (= Highlight) on Qt >= 6.6.
  roles = [
    k.fg # WindowText
    k.bgAlt # Button
    c.sumiInk6 # Light
    k.border # Midlight
    c.sumiInk1 # Dark
    k.bgAlt # Mid
    k.fg # Text
    c.oldWhite # BrightText
    k.fg # ButtonText
    k.bgDim # Base
    k.bg # Window
    k.bgDim # Shadow
    k.selection # Highlight
    k.fg # HighlightedText
    k.focus # Link
    k.hover # LinkVisited
    c.sumiInk1 # AlternateBase
    k.bg # NoRole
    k.bgAlt # ToolTipBase
    k.fg # ToolTipText
    k.muted # PlaceholderText
  ];
  # Text-bearing roles grey out when disabled.
  disabled = lib.imap0 (i: x:
    if builtins.elem i [0 6 7 8 13 19]
    then k.muted
    else x)
  roles;
  line = xs: lib.concatMapStringsSep ", " (x: "#ff${x}") xs;

  scheme = ''
    [ColorScheme]
    active_colors=${line roles}
    inactive_colors=${line roles}
    disabled_colors=${line disabled}
  '';

  conf = name: ''
    [Appearance]
    style=Fusion
    custom_palette=true
    color_scheme_path=${config.xdg.configHome}/${name}/colors/kanagawa.conf
    icon_theme=Kanagawa
    standard_dialogs=default
  '';
in {
  # qt5ct for Qt5 apps (KeePassXC), qt6ct for Qt6 (qBittorrent).
  xdg.configFile = lib.mkMerge (map (name: {
    "${name}/${name}.conf".text = conf name;
    "${name}/colors/kanagawa.conf".text = scheme;
  }) ["qt5ct" "qt6ct"]);
}
