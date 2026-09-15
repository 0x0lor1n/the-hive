# kanshi — output profiles switched on hotplug (wlr-output-management, which
# dwl implements). Connector names are what wlroots reports: the internal
# panel is eDP-1; the DisplayLink 4K via the Lenovo dock comes up as the
# evdi card, exposed as DVI-I-1 (evdi's fixed connector name, not a real DVI).
#
# docked:   only the 4K on, panel off -- the laptop lid stays closed on the
#           desk, no point driving the panel through evdi's USB framebuffer.
# undocked: panel only.
# Profiles match the exact output set, so pulling the dock cable flips back
# to `undocked` automatically; kanshi is PartOf graphical-session.target and
# needs no manual restart. `kanshictl reload` after editing by hand.
{...}: {
  services.kanshi = {
    enable = true;
    settings = [
      {
        profile.name = "docked";
        profile.outputs = [
          {
            criteria = "DVI-I-1";
            status = "enable";
            mode = "3840x2160@60Hz";
            position = "0,0";
          }
          {
            criteria = "eDP-1";
            status = "disable";
          }
        ];
      }
      {
        profile.name = "undocked";
        profile.outputs = [
          {
            criteria = "eDP-1";
            status = "enable";
            mode = "1920x1200@60Hz";
            position = "0,0";
          }
        ];
      }
    ];
  };
}
