# kanshi. DVI-I-1 is evdi's fixed name for the DisplayLink 4K; the HP matches by
# EDID, MST connector numbers change on replug.
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
            mode = "1920x1200@60Hz";
            position = "0,0";
          }
        ];
      }
    ];
  };
}
