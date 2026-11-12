# kanshi. External monitors match by EDID description, not connector name:
# DP-N numbers come from the TB/MST topology and change on replug.
#
# `home`: the LG 4K behind the WD19TBS, shared by both laptops (the dock
# moves). Its EDID tops out at 3840x2160@60 (range 56-61 Hz), so the mode is
# pinned there. The panel goes dark while docked.
# `work`: the HP E27u at elster's desk (session.workMonitor, host-elster.nix).
# eDP-1 is the panel on both: 1920x1200 on elster, 1920x1080 on penrose.
{
  config,
  lib,
  workMonitor,
  ...
}: let
  panelOff = {
    criteria = "eDP-1";
    status = "disable";
  };
in {
  services.kanshi = {
    enable = true;
    settings =
      [
        {
          profile.name = "home";
          profile.outputs = [
            {
              # Make/serial strings depend on libdisplay-info (PNP GSM, no
              # serial descriptor in the EDID); match the model name only.
              criteria = "*LG Ultra HD*";
              status = "enable";
              mode = "3840x2160@60Hz";
              position = "0,0";
            }
            panelOff
          ];
        }
      ]
      ++ lib.optional workMonitor {
        profile.name = "work";
        profile.outputs = [
          {
            criteria = "HP Inc. HP E27u G4 CN423206D3";
            status = "enable";
            mode = "2560x1440@60Hz";
            position = "0,0";
          }
          panelOff
        ];
      }
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
