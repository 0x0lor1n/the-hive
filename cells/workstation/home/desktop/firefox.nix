# Firefox chrome in the palette. The "System theme" follows GTK only for the
# tabstrip; toolbar, urlbar and panels are Firefox's own greys (theme-coverage
# 7.1a). A signed static theme is impossible (unsigned xpi refused), so
# userChrome.css (enabled by autoconfig in browser-firefox.nix) sets the
# design-system tokens of Fx 154. Content stays Dark Reader's job.
#
# The profile is Firefox-owned (random name, no programs.firefox), so
# activation links the file into every profile listed in profiles.ini. A
# profile created after activation gets it on the next switch/login.
{
  config,
  lib,
  pkgs,
  theme,
  ...
}: let
  r = theme.roles;
  tokens = {
    toolbox-background-color = r.bgAlt;
    toolbox-background-color-inactive = r.bgAlt;
    toolbox-text-color = r.fg;
    toolbox-text-color-inactive = r.muted;
    toolbar-background-color = r.bg;
    toolbar-text-color = r.fg;
    toolbar-field-background-color = r.bgDim;
    toolbar-field-text-color = r.fg;
    toolbar-field-border-color = r.border;
    toolbar-field-background-color-focus = r.bgDim;
    toolbar-field-text-color-focus = r.fg;
    toolbar-field-border-color-focus = r.focus;
    # Identity/permission pills inside the urlbar; default = fg at 16% alpha.
    urlbar-box-background-color = r.bgAlt;
    urlbar-box-background-color-focus = r.bgAlt;
    urlbar-box-background-color-hover = r.border;
    urlbar-box-background-color-active = r.selection;
    toolbarseparator-color = r.border;
    toolbarbutton-background-color-hover = r.border;
    toolbarbutton-background-color-active = r.selection;
    tab-background-color-selected = r.bg;
    tab-selected-textcolor = r.fg;
    tab-background-color-hover = r.border;
    tabs-navbar-separator-color = r.border;
    chrome-content-separator-color = r.border;
    tabpanel-background-color = r.bg;
    urlbarview-background-color-hover = r.border;
    urlbarview-background-color-selected = r.selection;
    urlbarview-text-color-selected = r.fg;
    urlbarview-text-color-secondary = r.muted;
    urlbarview-separator-color = r.border;
    panel-background-color = r.bgAlt;
    panel-text-color = r.fg;
    panel-border-color = r.border;
    panel-separator-color = r.border;
    menu-bg = r.bgAlt;
    menu-text-color = r.fg;
    menu-border-color = r.border;
    menuitem-hover-bg = r.selection;
    sidebar-background-color = r.bgAlt;
    sidebar-text-color = r.fg;
    focus-outline-color = r.focus;
    color-accent-primary = r.focus;
    # Primary buttons (translation/permission popups) fill with the accent;
    # their text defaults to white/AccentColorText, unreadable on light blue.
    color-accent-primary-hover = r.info;
    color-accent-primary-active = r.selection;
    button-background-color-primary = r.focus;
    button-background-color-primary-hover = r.info;
    button-background-color-primary-active = r.selection;
    button-text-color-primary = r.bgDim;
    button-text-color-primary-hover = r.bgDim;
    button-text-color-primary-active = r.fg;
  };
  # !important: a user sheet otherwise loses to the browser's own :root rules.
  userChrome = pkgs.writeText "firefox-userChrome.css" ''
    :root {
    ${lib.concatStrings (lib.mapAttrsToList (k: v: "  --${k}: #${v} !important;\n") tokens)}}
  '';
in {
  home.activation.firefoxUserChrome = lib.hm.dag.entryAfter ["writeBoundary"] ''
    base=${lib.escapeShellArg "${config.xdg.configHome}/mozilla/firefox"}
    if [ -f "$base/profiles.ini" ]; then
      ${pkgs.gnused}/bin/sed -n 's/^Path=//p' "$base/profiles.ini" | while read -r p; do
        case "$p" in /*) dir=$p ;; *) dir=$base/$p ;; esac
        [ -d "$dir" ] || continue
        css=$dir/chrome/userChrome.css
        # A hand-written file is left alone; only our own link is replaced.
        if [ -e "$css" ] && [ ! -L "$css" ]; then
          warnEcho "firefox: $css is a regular file, not linking"
          continue
        fi
        run mkdir -p "$dir/chrome"
        run ln -sfn ${userChrome} "$css"
      done
    fi
  '';
}
