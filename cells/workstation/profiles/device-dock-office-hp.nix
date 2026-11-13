# HP Thunderbolt Dock G4 at elster's office desk and the HP E27u on it.
# No authorise rule: unauthorised, its USB hub enumerates on the host xHCI
# and the monitor runs over DP alt mode; elster stays on Wi-Fi there.
#
# kanshi `work`: the laptop panel goes dark while docked.
{
  inputs,
  cell,
}: {...}: {
  session.outputProfiles = [
    {
      profile.name = "work";
      profile.outputs = [
        {
          criteria = "HP Inc. HP E27u G4 CN423206D3";
          status = "enable";
          mode = "2560x1440@60Hz";
          position = "0,0";
        }
        {
          criteria = "eDP-1";
          status = "disable";
        }
      ];
    }
  ];
}
