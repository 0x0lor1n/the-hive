# kanshi. External monitors match by EDID description, not connector name:
# DP-N numbers come from the TB/MST topology and change on replug.
#
# The docked profiles come from the host (outputProfiles, filled by each
# profiles/device-dock-*.nix through session.outputProfiles); this file only
# adds the `undocked` fallback after them. eDP-1 is the panel on both laptops:
# 1920x1200 on elster, 1920x1080 on penrose.
{
  config,
  outputProfiles,
  ...
}: {
  services.kanshi = {
    enable = true;
    settings =
      outputProfiles
      ++ [
        {
          profile.name = "undocked";
          profile.outputs = [
            {
              criteria = "eDP-1";
              status = "enable";
              position = "0,0";
            }
          ];
        }
      ];
  };

  # kanshi reads its config once at startup and the unit itself does not
  # change with the profiles, so a switch would leave the old ones running.
  # Hash the settings, not xdg.configFile: that attrset also carries the
  # secret-backed git includes and drags them into evaluation.
  systemd.user.services.kanshi.Unit.X-Restart-Triggers = [
    (builtins.hashString "sha256" (builtins.toJSON config.services.kanshi.settings))
  ];
}
