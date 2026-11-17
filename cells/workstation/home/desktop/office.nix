# ONLYOFFICE Desktop Editors for local office files. OOXML is its native
# format, so Word/Excel/PowerPoint files keep their layout better than in
# LibreOffice. M365 links still go to the o365 apps (roles/employer.nix);
# those are web wrappers that cannot open a local file.
#
# The theme is a custom interface theme in the palette. The Qt shell and
# the web editors both read the same JSON from <data>/uithemes; any token
# left out falls back to the stock Dark theme. The page itself stays white.
# DesktopEditors.conf is a QSettings file the app rewrites on exit, so only
# UITheme is forced from activation and the rest stays the app's.
# State to persist: ~/.config/onlyoffice (settings), ~/.local/share/onlyoffice
# (recent files, plugins, the uithemes dir).
{
  config,
  lib,
  pkgs,
  theme,
  ...
}: let
  k = theme.roles;
  c = theme.colors;
  h = x: "#${x}";

  themeFile = "onlyoffice/desktopeditors/uithemes/kanagawa.json";
  themePath = "${config.xdg.dataHome}/${themeFile}";

  editors = ["document" "spreadsheet" "presentation" "pdf" "visio"];
  perEditor = prefix: value: lib.genAttrs (map (e: "${prefix}-${e}") editors) (_: value);

  # Token names from web-apps colors-table-night.less (9.4).
  colors =
    perEditor "toolbar-header" (h k.bgDim)
    // perEditor "text-toolbar-header-on-background" (h k.bgDim)
    // perEditor "highlight-header-tab-underline" (h k.focus)
    // perEditor "highlight-toolbar-tab-underline" (h k.focus)
    // {
      "background-normal" = h k.bg;
      "background-toolbar" = h k.bg;
      "background-toolbar-tab" = h k.bg;
      "background-statusbar" = h k.bg;
      "background-toolbar-additional" = h k.bg;
      "background-primary-dialog-button" = h k.selection;
      "background-accent-button" = h k.selection;
      "background-notification-popover" = h c.waveBlue1;
      "background-notification-badge" = h k.highlight;
      "background-alt-key-hint" = h k.highlight;
      "background-contrast-popover" = h k.bgAlt;
      "background-fill-button" = h k.highlight;
      "background-pane" = h k.bgDim;
      "background-pane-additional" = h k.bgDim;

      "highlight-button-hover" = h k.bgAlt;
      "highlight-button-pressed" = h k.border;
      "highlight-button-pressed-hover" = h c.sumiInk6;
      "highlight-primary-dialog-button-hover" = h c.dragonBlue;
      "highlight-primary-dialog-button-pressed" = h c.waveBlue1;
      "highlight-text-select" = h k.selection;
      "highlight-fill-button-hover" = h c.carpYellow;
      "highlight-fill-button-pressed" = h c.boatYellow2;

      "border-toolbar" = h k.border;
      "border-toolbar-active-panel-top" = h k.bgDim;
      "border-divider" = h k.border;
      "border-regular-control" = h c.sumiInk6;
      "border-preview-hover" = h k.info;
      "border-preview-select" = h k.focus;
      "border-control-focus" = h k.focus;
      "border-contrast-popover" = h c.sumiInk6;
      "border-button-pressed-focus" = h k.focus;

      "text-normal" = h k.fg;
      "text-normal-pressed" = h k.fg;
      "text-secondary" = h c.oldWhite;
      "text-tertiary" = h k.muted;
      "text-link" = h k.focus;
      "text-link-hover" = h k.info;
      "text-link-active" = h k.info;
      "text-link-visited" = h k.hover;
      "text-inverse" = h k.fg;
      "text-toolbar-header" = h k.fg;
      "text-contrast-background" = h k.fg;
      "text-alt-key-hint" = h k.bg;

      "icon-normal" = h k.fg;
      "icon-normal-pressed" = h k.fg;
      "icon-toolbar-header" = h k.fg;
      "icon-gray-primary" = h k.fg;
      "icon-gray-secondary" = h k.muted;
      "icon-blue-primary" = h k.focus;
      "icon-blue-secondary" = h k.info;
      "icon-red" = h c.peachRed;
      "icon-success" = h k.success;

      "canvas-background" = h k.bgDim;
      "canvas-page-border" = h k.border;
      "canvas-ruler-background" = h k.bgDim;
      "canvas-ruler-border" = h c.sumiInk6;
      "canvas-ruler-margins-background" = h k.bgAlt;
      "canvas-ruler-mark" = h k.muted;
      "canvas-ruler-handle-border" = h k.muted;
      "canvas-ruler-handle-border-disabled" = h k.border;
      "canvas-high-contrast" = h k.fg;
      "canvas-high-contrast-disabled" = h c.sumiInk6;

      "canvas-cell-title-text" = h k.muted;
      "canvas-cell-title-background" = h k.bgDim;
      "canvas-cell-title-background-hover" = h k.bg;
      "canvas-cell-title-background-selected" = h k.bgAlt;
      "canvas-cell-title-border" = h k.border;
      "canvas-cell-title-border-hover" = h c.sumiInk6;
      "canvas-cell-title-border-selected" = h c.oldWhite;
      "canvas-select-all-icon" = h k.muted;

      "canvas-scroll-thumb" = h k.bgAlt;
      "canvas-scroll-thumb-hover" = h k.border;
      "canvas-scroll-thumb-pressed" = h c.sumiInk6;
      "canvas-scroll-thumb-border" = h k.border;
      "canvas-scroll-thumb-border-hover" = h c.sumiInk6;
      "canvas-scroll-thumb-border-pressed" = h k.muted;
      "canvas-scroll-arrow" = h k.muted;
      "canvas-scroll-arrow-hover" = h c.oldWhite;
      "canvas-scroll-arrow-pressed" = h k.fg;
    };

  # Everything the .desktop entry declares minus pdf/djvu/epub/plain text,
  # which keep their own viewers.
  desktopId = "onlyoffice-desktopeditors.desktop";
  officeTypes = [
    "application/msword"
    "application/msword-template"
    "application/vnd.ms-word.document.macroEnabled.12"
    "application/vnd.ms-word.template.macroEnabled.12"
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    "application/vnd.openxmlformats-officedocument.wordprocessingml.template"
    "application/vnd.ms-excel"
    "application/vnd.ms-excel.sheet.macroEnabled.12"
    "application/vnd.ms-excel.sheet.binary.macroEnabled.12"
    "application/vnd.ms-excel.template.macroEnabled.12"
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    "application/vnd.openxmlformats-officedocument.spreadsheetml.template"
    "application/vnd.ms-powerpoint"
    "application/vnd.ms-powerpoint.presentation.macroEnabled.12"
    "application/vnd.ms-powerpoint.slideshow.macroEnabled.12"
    "application/vnd.ms-powerpoint.template.macroEnabled.12"
    "application/vnd.openxmlformats-officedocument.presentationml.presentation"
    "application/vnd.openxmlformats-officedocument.presentationml.slideshow"
    "application/vnd.openxmlformats-officedocument.presentationml.template"
    "application/vnd.ms-visio.drawing.main+xml"
    "application/vnd.oasis.opendocument.text"
    "application/vnd.oasis.opendocument.text-template"
    "application/vnd.oasis.opendocument.spreadsheet"
    "application/vnd.oasis.opendocument.spreadsheet-template"
    "application/vnd.oasis.opendocument.presentation"
    "application/vnd.oasis.opendocument.presentation-template"
    "application/rtf"
  ];
in {
  home.packages = [pkgs.onlyoffice-desktopeditors];

  # Merges into the mimeApps set in home/desktop/mime.nix.
  xdg.mimeApps.defaultApplications = lib.genAttrs officeTypes (_: desktopId);

  xdg.dataFile.${themeFile}.text = builtins.toJSON {
    id = "theme-kanagawa";
    name = "Kanagawa";
    type = "dark";
    inherit colors;
  };

  # A .json value is looked up as a user theme file (cthemes.cpp); an id
  # alone only matches the built-ins.
  home.activation.onlyofficeTheme = lib.hm.dag.entryAfter ["writeBoundary"] ''
    conf=${lib.escapeShellArg "${config.xdg.configHome}/onlyoffice/DesktopEditors.conf"}
    run mkdir -p "$(dirname "$conf")"
    run ${pkgs.crudini}/bin/crudini --ini-options=nospace --set "$conf" General UITheme ${lib.escapeShellArg themePath}
  '';
}
