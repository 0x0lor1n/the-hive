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

  # A real theme directory so the name is not a lie: adw-gtk3-dark's assets
  # with our @define-colors prepended to both gtk.css entry points.
  kanagawaGtk = pkgs.runCommand "kanagawa-gtk3" {} ''
    mkdir -p $out/share/themes
    cp -r ${pkgs.adw-gtk3}/share/themes/adw-gtk3-dark $out/share/themes/Kanagawa
    chmod -R u+w $out/share/themes/Kanagawa
    for f in $out/share/themes/Kanagawa/gtk-3.0/gtk.css \
             $out/share/themes/Kanagawa/gtk-3.0/gtk-dark.css; do
      [ -e "$f" ] || continue
      cat ${pkgs.writeText "kanagawa-colors.css" kanagawaCss} "$f" > "$f.new"
      mv "$f.new" "$f"
    done
  '';
in {
  # Bibata's hand2 (link hover) is drawn mirrored -- it points away from the
  # link. phinger-cursors has a conventional pointing hand.
  home.pointerCursor = {
    package = pkgs.phinger-cursors;
    name = "phinger-cursors-dark";
    size = 24;
    gtk.enable = true;
  };

  gtk = {
    enable = true;
    # adw-gtk3-dark is the widget engine; kanagawaCss below repaints it, so
    # the theme is exported under its own name (which is also what fastfetch
    # and every theme switcher report).
    theme = {
      package = kanagawaGtk;
      name = "Kanagawa";
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
