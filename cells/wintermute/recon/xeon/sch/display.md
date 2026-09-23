# LA-E152P — Display: eDP / HDMI / DP demux / VGA / panel (Phase 7)

Source: `Dell-3520-LA-E152P-schematic.pdf` sha256 `551d1fe5…1a9cb`. `[visual]` = read on a 400–600 dpi render this session; `[text]` = pdftotext, net seen on ≥2 sheets.
Sheets: p.9 CPU DDI/eDP balls, p.25 PS8338 SW1, p.26 PS8338 SW2, p.27 HDMI (PS8407), p.28 DP→VGA (RTD2166), p.29 Alpine Ridge DP sinks, p.34 eDP connector + panel/backlight/camera/touch power, p.37 WLAN Key A DP pins, p.39 EC, p.16/p.17/p.19–21 PCH GPIO side.

## Who owns the pixels
- Every display output is driven by the CPU iGPU. The M620 has no display outputs: `IFPA..F` are NC and `DACA_*` is NC (see `dgpu.md`) (p.50, p.49). No eDP mux, no DDI mux to the dGPU anywhere on p.25–p.34 [visual] (p.9, p.34).
- The KBL-H display engine drives at most 3 independent displays (eDP + 2 external), whatever the connector count. https://www.intel.com/content/www/us/en/support/articles/000025675/graphics/processor-graphics.html (p.9).

## CPU display ports → connectors
| CPU port | balls | goes to | sideband (PCH) | cite |
|---|---|---|---|---|
| eDP | TXP/N0 D29/E29, TXP/N1 F28/E28, AUX C26/B26 | `JEDP1` (panel), AC caps `CV1..CV6` 0.1 µF on p.34 | HPD `EDP_HPD` → `GPP_I4` | [visual] p.9, p.34 |
| eDP lanes 2/3 | B29, A29, B28, C28 | `X` NC | - | [visual] p.9 |
| `EDP_DISP_UTIL` | A33 | `@T194` test pad | - | [visual] p.9 |
| DDI1 (DDPB), sheet label "HDMI" | `CPU_DP1_*` | `UV21` PS8407 retimer → `JHDMI1` | HPD `PCH_DP1_HPD` `GPP_I0`, DDC `PCH_DP1_CTRL_CLK/DATA` `GPP_I5/I6` | [visual] p.9, p.27 |
| DDI2 (DDPC), label "AR P0" | `CPU_DP2_*` | Alpine Ridge `DPSNK0` (USB-C DP-alt / TB3 DP) | HPD `PCH_DP2_HPD` `GPP_I1` | [visual] p.9, p.29 |
| DDI3 (DDPD), label "AR P1, WIGIG, VGA" | `CPU_DP3_*` | `UV8` PS8338 SW1 (demux, below) | HPD `PCH_DP3_HPD` `GPP_I2`, DDC `PCH_DP3_CTRL_CLK/DATA` `GPP_I9/I10` | [visual] p.9, p.25 |

## DDI3 demux tree (two PS8338 in series)
```
CPU DDI3 ─ CV65..74 ─ UV8 SW1 ─OUT1─ SW1_DP1_* ─ Alpine Ridge DPSNK1 (2nd TB3/USB-C stream)   (p.25, p.29)
                              └OUT2─ SW1_DP2_* ─ UV7 SW2 ─OUT1─ SW2_DP1_* ─ JNGFF1 WLAN Key A DP x4 (WiGig)  (p.26, p.37)
                                                        └OUT2─ SW2_DP2_* (x2) ─ UV6 RTD2166 ─ JCRT1 VGA        (p.26, p.28)
```
- Strap setting, the same on both chips: `CFG0` pulled high (`RV125` SW1, `RV85` SW2, 4.7 K to `+3.3V_RUN`), which selects automatic switching by HPD. `SW` has only a nopop pull-up (`@RV126`, `@RV89`), so it sits low from the internal PD: OUT1 wins when both outputs are plugged [visual] (p.25, p.26).
  Sheet notes: SW1 "Priority : AR -> WIGI/VGA(PS8338)", SW2 "Priority : WIGI -> VGA" [visual] (p.25, p.26).
- `PEQ` has both `RV55`/`RV56` (SW1) and `RV79`/`RV80` (SW2) fitted at 4.7 K, which puts it at mid level = "LLEQ", 8.5 dB. The `P0` net (pin 60) is pulled high by `RV127`/`RV95`, which disables auto EQ. Both follow the sheet note "vendor suggest MUX use LLEQ PEQ=M and PI0=H". `I2C_CTL_EN` (net `P1`, pin 1) has both pulls nopop, so the chips are pin-controlled and not on any I2C bus. `PC10..PC21` pulls are all `@` [visual] (p.25, p.26).
- Nothing drives the demux from software: `SW1_PS8338_SW`/`SW2_PS8338_SW` appear only on their own sheet [text] (p.25, p.26). The only thing that switches it is which sink raises HPD.
- Consequence: VGA gets a picture only when the second TB3/USB-C DP stream is unplugged and no WiGig card is asserting HPD. VGA uses only 2 lanes (`SW2_DP2_P/N0..1`) (p.28).
- `SW2` OUT2 AUX pull pair `RV71`/`RV77` fitted; `SW1` OUT2 AUX pulls `@RV129`/`@RV133` nopop, which is fine because that output is a chip-to-chip link [visual] (p.25, p.26).

## HDMI (DDI1)
- `UV21` PS8407A retimer/level shifter. Straps: `HDMI_EQ` `RV41` PU fitted → "H: EQ for loss up to 4.3 dB"; `HDMI_BUF` `@RV39/@RV40` both nopop → passive DDC pass-through; `I2C_CTL_EN` `@RV43/@RV44` nopop → pin control with auto jitter cleaning; `HDMI_PRE` `RV47` PU fitted; `HDMI_ISET` `@RV45/@RV46` nopop [visual] (p.27).
- Supply `+VHDMI_VCC` from `UV2` AP2330W load switch on `+5V_RUN`. `HDMI_CEC` has only `@RV19` 10 K PU (nopop), so CEC is not wired in practice [visual] (p.27).
- HDMI 1.4 only: PS8407 is a TMDS level shifter with no LSPCON, so the Intel article caps this at 4096×2160@24 / 2560×1600@60 (p.27).

## VGA
- `UV6` RTD2166 DP→VGA bridge on `SW2_DP2` x2, powered `+3.3V_VGA`/`+VDD_DAC_33` from `+3.3V_RUN` through 60 Ω beads; `+CRT_VCC` from `+5V_RUN` via `UV4` [text] (p.28).
- Removing VGA (ties to `dgpu.md` 3.3 idea) frees **no PCIe**. The bridge sits on DP lanes behind two demuxes, and the space is the RTD2166 + `JCRT1` corner of p.28 only (p.28, p.26).

## Internal panel connector `JEDP1`
ACES 50398-04041-001, 40 pin, `CONN@` [visual] (p.34). Pinout as drawn; cap notes "Close to JEDP1.17~19 / 30~31 / 11 / 1 / 10" confirm the rail pins:

| pin | net | pin | net |
|---|---|---|---|
| 1 | `+5V_TSP` (touch 5 V) | 21 | `BIA_PWM` via `EMI@LV1` BLM15PX221 |
| 2 / 3 | `USB20_N9_R` / `USB20_P9_R` (touch, USB2 port 9, `LV27` EMI) | 22 | `DISP_ON` (backlight enable) |
| 5 | `TOUCH_SCREEN_PD#` ← `GPP_E7` | 26 | `EDP_HPD` → `GPP_I4` (`@RV7` 100 K PU nopop) |
| 7 / 9 | `DMIC0` / `DMIC_CLK0` (to codec p.38) | 29 | `LCD_TST` ↔ EC `GPIO051` (BIST) |
| 10 | `+3.3V_RUN` | 30–31 | `+LCDVDD` (panel logic) |
| 11 | `+3.3V_CAM` | 32 | `TOUCH_SCREEN_DET#` → `GPP_B4` |
| 12 / 13 | `USB20_N11_R` / `USB20_P11_R` (camera, USB2 port 11, `LZ1` EMI) | 33 / 34 | `EDP_AUXN_C` / `EDP_AUXP_C` |
| 14 | `CAM_MIC_CBL_DET#` → `GPP_G0` | 35–38 | `EDP_TXP0`, `TXN0`, `TXP1`, `TXN1` (`_C`, after `CV1..CV6`) |
| 17–19 | `+BL_PWR_SRC` (backlight supply) | 40 | `LCD_CBL_DET#` → `GPP_C14` |

Remaining pins are GND or NC. There are no eDP lane 2/3 pins [visual] (p.34). Separate `JIR1` 6-pin ACES 50208-0060N for an IR camera, `IR_CAM_DET#` → `GPP_D19` [text] (p.34, p.20).
- Dell only lists HD / FHD / FHD-touch panels for the 3520, which matches eDP x2 https://www.dell.com/support/manuals/en-us/precision-15-3520-laptop/prec3520_om_pub/display-options?guid=guid-99e028b7-a569-4a9f-8d89-f1c22bb53f37&lang=en-us (p.34).

## Panel power, backlight: nets coreboot and EC touch
All [visual] on p.34; EC balls [visual] p.39; PCH pads from `gpio.md` [visual] p.16/p.17/p.21.

| function | chain | driven by | cite |
|---|---|---|---|
| Panel VDD | `UV24` G524B1T11U load switch: VIN `+3.3V_ALW` → VOUT `+EDP_VDD` → `PJP12` pad → `+LCDVDD`; EN = `EN_LCDPWR`, `RV3` 100 K PD | `DV3` BAT54CW diode-OR of `ENVDD_PCH` (PCH `GPP_F19` = EDP_VDDEN, NF1) and `LCD_VCC_TEST_EN` (EC `GPIO226`) | p.34, p.16, p.39 |
| Backlight supply | `QV1` AO6405 P-FET `+PWR_SRC` → `+BL_PWR_SRC_P` → `PJP13` pad → `+BL_PWR_SRC`; gate `BL_PWR_SRC_ON` held off by `RV4` 270 K, pulled on via `RV5` 47 K by `QV2` 2N7002 | EC `EN_INVPWR` (MEC5105 ball B2, `GPIO023`) **only** | p.34, p.39 |
| Backlight enable | `DV2` BAT54CW OR → `DISP_ON`, `RV2` 4.7 K PD | `PANEL_BKEN_PCH` (`GPP_F20` = EDP_BKLTEN, NF1) OR `PANEL_BKEN_EC` (EC ball J9, `GPIO015/PWM7`) | p.34, p.16, p.39 |
| Backlight PWM | `DV1` BAT54CW OR → `BIA_PWM`, `RV1` 4.7 K PD | `BIA_PWM_PCH` (`GPP_F21` = EDP_BKLTCTL, NF1) OR `BIA_PWM_EC` (EC ball N1, `GPIO001/PWM4`) | p.34, p.16, p.39 |
| Camera 3.3 V | `QZ1` LP2301 P-FET `+3.3V_RUN` → `+3.3V_CAM` | `3.3V_CAM_EN#` = `GPD7`, active low | p.34, p.17 |
| Touch 5 V | `QV8` LP2301 P-FET `+5V_RUN` → `+5V_TSP`, gate `RV6` 47 K PU, pulled low by `QV7` 2N7002 | `3.3V_TS_EN` = `GPP_B21` (active high) | p.34, p.21 |
| Current sense | `@RZ90`/`@RZ93` 10 mΩ shunts + `@RZ91/92/94/95` `BL_PWR_*`/`LCDVDD_PWR_*` `<48>` all nopop; the `PJP` pads carry the current | - | p.34 |

- The p.56 block diagram names the LCDVDD switch "AP2821K"; the sheet has `UV24` G524B1T11U. This is the same stale-BOM pattern as `power.md` (p.56, p.34).
- Diode-OR means either the PCH or the EC can light the panel. **Backlight supply has no PCH path.** If the Dell EC firmware does not assert `EN_INVPWR`, `DISP_ON`/`PWM` from the iGPU produce a black panel with a live eDP link (p.34).

### coreboot duties (feeds coreboot-5580 Phase 4, gfx)
- `gpio.c`: `GPP_F19/F20/F21` NF1 (eDP VDDEN/BKLTEN/BKLTCTL); `GPP_I0/I1/I2/I4` NF1 HPD; `GPP_I5/I6/I9/I10` NF1 DDC; `GPP_B21` GPO high when touch is wanted; `GPP_E7` GPO high (touch not powered down); `GPD7` GPO **low** (camera on); `GPP_C14`, `GPP_G0`, `GPP_D19`, `GPP_B4` GPI (p.16, p.17, p.19, p.21).
- DDI presence straps `GPP_I6` (`RH223`), `GPP_I8` (`RH221`), `GPP_I10` (`RH225`) have 2.2 K pull-ups, so DDPB/C/D are all detected as present (see `gpio.md`) (p.21).
- Devicetree/VBT: eDP x2 (max HBR2), DDPB = HDMI (through a level shifter, so libgfxinit type HDMI), DDPC/DDPD = DP. `EN_INVPWR` stays EC business: Dell EC firmware lives in `UC5` next to the BIOS (`spi-ec.md`), so coreboot does not have to drive it. Check backlight-on-first-boot as an explicit test item (p.34, p.39).

## eGPU and the image path
- Hard wiring: the eDP lanes go CPU → `JEDP1` directly with no mux, and the board has no DP input. An eGPU cannot drive the internal panel electrically; it can only reach it by copying frames over PCIe to the iGPU (PRIME display offload / Windows Optimus-style copy) (p.9, p.34).
- The copy costs bandwidth on the same x4 link that feeds the eGPU. egpu.io measurements: internal display runs about 20–35 % slower than an external monitor on the eGPU over TB3 x4 https://egpu.io/performance-internal-vs-external-display (p.29).

## What fits here
FIT: eGPU (TB3 or OCuLink) → external monitor plugged into the eGPU card | needs: monitor on the eGPU's own DP/HDMI | lanes/bus: full x4 Gen3 for render traffic, no frame copy back | power: n/a (eGPU PSU) | displaces: nothing; the internal panel stays on the iGPU | DIY: https://egpu.io/performance-internal-vs-external-display | risk: L (p.9, p.34)
FIT: eGPU → internal panel via PRIME display offload (Linux) / Optimus copy (Windows) | needs: iGPU enabled, `modesetting` + NVIDIA/AMD offload setup (ArchWiki External GPU) | lanes/bus: frames return over the same PCIe x4 (TB3 PCH RP5–8 or KEYM RP9–12) | power: n/a | displaces: ~20–35 % eGPU fps vs external screen | DIY: https://egpu.io/performance-internal-vs-external-display, https://wiki.archlinux.org/title/External_GPU | risk: L (p.9, p.34)
FIT: eGPU DP output wired straight into the panel (cut eDP cable, DP→eDP converter board) | needs: DP→eDP bridge board + cable surgery; laptop loses its own panel control (`DISP_ON`/`BIA_PWM`/`+BL_PWR_SRC` must be re-supplied) | lanes/bus: eDP x2 panel | power: `+LCDVDD` 3.3 V + `+BL_PWR_SRC` (`+PWR_SRC`) must come from the new board | displaces: iGPU panel, lid cable | DIY: none found | risk: H (p.34)
FIT: nothing — M620 as display adapter for any port: `IFPA..F`/`DACA` NC, no mux on DDI/eDP | DIY: none found — schematic alone proves it | risk: - (p.50, p.9)
FIT: nothing — freeing PCIe by removing VGA: `UV6` RTD2166 is on DDI3 DP lanes behind SW1/SW2, and no PCIe lane passes through p.25–p.28 | DIY: none found — schematic alone proves it | risk: - (p.28, p.26)
FIT: extra DP monitor from the WLAN Key A slot (`SW2_DP1` DP x4 on `JNGFF1`) through an M.2-Key-A→DP breakout | needs: Key A DP breakout board (WiGig pinout); nothing else asserting HPD on SW2 OUT1 | lanes/bus: DDI3 via SW1 OUT2 → SW2 OUT1, x4 | power: `+3.3V_WLAN` `PJP36` "2A" (breakout draws ~0) | displaces: Wi-Fi card in `WLAN` and the second TB3 DP stream (SW1 gives AR priority) | DIY: none found (Dell documents the slot as "Key A with 1-DP pinout ... WiGig Audio/Video DP v1.2" https://manualslib.com/manual/1091495/Dell-Latitude-7000-Series.html?page=53) | risk: H (p.26, p.37)
FIT: FHD 120/144 Hz 40-pin eDP panel (touch pinout) | needs: panel with the same 40-pin Dell-touch pinout and eDP x2 at HBR2; 1080p144 CVT-RB ≈ 7.7 Gb/s fits under x2 HBR2 8.64 Gb/s | lanes/bus: eDP x2 (lanes 2/3 NC) | power: `+LCDVDD` from `UV24` on `+3.3V_ALW` | displaces: stock panel | DIY: none found for 3520/5580 | risk: H (pinout per panel model) (p.9, p.34)
FIT: nothing — 4K UHD internal panel: eDP lanes 2/3 are NC at the CPU and have no pins on `JEDP1`; UHD60 needs x4 HBR2 | DIY: none found — schematic alone proves it | risk: - (p.9, p.34)
