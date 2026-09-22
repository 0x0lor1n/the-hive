# LA-E152P / Latitude 5580 / Precision 3520 — DIY backlog (not now)

Same chassis, same LA-E152P board family. Ordered by payoff/risk. Nothing here blocks coreboot-5580.md.

## Cheap, reversible, well-trodden
- Wi-Fi: M.2 2230 CNVi-free slot, no whitelist → Intel AX210 (Wi-Fi 6E + BT 5.3). Needs the 2 IPEX antennas already there. ~$20.
- RAM: 2× SO-DIMM DDR4-2400. i7-U caps at 32 GB; Xeon E3-1505M v6 takes 2×32 = 64 GB ECC (Micron MTA18ASF4G72HZ-2G6B1ZI, in plan).
  Non-ECC works too, ECC just disabled. Verify `edac` after coreboot (5.5).
- Storage: M.2 2280 NVMe (PCIe x4) + 2.5" SATA bay. Both at once = the 4-cell 68 Wh battery. Bay adapter for 2nd NVMe is not a thing (SATA only).
- WWAN M.2 3042 B-key: PCIe x1 + USB. 2242 NVMe with B+M key SSD works on 5x80 per forum reports (single lane, ~700 MB/s). Cheap 3rd drive.
- Battery: 6-cell 92 Wh (VG93N / NY5PG) instead of 4-cell 68 Wh (GJKNX). Drops the 2.5" bay. Straight swap, BIOS/EC recognises it.
- Keyboard: backlit unit (single-point vs dual-point, part differs) is a drop-in; EC handles it, coreboot needs the brightness key mapped (4.3).
- 130 W charger + Xeon: 90 W throttles under dGPU+CPU load. Already bought.

## Panel
- 5580 ships 1366×768 TN or 1920×1080 IPS (30-pin eDP). Swap to FHD IPS (e.g. NV156FHM-N4x / LP156WF6) is standard. Touch variants need
  different lid+cable.
- Precision 3520 had a factory 4K UHD IGZO option (Sharp LQ156D1JW31/33, 40-pin eDP, 2 lanes) — needs the 40-pin LCD cable (Dell P/N differs)
  and the Xeon board's eDP is wired for it. Relevant to coreboot: VBT must carry the 4-lane/2-lane config for the panel actually fitted (4.3).
- 120 Hz 40-pin panels (Lenovo Legion parts) reported working on similar KBL-H Dells via the same cable — untested for 3520, nice-to-have.

## Thermal / power
- Undervolt via coreboot (5.8 in plan). ~−80 to −125 mV typical on 7820HQ/1505M v6; 10-15 °C off sustained, +200-300 MHz all-core.
- PL1/PL2 in devicetree instead of ThrottleStop hackery — sustained 45 W on 130 W adapter is fine on the M620 heatsink.
- Heatsink: stock thermal paste on these is bad. Liquid metal on a 7820HQ/M620 is documented (lapped IHS not needed, die is bare) —
  only with a foam dam around the die, nickel-plated heatsink.
- Fan curve: EC-controlled; on coreboot EC firmware stays stock, so the curve is whatever Dell shipped. Only lever = tune via `smm`/`dell-smm-hwmon`
  (`i8k`) manual fan mode — works on Linux with `fan_mult`/`force` (5580 is in the list).

## Ports / dock
- TB3 (JHL6540) on the Xeon board: eGPU works (Razer Core / ADT-Link R43SG adapter) at x4 3.0. Under coreboot needs 5.5 done.
- USB-C PD charging: not supported by EC — the port is TB3 data/DP only on this generation; 130 W barrel stays. No mod path without EC firmware.
- DisplayPort over TB3 + HDMI 1.4 + VGA: 3 external displays. HDMI 2.0 is *not* there (iGPU + LSPCON not populated).

## Firmware-adjacent (after coreboot works)
- me_cleaner -S + HAP (4.7 / 5.6 already in plan).
- Own Secure Boot keys via edk2 → lanzaboote (in plan).
- TB3 controller firmware (NVM) on its own SPI: Dell updates it via the BIOS package. Under coreboot use `fwupd` with the Dell TB plugin
  only if NVM version lags — otherwise leave.
- Replace Dell's EC "battery whitelist" behaviour: impossible without EC firmware, don't chase.

## Not worth it
- CPU upgrade on the i7-U board: BGA, no.
- Second LAN / more USB via the ExpressCard-less chassis: no slot.
- HDMI 2.0 rework: LSPCON pads exist on some LA-E152P revisions but no BOM, no.
