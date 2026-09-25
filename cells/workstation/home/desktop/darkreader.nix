# Dark Reader settings for Settings → Advanced → Import (Firefox and Edge).
# The addon has no managed-storage or policy input, so this file is imported
# by hand once per browser, and again after a palette change.
# Only `theme` is set: the import merges top-level keys, so site lists and
# the rest stay as they are; `theme` itself is replaced whole, hence every key.
{
  pkgs,
  theme,
  ...
}: let
  r = theme.roles;
  # darkColorScheme names the addon's bundled Kanagawa (color-schemes.drconf),
  # so its picker shows it selected; the two colours are what actually paints.
  settings.theme = {
    mode = 1;
    brightness = 100;
    contrast = 100;
    grayscale = 0;
    sepia = 0;
    useFont = false;
    fontFamily = "Open Sans";
    textStroke = 0;
    engine = "dynamicTheme";
    stylesheet = "";
    darkColorScheme = "Kanagawa";
    darkSchemeBackgroundColor = "#${r.bg}";
    darkSchemeTextColor = "#${r.fg}";
    lightColorScheme = "Default";
    lightSchemeBackgroundColor = "#dcdad7";
    lightSchemeTextColor = "#181a1b";
    scrollbarColor = "";
    selectionColor = "auto";
    styleSystemControls = false;
    immediateModify = false;
  };
in {
  xdg.configFile."darkreader/kanagawa.json".source =
    (pkgs.formats.json {}).generate "darkreader-kanagawa.json" settings;
}
