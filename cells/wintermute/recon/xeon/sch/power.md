# LA-E152P — power tree, charger, batteries (Phase 6)

Source: `Dell-3520-LA-E152P-schematic.pdf` sha256 `551d1fe5…1a9cb`. `[visual]` = read on a 300–400 dpi render this session; `[text]` = pdftotext, net seen on ≥2 sheets.
Sheets: p.56 power-sequence block diagram, p.57 DC-in + battery connector, p.58 `+3.3V_ALW`/`+5V_ALW`, p.59 DDR, p.60 `+1.0V_PRIM`, p.61 `+1.0VS_VCCIO`, p.62 small LDO/bucks, p.63–65 CPU VR, p.66 charger, p.48 load switches, p.31 PD 5 V source, p.69–70 GPU rails.
No E151P-style "Power Tree" page with loads exists on E152P. p.56 is a block diagram with a stale BOM (it names ISL95857 and RT8207MZ, but the sheets use ISL95855 and SY8210A). The rail table below is built from the TDC boxes on each regulator sheet (p.56, p.59, p.63).

## Rail table (regulator → TDC / peak / OCP)
| rail | regulator | from | TDC / peak / OCP | enable | main loads | cite |
|---|---|---|---|---|---|---|
| `+3.3V_ALW` | `PU100` SY8288BRAC, `PL100` 1.5 µH 9 A; LDO out `+3.3V_RTC_LDO` 150–300 mA | `+PWR_SRC` | 6.8 / 9.7 / 11.6 A, Vout 3.234–3.366 V | `3V5V_EN`/`ENLDO_3V5V` | EC, `UZ2` (WWAN+LAN), `UZ3` (`+3.3V_ALW_PCH`, `+3.3V_RUN`), `UZ4` ch2 (WLAN), PD `+3.3V_VDD_PIC` side, TPM | [visual] p.58, p.48 |
| `+5V_ALW` | `PU102` SY8288CRAC, `PL101` 2.2 µH 7.8 A | `+PWR_SRC` | 5.4 / 7.7 / 9.2 A | same | `UZ4` ch1 `+5V_RUN`, `UZ23` `+5V_HDD`, PD `PP_5V0` (Type-C source) via `PJP8`, VR drivers, load-switch VBIAS | [visual] p.58, p.31, p.48 |
| `+VCC_CORE` | `PU601` ISL95855AHRTZ + 2 phases `PU610`/`PU611` CSD97396Q4M, `PL610/611` 0.15 µH 37 A | `+PWR_SRC` | 50 / 68 / 81.6 A | `IMVP_VR_ON` (EC) | CPU cores | [visual] p.64, [text] p.63 |
| `+VCC_GT` | same controller, 2 phases `PU612`/`PU613` CSD97396Q4M | `+PWR_SRC` | 25 / 55 / 66 A | same | iGPU (P630) | [visual] p.65 |
| `+VCC_SA` | same controller, 1 phase `PU614` ISL95808 + `PQ614` AON6994, 0.47 µH 12 A | `+PWR_SRC` | 10 / 11.1 / 13.32 A | same | system agent | [visual] p.65 |
| `+1.2V_DDR` + `+0.6V_DDR_VTT` | `PU200` SY8210A, `PL201` 1 µH 11 A | `+PWR_SRC` | 5.6 / 8 / 9.5 A; VTT 0.007 A / OCP 2 A | `SIO_SLP_S4#`, `0.6V_DDR_VTT_ON` | DIMMs | [visual] p.59 |
| `+1.0V_PRIM` | `PU301` SYX198D, 0.68 µH 7.9 A | `+PWR_SRC` | 5 / 7.2 / 8.6 A | `SIO_SLP_SUS#` | PCH primary | [visual] p.60 |
| `+1.05V_PRIM` | `PU1600` SYX198D | `+PWR_SRC` | 3 / 3.6 / 4.32 A | - | PCH (loads not traced) | [visual] p.72 |
| `+1.0VS_VCCIO` | `PU401` (part not in text layer), `PL401` 1 µH 4.5 A | `+5V_ALW`/`+3.3V_ALW` | 3.9 / 5.5 / 6.6 A | `RUN_ON` | CPU VCCIO | [visual] p.61 |
| `+1.8V_PRIM` | p.62 buck | `+3.3V_ALW` | Imax 2 A, Ipeak 3 A | `SIO_SLP_SUS#` | PCH 1.8 V | [text] p.62 |
| `+2.5V_MEM` / `+1.2V_RUN` | `AP7361C` LDO, `RT8097A` | `+3.3V_ALW`/`+3.3V_RUN` | 0.896 / 0.4 / 0.3 A TDC | - | DDR VPP, misc | [text] p.62 |
| `+GPU_CORE` | RT8813A, see `dgpu.md` | `+PWR_SRC` | 26.5 / 53 / 63.6 A | GPU `3V3_MAIN_EN` | M620 | [text] p.69 |
| `+1.35V_MEM_GFX` | `PU1400` SY8210A (sheet title says SYX198D, IC symbol says SY8210AQVC) | `+PWR_SRC` | 9 / 12 / 14.4 A | `VRAM_EN` | GDDR5 | [text] p.70 |

The "8A 12A 16A" tables on p.59/p.60/p.70/p.72 are the SY8210A/SYX198D `ILMT` current-limit options for those bucks. They are not a charger ILIM strap (p.59, p.70).

## Load switches (p.48) — pad labels are the design current of the `PJP` jumper, not a measured load
| rail | switch / channel | in | pad, label | enable | cite |
|---|---|---|---|---|---|
| `+3.3V_WWAN` | `UZ2` EM5209VF ch1 | `+3.3V_ALW` | `PJP41` "2.5A" | `3.3V_WWAN_EN` (EC) | [visual] p.48 |
| `+3.3V_LAN` | `UZ2` ch2 | `+3.3V_ALW` | `PJP37` "1A" | `SIO_SLP_LAN#` | [text] p.48 |
| `+3.3V_ALW_PCH` | `UZ3` ch1 | `+3.3V_ALW` | `PJP38` "1.102A" | `@RZ65` `PCH_ALW_ON` / `@RZ64` `SIO_SLP_SUS#`, both drawn nopop (one must be fitted) | [visual] p.48 |
| `+3.3V_RUN` | `UZ3` ch2 | `+3.3V_ALW` | `PJP39` "4.677A" | `RUN_ON` | [text] p.48 |
| `+5V_RUN` | `UZ4` ch1 | `+5V_ALW` | `PJP40` "3.076A" | `RUN_ON` | [visual] p.48 |
| `+3.3V_WLAN` | `UZ4` ch2 | `+3.3V_ALW` | `PJP36` "2A" | `@RZ71` `SIO_SLP_WLAN#` / `@RZ70` `AUX_EN_WOWL` | [visual] p.48 |
| `+1.8V_RUN` | `UZ8` AOZ1336 | `+1.8V_PRIM` | `PJP42` "0.025A" | `RUN_ON` | [text] p.48 |
| `+3.3V_HDD_M2` (KEYM) | none, `PJP31` straight off `+3.3V_RUN` | `+3.3V_RUN` | "2.8A" | = `RUN_ON` | [visual] p.42 (Phase 5) |
| `+5V_HDD` (bay) | `UZ23` AOZ1336 | `+5V_ALW` | `PJP32` "1.5A" | `HDD_EN` = `GPP_C15` | [visual] p.43 (Phase 5) |
| Type-C source `PP_5V0` | TPS65982 internal switch | `+5V_ALW` → `PJP8` PAD-OPEN 1x3m → `+5V_ALW_PDA` | - | PD firmware | [visual] p.31 |
- EM5209VF: 6 A continuous, 8 A peak, 20 mΩ per channel (datasheet `web.excelliancemos.com/datasheet/IC/EM5209.pdf`). The switch is never the bottleneck; the upstream buck TDC is (p.48).
- Correction to `m2-storage.md`: the WLAN pad is `PJP36` "2A", not `PJP38`. `PJP38` is `+3.3V_ALW_PCH` [visual] (p.48). Also seen: `@UZ25` MAX34407 power monitor on the WLAN/LCD/HDD/backlight rails with `@RZ96` 0.01 Ω shunts, "BR15H Only" = nopop here (p.48).
- `+3.3V_ALW` budget: the pad labels hanging off it add up to 2.5 + 1 + 1.102 + 4.677 + 2 = 11.3 A against a 6.8 A TDC buck. Compal sized each pad for its own worst case, and they never all peak at once. Any added load comes out of the 6.8 A TDC, and the WWAN is the biggest single consumer (p.58, p.48).

## DC-in and adapter ID (p.57)
- Barrel: cable connector `CVILU CI0805M1HRC-NH`. `+DCIN_JACK` → `EMC@PL4` bead → `PQ9` AON7409 (S1) → `+DC_IN_SS` → `PQ4` AON7409 (S2, back-to-back) → `+SDC_IN`; `PD5` 5 A/100 V diode across S2. `-DCIN_JACK` goes **straight to GND** [visual] (p.57).
- S1 gate: `PQ6` 2N7002 ← `PU1` MC74VHC1G08 AND(`ACAV_IN_NB`, `DCIN2_EN` via `PQ8`). S2 gate: `PQ5` AO3409 ← `PQ1A/B` DMN65D8LDW ← `AC_DISC#`; `PQ7` ← `VBUS2_ECOK` `<40,68>`. The logic runs from `+3.3V_VDD_DCIN` = `PU2` AP2204RA-3.3 LDO off `+DC_IN` [visual] (p.57). The EC chooses barrel or Type-C; both feed `+SDC_IN` (Type-C path in `tb3.md`, p.68).
- PSID: jack `NB_PSID` → `PD4` PESD5V0U2BT → `EMC@PL3` bead → `PQ2` FDV301N pass FET → `PR5` 33 Ω → `PS_ID` `<39>` (EC 1-wire). `PQ2` gate has `PR7` 10 K to `+5V_ALW`, pulled down by `PQ3` MMST3904. `PQ3`'s base is fed by the `PR6` 100 K / `PR8` 15 K divider off `NB_PSID`, so a PSID pin shorted to 19.5 V opens `PQ2` and protects the EC. `@PR3` 0 Ω bypass nopop [visual] (p.57).
- So the adapter wattage is **firmware**: EC reads the DA-2-style 1-wire ID and programs the charger over SMBus. No resistor on the board encodes 90/130/180 W (p.57, p.66).
- Battery connector `PBATT1` DEREN 40-42251-01001RHF: `PBAT_SMBCLK/DAT/PRES#` through `PRP1` 100 Ω 8P4R to `PBAT_CHARGER_SMB*` `<39,66>`; `PBAT_PRES#` also goes to charger `BATGONE` (`PR931` 100 K). RTC cell `JRTC1` via `PD3` BAS40CW OR `+3.3V_RTC_LDO` [visual] (p.57, p.66).

## Charger (p.66)
- `PU901` **ISL88738HRTZ-T** TQFN32 (Dell custom; sheet title "PWR_CHARGER_ISL9237 (Colay)" = ISL9237 footprint-compatible). NVDC buck-boost [visual] (p.66).
- Input: `+SDC_IN` → `PR901` 0.01 Ω 1206 (Rs1 = 10 mΩ, `CSIP/CSIN` via `PR909/PR910` 3.3 Ω) → `+PWR_SRC_AC` → `EMC@PL901` **1 µH 6.6 A** in series (`@PJP901` 4×4 mm bypass pad nopop) → `+CHARGER_SRC` → system `+PWR_SRC` [visual] (p.66).
- Power stage `PQ905`/`PQ904` CSD87351Q5D, `PL902` 1 µH 18 A; battery sense `PR917` 0.005 Ω (Rs2) `LX2` → `+VCHGR`; `PQ906` AON7409 BGATE `+VCHGR` ↔ `+PBATT` [visual] (p.66).
- `PROG` (pin 27) → `PR932` **105 K** 1 % → GND [visual]. ISL9237 Table 18 has 102 K (2-cell, 733 kHz, 0.476 A) and 115 K (2-cell, 733 kHz, 1.5 A). 105 K falls in neither window, so this is an ISL88738 code, and its meaning is not public. It only sets the power-on default; the EC overwrites it (p.66; https://www.renesas.com/en/document/dst/isl9237-datasheet).
- **No ILIM strap.** The input current limit is the `AdapterCurrentLimit1/2` SMBus register. With Rs1 = 10 mΩ the ISL9237 register tops out at 12.16 A (datasheet Table 5). The EC writes it after reading PSID (p.66).
- SMBus to charger: `SDA`/`SCL` via `@PR920`/`@PR922` 0 Ω, **drawn nopop** [visual]. Same stale-BOM pattern as `RH10..17` / `@RZ1/2`. A charging board must have them fitted → DMM (p.66).
- `PROCHOT#` → `@PR926` → `H_PROCHOT#` `<7,39,63>`; `PROCHOT#_ISL88738` also → p.68 (Type-C). `PSYS` → `@PR936` → `I_SYS` `<39,63>` (to EC and to the CPU VR PSYS input). `ACIN` ← `PR944` 442 K / `PR945` 100 K divider from `+SDC_IN` side, 0.8 V threshold → ~4.3 V [text] (p.66, datasheet ACIN_r 0.8 V).
- **Ceiling = `PL901` rated 6.6 A** (inductor rating, not a fuse). At 19.5 V that is 129 W, exactly the 130 W brick. A 180 W brick (9.23 A) or 20 V/6.5 A Type-C both hit `PL901` / the 2 × 5 A Type-C beads, not the charger IC (p.66, p.68).

## CPU VR ceiling (for backlog B2)
- `+VCC_CORE` 2-phase, TDC 50 A, peak 68 A, OCP 81.6 A. At ~1.0 V that is ≈50 W sustained into the cores alone, above the 45 W TDP, so PL tuning in B2 hits the cooler before the VR (p.64).
- `+VCC_GT` 25 / 55 A, `+VCC_SA` 10 A (p.65). IccMax programmed by BIOS/coreboot must not exceed 68 / 55 / 11.1 A (peak) for core / GT / SA (p.64, p.65).

## Ground topology (for eGPU with its own PSU)
- Barrel `-DCIN_JACK` → board GND directly; adapter current is sensed high-side (`PR901` between `+SDC_IN` and `+PWR_SRC_AC`), battery high-side (`PR917`). **No ground-return shunt** that a second ground path could bypass [visual] (p.57, p.66).
- So bonding the eGPU PSU ground to laptop GND through the PCIe/OCuLink cable's ground pins does not corrupt charger sensing. The only issue is ordinary ground loop / potential difference between two mains supplies. Both bricks go on one power strip, and the eGPU PSU is powered before the laptop (p.57, p.66).

## Power verdict per Phase 4–5 FIT
| FIT (file) | rail, budget | draw (source) | verdict |
|---|---|---|---|
| NVMe 2 TB in KEYM (m2-storage) | `+3.3V_HDD_M2` "2.8A" ← `+3.3V_RUN` "4.677A" ← `+3.3V_ALW` 6.8 A TDC | M.2 M-key SSDs stay within the 3.3 V socket budget; 970-class is the stock config | OK, risk unchanged L (p.42, p.48) |
| M.2 → OCuLink eGPU in KEYM (m2-storage) | same pad | adapter draws only redriver/detect logic from 3.3 V; GPU on own PSU | OK; ground bonding fine (see above), risk unchanged M (p.42, p.57) |
| 2.5" SATA SSD in bay (m2-storage) | `+5V_HDD` "1.5A" via `UZ23` ← `+5V_ALW` 5.4 A TDC | 2.5" SATA SSD; datasheet not checked, SATA SSDs are well under 1.5 A at 5 V | OK, L (p.43, p.58) |
| RM520N-GL in WWAN (m2-storage) | `+3.3V_WWAN` `PJP41` "2.5A", `UZ2` 6 A, buck 3.234 V min | Quectel HW design: supply "continuous current capability 3.0 A at least", VCC min 3.135 V; max average 1512 mA (LTE CA) | **exceeds pad label (3.0 > 2.5 A) → risk H.** Averages fit; the margin is voltage: 3.234 V − 3 A × 20 mΩ = 3.17 V vs 3.135 V (p.48, p.58) |
| EM9191 in WWAN (m2-storage) | same | "up to 2.7 A" at 3.3 V (everythingrf spec page) | **exceeds 2.5 A label → risk H**, same voltage margin (p.48) |
| 2242 NVMe / SATA / 2.5 GbE in WWAN (m2-storage) | same | no module datasheet checked | already H; power adds nothing new (p.48) |
| MT7925 in WLAN (m2-storage) | `+3.3V_WLAN` `PJP36` "2A" | BL-M7925BP1 module sheet "3.3 V ± 0.2 V @ 500 mA (max)" (same listing also says 1500 mA) | OK either way, L (p.48) |
| BE200 in WLAN (m2-storage) | same | no figure found | unchanged M (p.48) |
| eGPU on TB3 direct / via WD19TB (tb3) | self-powered enclosure; laptop only sources `PP_5V0` from `+5V_ALW` if the device asks | 0 for enclosure | OK (p.31) |
| 10/2.5 GbE bus-powered TB3 adapter (tb3) | `PP_5V0` ← `PJP8` ← `+5V_ALW` 5.4 A TDC, shared with `+5V_RUN` 3.076 A + `+5V_HDD` 1.5 A + USB-A | 15 W = 3 A at 5 V | fits alone; with SATA SSD + USB-A loads it eats most of `+5V_ALW` → risk M (p.31, p.58) |
| WD19TB 130 W as only source (tb3) | Type-C 2 × 5 A beads → `+SDC_IN` → `PR901` → `PL901` 6.6 A | 20 V × 6.5 A = 130 W, 6.5 A | fits under `PL901` by 0.1 A, L (p.68, p.66) |
| dGPU forced off (dgpu) | frees `+GPU_CORE` (26.5 A TDC), `+1.35V_MEM_GFX` (9 A) off `+PWR_SRC` | - | saves adapter headroom for charging while an eGPU runs, L (p.69, p.70) |

## DMM list added by this phase
`@PR920`/`@PR922` (charger SMBus), `@PR936` (PSYS → EC/VR), `@PR926` (charger PROCHOT#), `@RZ64`/`@RZ65` (`+3.3V_ALW_PCH` enable) (p.66, p.48).

## What fits here
FIT: Dell 180 W barrel adapter (Precision 3520/7520 listed) | needs: nothing | lanes/bus: n/a | power: adds **no** power over 130 W: `EMC@PL901` 1 µH 6.6 A in series on the charger input = 129 W at 19.5 V; charger register could go to 12.16 A with the 10 mΩ `PR901`, but EC/PSID policy and `PL901` cap it | displaces: 130 W brick | DIY: https://kur.lt/documents/catalog/1176424/other-digital-assets-575c856851d24ce6312206a96d2e59e7.pdf (third-party 180 W listed for Precision 3520), https://www.dell.com/support/manuals/en-us/precision-15-3520-laptop/precision_3520_om/ac-adapter-specifications?guid=guid-fa153a26-f678-47b4-bc89-be48b3764977&lang=en-us (Dell lists only 65/90/130 W) | risk: L (harmless, pointless) (p.66, p.57)
FIT: RM520N-GL on `+3.3V_WWAN` power-wise | needs: nothing to fit; if drops/resets under TX appear, bench-measure `+3.3V_WWAN` at the slot during an upload | lanes/bus: see m2-storage | power: `PJP41` "2.5A" < Quectel's 3.0 A continuous requirement; average ≤ 1.51 A; VCC floor 3.135 V vs ~3.17 V at 3 A | displaces: - | DIY: https://forums.quectel.com/uploads/short-url/1zkjPRnxF5BZ2woox386baCZx4g.pdf (RM520N-GL HW design, 3.0 A / 3.135 V) | risk: H (p.48, p.58)
FIT: Sierra EM9191 on `+3.3V_WWAN` power-wise | needs: same bench check | lanes/bus: see m2-storage | power: up to 2.7 A > 2.5 A pad label | displaces: - | DIY: https://www.everythingrf.com/products/cellular-modules/sierra-wireless/811-908-em9191 (3.3 V, up to 2.7 A) | risk: H (p.48)
FIT: eGPU PSU (OCuLink/M.2 adapter) sharing ground with the laptop | needs: both bricks on one power strip, eGPU PSU on before laptop boot | lanes/bus: n/a | power: laptop GND = barrel `-DCIN_JACK` directly, all current sense high-side (`PR901`, `PR917`) → no sense path bypassed | displaces: - | DIY: https://egpu.io/forums/expresscard-mpcie-m-2-adapters/help-m-2-egpu-adt-link-r43sg-with-2014-macbook-pro-problem/ (R43SG power-on order) | risk: L (p.57, p.66)
FIT: CPU PL/IccMax tuning (backlog B2) within VR limits | needs: coreboot or BIOS PL1/PL2; IccMax ≤ VR peak | lanes/bus: SVID | power: `+VCC_CORE` 2-phase TDC 50 A / peak 68 A / OCP 81.6 A; GT 25/55 A; SA 10/11.1 A | displaces: - | DIY: none found — schematic alone (TDC boxes printed on the sheets) | risk: L (p.64, p.65)
