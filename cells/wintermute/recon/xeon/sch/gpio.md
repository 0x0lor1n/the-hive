# LA-E152P — PCH GPIO map (Phase 2)

Source: `Dell-3520-LA-E152P-schematic.pdf` sha256 `551d1fe5…1a9cb`. PCH symbol sheets p.16–p.21 (GPIO lives on six sheets, not only p.18/20/21), strap and pull networks on the same pages.
Method: pdftotext `-bbox` gave a draft pin→ball→net pairing; every row was then read `[visual]` from 400 dpi crops (Compal draws the ball number and the net on the wire just above the pin label; `X` on the wire = NC). Net destinations cross-checked `[text]` on the `<NN>` sheet (script over p1–p74; misses listed under Open). Balls re-matched against bbox geometry: 0 mismatches on real pin labels (p.16–p.21).
The Dell doc on the cover ("GPIO map EC16 062416, Compal Only", p.1) is not available. Where the function isn't legible on the sheet the row says `?`; nothing is invented.
Columns: `dir` from the PCH's point of view; `pull` = parts on the sheet (`@` = nopop, per p.1 legend `@RF@` = RF nopop too); `pad guess` = starting point for `gpio.c`, to be diffed against an `intelp2m` dump of the stock BIOS on this board, never used blind.

## Key rows (coreboot must get these right)
- `GPP_D12` `DGPU_PWR_EN` <18,53>: `RH346` 100 K pull-up to `+3.3V_RUN` fitted, `@RH349` 100 K pull-down to GND not fitted [visual] (p.21). So the dGPU rails come up with `RUN` unless the PCH drives D12 low. Matches p.74 rev #34, "DGPU_PWR_EN need to use BIOS solution… De-POP RH349, POP RH346" [text] (p.74). `@QH5` (nopop) would tie `CLKREQ_PCIE#7` to it (p.18).
- `GPP_D18` `DGPU_PWROK` <40,53,69> input; `GPP_D10` `DGPU_HOLD_RST#` <49> output, `@RH350` pull-up not fitted [visual] (p.20, p.21). `GPP_G1` `GC6_EVENT#` <49> in, `GPP_G3` `GPU_GC6_FB_EN` <49,53> out [visual] (p.16). Power-on order is Phase 3.
- `GPP_G2` `TBT_CIO_PLUG_EVENT#` <29>, `GPP_C13` `RTD3_CIO_PWR_EN` <29>, `GPP_D4` `TBT_FORCE_PWR` <29> [visual] (p.16, p.21). `GPP_D20` `TBT_PWR_EN` goes only to test pad `@T269` [visual] (p.20). Alpine Ridge side is Phase 4.
- Panel: `GPP_F19` `ENVDD_PCH`, `GPP_F20` `PANEL_BKEN_PCH`, `GPP_F21` `BIA_PWM_PCH` → <34>. These are native EDP_VDDEN/BKLTEN/BKLTCTL [visual] (p.16). Phase 7.
- eSPI pins `GPP_A0..A6, A9, A14` are native eSPI because the strap is `GPP_C5` via `ESPI@RH78` 4.7 K pull-up, fitted (p.20, see spi-ec.md). `LPC@RH213`/`LPC@RH202` pulls are absent on this build (p.20).
- Straps sampled at reset: `GPP_B14`/SPKR top swap (`@RH86` not fitted → off), `GPP_B18` NRB_BIT (`@RH331` not fitted → reboot allowed), `GPP_B22` BBS_BIT6 (no pull → SPI boot), `GPP_C5` eSPI, `GPP_B23` (RH347 + nopop `@QC3`, "EXI BOOT STALL BYPASS"), `GPP_C8` (`@RH207` "Reserved") [visual] (p.20, p.21). Leave them as inputs after reset.
- Board-ID-style straps read by BIOS: `GPP_B16` ONE_DIMM# (RH268 pull-down → 2 DIMM), `GPP_D9` MEM_INTERLEAVED (RH372 pull-down → non-interleaved), `GPP_D11` AR_DET# (RH401 pull-down → Alpine Ridge present), `GPP_A22` TPM_TYPE (`@RH379` not fitted, "Reserved") [visual] (p.21).
- SATA/PCIe mux select: `GPP_E0` SATAXPCIE0 = `M2280_PCIE_SATA#` <42> (KEYM), `GPP_F1` SATAXPCIE4 = `m3042_PCIE#_SATA` <37,39> (WWAN slot, PCIe17/SATA4). The sheet table `SPSGP0..4 = 1,0,1,0,1` marks which SATAGP pins carry a detect (p.16) [visual]. DEVSLP: `GPP_E4`→KEYM, `GPP_E6`→2.5" bay, `GPP_F6`→WWAN slot (p.20) [visual].

## CLKREQ / reference clocks — flag for coreboot
- `SRCCLKREQ0#..7#` = `GPP_B5..B10, H0, H1` → `CLKREQ_PCIE#0..7_R`. Destinations: #0 WWAN <37>, #1 WLAN <37>, #2 WiGig <37>, #3 KEYM <42>, #4 LAN <35>, #5 card reader <36>, #6 Alpine Ridge <29>, #7 dGPU <49> [visual] (p.18).
- The series 0 Ω links from the device to the PCH, `@RF@RH10..RH17`, are drawn not fitted, and PCH-side pull-ups `RH123–127, RH131–133` 10 K to `+3.3V_RUN` (#0..#7 in that order) are fitted [visual] (p.18). On E151P the same links are `RF@` = fitted (E151P p.18) [text]. Same pattern as the SPI 0 Ω bridges in spi-ec.md: either the BOM view is stale or E152P really runs every root port with free-running clocks. DMM `RH10` / `RH13` before writing the devicetree.
- Coreboot consequence in either case: `PcieRpClkReqSupport[n] = false` works for both, because the clock just runs. That is how the upstream Dell SKL/KBL port handles its slots (`optiplex_3050/overridetree.cb`, rp5/rp8). Enable CLKREQ only after the DMM check.
- `CLKOUT_PCIE_0..7` → `CLK_PCIE_P/N0..7` to the same eight devices [visual] (p.18), all cross-referenced [text] (p.29, p.35–37, p.42, p.49). `CLKOUT_PCIE_8..15` and `SRCCLKREQ8#..15#` (`GPP_H2..H9`) are NC with `X` at the ball [visual] (p.18).

## Pin table (GPP_A…GPP_I, GPD) — every row `[visual]` p.16–p.21
| GPP | ball | net | dir | pull | page | function | coreboot pad-config guess |
|---|---|---|---|---|---|---|---|
| GPP_A0 | AT17 | SIO_RCIN# <39> | in | LPC@RH213 10K +3.3V_RUN (absent, eSPI build) | p.20 | KBC reset from EC | NF1 (eSPI-owned) |
| GPP_A1 | AT22 | ESPI_IO0 <39,40> | io | RC366 series | p.20 | eSPI IO0 | NF1 (eSPI-owned) |
| GPP_A2 | AV22 | ESPI_IO1 <39,40> | io | RC367 series | p.20 | eSPI IO1 | NF1 (eSPI-owned) |
| GPP_A3 | AT19 | ESPI_IO2 <39,40> | io | RC368 series | p.20 | eSPI IO2 | NF1 (eSPI-owned) |
| GPP_A4 | BD16 | ESPI_IO3 <39,40> | io | RC369 series | p.20 | eSPI IO3 | NF1 (eSPI-owned) |
| GPP_A5 | BE16 | ESPI_CS# <39,40> | out | - | p.20 | eSPI CS0# | NF1 (eSPI-owned) |
| GPP_A6 | BA17 | ESPI_ALERT# <39> | in | - | p.20 | eSPI alert from EC | NF1 (eSPI-owned) |
| GPP_A7 | AW17 | NC | NC | - | p.20 | - | PAD_NC |
| GPP_A8 | AW22 | CLKRUN# <39> | io | LPC@RH202 8.2K +3.3V_RUN (absent) | p.20 | LPC leftover, routed to EC | ? (NF1 or PAD_NC) |
| GPP_A9 | BC17 | ESPI_CLK -> EMI@RH97 -> ESPI_CLK_5105 <39,40> | out | - | p.20 | eSPI clock | NF1 (eSPI-owned) |
| GPP_A10 | AV19 | PCI_CLK_LPC1 via @RH99 22R (nopop) | NC | - | p.20 | debug-card LPC clock option | PAD_NC |
| GPP_A11 | BD17 | PME# -> @T178 pad | NC | - | p.19 | test pad only | PAD_NC |
| GPP_A12 | BB17 | NC | NC | - | p.20 | - | PAD_NC |
| GPP_A13 | BD19 | ME_SUS_PWR_ACK <39> | out | @RH327 10K +3.3V_ALW_PCH (nopop) | p.20 | SUSPWRDNACK to EC | NF1 (DEEP) |
| GPP_A14 | BC18 | ESPI_RESET# <39> | out | - | p.20 | eSPI reset | NF1 (eSPI-owned) |
| GPP_A15 | BB19 | SUSACK# <39> | in | - | p.20 | SUSACK# from EC | NF1 (DEEP) |
| GPP_A16 | AR17 | NC | NC | - | p.18 | - | PAD_NC |
| GPP_A17 | BC19 | NC | NC | - | p.21 | - | PAD_NC |
| GPP_A18 | BB22 | CLKDET# -> @T258 pad | NC | - | p.21 | test pad only | PAD_NC |
| GPP_A19 | BD21 | NC | NC | - | p.21 | - | PAD_NC |
| GPP_A20 | BD22 | NC | NC | - | p.21 | - | PAD_NC |
| GPP_A21 | BE21 | NC | NC | - | p.21 | - | PAD_NC |
| GPP_A22 | BD18 | TPM_TYPE | strap | @RH379 100R PD GND (nopop), "Reserved" | p.21 | TPM type ID (unused) | GPI or PAD_NC |
| GPP_A23 | BC22 | LID_CL#_PCH -> @T268 pad | NC | - | p.21 | test pad only; lid goes to EC | PAD_NC |
| GPP_B0 | AR27 | NC | NC | - | p.20 | - | PAD_NC |
| GPP_B1 | AL27 | NC | NC | - | p.20 | - | PAD_NC |
| GPP_B2 | BD23 | VRALERT# (no dest) | NC | @RH203 10K +3.3V_ALW_PCH (nopop) | p.20 | unused | PAD_NC |
| GPP_B3 | BC23 | TOUCHPAD_INTR# <39,46> | in | - | p.19 | touchpad IRQ | GPI_APIC (level, low) |
| GPP_B4 | BD24 | TOUCH_SCREEN_DET# <34> | in | - | p.19 | touchscreen present | GPI |
| GPP_B5 | BC24 | CLKREQ_PCIE#0_R | in | RH123 10K +3.3V_RUN; @RF@RH10 0R to CLKREQ_PCIE#0 <37> (nopop) | p.18 | SRCCLKREQ0# WWAN | NF1 |
| GPP_B6 | AW24 | CLKREQ_PCIE#1_R | in | RH124 10K; @RF@RH11 (nopop) <37> | p.18 | SRCCLKREQ1# WLAN | NF1 |
| GPP_B7 | AT24 | CLKREQ_PCIE#2_R | in | RH125 10K; @RF@RH12 (nopop) <37> | p.18 | SRCCLKREQ2# WiGig (WLAN slot 2nd port) | NF1 |
| GPP_B8 | BD25 | CLKREQ_PCIE#3_R | in | RH126 10K; @RF@RH13 (nopop) <42> | p.18 | SRCCLKREQ3# KEYM | NF1 |
| GPP_B9 | BB24 | CLKREQ_PCIE#4_R | in | RH127 10K; @RF@RH14 (nopop) <35> | p.18 | SRCCLKREQ4# LAN I219 | NF1 |
| GPP_B10 | BE25 | CLKREQ_PCIE#5_R | in | RH131 10K; @RF@RH15 (nopop) <36> | p.18 | SRCCLKREQ5# card reader | NF1 |
| GPP_B11 | AN24 | NC | NC | - | p.20 | - | PAD_NC |
| GPP_B12 | BC26 | SIO_SLP_S0# <11,21,41,61> | out | - | p.20 | SLP_S0# | NF1 |
| GPP_B13 | BB27 | PCH_PLTRST# | out | @RH62/@RH244/@RH195 0R options | p.19 | platform reset (fan-out p.19 options) | NF1 |
| GPP_B14 | BD26 | SPKR <38> | out/strap | @RH86 4.7K (nopop) = top swap off | p.20 | speaker + top-swap strap | NF1 |
| GPP_B15 | AR24 | MEDIACARD_IRQ# <36> | in | - | p.21 | SD reader IRQ | GPI_APIC |
| GPP_B16 | AW27 | ONE_DIMM# | strap | @RH267 10K PU (nopop), RH268 10K PD | p.21 | LOW = 2 DIMM | GPI |
| GPP_B17 | BD27 | TPM_PIRQ# <41> | in | - | p.21 | TPM IRQ | GPI_APIC (level, low) |
| GPP_B18 | BD28 | NRB_BIT | strap | @RH331 4.7K PU (nopop) -> LOW | p.21 | no-reboot strap off | GPI |
| GPP_B19 | BC27 | HDD_FALL_INT <43> | in | RH355 10K +3.3V_RUN | p.21 | free-fall sensor IRQ | GPI_APIC |
| GPP_B20 | AV29 | SIO_EXT_SCI# <39> | in | RH339 10K +3.3V_RUN | p.21 | EC SCI | GPI_SCI (low) |
| GPP_B21 | AR29 | 3.3V_TS_EN <34> | out | RH375 100K +3.3V_RUN | p.21 | touchscreen power enable | GPO |
| GPP_B22 | AT29 | BBS_BIT6 | strap | no pull on sheet | p.21 | boot BIOS strap (LOW = SPI) | GPI |
| GPP_B23 | AT27 | GPP_B23 (strap net) | strap | RH347 (value unread); @QC3 + @RC327 "EXI BOOT STALL BYPASS" | p.20 | strap only | GPI or PAD_NC |
| GPP_C0 | AW44 | MEM_SMBCLK | od | - | p.20 | SMBus host (DIMM SPD) | NF1 |
| GPP_C1 | BB43 | MEM_SMBDATA | od | - | p.20 | SMBus host | NF1 |
| GPP_C2 | BB41 | PCH_SMB_ALERT# | in | local pull | p.20 | SMBALERT# | NF1 |
| GPP_C3 | AY44 | SML0_SMBCLK <35> | od | - | p.20 | SMLink0 to LAN | NF1 |
| GPP_C4 | BB39 | SML0_SMBDATA <35> | od | - | p.20 | SMLink0 to LAN | NF1 |
| GPP_C5 | BA40 | GPP_C5 (strap net) | strap | ESPI@RH78 4.7K PU (pop) -> eSPI | p.20 | eSPI/LPC select strap | GPI or PAD_NC |
| GPP_C6 | AW42 | SML1_SMBCLK <39> | od | - | p.20 | SMLink1 to EC | NF1 |
| GPP_C7 | AW45 | SML1_SMBDATA <39> | od | - | p.20 | SMLink1 to EC | NF1 |
| GPP_C8 | BA41 | GPP_C8 (UART0_RXD) | NC | @RH207 100K +3.3V_RUN (nopop), "Reserved" | p.21 | unused | PAD_NC |
| GPP_C9 | AV44 | SBIOS_TX <40> -> @RE306 0R (nopop) -> HOST_DEBUG_TX <37,39> | out | - | p.21 | UART0 TX, debug option (link nopop) | NF1 if console on UART0 |
| GPP_C10 | AV43 | NC | NC | - | p.21 | - | PAD_NC |
| GPP_C11 | AU44 | NC | NC | - | p.21 | - | PAD_NC |
| GPP_C12 | AU43 | SIO_EXT_WAKE# <39> | in | RH309 10K +3.3V_ALW_PCH | p.21 | EC wake | GPI_SCI or GPI_ACPI_WAKE |
| GPP_C13 | AT43 | RTD3_CIO_PWR_EN <29> | out | - | p.21 | Alpine Ridge CIO power (RTD3) | GPO |
| GPP_C14 | AT44 | LCD_CBL_DET# <34> | in | RC370 10K +3.3V_RUN | p.21 | eDP cable present | GPI |
| GPP_C15 | AU41 | HDD_EN <43> | out | - | p.21 | 2.5" bay power enable | GPO(1) |
| GPP_C16 | AT42 | NC | NC | - | p.21 | - | PAD_NC |
| GPP_C17 | AR38 | NC | NC | - | p.21 | - | PAD_NC |
| GPP_C18 | AR44 | I2C1_SDA_TP <46> | od | - | p.21 | touchpad I2C | NF1 |
| GPP_C19 | AR41 | I2C1_SCK_TP <46> | od | - | p.21 | touchpad I2C | NF1 |
| GPP_C20 | AR45 | LPSS_UART2_RXD -> JUART1 pin 3 | in | RH376 49.9K +3.3V_ALW_PCH; @RH361 | p.21 | UART2 RX, debug header | NF1 (console) |
| GPP_C21 | AR39 | LPSS_UART2_TXD -> JUART1 pin 2 | out | RH330 49.9K +3.3V_ALW_PCH; @RH360 | p.21 | UART2 TX, debug header | NF1 (console) |
| GPP_C22 | AN44 | NC | NC | - | p.21 | - | PAD_NC |
| GPP_C23 | AN43 | NC | NC | - | p.21 | - | PAD_NC |
| GPP_D0 | AL39 | NC | NC | - | p.19 | - | PAD_NC |
| GPP_D1 | AN36 | NC | NC | - | p.19 | - | PAD_NC |
| GPP_D2 | AN38 | NC | NC | - | p.19 | - | PAD_NC |
| GPP_D3 | AN41 | NC | NC | - | p.19 | - | PAD_NC |
| GPP_D4 | AM44 | TBT_FORCE_PWR <29> | out | - | p.21 | Alpine Ridge force power | GPO(0) |
| GPP_D5 | AJ33 | NC | NC | - | p.20 | - | PAD_NC |
| GPP_D6 | AM43 | NC | NC | - | p.20 | - | PAD_NC |
| GPP_D7 | AN42 | NC | NC | - | p.20 | - | PAD_NC |
| GPP_D8 | AL42 | NC | NC | - | p.20 | - | PAD_NC |
| GPP_D9 | AL44 | MEM_INTERLEAVED | strap | @RH371 10K PU (nopop), RH372 10K PD | p.21 | LOW = non-interleaved | GPI |
| GPP_D10 | AL36 | DGPU_HOLD_RST# <49> | out | @RH350 100K (nopop) | p.21 | dGPU reset hold | GPO |
| GPP_D11 | AL35 | AR_DET# | strap | @RH400 10K PU (nopop), RH401 10K PD | p.21 | LOW = Alpine Ridge fitted | GPI |
| GPP_D12 | AJ39 | DGPU_PWR_EN <18,53> | out | RH346 100K PU +3.3V_RUN (pop); @RH349 100K PD GND (nopop) | p.21 | dGPU power enable; default HIGH (dGPU on) until PCH drives it | GPO |
| GPP_D13 | AK45 | ISH_UART0_RXD <37> | in | - | p.21 | UART to WLAN slot (BT) | NF? / PAD_NC |
| GPP_D14 | AK44 | ISH_UART0_TXD <37> | out | - | p.21 | UART to WLAN slot (BT) | NF? / PAD_NC |
| GPP_D15 | AL43 | ISH_UART0_RTS# <37> | out | - | p.21 | UART to WLAN slot (BT) | NF? / PAD_NC |
| GPP_D16 | AJ43 | ISH_UART0_CTS# <37> | in | - | p.21 | UART to WLAN slot (BT) | NF? / PAD_NC |
| GPP_D17 | AJ42 | KB_DET# <46> | in | - | p.20 | keyboard present | GPI |
| GPP_D18 | AJ38 | DGPU_PWROK <40,53,69> | in | - | p.20 | dGPU power good | GPI |
| GPP_D19 | AJ35 | IR_CAM_DET# <34> | in | RH373 100K +3.3V_RUN | p.20 | IR camera present | GPI |
| GPP_D20 | AH44 | TBT_PWR_EN -> @T269 pad | NC | - | p.20 | test pad only | PAD_NC |
| GPP_D21 | AG44 | NC | NC | - | p.19 | - | PAD_NC |
| GPP_D22 | AH43 | NC | NC | - | p.19 | - | PAD_NC |
| GPP_D23 | AJ44 | FFS_INT2 <43> | in | RH378 10K +3.3V_RUN | p.21 | free-fall sensor INT2 | GPI |
| GPP_E0 | AG36 | M2280_PCIE_SATA# <42> | in | - | p.16 | SATAXPCIE0: KEYM module type | NF1 |
| GPP_E1 | AG35 | SATAGP1 (stub) | NC | - | p.16 | SPSGP1=0 | PAD_NC |
| GPP_E2 | AG39 | HDD_DET# <43> | in | - | p.16 | 2.5" drive present | GPI |
| GPP_E3 | AF41 | SIO_EXT_SMI# <39> | in | - | p.19 | EC SMI | GPI_SMI (low) |
| GPP_E4 | AG42 | M2280_DEVSLP <42> | out | - | p.20 | DEVSLP0: KEYM | NF1 |
| GPP_E5 | AG43 | NC | NC | - | p.20 | - | PAD_NC |
| GPP_E6 | AE45 | HDD_DEVSLP <43> | out | - | p.20 | DEVSLP2: 2.5" bay (SATA-2) | NF1 |
| GPP_E7 | AE44 | TOUCH_SCREEN_PD# <34> | out | - | p.19 | touchscreen power-down | GPO |
| GPP_E8 | AD44 | SATALED# <37,42,47> | out | - | p.16 | SATA activity LED | NF1 |
| GPP_E9 | AD43 | USB_OC0# <44> | in | RPH6 10K | p.17 | USB2 OC0 | NF1 |
| GPP_E10 | AD42 | USB_OC1# <45> | in | RPH6 10K | p.17 | USB2 OC1 | NF1 |
| GPP_E11 | AD39 | USB_OC2# <45> | in | RPH6 10K | p.17 | USB2 OC2 | NF1 |
| GPP_E12 | AC44 | USB_OC3# ("Reserve") | in | RPH6 10K | p.17 | unused OC | NF1 or PAD_NC |
| GPP_F0 | AD35 | SATAGP3 (stub) | NC | - | p.16 | SPSGP3=0 | PAD_NC |
| GPP_F1 | AD31 | m3042_PCIE#_SATA <37,39> | in | RH344 10K +3.3V_RUN (p.16) | p.16 | SATAXPCIE4: WWAN slot PCIe17 vs SATA4 | NF1 |
| GPP_F2 | AD38 | SATAGP5 "Reserve" | NC | - | p.16 | - | PAD_NC |
| GPP_F3 | AC43 | SATAGP6 "Reserve" | NC | - | p.16 | - | PAD_NC |
| GPP_F4 | AB44 | SATAGP7 "Reserve" | NC | - | p.16 | - | PAD_NC |
| GPP_F5 | AB41 | NC | NC | - | p.20 | - | PAD_NC |
| GPP_F6 | AB42 | m3042_DEVSLP <37> | out | - | p.20 | DEVSLP4: WWAN slot as SSD | NF1 |
| GPP_F7 | AB43 | NC | NC | - | p.20 | - | PAD_NC |
| GPP_F8 | AB36 | NC | NC | - | p.20 | - | PAD_NC |
| GPP_F9 | AB39 | NC | NC | - | p.20 | - | PAD_NC |
| GPP_F10 | AB33 | BIOS_REC | strap/in | RH76 10K +3.3V_RUN (p.16) | p.16 | Dell recovery (pull low) | GPI |
| GPP_F11 | AB35 | NC | NC | - | p.16 | - | PAD_NC |
| GPP_F12 | AA45 | NC | NC | - | p.16 | - | PAD_NC |
| GPP_F13 | AA44 | NC | NC | - | p.16 | - | PAD_NC |
| GPP_F14 | Y44 | NC | NC | - | p.21 | - | PAD_NC |
| GPP_F15 | Y43 | NC | NC | - | p.17 | - | PAD_NC |
| GPP_F16 | Y41 | NC | NC | - | p.17 | - | PAD_NC |
| GPP_F17 | W44 | NC | NC | - | p.17 | - | PAD_NC |
| GPP_F18 | W43 | NC | NC | - | p.17 | - | PAD_NC |
| GPP_F19 | W42 | ENVDD_PCH <34,39> | out | - | p.16 | EDP_VDDEN panel power | NF1 |
| GPP_F20 | W35 | PANEL_BKEN_PCH <34> | out | - | p.16 | EDP_BKLTEN | NF1 |
| GPP_F21 | W36 | BIA_PWM_PCH <34> | out | - | p.16 | EDP_BKLTCTL (PWM) | NF1 |
| GPP_F22 | W39 | NC | NC | - | p.21 | - | PAD_NC |
| GPP_F23 | V44 | NC | NC | - | p.21 | - | PAD_NC |
| GPP_G0 | U43 | CAM_MIC_CBL_DET# <34> | in | - | p.16 | camera/mic cable present | GPI |
| GPP_G1 | U42 | GC6_EVENT# <49> | in | - | p.16 | dGPU GC6 event | GPI_SCI |
| GPP_G2 | U41 | TBT_CIO_PLUG_EVENT# <29> | in | - | p.16 | TB3 hot-plug | GPI_SCI (low) |
| GPP_G3 | M44 | GPU_GC6_FB_EN <49,53> | out | - | p.16 | dGPU GC6 framebuffer enable | GPO |
| GPP_G4 | U36 | CONTACTLESS_DET# <41> | in | - | p.16 | USH/NFC present | GPI |
| GPP_G5 | P44 | HOST_SD_WP# <36> | in | - | p.16 | SD write-protect | GPI |
| GPP_G6 | T45 | AUD_PWR_EN <38> | out | - | p.16 | codec power | GPO(1) |
| GPP_G7 | T44 | NC | NC | - | p.16 | - | PAD_NC |
| GPP_G8 | R44 | NC | NC | - | p.16 | - | PAD_NC |
| GPP_G9 | R43 | NC | NC | - | p.16 | - | PAD_NC |
| GPP_G10 | U39 | NC | NC | - | p.16 | - | PAD_NC |
| GPP_G11 | N42 | NC | NC | - | p.16 | - | PAD_NC |
| GPP_G12 | R39 | NC | NC | - | p.19 | - | PAD_NC |
| GPP_G13 | R36 | NC | NC | - | p.19 | - | PAD_NC |
| GPP_G14 | R42 | NC | NC | - | p.19 | - | PAD_NC |
| GPP_G15 | R41 | NC | NC | - | p.19 | - | PAD_NC |
| GPP_G16 | P43 | NC | NC | - | p.19 | - | PAD_NC |
| GPP_G17 | N44 | NC | NC | - | p.20 | - | PAD_NC |
| GPP_G18 | N43 | NC | NC | - | p.20 | - | PAD_NC |
| GPP_G19 | M45 | NC | NC | - | p.20 | - | PAD_NC |
| GPP_G20 | R35 | NC | NC | - | p.21 | - | PAD_NC |
| GPP_G21 | U35 | NC | NC | - | p.21 | - | PAD_NC |
| GPP_G22 | L44 | NC | NC | - | p.21 | - | PAD_NC |
| GPP_G23 | L43 | NC | NC | - | p.21 | - | PAD_NC |
| GPP_H0 | AT33 | CLKREQ_PCIE#6_R | in | RH132 10K +3.3V_RUN; @RF@RH16 (nopop) <29> | p.18 | SRCCLKREQ6# Alpine Ridge | NF1 |
| GPP_H1 | AR31 | CLKREQ_PCIE#7_R | in | RH133 10K +3.3V_RUN; @RF@RH17 (nopop) <49>; @QH5 from DGPU_PWR_EN | p.18 | SRCCLKREQ7# dGPU | NF1 |
| GPP_H2 | BD32 | NC | NC | - | p.18 | - | PAD_NC |
| GPP_H3 | BC32 | NC | NC | - | p.18 | - | PAD_NC |
| GPP_H4 | BB31 | NC | NC | - | p.18 | - | PAD_NC |
| GPP_H5 | BC33 | NC | NC | - | p.18 | - | PAD_NC |
| GPP_H6 | BA33 | NC | NC | - | p.18 | - | PAD_NC |
| GPP_H7 | AW33 | NC | NC | - | p.18 | - | PAD_NC |
| GPP_H8 | BB33 | NC | NC | - | p.18 | - | PAD_NC |
| GPP_H9 | BD33 | NC | NC | - | p.18 | - | PAD_NC |
| GPP_H10 | BD34 | NC | NC | - | p.19 | - | PAD_NC |
| GPP_H11 | AW35 | NC | NC | - | p.19 | - | PAD_NC |
| GPP_H12 | BD35 | NC | NC | - | p.19 | - | PAD_NC |
| GPP_H13 | BC35 | NC | NC | - | p.19 | - | PAD_NC |
| GPP_H14 | BA35 | NC | NC | - | p.19 | - | PAD_NC |
| GPP_H15 | BB36 | NC | NC | - | p.19 | - | PAD_NC |
| GPP_H16 | BD39 | NC | NC | - | p.19 | - | PAD_NC |
| GPP_H17 | BE34 | NC | NC | - | p.19 | - | PAD_NC |
| GPP_H18 | BC36 | NC | NC | - | p.19 | - | PAD_NC |
| GPP_H19 | BB38 | NC | NC | - | p.21 | - | PAD_NC |
| GPP_H20 | BC38 | NC | NC | - | p.21 | - | PAD_NC |
| GPP_H21 | BE39 | NC | NC | - | p.21 | - | PAD_NC |
| GPP_H22 | BD38 | NC | NC | - | p.21 | - | PAD_NC |
| GPP_H23 | BD36 | NC | NC | - | p.21 | - | PAD_NC |
| GPP_I0 | AW4 | PCH_DP1_HPD <27> | in | - | p.21 | DDPB HPD: HDMI | NF1 |
| GPP_I1 | AY2 | PCH_DP2_HPD <29> | in | - | p.21 | DDPC HPD: TB3 DP | NF1 |
| GPP_I2 | AV4 | PCH_DP3_HPD <25> | in | - | p.21 | DDPD HPD: DP switch 1 | NF1 |
| GPP_I3 | BA4 | NC | NC | - | p.21 | - | PAD_NC |
| GPP_I4 | BD7 | EDP_HPD <34> | in | RH1 100K | p.21 | eDP HPD | NF1 |
| GPP_I5 | BA5 | PCH_DP1_CTRL_CLK <27> | od | RH222 2.2K +3.3V_RUN | p.21 | DDPB DDC | NF1 |
| GPP_I6 | BC4 | PCH_DP1_CTRL_DATA <27> | od | RH223 2.2K +3.3V_RUN | p.21 | DDPB DDC | NF1 |
| GPP_I7 | BB3 | NC | NC | - | p.21 | - | PAD_NC |
| GPP_I8 | BD6 | PCH_DP2_CTRL_DATA (local) | strap | RH221 2.2K +3.3V_RUN | p.21 | DDPC presence strap | NF1 |
| GPP_I9 | BE5 | PCH_DP3_CTRL_CLK <25> | od | RH224 2.2K +3.3V_RUN | p.21 | DDPD DDC | NF1 |
| GPP_I10 | BE6 | PCH_DP3_CTRL_DATA <25> | od | RH225 2.2K +3.3V_RUN | p.21 | DDPD DDC | NF1 |
| GPD0 | BD13 | PCH_BATLOW# | in | RH94 8.2K +3.3V_DSW | p.20 | tied high, no source | NF1 (DEEP) |
| GPD1 | BB15 | AC_PRESENT <39> | in | RH243 10K +3.3V_DSW | p.20 | AC present from EC | NF1 (DEEP) |
| GPD2 | BD11 | LAN_WAKE# <35,39> | in | RH93 10K +3.3V_DSW | p.20 | LAN wake | NF1 (DEEP) |
| GPD3 | AT13 | SIO_PWRBTN# <7,39> | in | - | p.20 | power button from EC | NF1 (DEEP) |
| GPD4 | AW15 | SIO_SLP_S3# <21,29,39,40,62> | out | - | p.20 | SLP_S3# | NF1 (DEEP) |
| GPD5 | BD15 | SIO_SLP_S4# <11,21,39,59,62> | out | - | p.20 | SLP_S4# | NF1 (DEEP) |
| GPD6 | BC15 | SIO_SLP_A# <20,21,39> | out | - | p.20 | SLP_A# | NF1 (DEEP) |
| GPD7 | BD14 | 3.3V_CAM_EN# <34> | out | - | p.17 | camera power enable | GPO (DEEP) |
| GPD8 | AN15 | SUSCLK <37,42> | out | - | p.20 | 32 kHz to M.2 slots | NF1 (DEEP) |
| GPD9 | AV13 | SIO_SLP_WLAN# <39,48> | out | - | p.20 | SLP_WLAN# | NF1 (DEEP) |
| GPD10 | BA13 | SIO_SLP_S5# <21,39> | out | - | p.20 | SLP_S5# | NF1 (DEEP) |
| GPD11 | AR15 | PM_LANPHY_ENABLE <35> | out | - | p.20 | LANPHYPC to I219 | NF1 (DEEP) |

Totals: 204 pads (GPP_A..I + GPD). 94 NC, 110 routed/strap (script count over the table) (p.16–p.21).

## What fits here
Spare sidebands for an extra slot: none on copper. Unused root ports `PCIE-13, 14, 16, 20` have `X` on all four balls [visual], and `PCIE-19` (H44/H43/L39/L37) has no net [text] (p.16). `CLKOUT_PCIE_8..15` and `SRCCLKREQ8#..15#` are ball-only NC (p.18). A new slot would need BGA-ball rework on the PCH, so no.
FIT: new PCIe slot on PCIE-13/14/16/19/20 | needs: wires to PCH BGA balls (lanes + CLKOUT_PCIE_8+) | lanes/bus: up to 5 × x1 Gen3 | power: none routed | displaces: nothing | DIY: none found | risk: H — no pads, BGA only (p.16, p.18)
FIT: coreboot/Linux serial console on `JUART1` footprint (PCH LPSS UART2, `GPP_C20` RX / `GPP_C21` TX) | needs: 6-pin CVILU CI1804M1VRA-NH header or 3 wires soldered to the pads + 3.3 V USB-UART. Leave pin 1 `+5V_ALW` unconnected, and note that `RH330`/`RH376` 49.9 K pull-ups hold both lines at `+3.3V_ALW_PCH` | lanes/bus: UART2 | power: none drawn | displaces: nothing | DIY: https://github.com/coreboot/coreboot/blob/main/src/soc/intel/skylake/Kconfig (SKL/KBL LPSS UART console, `INTEL_LPSS_UART_FOR_CONSOLE`), no Dell laptop precedent found | risk: L (p.21)
FIT: spare GPIO taps on test pads: `GPP_D20` (`@T269`, net `TBT_PWR_EN`), `GPP_A23` (`@T268`, `LID_CL#_PCH`), `GPP_A18` (`@T258`, `CLKDET#`), `GPP_A11` (`@T178`, `PME#`). Usable as reset/enable for a DIY device once coreboot owns the pad config | needs: fine wire to TP, pad config GPO/GPI | lanes/bus: GPIO 3.3 V | power: - | displaces: nothing (no other load on these nets) | DIY: none found | risk: H — test-pad copper not confirmed on PCB (p.19, p.20, p.21)
FIT: existing slot sidebands already complete: WWAN (#0), WLAN (#1) and the WiGig second port (#2) have their own CLKOUT + CLKREQ into JNGFF1/JNGFF2. The WLAN slot also gets `ISH_UART0` (`GPP_D13..D16`) for UART Bluetooth | needs: nothing | lanes/bus: see Phase 5 | power: Phase 6 | displaces: - | DIY: none found — schematic alone (clocks + CLKREQ + UART all routed) | risk: L (p.18, p.21, p.37)
Hidden root ports on other Dell ports: upstream `sklkbl_desktops` just switches individual RPs on in `overridetree.cb` (`device ref pcie_rp21 on`, https://github.com/coreboot/coreboot/blob/main/src/mainboard/dell/sklkbl_desktops/variants/optiplex_3050/overridetree.cb). On this board there is nothing to switch on beyond RP1–12, 15, 17, 18 (p.16).

## Open
- `@RF@RH10..17` (CLKREQ links) vs E151P `RF@`: DMM on the board (p.18).
- `RH347` value and pull direction on `GPP_B23` not legible (p.20).
- `[text]` cross-refs that did not resolve: `LID_CL#_PCH`, `CLKDET#`, `TPM_TYPE`, `ONE_DIMM#`, `RTD3_CIO_PWR_EN` (p.29 draws it `RTD3_CIO_PW…`, truncated), `TBT_PWR_EN` (pad only), `PCH_DP2_CTRL_DATA` (local strap), `MEM_SMBCLK` (p.5 only; DIMM sheets use their own name) (p.21, p.20, p.29).
- `GPP_D13..D16` native function (ISH UART0 vs GPIO) depends on the stock BIOS; read the stock pad config (`intelp2m`) (p.21).
- Plan source ref `src/mainboard/dell/optiplex_3050` moved upstream to `src/mainboard/dell/sklkbl_desktops/variants/optiplex_3050` (p.18 context).
