# LA-E152P — dGPU (GM107 / Quadro M620) and CPU PEG (Phase 3)

Source: `Dell-3520-LA-E152P-schematic.pdf` sha256 `551d1fe5…1a9cb`. `[visual]` = read on a 300 dpi render (crops upscaled 2–3×) this session; `[text]` = pdftotext, net seen on ≥2 sheets.
Sheets: p.6 CPU PEG, p.49 GPU PCIe/GPIO/I2C, p.50 GPU DP/straps, p.51 GPU power pins, p.53 GPU memory + GPU power switches, p.69 `+GPU_CORE`, p.70 `+1.35V_MEM_GFX`, p.19/p.21/p.16/p.18 PCH side, p.40 GPIO expander, p.74 rev history.

## GPU identity
- `UV1` `GM107-ES-A1_BGA908`, board option `N16S` (GT1-KA), 2 GB GDDR5 (2 pcs x32, Samsung `K4G80325FB-HC03` strap 0x8 marked as the fitted part) [visual] (p.49, p.50).
- No display output: `IFPA..IFPF` (all LVDS/TMDS/DP lanes and AUX) are `X` NC on every ball; GM107 VGA DAC `DACA_*` also NC [visual] (p.50, p.49). ⇒ muxless Optimus: every panel/port is iGPU-driven; M620 is a render-only device (p.50).
- No VBIOS flash: `ROM_CS_N` has no net, `ROM_SCLK/SI/SO` only carry strap resistors [visual] (p.50). ⇒ the dGPU VBIOS lives in the system firmware image and is handed to the driver via ACPI `_ROM` (p.50).
- Class strap: `ROM_SO` = `RV249` 4.99 K pull-up (`N16@`, fitted for N16S), `RV250` pull-down is `N17@` [visual] (p.50). The sheet contradicts itself: the resistor-to-hex table gives 4.99 K PU = `1000` → bit0 `VGA_DEVICE=0` = "Non-Primary 3D Acceleration Device (Class Code 302h)", while the strap-table cell says "VGA_DEVICE->1 (N16S)" (p.50). Field data sides with 302h: a 3520 probe lists the M620 as class `03-02` `GM107GLM [Quadro M620 Mobile]` https://linux-hardware.org/?probe=4b9a52ac5c (p.50). Confirm with `lspci -nn` on our board.
- Other straps: `STRAP0` `RV235` 49.9 K PU to `+3.3V_GFX_AON`; `STRAP1..4` pairs `@RV236..@RV244` all nopop; `ROM_SCLK` `RV246` 4.99 K PD; `ROM_SI` `RV247` 4.99 K PU (RAM_CFG 0x8); `GPU_TESTMODE` `RV255` 10 K PD; `JTAG_TRST` `RV256` 10 K PD; `@RPV1` JTAG pull-ups nopop; `MULTI_STRAP_REF0_GND` `RV252` 40.2 K 1 % [visual] (p.50). Sheet note: `ROM_SO` pull-up rail written as `+3.3V_GFX_AON`, drawing puts `RV245/RV247/RV249` on `+3.3V_RUN_GFX` — drawing wins, irrelevant unless the part is swapped (p.50).
- Thermal: GPU diode `THERMDP/THERMDN` NC [visual] (p.50); temperature is read over the GPU `I2CS` slave → `QV12` DMN66D0LDW level shift (gate `+3.3V_RUN_GFX`) → `EXPANDER_GPU_SMCLK/SMDAT` → EC [visual] (p.49), EC side [text] (p.39). SMBus alt address table: 0 = 0x9E default (p.50).

## PEG link
- Width: x16, all 16 pairs in both directions are routed and AC-coupled [visual] (p.6, p.49).
  - CPU TX → GPU RX: `PEG_CTX_GRX_P/N[0..15]` → `CC34..CC65` 0.22 µF 0402 16 V (32 caps, none `@`) → `PEG_CTX_C_GRX_*` → GM107 `PEX_RX0..15` [visual] (p.6, p.49).
  - GPU TX → CPU RX: GM107 `PEX_TX0..15` → `PEG_CRX_GTX_*` → `CV427..CV458` 0.22 µF 0402 16 V (32 caps, none `@`) → `PEG_CRX_C_GTX_*` → CPU `PEG_RX` [visual] (p.49, p.6).
  - Caps sit at each transmitter, per PCIe spec: host-TX caps on the CPU sheet, device-TX caps on the GPU sheet (p.6, p.49).
- Lane reversal on the board: CPU `PEG_RX/TX[k]` ↔ GPU lane `[15-k]` (CPU `PEG_RXP0` E25 = `PEG_CRX_GTXP15`, CPU `PEG_RXP15` F10 = `PEG_CRX_GTXP0`; same for TX) [visual] (p.6). The x16 link trains reversed; a narrower device must sit on CPU lanes 0..n = GPU pads 15..15-n (p.6).
- `PEG_COMP` G2 → `RC2` 24.9 Ω 1 % to `+1.0VS_VCCIO` [visual] (p.6). No PEG bifurcation (`CFG[6:5]`) straps on p.6; CFG straps not checked in this phase (p.6).
- Refclk: PCH `CLKOUT_PCIE_P7/N7` → `CLK_PCIE_P7/N7` → GM107 `PEX_REFCLK` AL13/AK13 [visual] (p.49), [text] (p.18). PEG uses a PCH SRC clock, not a CPU clock (p.18, p.49).
- CLKREQ: GM107 `PEX_CLKREQ_N` AK12 ← `GFXCLK_REQ_Q#` ← `QV10` L2N7002 (gate `VRAM_EN`) ← `CLKREQ_PCIE#7` → PCH `GPP_H1/SRCCLKREQ7#` [visual] (p.49); `RV201` 10 K PU to `+3.3V_GFX_AON`; `@RV200` direct bypass nopop [visual] (p.49). PCH side link `@RF@RH17` drawn nopop, `@QH5` (tie to `DGPU_PWR_EN`) nopop — see `gpio.md` (p.18).
- `PEX_TSTCLK_OUT` `@RV207` nopop; `PEX_TERMP` AP29 2.49 K 1 % to GND [visual] (p.49).
- PERST: `PEX_RST_N` AJ12 ← `RV209` 0 Ω ← `DGPU_PEX_RST#` [visual] (p.49). See reset chain below.

## Power rails
| rail | source (part) | enable | feeds | cite |
|---|---|---|---|---|
| `+3.3V_GFX_AON` | `QV14` LP2301ALT1G P-FET from `+3.3V_RUN` | `DGPU_PWR_EN#` = `QV13` L2N7002 inverting `DGPU_PWR_EN` (`RV268` 100 K PU `+5V_RUN`) | GPU `3V3_AON`, `PEX_PLL_HVDD`, `PEX_SVDD_3V3`, `PEX_PLLVDD`, all GPU GPIO pull-ups, `STRAP0` | [visual] p.53; pins [text] p.51 |
| `+GPU_CORE` (`+VGA_CORE`) | `PU1300` RT8813AGQW 2-phase, `PQ1300/PQ1301` CSD87351Q5D, `PL1301/PL1302` 0.22 µH 28 A, from `+GPU_PWR_SRC` (`PJP1301` open-pad jumper + `@EMC@` bead from `+PWR_SRC`) | `EN` ← `PR1309` 1 K ← `3V3_MAIN_EN` (GPU `GPIO5`) | GPU core | [visual] p.69 |
| `+3.3V_RUN_GFX` | `UV15` EM5209VF ch2 from `+3.3V_RUN`, `PJP43`, soft-start `CV248` 470 pF | `ON2` = `3V3_MAIN_EN_R` ← `@RV269` ← `3V3_MAIN_EN` | GPU `3V3_MAIN`, `IFPA_IOVDD`, `QV12` gate, strap pulls | [visual] p.53 |
| `+1.05V_PEX_VDD` | `UV15` EM5209VF ch1 from `+1.05V_PRIM`, `PJP44`, soft-start `CV247` 4700 pF | `ON1` = `3V3_MAIN_EN_R` (same as ch2) | GPU `PEX_IOVDD/IOVDDQ`, PLLs via `LV8`/`LV10` | [visual] p.53, p.49 |
| `+1.35V_MEM_GFX` (FBVDDQ) | SYX198D buck, 0.68 µH 15.5 A, from `+PWR_SRC` | `EN_+1.35_VRAM` ← `PR1401` 0 Ω ← `VRAM_EN` | GPU `FBVDDQ*`, `FBVDDQ_AON`, both GDDR5 | [text] p.70, p.51, p.53 |

- `+GPU_CORE` design box: "TDC 26.5 A, Peak 53 A, OCP 63.6 A"; notes "OCP = 54 A/2 = 27 A per phase", "Ivalley = 27 − 7.811/2 = 23.1 A", Fsw ≈ 305 kHz; PWM-VID config B: Vmin 0.6 V, Vmax 1.2 V, Vboot 0.9 V, 6.25 mV step [visual] (p.69).
- `+GPU_CORE` control: `VID` ← `PR1302` ← `GPU_PWM_VID` (GPU `GPIO11`), `PSI` ← `PR1305` ← `NVVDD_PSI` (GPU `GPIO13`); both drawn as short-pad 0 Ω with `@`; `@PR1301` 1 K VID pull-up nopop; `PGOOD` → `DGPU_PWROK` with `PR1322` 10 K PU to `+3.3V_RUN`; remote sense `GPU_VDD_SENSE/GPU_VSS_SENSE` from GM107 L4/L5 [visual] (p.69, p.50).
- `+1.35V_MEM_GFX` box: "TDC 9 A, Peak 12 A, OCP 14.4 A" [text] (p.70).
- No separate 1.8 V GPU rail on the sheets (p.51).

## Power-on sequence (order inferred from wiring; no timing diagram for the GPU in the PDF)
1. S0: `RUN_ON` → `+3.3V_RUN`, `+5V_RUN`; `+1.05V_PRIM` up (p.48, p.56).
2. `DGPU_PWR_EN` (`GPP_D12`) high — default via `RH346` 100 K PU, `@RH349` PD nopop — → `QV13`/`QV14` → `+3.3V_GFX_AON` [visual] (p.21, p.53). Rev #34: "DGPU_PWR_EN need to use BIOS solution… De-POP RH349, POP RH346" [text] (p.74).
3. GM107 AON domain alive → GPU drives `3V3_MAIN_EN` (`GPIO5`, `RV223` 10 K PU `+3.3V_GFX_AON`) → RT8813 `EN` (`+GPU_CORE`) and `UV15` → `+3.3V_RUN_GFX` (470 pF ramp) then `+1.05V_PEX_VDD` (4700 pF ramp) [visual] (p.49, p.53, p.69). Rev #45 "Fine tune NV power sequence": `CV247` 3900 → 4700 pF, `CV248` 220 → 470 pF [text] (p.74).
4. RT8813 `PGOOD` → `DGPU_PWROK` → PCH `GPP_D18`, EC via `UE2` MCP23008 `GP2` (SMBus 0x40, `EXPANDER_GPU_SM*` bus), and `DV8` BAT54CW diode-OR [visual] (p.69, p.40, p.53), PCH [visual] (p.20, per `gpio.md`).
5. `VRAM_EN` = `DGPU_PWROK` OR `GPU_GC6_FB_EN` (PCH `GPP_G3`, `RV299` 10 K PD) → `+1.35V_MEM_GFX` on, and `QV10` passes CLKREQ [visual] (p.53, p.49). In GC6 the core drops but `GPU_GC6_FB_EN` keeps FBVDDQ up for self-refresh (p.53).
6. Reset release — `DGPU_PEX_RST#` = `UV25`(`SYS_PEX_RST_MON#` AND `GPU_PEX_RST_HOLD#`), `SYS_PEX_RST_MON#_R` = `UV14`(`PLTRST_GPU#` AND `DGPU_HOLD_RST#`) [visual] (p.49). Inputs: `PLTRST_GPU#` ← PCH `PLTRST#` via `@RH195` 0 Ω [visual] (p.19); `DGPU_HOLD_RST#` ← PCH `GPP_D10` (`RV202` 10 K PU; `@RH350` nopop) [visual] (p.49, p.21); `GPU_PEX_RST_HOLD#` ← GM107 `GPIO21`, `RV224` 10 K PU `+3.3V_GFX_AON` [visual] (p.49). Pull-downs `RV203`, `RV205` 10 K on the AND outputs; both gates on `+3.3V_ALW` [visual] (p.49).
7. GC6 exit/event: GM107 `GPIO6` → `DV10` RB751 → `GC6_EVENT#` → PCH `GPP_G1` [visual] (p.49, p.16).

Other GPU GPIOs: `GPIO0` `GPU_GC6_FB_EN` (in), `GPIO8` `SYS_PEX_RST_MON#` (in, `@RV226` PU nopop), `GPIO10` `FBVREF_ALTV` (`RV227` 100 K PD), `GPIO12` `GPU_HOT#` (`RV221` 100 K PU), rest NC [visual] (p.49). `GPU_PWR_LEVEL` from expander `GP1` reaches `GPU_HOT#` only through `@RV210` (nopop) [visual] (p.49, p.40). `THERMATRIP_GPU#` (GM107 `OVERT` M1) → `QV11` (gate `DGPU_PEX_RST#`) → `THERMATRIP1#` → EC; `@RV211` bypass nopop [visual] (p.50, p.49), EC [text] (p.39).

### Stale-BOM flags (same pattern as p.19 SPI, for the DMM list)
In-path parts drawn `@` that a working dGPU needs: `@RH195` (`PLTRST_GPU#`; neighbours `@RH62` LAN and `@RH244` EC reset are drawn the same way) (p.19), `@RV269` (`3V3_MAIN_EN` → `UV15`), `@RV204` + `@RV206` (both paths into `UV25`/`DGPU_PEX_RST#`) (p.53, p.49), `PR1302`/`PR1305` short-pads marked `@` (VID/PSI) (p.69). linux-hardware probes show the M620 enumerating on 3520s, so these are populated or shorted on real boards — DMM before any rework (p.19, p.49, p.53, p.69).

## coreboot vs EC duties
- coreboot/FSP: enable PEG `00:01.0` x16 with PCH `SRCCLKREQ7#` (`GPP_H1`) mapping; `GPP_D12` `DGPU_PWR_EN` GPO (keep HIGH to have the dGPU, LOW = fully off, saves `+3.3V_GFX_AON` and everything downstream); `GPP_D10` `DGPU_HOLD_RST#` GPO HIGH after power-good; `GPP_D18` GPI; `GPP_G3` GPO LOW unless GC6; `GPP_G1` GPI/SCI (p.21, p.20, p.16).
- ACPI: `_ROM` with the M620 VBIOS extracted from the Dell image (no GPU ROM on board); optional `_PR0/_PS0/_PS3` sequencing D12 → wait `DGPU_PWROK` → D10 for runtime power-off (p.50, p.21).
- iGPU stays primary: dGPU is class 302h, never a boot VGA device; no option ROM needed for firmware display (p.50).
- EC: reads GPU temperature over `EXPANDER_GPU_SM*`, sees `DGPU_PWROK` on `UE2 GP2`, takes `THERMATRIP1#`; it does not gate any GPU rail (p.39, p.40, p.49).

## What fits here
The "remove M620, bring PEG out" idea, read against the sheets:
- After a GM107 lift the BGA land pattern exposes a spec-shaped host port: host-TX caps `CC34..CC65` stay on the CPU side, device-TX caps `CV427..CV458` stay inline, in series with the add-in card's own TX caps (0.22 µF in series with 0.22 µF ≈ 110 nF, inside the PCIe 75–265 nF range; bridge `CV427..CV458` with 0 Ω if a card uses smaller caps) (p.6, p.49).
- Sidebands also survive the lift: `CLK_PCIE_P7/N7` (PCH SRC7), `CLKREQ_PCIE#7` (through `QV10`, needs `VRAM_EN` high or `@RV200` fitted), `DGPU_PEX_RST#` (with the GPU gone, `GPU_PEX_RST_HOLD#` idles high via `RV224` → PERST follows `PLTRST#` AND `GPP_D10`) (p.49).
- For an x4 tap the lanes to take are GPU pads 15..12 (= CPU lanes 0..3) because of the board's lane reversal (p.6).
- Nothing on the board delivers 12 V to an external card; the eGPU PSU carries it (p.69, p.70).
- Catch: with the GPU gone `3V3_MAIN_EN` is held high by `RV223` → `+GPU_CORE`, `UV15` and (via `DGPU_PWROK`) `+1.35V_MEM_GFX` still start, unloaded. That is what keeps `VRAM_EN` high for `QV10`/CLKREQ, so the tap depends on the dead GPU's power tree; `GPP_D12` LOW kills `+3.3V_GFX_AON` and with it the `RV201` CLKREQ pull-up. Cleaner: fit `@RV200` (CLKREQ bypass) and pull `3V3_MAIN_EN` low (p.49, p.53, p.69).
- VGA-port idea: the VGA DAC is not on the GPU (GM107 `DACA_*` NC); a VGA port removal frees nothing on the PEG side — Phase 7 tracks where VGA really comes from (p.49, p.50).

FIT: PEG tap via GM107 removal → OCuLink/riser, x4 on GPU pads 15..12 (x16 possible in theory) | needs: BGA908 rework (GM107 lift + VRAM irrelevant), micro-coax or flex soldered to the bare BGA908 lands, length-matched pairs, stock BIOS with PEG enabled (dGPU-less board may hide PEG) or coreboot | lanes/bus: CPU PEG Gen3, x4 realistic, x16 routed | power: none from laptop for the card; tap sidebands from `+3.3V_GFX_AON` | displaces: M620 (permanently), GC6 | DIY: https://electronics.stackexchange.com/questions/653132/trying-to-replace-laptops-dgpu-with-egpu-is-it-possible (Acer V3-572PG: GT 840M desoldered, x1 riser wired to GPU pads, PERST source unresolved, no reported success) | risk: H (p.6, p.49)
FIT: dGPU kept, forced off to free power/thermals for an eGPU on TB3/KEYM | needs: `GPP_D12` LOW (coreboot gpio.c, or `@RH349` fitted + `RH346` removed) | lanes/bus: PEG idle | power: saves `+3.3V_GFX_AON` + `+GPU_CORE` + `+1.35V_MEM_GFX` domains | displaces: M620 compute | DIY: https://swerc.eu/2022/environment (contest fleet of 3520s run with "the Nvidia GPU disabled", method unstated — the D12 path itself is proven by the schematic alone) | risk: L (p.21, p.53)
FIT: M620 in Linux with coreboot | needs: ACPI `_ROM` carrying the Dell VBIOS, PEG enabled in devicetree | lanes/bus: PEG x16 | power: stock rails | displaces: nothing | DIY: https://crayphish.github.io/posts/t440p-adventures/ (T440p coreboot: dGPU works after re-enabling PEG and adding the dGPU VBIOS) | risk: M (p.50)
