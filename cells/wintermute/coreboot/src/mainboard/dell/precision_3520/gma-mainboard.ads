-- SPDX-License-Identifier: GPL-2.0-or-later

with HW.GFX.GMA;
with HW.GFX.GMA.Display_Probing;

use HW.GFX.GMA;
use HW.GFX.GMA.Display_Probing;

private package GMA.Mainboard is

   ports : constant Port_List :=
     (eDP,
      HDMI1,  -- DDI B, PS8407 level shifter
      DP2,    -- DDI C, Alpine Ridge DP sink 0
      DP3,    -- DDI D, PS8338 demux: Alpine Ridge sink 1 / WiGig / VGA
      others => Disabled);

end GMA.Mainboard;
