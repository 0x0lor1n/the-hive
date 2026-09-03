# GTK apps (Edge dialogs, file pickers via the gtk portal) would otherwise
# come up in stock Adwaita with the default X cursor. nixpkgs dropped
# kanagawa-gtk-theme (GTK2 murrine dep), so: adw-gtk3 as the base and the
# palette from cells/theme injected via libadwaita named colours -- same
# source as foot/somebar/tuigreet.
{
  pkgs,
  theme,
  ...
}: let
  k = theme.roles;
  # GTK CSS wants #rrggbb; the palette stores rrggbb.
  kanagawaCss = ''
    @define-color window_bg_color #${k.bg};
    @define-color window_fg_color #${k.fg};
    @define-color view_bg_color #${k.bgDim};
    @define-color view_fg_color #${k.fg};
    @define-color headerbar_bg_color #${k.bgAlt};
    @define-color headerbar_fg_color #${k.fg};
    @define-color headerbar_border_color #${k.border};
    @define-color sidebar_bg_color #${k.bgAlt};
    @define-color sidebar_fg_color #${k.fg};
    @define-color card_bg_color #${k.bgAlt};
    @define-color card_fg_color #${k.fg};
    @define-color dialog_bg_color #${k.bgAlt};
    @define-color dialog_fg_color #${k.fg};
    @define-color popover_bg_color #${k.bgAlt};
    @define-color popover_fg_color #${k.fg};
    @define-color accent_bg_color #${k.focus};
    @define-color accent_fg_color #${k.bgDim};
    @define-color accent_color #${k.focus};
    @define-color destructive_bg_color #${k.urgent};
    @define-color destructive_fg_color #${k.fg};
    @define-color destructive_color #${k.urgent};
    @define-color success_color #${k.accent};
    @define-color warning_color #${k.highlight};
    @define-color error_color #${k.urgent};
    @define-color borders #${k.border};
  '';
in {
  home.pointerCursor = {
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Ice";
    size = 24;
    gtk.enable = true;
  };

  gtk = {
    enable = true;
    theme = {
      package = pkgs.adw-gtk3;
      name = "adw-gtk3-dark";
    };
    iconTheme = {
      package = pkgs.kanagawa-icon-theme;
      name = "Kanagawa";
    };
    font = {
      name = "sans-serif";
      size = 10;
    };
    gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;
    gtk3.extraCss = kanagawaCss;
    gtk4.extraConfig.gtk-application-prefer-dark-theme = 1;
    gtk4.extraCss = kanagawaCss;
  };

  dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";

  # System-wide fonts are in layer-session.nix; this only pins which one
  # each generic family resolves to.
  fonts.fontconfig = {
    enable = true;
    defaultFonts = {
      monospace = ["JetBrainsMono Nerd Font"];
      sansSerif = ["Inter"];
      serif = ["Noto Serif"];
      emoji = ["Noto Color Emoji"];
    };
  };
}
