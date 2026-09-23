# LA-E152P — Thunderbolt 3 / USB-C PD (Phase 4)

Source: `Dell-3520-LA-E152P-schematic.pdf` sha256 `551d1fe5…1a9cb`. `[visual]` = read on a 300–600 dpi render this session; `[text]` = pdftotext, net seen on ≥2 sheets.
Sheets: p.29 Alpine Ridge signals, p.30 Alpine Ridge power, p.31 TPS65982 PD, p.32 PD LDOs, p.33 Type-C receptacle, p.68 Type-C power path, p.17/p.18/p.21/p.16 PCH side, p.73–74 rev history.

## Controller
- `UT1` symbol `ALPINE-RIDGE_BGA337`, block title "PCIe GEN3" [visual] (p.29). The sheet does not name the SKU. Field probes of 3520s report `JHL6340 Thunderbolt 3 Bridge (C step) [Alpine Ridge 2C 2016]` (`8086:15da`), USB `8086:15db` https://linux-hardware.org/?probe=2502fbaef2 (p.29).
- One port only, matching the 2C part: port A (`PA_*` → `TBTA_*`) goes to `JUSBC1`; port B `PB_TX/RX`, `TBTB_LSTX/LSRX/HPD` only have pull-downs (`RT31`, `RT32` 1 M, `RT33` 100 K) and no connector [visual] (p.29, p.33).
- DP source output (`DPSRC_ML0..3`, `AUX`) is NC; `DPSRC_HPD` = `TBT_SRC_HPD` `RT184` 1 M PD [visual] (p.29). The controller only receives DP from the host.
- NVM: `UT2` `W25Q80DVSSIG` (8 Mbit) on `TBT_ROM_*`; `RT1` 3.3 K `HOLD#`, `RT2`/`RT3` 2.2 K `CS#`/`DO`, `RT4` 3.3 K `WP#`. Supply `+3.3V_TBT_FLASH_R` comes through `@RT9` 0 Ω from `+3.3V_TBT_LC` or `@RT10` 0 Ω from `+3.3V_TBTA_FLASH`, both drawn nopop. One of them must be fitted on a working board, so check both with the DMM [visual] (p.29).
- JTAG `TBT_JTAG_*` `RT5..RT8` 10 K PU `+3.3V_TBT_LC`; debug header note "Pin1 +3.3V_TBT_LC, Pin6 GND" [visual] (p.29).

## Host links
| link | PCH / CPU side | Alpine Ridge side | cite |
|---|---|---|---|
| PCIe x4 Gen3 | PCH `PCIE5..8` (`PCIE_PTX_DRX_*5..8` / `PCIE_PRX_DTX_*5..8`, label "TBT") | `PCIE_RX0..3` / `PCIE_TX0..3`; device-TX caps `CT6..CT9`, `CT127..CT130` 0.22 µF on p.29 | [visual] p.17, p.29 |
| Refclk | PCH `CLKOUT_PCIE_P6/N6` → `CLK_PCIE_P6/N6` | `PCIE_REFCLK_100_IN_P/N` | [visual] p.18, p.29 |
| CLKREQ | PCH `GPP_H0`/`SRCCLKREQ6#` = `CLKREQ_PCIE#6_R`, `RH132` 10 K PU `+3.3V_RUN`, `@RF@RH13` 0 Ω link to `CLKREQ_PCIE#6` (drawn nopop) | `PCIE_CLKREQ_N` AC5 | [visual] p.18, p.29 |
| PERST | `PCH_PLTRST#_AND` `<19,36,37,41,42>` (shared with card reader, M.2, TPM) | `PERST_N` L4 | [visual] p.29; source [text] p.19 |
| DP in 0 | CPU `DDI2` `CPU_DP2_P/N0..3`, `AUX` via `CT10..CT19` 0.1 µF; HPD `PCH_DP2_HPD` `<21>` (`RT24` 100 K PD) | `DPSNK0` | [visual] p.29 |
| DP in 1 | `SW1_DP1_*` from PS8338 `<25>` (DDI3 demux) via `CT178..CT187`; HPD `SW1_DP1_HPD` (`@RT29` PD nopop) | `DPSNK1` | [visual] p.29 |
| USB2 | `TBTA_USB20_P/N` → PD `C_USB_T/B` | port A USB2 | [text] p.29, p.31 |

- Correction to `gpio.md`: the CLKREQ#6 pull-up is `RH132`. `RH133` is on the `#7` (dGPU) row (p.18). The `@RF@RH13` link is drawn nopop, the same stale-BOM pattern as `RH10..RH17` in Phase 2 (p.18). Linux enumerates the port, so it is fitted on real boards.
- `PCH_PLTRST#_AND` also drives the card reader and M.2 slots. The Alpine Ridge has no separate PERST GPIO (p.29).

## Sideband / GPIO
| AR pin | ball | net | other end | pull | cite |
|---|---|---|---|---|---|
| GPIO_0 / GPIO_1 | U1 / U2 | `TBT_I2C_SDA` / `TBT_I2C_SCL` | TPS65982 I2C1 `<31>` | `RT18`/`RT19` 2.2 K `+3.3V_TBT_SX` | [visual] p.29 |
| GPIO_2 | V1 | `TBT_ROM_WP#` | `UT2` | `RT4` 3.3 K | [visual] p.29 |
| GPIO_3 | V2 | `TBT_TMU_CLK_OUT` | - | `RT28` 100 K PD | [visual] p.29 |
| GPIO_4 | W1 | `PCIE_WAKE#` | `<37,40,42>` shared wake | - | [visual] p.29 |
| GPIO_5 | W2 | `TBT_CIO_PLUG_EVENT#` | PCH `GPP_G2` `<16>` | `RT391` 10 K `+3.3V_ALW_PCH` (rev #14 "for backdrive issue"); `@RT371` alt PU nopop | [visual] p.29, [text] p.74 |
| GPIO_6 / GPIO_7 | Y1 / Y2 | `AR_DP1_CTRL_DATA` / `_CLK` | - | `RT12`/`RT13` 2.2 K `+3.3V_TBT` | [visual] p.29 |
| GPIO_8 | AA1 | `TBT_SRC_CFG1` | - | `RT30` 1 M PD; `@RT338` PU nopop | [visual] p.29 |
| POC_GPIO_0 | J4 | `TBTA_I2C_INT` | TPS65982 `<31>` | `RT16` 10 K `+3.3V_TBT_SX` | [visual] p.29 |
| POC_GPIO_2 | D4 | `RTD3_USB_PWR_EN` | - | `RT26` 100 K PD | [visual] p.29 |
| POC_GPIO_3 | H4 | `TBT_FORCE_PWR` | PCH `GPP_D4` `<21>` | `RT27` 10 K PD | [visual] p.29 |
| POC_GPIO_4 | F2 | `TDOCK_BATLOW#` | - | `RT20` 10 K PU | [visual] p.29 |
| POC_GPIO_5 | D2 | `SIO_SLP_S3#` | PCH `GPD4` `<20,21,39,40,62>` | - | [visual] p.29 |
| POC_GPIO_6 | F1 | `RTD3_CIO_PWR_EN_R` | ← `@RT392` 0 Ω ← PCH `GPP_C13` `RTD3_CIO_PWR_EN` | `RT25` 100 K PD | [visual] p.29 |
| RESET_N | F4 | `TBT_RESET_N_EC` | EC `<39>` and TPS65982 `<31>` | `@RT11` 10 K PU nopop | [visual] p.29, [text] p.39 |

- RTD3 is not wired up: `@RT392` is nopop and `RT25` holds `RTD3_CIO_PWR_EN_R` low, so PCH `GPP_C13` drives nothing (p.29). Power control comes from `SLP_S3#` plus `TBT_FORCE_PWR` (p.29).
- For coreboot: `GPP_D4` GPO (pulse/hold high to wake the controller for enumeration without a device), `GPP_G2` GPI/SCI for hot-plug, root port 5 x4 with `SRCCLKREQ6#`, hot-plug enabled, bus/mem padding for a TB chain. The controller runs its own NVM (`UT2`) and connection manager, so coreboot does not ship TBT firmware (p.29, p.21, p.16).

## Power
| rail | source | domain | loads | cite |
|---|---|---|---|---|
| `+3.3V_TBT` | `+3.3V_RUN` through `PJP5` (JUMP_43X79) | S0 only | `VCC3P3_SVR` (internal 0.9 V buck input), pull-ups `RT11..RT15`, `RT336/337` | [visual] p.30, p.29 |
| `+3.3V_TBT_S0` | `+3.3V_TBT` via `LT2` 1 µH (`LQM18NN1R0K00D`, note "change pn to SHI0000N600") | S0 | `VCC3P3_S0` R13 | [visual] p.30 |
| `+3.3V_TBT_SX` | `+3.3V_VDD_PIC` through `PJP6` (PAD-OPEN 1x1 mm); `@RT48` 0 Ω from `+3.3V_ALW` and `@RT49` 0 Ω from `+3.3V_TBT` are nopop alternates | always-on while `+3.3V_VDD_PIC` lives | `VCC3P3_SX` F8, I2C/INT pull-ups `RT16..RT20` | [visual] p.30, p.29 |
| `+3.3V_TBT_LC` | not traced this phase | ? | `VCC3P3_LC` R6, JTAG pull-ups | [visual] pin p.30 |
| `+0.9V_TBT_*` | Alpine Ridge internal SVR, 0.6 µH (`MND-04ABIR60M`) → `+0.9V_TBT_SVR` → `_CIO/_DP/_PCIE/_USB/_LVR` | follows `+3.3V_TBT` | core | [visual] p.30 |
| `+3.3V_VDD_PIC` | `UT7` AP2112K-3.3 LDO from `+5V_PD_VDD` = `DT1` (`+5V_ALW`) OR `DT2` (`+5V_TBT_VBUS`) | alive from battery or from Type-C VBUS alone | PD `VIN_3V3`, PD flash, TBT SX, DC-in comparators p.68 | [visual] p.32 |
| `+5V_TBT_VBUS` | `UT8` AP2204R-5.0 LDO from `+TBTA_Vbus_1` via `DT3` | when a source is attached | dead-battery boot of the PD | [visual] p.32 |

- In S3/S4/S5 the PCIe side of the controller has no power, because `+3.3V_TBT` hangs on `+3.3V_RUN`. Only the SX/PD domain stays up. So there is no TB3 wake from S3, and a TB device re-enumerates on every resume (p.30).
- Budget for Phase 6: `+3.3V_TBT` comes off `+3.3V_RUN` with no dedicated regulator. The only local current note is the SVR inductor ("1.8A") (p.30).

## USB-C PD (TPS65982)
- `UT5` `TPS65982D` BGA96 with its own flash `UT6` `25Q80DVSSIG` on `+3.3V_TBTA_FLASH` (p.31). It is not on the PCH SPI bus, so no BIOS-dump caveat (p.31).
- Boot config: `ADCIN` divider `RT76` 10 K / 43 K 1 % [visual]. The sheet's DIV table maps 0.70–1.00 to config 7, "Infinite boot retry from Flash", and 0.10–0.18 to config 1, "UFP only, 5V @0.9A Sink" [text] (p.31). Only the 43/(10+43) ≈ 0.81 orientation makes sense for a TB3 host, so all PD policy (source/sink PDOs, DP/TBT alt modes) lives in the `UT6` firmware and no strap caps it (p.31).
- Host interfaces: I2C1 ↔ Alpine Ridge (`TBT_I2C_*`, `TBTA_I2C_INT`); `UPD1_SMBCLK/SMBDAT/ALERT#` ↔ EC `<39>`; `EN_PD_HV_1` (PD `GPIO1`, "From TI GPIO1") → p.68; `AC1_DISC#` `<66,68>` → PD `GPIO3`; `TBT_RESET_N_EC` → `HRESET`/`RESET_N` [visual] (p.31, p.68), EC [text] (p.39).
- The internal high-voltage path is unused: `HV_GATE1/2` go to GND through `@RT64`/`@RT65` (nopop), and `SENSEP`/`SENSEN` are both tied to `+TBTA_Vbus_1` (no shunt) [visual] (p.31). The 20 V sink path is discrete, on p.68.
- Rev X01: "Reserve the OVP function to protect the typeC device. Depop PJP1202, PR1255, PR1239, PR1246, PC1211…" [text] (p.73).

## Type-C → charger path (does WD19TB 130 W reach the charger)
- `+TBTA_VBUS` (connector) → `PL1201` ‖ `PL1202` `5A_Z120_25M_0805` beads (EMC) → `+TBTA_Vbus_1` → S3 `PQ1206` AON7409 / `PJP1202` JUMP_43X118 (one of them `@`; rev X01 depops `PJP1202`, so S3 should be fitted, but check with the DMM) → `+AC_IN` → S4 `PQ1213` AON7409 → `+VBUS_DC_SS` → S5 `PQ1202` AON7409 → `+SDC_IN`, the same node the barrel jack feeds (p.57) → charger `+CHARGER_SRC` (p.66) [visual] (p.68).
- S4 gate: `PQ1215` AO3409 ← `PQ1214A/B` DMN65D8LDW ← `EN_PD_HV_1` (PD asserts after the contract). S5 gate: `PQ1201B` ← `VBUS1_ECOK` `<40,68>` from the EC (via `PR1220`) [visual] (p.68). The PD accepts the contract, and then the EC decides to connect it to the charger.
- `EN_PD_HV_1` with `AC1_DISC#` → `PQ1208A/B` → joins `ACAV_IN_NB` `<39,57,66,68>`, so the EC and charger see "AC present" from Type-C as well [visual] (p.68). `PU1200` MC74VHC1G08 AND gate (`EN_PD_HV_1` with …) has 0 Ω options `@PR1211`, `@PR1215`, `@PR1216`; this is the unsettled OVP variant (p.68, p.73).
- Barrel detect: `PU1201A` LM393 on `+DC_IN` through `PR1201` 240 K / `PR1219` 23.2 K → `ACAV_IN_NB`, threshold ">17.6V" on the sheet, retuned to 16.9 V by rev X01 #3 [visual] (p.68), [text] (p.73).
- No current sense and no current-limit part in the Type-C path. The ceiling is the parts: 2 × 5 A beads in parallel and AON7409 P-FETs, fine for 20 V × 6.5 A = 130 W. The negotiated wattage is set by PD firmware (`UT6`), and the input current by the charger's `ACIN`/ILIM set-up (Phase 6) (p.68, p.31, p.66).
- Verdict 4.2: no board-level strap caps Type-C input below 130 W. Whether a 3520 draws 130 W from a WD19TB depends on the Dell PD firmware and the charger ILIM, not on the schematic (p.68, p.31).

## What fits here
FIT: eGPU on the laptop USB-C directly (TB3 enclosure: Razer Core X / AKiTiO Node / ADT-Link UT3G) | needs: TB3 enclosure + PSU, Linux `thunderbolt` authorisation (`boltctl`), BIOS "Thunderbolt security" off or user-authorise | lanes/bus: PCH PCIe 5..8 x4 Gen3 behind DMI 3.0 x4 (shared with `KEYM` NVMe, WLAN, LAN, card reader); TB3 PCIe tunnel ≈ 22 Gb/s usable | power: none from laptop (enclosure PSU; enclosures with PD can also charge the laptop over the same cable through S3/S4/S5) | displaces: the only TB3/USB-C port | DIY: https://dell.com/support/kbdoc/de-at/000060905/thunderbolt-3-40-gbit-s-daten%C3%BCbertragungsrate?lang=en (Dell: "Precision 3520 * — Four lanes"), https://visiontek.com/blogs/news/visiontek-introduces-new-thunderbolt%E2%84%A2-3-egfx-external-graphics-accelerator-enclosure (VisionTek eGFX lists the 3520 as tested), https://www.sapphiretech.com/en/consumer/gearbox-thunderbolt-3-egfx-solution (GearBox list includes the 3520) | risk: L (p.17, p.29)
FIT: eGPU through WD19TB's downstream TB3 port | needs: WD19TB (Titan Ridge) + enclosure; eGPU on the dock's TB3 downstream port | lanes/bus: the same single x4 / ≈22 Gb/s PCIe tunnel as above, shared with the dock's USB 3.x hub, NIC and audio; DP streams share the 40 Gb/s link on top; each TB hop costs ≈10 % eGPU performance (latency) | power: WD19TB PD to the laptop (see charger path); eGPU on its own PSU | displaces: nothing extra, but the dock's USB/LAN compete for the same tunnel | DIY: https://egpu.io/forums/thunderbolt-enclosures/thunderbolt-4-docks-egpu-daisy-chaining-and-the-one-cable-dream/paged/2/ (boltoway: "used the WD19TB and WD19TBS as an eGPU Daisy Chain Host… full speed downstream port"; wildfear: ~10 % loss per hop) | risk: M (p.29, p.68)
FIT: 10 GbE / 2.5 GbE over TB3 (Sonnet Solo10G, QNAP QNA-T310G1S, other AQC107/AQC113 adapters) | needs: adapter; Linux `atlantic` driver | lanes/bus: x4 Gen3 tunnel, 10 Gb/s fits under ≈22 Gb/s; shares the port with an eGPU/dock unless behind WD19TB | power: bus-powered from `+TBTA_VBUS` source side (PD source contract in `UT6` fw; BIOS "Type-C Connector Power" 7.5/15 W) | displaces: the TB3 port (or rides on the WD19TB chain) | DIY: https://www.reddit.com/r/linuxhardware/comments/153m3ru/linux_support_for_external_thunderbolt3_10gbe/ (Linux TB3 10GbE adapters), https://github.com/Aquantia/AQtion/issues/26 (Solo10G SFP+ TB3 on Linux: works, noisy dmesg) | risk: L (p.29, p.31)
FIT: WD19TB (130 W PD) as the only power source | needs: WD19TB 180 W brick; Dell PD firmware to request 20 V/6.5 A | lanes/bus: n/a | power: `+TBTA_VBUS` → 2 × 5 A beads → S3/S4/S5 AON7409 → `+SDC_IN`, the same charger input as the 130 W barrel; no sense resistor or strap caps it | displaces: barrel adapter | DIY: https://www.delltechnologies.com/asset/en-us/products/electronics-and-accessories/technical-support/dell-wd15-tb16-tb18dc-commercial-docking-compatibility-guide.pdf (Dell lists the 3520 as supported on WD15 130 W/180 W and TB16 180 W/240 W; WD19TB row for 3520 not found) | risk: M — PD fw contract and charger ILIM unverified until Phase 6 (p.68, p.31)
