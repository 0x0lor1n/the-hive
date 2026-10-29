# kanshi. DVI-I-1 is evdi's fixed name for any DisplayLink head (elster's 4K at
# work, penrose's dock at home), so `docked` takes the monitor's preferred mode
# rather than pinning one; the HP matches by EDID, MST connector numbers change
# on replug. eDP-1 likewise: elster's panel is 1920x1200, penrose's 1920x1080.
_: {
  services.kanshi = {
    enable = true;
    settings = [
      {
        profile.name = "docked";
        profile.outputs = [
          {
            criteria = "DVI-I-1";
            status = "enable";
            position = "0,0";
          }
          {
            criteria = "eDP-1";
            status = "disable";
          }
        ];
      }
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
}
