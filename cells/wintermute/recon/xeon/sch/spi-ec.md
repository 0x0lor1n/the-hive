# LA-E152P — SPI flash, EC, boot path (Phase 1)

Source: `Dell-3520-LA-E152P-schematic.pdf` sha256 `551d1fe5…1a9cb`. `[visual]` = read on a 300–400 dpi render this session; `[text]` = pdftotext + cross-ref on ≥2 sheets only.
E151P (5580) diff noted where it matters (p.19 of that PDF).

## Flash

- One SPI flash on the board: `UC5` `W25Q128FVSIQ_SO8`, "128Mb Flash ROM" = 16 MiB, SOIC-8, on PCH `SPI0_CS0#` [visual] (p.19).
- `@UC6` `W25Q64FVSSIQ_SO8` "64Mb Flash ROM" on `SPI0_CS1#` is nopop, together with `@RPC2`, `@RH352`, `@RH353` [visual] (p.19). The second chip on the p2 block diagram is this nopop footprint, not an EC or TBT flash — corrects the Phase 0 note (p.2, p.19).
- `UC5` pins: 1 `/CS`=`PCH_SPI_CS#0_R2`, 2 `DO`=`PCH_SPI_D1_0_R`, 3 `/WP`=`PCH_SPI_D2_0_R`, 4 GND, 5 `DI`=`PCH_SPI_D0_0_R`, 6 `CLK`=`PCH_SPI_CLK_0_R`, 7 `/HOLD`=`PCH_SPI_D3_0_R`, 8 `VCC`=`+3.3V_SPI` [visual] (p.19).
- Series parts to `UC5`: `RPC1` 33 Ω ×4 (D1, D0, CLK, D3), `RH351` 33 Ω (D2) [visual] (p.19). WP/HOLD pulls `@RH30`/`@RH335`/`@RH334` all nopop — QE bit in the flash decides IO2/IO3 (p.19).
- PCH side: `SPI0_MOSI` BB29=`PCH_SPI_D0`, `SPI0_MISO` BE30=`PCH_SPI_D1`, `SPI0_CS0#` BD31=`PCH_SPI_CS#0`, `SPI0_CLK` BC31=`PCH_SPI_CLK`, `SPI0_CS1#` AW31, `SPI0_IO2` BC29, `SPI0_IO3` BD30, `SPI0_CS2#` AT31=`PCH_SPI_CS#2`→TPM `<41>` [visual] (p.19).
- OPEN: on E152P the 0 Ω bridges PCH→`_R1` (`@RH177..@RH184`), `@RH37` (`CS#0_R1`→`CS#0_R2`) and `@RH185` (`+3.3V_ALW_PCH`→`+3.3V_SPI`) are all drawn `@`; on E151P the same parts are populated (E151P p.19). The board boots, so the path exists — either the BOM view in this PDF is stale or `JSPI1` carries it. Verify on the board with a DMM before trusting either: RH37, RH182, RH185 pads (p.19).
- `JSPI1` `CONN@` `E-T_6705K-Y20N-00L`, 22-pin, "CIS link OK": pairs `PCH_SPI_x` / `PCH_SPI_x_R1` on pins 7–20, pin 5 `+3.3V_ALW_PCH`, pin 6 `+3.3V_SPI` — Dell in-series SPI debug/emulator header, sits between PCH and flash [visual] (p.19).
- `+3.3V_SPI` = "Pop option" branch of `+3.3V_ALW_PCH` [visual] (p.56). `+3.3V_ALW_PCH` = `UZ3` EM5209VF ch1: `+3.3V_ALW` in, `ON1`=`SIO_SLP_SUS#` (`@RZ65` from `PCH_ALW_ON` nopop), via `PJP38`, 1.102 A [visual] (p.48). Ch2 = `+3.3V_RUN` 4.677 A, `ON2`=`RUN_ON` (p.48).
- Descriptor layout (not in schematic; from a public E151P 5580 dump, same PCH/flash family — re-check on our own dump): Desc, GbE 8 KiB, ME 0x3000–0x6FFFFF, **EC 0x700000–0x74FFFF (320 KiB)**, BIOS 0x750000–0xFFFFFF, one component (p.19).

## EC

- EC = `MEC5105` (`MEC5105_W FBGA169_11X11`, `UE1`) [text] (p.39, p.74).
- EC↔PCH bus = eSPI, not LPC: strap `ESPI@ RH78` 4.7 kΩ populated, table "HIGH = ESPI / LOW(DEFAULT) = LPC" [visual] (p.20). PCH pins `GPP_A1..A4`=`ESPI_IO0..3`, `GPP_A5`=`ESPI_CS#`, `GPP_A9`=`ESPI_CLK`→`ESPI_CLK_5105`, `GPP_A6`→`ESPI_ALERT#`, `GPP_A14`=`ESPI_RESET#`, `GPP_A0`=`SIO_RCIN#`, all `<39,40>` [visual] (p.20); EC side `GPIO070..073`, `GPIO066`, `GPIO065`, `GPIO063`, `GPIO061` [text] (p.39).
- No separate EC flash: the EC shared-flash pins `SHD_IO0..3/SHD_CLK/SHD_CS#` go through `LPC@` resistors `RE366..RE374` to `UE9`, which is itself `LPC@` — LPC build only; this is the eSPI build [text] (p.39). Note on sheet: "GPIO055 use for SHD_CS# (LPC) or PCH_RSMRST#(eSPI)" (p.39). ⇒ EC firmware lives in `UC5` (EC region, loaded over eSPI) — a full `UC5` dump is also the EC backup (p.19, p.39).
- EC SMBus: `SML1_SMBCLK/DATA` to PCH, `PBAT_CHARGER_SMB*` `<57,66>`, `UPD1/UPD2_SMB*` to PD `<31>`, `USH_SMB*`, `EXPANDER_GPU_SM*` `<40,49>` [text] (p.39).
- EC JTAG `JTAG_TDI/TDO/CLK/TMS` → `<40>` [text] (p.39, p.40).

## Power-sequence nets
| net | source → sink | page | status |
|---|---|---|---|
| `PCH_RSMRST#` | EC `GPIO204` → `UZ6` TC7SH08 AND with `ALW_PWRGD_3V_5V` `<58>` → `PCH_RSMRST#_AND` → PCH `RSMRST#` + CPU `<7>` | p.39, p.46, p.20 | [visual] p.46/p.20 |
| `PCH_DPWROK` | EC `PCH_DPWROK_EC` → backdrive-guard (`QE13`, ACAV_IN) → PCH `DSW_PWROK` | p.39, p.40, p.20 | [text] |
| `PCH_PWROK` | power sheet `PR618` `<63>` → PCH `PCH_PWROK` | p.63, p.20 | [visual] p.20 |
| `SYS_PWROK` | EC `GPIO106/PWROK` → PCH `SYS_PWROK` + CPU `<7,20>` | p.39, p.20 | [visual] p.20 |
| `SIO_PWRBTN#` | EC → PCH `GPD3/PWRBTN#` `<7,20>`; button = `POWER_SW_IN#` from `POWER_SW#_MB` `<21,47>` | p.39, p.40, p.20 | [visual] p.20 |
| `SIO_SLP_S3#/S4#/S5#/A#/SUS#/LAN#/WLAN#` | PCH `GPD4/GPD5/GPD10/GPD6/SLP_SUS#/SLP_LAN#/GPD9` → EC + rails | p.20, p.39, p.48 | [visual] p.20 |
| `ESPI_RESET#` | PCH `GPP_A14` → EC `GPIO061` | p.20, p.39 | [visual] p.20 |
| `RUN_ON` / `PCH_ALW_ON` | EC → `UZ3` `ON2` / (`ON1` option, nopop) | p.39, p.48 | [visual] p.48 |
| `LID_CL#` → `LID_CL#_NB` | lid board `<47>` → `UE3` → EC | p.47, p.40, p.39 | [text] |
| `SYS_RESET#` | PCH `SYS_RESET#` `<17,21>` | p.20 | [visual] |
| `PCH_RTCRST#` / `SRTCRST#` | RC to `+RTC_CELL` (RH200 220K, RH201 20K), `PCH_RTCRST#` also to EC `<21,39>` | p.20 | [visual] |

## Straps
- `BIOS_REC` on `GPP_F10/SCLOCK` (AB33), `RH76` 10 kΩ pull-up to `+3.3V_RUN` [visual] (p.16). Dell recovery = pull low; no header on sheet.
- Top swap: strap on `SPKR`/`GPP_B14` via `@RH86` 4.7 kΩ — nopop → LOW → disabled (default) [visual] (p.20).
- Flash-descriptor override: `ME_FWP` → `RH328` 1 kΩ → `HDA_SDO` (BB7) [visual] (p.20). `ME_FWP` is driven by `QH4` DMN65D8LDW from EC `ME_FW_EC` `<20>`; note "Add a switch to ME_FWP signal to unlock the ME region… using FPT", "LOW = ENABLE (DEFAULT) / HIGH = DISABLE (ME can update)", "PCH has internal 20K PD" [text] (p.20, p.39). ⇒ EC can open the descriptor in software; physical switch population unverified.
- `m3042_PCIE#_SATA` `RH344` 10 kΩ to `+3.3V_RUN` (WWAN slot mode, Phase 5) [visual] (p.16).
- TPM bus = SPI, not LPC: `UZ12` `NPCT650JB2YX_QFN32` (Nuvoton) on `SPI0_CS2#`, `RZ58/RZ59/RZ60` 33 Ω on MISO/MOSI/CLK from the `_R1` nets, reset `PLTRST_TPM#` from `UH7` TC7SH08, `TPM_PIRQ#` `<21>`; `VSB`=`+3.3V_M_TPM` from `+3.3V_ALW` (`PJP391` option from `+3.3V_ALW_PCH`) [visual] (p.41, p.19).

## Programmer caveats (feeds `dump` wording)
- Clip target: `UC5` W25Q128FV, SOIC-8, 3.3 V native — matches old-board 1.1 part family (p.19). flashrom `W25Q128.V`.
- Clip VCC lands on `+3.3V_SPI` = `+3.3V_ALW_PCH`: back-powers the PCH suspend well and anything on that net (`JSPI1` pin 5, `PJP391` TPM option) through `UZ3` output (p.19, p.48, p.56). Expect the PCH to wake partially and fight on the bus — if `flashrom` reads garbage, that is why.
- Same SPI0 bus carries the TPM (`CS#2`, 33 Ω isolated) — unpowered TPM IO sits on MISO/MOSI/CLK (p.41). The PD controller TPS65982 has its own SPI, not on this bus (p.31).
- ⇒ `dump` wording: battery out, coin cell out, AC and USB-C unplugged; clip `UC5` only; `UC5` also holds the EC firmware, so the dump is the EC backup too (p.19, p.39).

## What fits here
The only "does the board reject a card" mechanism on sheet is the M.2 `CONFIG_0..3` → EC path (`SLOT2_CONFIG_0..3` `<37>`→`<39>`), i.e. spec module-type detect (SSD-SATA / SSD-PCIe / WWAN / HCA), not a vendor-ID strap (p.37, p.39). No WLAN/WWAN ID straps on any sheet (p.37, p.39).
FIT: third-party WWAN modem (EM7455 non-Dell, RM520N-GL, EM9191) not blocked by BIOS | needs: nothing on board; driver/FCC-unlock is OS side | lanes/bus: USB3 port 2 + PCIe 17/18 per `CONFIG` straps | power: `+3.3V_WWAN` (Phase 5/6) | displaces: nothing | DIY: https://forum.sierrawireless.com/t/lenovo-em7455-on-dell-precision-3520-laptop/23736 (Lenovo EM7455 enumerates in a 3520, fails only on Windows driver) | risk: M (p.37)
FIT: third-party Wi-Fi in `WLAN` (MT7925, AX210-class) not blocked by BIOS | needs: nothing on board | lanes/bus: PCIe 2 + USB (Phase 5) | power: `+3.3V_WLAN` (p.48) | displaces: stock card | DIY: https://community.spiceworks.com/t/dell-blocking-non-dell-branded-wireless-cards/275610 (Dell rep: no BIOS peripheral whitelist; generic, not 3520-specific) | risk: M (p.37)
⇒ coreboot is not a prerequisite for a network mod (p.37, p.39).

## Open (not yet `[visual]`)
- EC-side pin balls on p.39 (sheet is an image-title page; text only) — needed only if coreboot EC code touches them (p.39).
- `@` status of `RH37`, `RH177..RH185` vs board reality — DMM (p.19).
- `SW1`/`RH100`/`RH101` population in the ME_FWP circuit (p.20).
