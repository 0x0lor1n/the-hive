# The HP dock at elster's office desk and the HP E27u on it. Only the
# monitor is configured: the dock needs nothing else here (model and any
# authorise rule unrecorded, recon 0.4 in .hermes/state/device-profiles.md).
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
