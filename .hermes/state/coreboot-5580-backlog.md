# LA-E152P Xeon (Precision 3520) — backlog (after coreboot-5580.md is green)

Nothing here blocks the coreboot port. Each item is a self-contained mini-plan; pick one when Phase 5 exit is met.
Old i7-U board is out of scope (basement).
Schematics on file (`~/.hermes/cache/web/`):
- `Dell-3520-LA-E152P-schematic.pdf` — **the Xeon board**, "Breckenridge 15 DSC (TBT), Kabylake H", REV 1.0 (A00), 74 p., Compal 2016-11-10.
  sha256 551d1fe5…1a9cb. Source: indiafix.in → Google Drive RAR (same 2.8 MB file as t.me/schematicslaptop). chinafix.tech "pdf" is a 5-page teaser — ignore.
- `Dell-5580-LA-E151P-schematic.pdf` — old i7-U UMA board, 61 p. Page refs below still come from E151P; E152P page map: p2 block diagram,
  p3 PM/lane table, p6 CPU PEG, p16 PCH lanes, p20–21 PCH GPIO (DGPU_PWR_EN RH346/RH349), p29–33 Alpine Ridge + TPS65982, p35 WWAN,
  p37 M.2 Key M, p42–43 SATA/SSD, p47 KB/TP, p49–55 GM107 (N17M-Q3 / N16S-GT1-KA) + GDDR5, p56 ISL95857 VCC_CORE, p57 battery, p69 +VGA_CORE, p74 rev history.
  Differs from E151P: Alpine Ridge TBT (PCIe 5..8 from PCH) + PD, dGPU on CPU PEG x16, HDMI via DP-demux; M.2 Key M is PCH PCIe 9..12 (x4) or SATA-0A.

Order (cheapest / least risk first): B1 WWAN → B2 CPU tuning → B3 eGPU → B4 small stuff. B5 = never.

---

## B1 — WWAN modem (M.2 3042 B-key, JNGFF2, sch p.35)
Verified from schematic, not from forums — re-verified on E152P (p.37, p.48, p.39), see `recon/xeon/sch/m2-storage.md`:
- USB 2.0 (pin 7/9 → PCH USB2 port 8) populated. **USB 3.0 port 2 reaches the slot through `UZ29` PI3PCIE3212 mux** (SEL = `SLOT2_CONFIG_1`,
  low = USB3 for a modem, high = PCIE18 for an x2 SSD) and then through `@RZ1/@RZ2` 0 Ω drawn nopop on lane-1 TX → DMM; if open, modem = USB2 only (E152P p.37).
- PCIe lane 0 = PCIE17/SATA4: on E152P `CZ10/CZ11` are drawn **fitted** (no `@`, E151P had `@`); CLK_PCIE_P0/N0 + CLKREQ_PCIE#0 wired.
  Lane 1 = PCIE18 via `UZ29` → slot can do x2 PCIe (CONFIG state 1). Stock BIOS very likely keeps ports 17/18 off. Not needed for a modem (E152P p.37).
- Power: +3.3V_ALW (SY8288B, TDC 5.9 A) → UZ2 EM5209VF load switch (6 A cont., 20 mΩ) → `PJP41` pad "2.5A" (E152P p.48) → +3.3V_WWAN, enabled by EC `3.3V_WWAN_EN` (EC ball C6, E152P p.39)
  + `WWAN_PWR_EN` pin 6 (RZ43 47k pull-up). Bulk 2×47u + 22u on the rail. RM520N-GL peak ~2.5 A → fine.
- Sideband: WWAN_RADIO_DIS# (pin 8, DZ4 → EC), WWAN_WAKE# (pin 15), HW_GPS_DISABLE# (pin 20), SIM via push-push JSIM1 (pins 22–30),
  COEX1..3 no-stuff, SLOT2_CONFIG_0..3 → EC (STATE 8 = WWAN).
- Antennas: lid has 2 WWAN pigtails (main + aux) besides the 2 Wi-Fi ones → 2×2 MIMO. No dedicated GNSS antenna; RM520N-GL / EM9191
  share GNSS on an ANT port — GPS will be weak-to-none indoors, acceptable.

Plan:
B1.1 Pick module. Quectel RM520N-GL (5G, 3052, USB3 + PCIe) vs Sierra EM9191 (5G, 3042). 3052 needs the standoff moved 10 mm →
     check clearance under the palmrest before ordering; EM9191 is drop-in. Either way B-key, USB3 mode.
B1.2 Stock BIOS first: fit module, `lsusb` shows it, `mmcli -L`, `nmcli` connection with the SIM. Record in `recon/xeon/wwan.txt`.
     If the module is not powered: stock BIOS has no WWAN whitelist on 5x80, but `WWAN_PWR_EN` is EC-driven — check EC exposes it.
B1.3 coreboot: nothing beyond 4.6 (USB port map + EC GPIO for `3.3V_WWAN_EN`). Verify same `lsusb` on coreboot, add to checklist.
B1.4 NixOS: ModemManager + `networkmanager` WWAN profile, `qmi`/`mbim` mode per module. Optional: `ntp` from GNSS.
B1.5 (optional, only if a PCIe device is ever wanted in that slot) DMM `CZ10/CZ11` (drawn fitted on E152P) and `@RZ1/@RZ2`; solder only
     what is missing. Devicetree: ports 17 (+18 for x2) on, SRC0/CLKREQ#0. Not for the modem (E152P p.37).
Done when: modem works on coreboot after suspend/resume, W_DISABLE via rfkill.

## B2 — CPU tuning (E3-1505M v6, 45 W) — cooling first, then voltage
Bench tool already exists (`bench <tag>`, cells/wintermute/devshells.nix). Rule: every step = bench before / bench after, same charger,
same room; table in Progress of coreboot-5580.md. Baselines `bench-stock` (A.7) and `bench-coreboot` (5.7) come from the main plan.

B2.1 Cooling audit (stock coreboot, no UV): 10 min stress-ng → PkgTmp, throttle hits (`turbostat` Bzy_MHz drop), fan RPM via
     `dell-smm-hwmon`. If sustained all-core < 3.0 GHz base or PkgTmp > 90 °C → cooling is the bottleneck, do B2.2 before any UV.
B2.2 Cooling fixes, cheapest first, one at a time with a bench between:
     a) repaste (already at board swap — confirm), pads on VRM/M620 not dried;
     b) clean fan + fin stack, check the dual-heatpipe M620 heatsink is the one fitted (UMA single-pipe unit is the wrong part);
     c) fan curve: `i8kmon`/`dell-smm-hwmon` manual curve, louder but 5–10 °C;
     d) liquid metal on the bare die (Conductonaut) — foam dam, Kapton around, nickel heatsink only. Reported −10…−15 °C on 7820HQ.
        Point of no return for the heatsink, do last and only if a)–c) still throttle.
B2.3 Power limits in devicetree: PL1 45 W / PL2 60 W / Tau 28 s (Dell stock is 45/45ish). Only raise if B2.1 shows headroom.
B2.4 Undervolt in devicetree (FSP UPD / MSR 0x150 offsets): start −50 mV core+cache, `bench coreboot-uv`, 1 h stress + 1 h
     normal use. Step −10 mV until any WHEA/MCE/hang, back off 20 mV. Typical stable: −80…−125 mV on this die. GPU/SA offsets last.
B2.5 Runtime toggle: keep UV in firmware but add `intel-undervolt` as a NixOS service for A/B without reflash.
Done when: three-column table stock / coreboot / coreboot-uv filled, no throttling at 45 W sustained, 1 week daily use clean.

## B3 — eGPU via M.2 → OCuLink (no TB3)
Decision stands: PCIe 3.0 x4 from the M.2 2280 slot (~3.2 GB/s), not TB3 (shares 40 Gbps with 4K60 DP + USB + LAN behind WD19TB,
PCIe tunnel ≤22 Gbps, and TB3 under coreboot is the riskiest bit of 5.5).

B3.1 Parts: M.2 M-key → OCuLink SFF-8612 adapter board (ADT-Link / generic, ~15 CHF) + OCuLink cable 0.5 m + OCuLink eGPU dock
     with ATX/DA-2 input (Minisforum DEG1 class, ~100 CHF) + PSU (Dell DA-2 220 W is enough for a ≤200 W card; ATX for a 3090).
     Alternative if the OCuLink board doesn't fit under the palmrest: ADT-Link R43SG ribbon (wider, uglier).
B3.2 Routing: OCuLink cable out through the VGA opening — cut the D-SUB shell, no desoldering. Slot ~15×2 mm. Keep the VGA
     connector body as strain relief.
B3.3 Storage moves: NVMe leaves the M.2 slot → 2.5" SATA SSD with the 68 Wh 4-cell (chosen). Re-verified on E152P: KEYM = PCIE9..12 x4,
     bay = SATA2 (separate PCH port), no lane sharing (p.16, p.42, p.43). Not the 92 Wh + WWAN-slot NVMe path (needs coreboot for PCIE17/18,
     x1/x2, DMM `@RZ1/@RZ2`; no 5580/3520 precedent) — see `recon/xeon/sch/m2-storage.md`.
B3.4 Devicetree on that root port: CLKREQ off, ASPM off, hotplug off (cold-plug only). Verify `lspci -vv` link width x4 speed 8 GT/s.
B3.5 NixOS: nvidia (or nouveau) on the eGPU as primary for the 4K monitor (DP on the card), iGPU keeps the dock DP for a 2nd screen.
     PRIME offload config. Note the internal M620 stays disabled or as a 3rd GPU — decide when it's there.
B3.6 Bench: `bench coreboot` unchanged (CPU), plus a GPU line (glmark2 / a game) at 1080p and 4K; compare with the same card in a
     desktop x16 if possible to see the x4 tax.
Done when: cold-plug eGPU drives the 4K monitor, laptop still suspends/resumes with the cable unplugged.

## B4 — small, reversible
- Wi-Fi: M.2 2230 A+E, no whitelist → **Fenvi WF-M925-MPA1 (MediaTek MT7925B22M)**: Wi-Fi 7 2×2, 2.4/5/6 GHz, 320 MHz, BT 5.4,
  PCIe (not CNVio), `mt7925e` (kernel ≥ 6.10 stable), MHF4. ~30 CHF. Chosen over BE200 (Kaby Lake acceptance unverified) and
  QCNCM865 (`ath12k` immature). MT7927 = same on 2 antennas. Stock card has no WPA3 → do this early, no coreboot dependency.
  Regdom CH: 6 GHz lower band only (5945–6425) → `options cfg80211 ieee80211_regdom=CH`. Needs a 6E/7 router to matter.
- Antennas (lid, 4 pigtail slots total — 2 WLAN corners + 2 WWAN centre; that is all the routing room there is, 4×4 WWAN is not
  a thing in laptops): WLAN pair — **deferred until the router goes 6E/7**; stock pigtails are fine on 2.4/5 GHz, MT7925 goes in on
  them now. Then 2× FPC 2.4/5/6 GHz MHF4 (~8 CHF pair). WWAN pair — 2× FPC 600–6000 MHz MHF4 with the modem (B1), stock LTE ones
  ok for n78, weak on n77/n79. Either swap = same lid teardown as the panel; batch them with the panel if timing allows.
- RAM: 2×32 GB DDR4-2400 ECC SO-DIMM (Micron MTA18ASF4G72HZ-2G6B1ZI). Verify `edac` (A.5). Check 2×32 on CM238 before ordering.
- Screen: 30-pin eDP 2-lane, FHD only (no 4K SKU on 3520 — that's the 7520). Upgrade = brighter FHD IPS: **BOE NV156FHM-N61**
  (300 nit, 72 % NTSC, matte, 3.2 mm) — first pick; AUO B156HAN06.1 second. Drop-in, VBT unchanged. Glued with double-sided tape.
- Hinges: L/R differ, buy as a pair.
- Thermal: PTM7950 on CPU + GPU dies; Thermalright Odyssey 85×45 in 1.0 mm (M620 GDDR5) and 1.5 mm (VRM tab) — measure the
  old pads with calipers first, thicker-than-stock lifts the heatsink off the die. 2.0 mm only for the 3090 backside.
- Storage: NVMe→SATA adapters do not exist (PCIe ≠ AHCI; "M.2 to SATA" = M.2 SATA only). PC801 1 TB stays in the M.2 slot until
  OCuLink (B3) needs it. 2.5" bay: **Fanxiang S101 2 TB** (~182 CHF, YMTC TLC, DRAM-less, 7 mm; 870 EVO is 240/TB now) — official
  Fanxiang seller only, `smartctl -a` + `f3probe --destructive` on arrival. Needs the bay cable + caddy (non-SATA SKU ships without).
  ZFS: same layout as elster (ashift=12, autotrim=on, zstd, atime=off, weekly zpool-trim + scrub) plus `zfs.zfs_arc_max=8G`
  (elster runs c_max=61 GiB unlimited — set 12G there too). Second NVMe: WWAN slot takes 2242 B+M (x1, ~800 MB/s) but conflicts with B1.
- Battery: 68 Wh 4-cell (GJKNX) keeps the 2.5" bay → this is the one, given B3.3. 92 Wh (VG93N/NY5PG) only if eGPU plan is dropped.
- Keyboard: backlit unit drop-in; coreboot only needs the brightness key (4.3).
- Dock: WD19TB gives 130 W (180 W brick) — power + LAN + USB + kb/mouse. Barrel 130 W for travel.
- me_cleaner -S + HAP, own SB keys → lanzaboote: already in the main plan (4.7/5.6).
- TB3 NVM firmware: own SPI, Dell ships updates in the BIOS package. Under coreboot only `fwupd` if it lags; otherwise leave it.

## B5 — not worth it
- HDMI 2.0 rework: LSPCON pads exist on some revisions, no BOM. No.
- 4K internal panel: see B4. No.
- eGPU over TB3: see B3. No.
- EC firmware (battery whitelist, fan curve, PD): closed. Don't chase.

## Progress
- 2026-09: mods.md is the source of truth for B1/B3/B4 slot decisions (`cells/wintermute/recon/xeon/sch/mods.md`). It contradicts B1 "RM520N-GL ~2.5 A fine" (3.0 A vs `PJP41` 2.5 A → H, EM9191 preferred), B4 "30-pin eDP" (`JEDP1` 40-pin) and B5 "eGPU over TB3: No" (kept as fallback).
