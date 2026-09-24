# Zathura (forward-search viewer for lang-texlive.lua) in the palette.
# The page itself stays as authored; Ctrl+R recolors it to bg/fg.
{
  lib,
  theme,
  ...
}: let
  r = theme.roles;
  hex = c: "#${c}";
  # GTK3's gdk_rgba_parse has no #rrggbbaa, only rgba().
  rgba = c: a: let
    ch = i: toString (lib.fromHexString (builtins.substring i 2 c));
  in "rgba(${ch 0},${ch 2},${ch 4},${a})";
in {
  programs.zathura = {
    enable = true;
    options = {
      default-bg = hex r.bg;
      default-fg = hex r.fg;
      statusbar-bg = hex r.bgAlt;
      statusbar-fg = hex r.fg;
      inputbar-bg = hex r.bg;
      inputbar-fg = hex r.fg;
      notification-bg = hex r.bgAlt;
      notification-fg = hex r.fg;
      notification-error-bg = hex r.urgent;
      notification-error-fg = hex r.fg;
      notification-warning-bg = hex r.highlight;
      notification-warning-fg = hex r.bg;
      completion-bg = hex r.bgAlt;
      completion-fg = hex r.fg;
      completion-group-bg = hex r.bg;
      completion-group-fg = hex r.focus;
      completion-highlight-bg = hex r.selection;
      completion-highlight-fg = hex r.fg;
      index-bg = hex r.bg;
      index-fg = hex r.fg;
      index-active-bg = hex r.selection;
      index-active-fg = hex r.fg;
      # Drawn over the page (usually white), hence the alpha.
      highlight-color = rgba r.highlight "0.5";
      highlight-active-color = rgba r.warning "0.5";
      highlight-fg = hex r.bg;
      render-loading-bg = hex r.bg;
      render-loading-fg = hex r.muted;
      recolor-lightcolor = hex r.bg;
      recolor-darkcolor = hex r.fg;
      signature-success-color = rgba r.success "0.9";
      signature-warning-color = rgba r.warning "0.9";
      signature-error-color = rgba r.urgent "0.9";
    };
  };
}
