# LA-E152P Xeon (Precision 3520) — DIY backlog (not now)

Old i7-U board is out of scope (basement). Nothing here blocks coreboot-5580.md. Sources checked: Dell 3520 owner's manual
(display/memory/battery), community reports where noted.

## Screen — facts first
- LCD connector on LA-E152P is 30-pin eDP, 2 lanes. Precision 3520 shipped HD / FHD / FHD-touch **only**; there is no 4K SKU
  (4K IGZO is Precision 7520, different board). 4K@60 needs 4 lanes; KBL has no DSC. Forget 4K on this chassis.
- Real upgrade: better FHD 30-pin IPS than the stock 220-nit unit — LP156WF6-SPK1/SPP1 or NV156FHM-N4x (300 nit, ~95 % sRGB).
  Drop-in, no cable change, VBT unchanged. Touch variants need a different lid+cable, skip.

## Cheap, reversible
- Wi-Fi: M.2 2230 slot, no whitelist → Intel AX210 (Wi-Fi 6E + BT 5.3), reuses the 2 IPEX antennas. ~$20.
- RAM: 2× SO-DIMM DDR4-2400, E3-1505M v6 takes 2×32 = 64 GB ECC (Micron MTA18ASF4G72HZ-2G6B1ZI, already in plan). Verify `edac` (5.5).
- Storage: M.2 2280 NVMe x4 + 2.5" SATA bay (bay only with the 4-cell battery).
- WWAN M.2 3042 B-key (PCIe x1 + USB): 2242 NVMe B+M SSD works on 5x80 per forum reports, ~700 MB/s. Cheap 3rd drive.
- Battery: 6-cell 92 Wh (VG93N / NY5PG) instead of 4-cell 68 Wh (GJKNX). Drops the 2.5" bay. EC recognises it, straight swap.
- Keyboard: backlit unit is a drop-in; EC handles it, coreboot only needs the brightness key (4.3).
- 130 W charger: required, 90 W throttles under CPU+M620 load. Already bought.

## Thermal / power
- Undervolt via coreboot (5.8 in plan). Community numbers for 7820HQ/1505M v6: −80…−125 mV stable, 10-15 °C off sustained, +200-300 MHz all-core.
- PL1/PL2 in devicetree, not ThrottleStop. 45 W sustained on 130 W adapter is fine on the M620 heatsink.
- Repaste at board swap (stock paste on these is dry). Liquid metal on the bare die is documented for 7820HQ — foam dam around die,
  nickel-plated heatsink only. Optional.
- Fan: EC-controlled, curve is Dell's regardless of coreboot. Manual override via `dell-smm-hwmon` (`i8k`), 5580 is in the supported list.

## Ports / dock
- USB-C PD input: supported. Dell WD19 compat table lists Latitude 5580 / Precision 3520 with 130 W from WD19TB (180 W brick).
  Dock = power + LAN + USB + keyboard/mouse. Barrel adapter only for travel.
- eGPU — decision: **M.2 2280 → ADT-Link R43SG**, PCIe 3.0 x4 direct (~3.2 GB/s), not TB3.
  TB3 behind WD19TB shares 40 Gbps with 4K60 DP tunnel + USB + LAN, PCIe tunnel is ≤22 Gbps anyway; and TB3 under coreboot is
  the riskiest part of 5.5. M.2 path is just a root port that's already enabled. Cold-plug only.
  Devicetree: CLKREQ off + ASPM off on that root port (ribbon adapters break both).
  Routing: ribbon out through the VGA opening — cut the DSUB shell, no need to desolder. Slot needed ~15×2 mm.
  4K monitor → eGPU DP, not the dock. Dock DP stays free for a second screen on iGPU.
  Power: ATX PSU or Dell DA-2 220 W.
- Storage after M.2 goes to eGPU: option A (chosen) 68 Wh 4-cell + 2.5" SATA SSD, zero risk.
  Option B 92 Wh + 2242 NVMe in WWAN slot (x1, ~900 MB/s) — needs proof the WWAN connector carries PCIe on LA-E152P first.
- TB3 (JHL6540) stays for the dock only. eGPU over TB3 not planned.
- Displays: DP over TB3 + HDMI 1.4 + VGA = 3 external. HDMI 2.0 absent (no LSPCON populated).

## Firmware-adjacent (after coreboot works)
- me_cleaner -S + HAP (5.6 in plan). Own SB keys via edk2 → lanzaboote (in plan).
- TB3 NVM firmware lives on its own SPI, Dell ships updates inside the BIOS package. Under coreboot: `fwupd` Dell TB plugin only if
  NVM lags; otherwise leave it.
- EC firmware (battery whitelist, fan curve, PD): closed, don't chase.

## Not worth it
- HDMI 2.0 rework: LSPCON pads exist on some revisions, no BOM, no.
- 4K panel: see top. No.
