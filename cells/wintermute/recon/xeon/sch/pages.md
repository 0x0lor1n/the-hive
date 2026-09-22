# LA-E152P (Dell Precision 3520, Compal CDP80/CDP81) — page index

Source: `~/.hermes/cache/web/Dell-3520-LA-E152P-schematic.pdf`, sha256 `551d1fe5…1a9cb` (74 pages, Compal "Breckenridge 15 DSC (TBT)", Rev 1.0 (A00), 2016-11-10).
Method: `pdftotext -layout` per page → title from `Title` field; where the title is drawn as an image (marked `[ocr]`) it was read with tesseract from a 400 dpi crop of the title block; `[vis]` = confirmed with vision on a crop. Key parts/nets are the most frequent refdes/net names on the page (text layer).
Legend for `feeds`: **Px** = phase of `.hermes/state/schematic-e152p.md`; **CB-n** = step of `coreboot-5580.md`; **B-n** = backlog item.

## Kill-switch (0.4) — PASSED
| check | page | evidence |
|---|---|---|
| cover says `LA-E152P` + `DSC (TBT)` | p1 | `[vis]` "Breckenridge 15 DSC (TBT)", MODEL NAME `CDP80/CDP81`, PCB NO `LA-E152P`, GPIO MAP `Dell GPIO map EC16 062416` |
| Alpine Ridge present | p29 | `[text]` `ALPINE-RIDGE_BGA337` (U-refdes on TBT-AR-SP sheet), `[vis]` title "TBT-AR-SP(1/2) DP, PCIE" |
| GM107 present | p49 | `[text]` `GM107-ES-A1_BGA908`, `[vis]` title "N16S PCIE,I2C,DAC,GPIO" |

→ This is the Xeon/dGPU/TBT board. Proceed; E151P (5580) used only for diff.

## Page table
| page | sheet title | key parts / nets | feeds |
|---|---|---|---|
| 1 | Cover Sheet | N16S-GT1-KA, N17M-Q3 (GPU SKUs); CDP80/CDP81; GPIO map EC16 062416 | P0 |
| 2 | Block diagram | PEG[0]~[15]→N16S, GDDR5 x2 (2GB), DMI x4 Gen3, PS8338 ×2, PS8407, ALC3246, W25Q128FVSIQ (BIOS), W25Q64FVSSIQ (EC/TBT?) | P0, P1, P5 |
| 3 | Port Assignment | PM table: USB3.0-1..10, SSIC-1/2, PCIE-1..20, SATA-0A..5, destinations, power planes per S-state | P0 lane budget, P6, P8 |
| 4 | Power Rails | TPS22961, ISL95857, SYX198D, TPS62134C/D, ISL88738; USB_PWR_* enables | P7 |
| 5 | SMbus Block Diagram | USH_SMBCLK/USH_SMBDAT topology | P2, P5 |
| 6 | KBL-H (1/8) | CPU PEG lanes (PEG_CRX/CTX, PEG_COMP) + DMI x4 (DMI_CRX_PTX_*/DMI_CTX_PRX_*) | P4 lane budget |
| 7 | KBL-H (2/8) `[ocr]` | CPU_XDP_TCLK/TDO/TRST, H_PROCHOT, H_THERMTRIP, VCCST_PWRGD, VR_SVID_DATA, PCH_CPU_PCIBCLK_R_D, XDP_DBRESET | P2 (debug), P7 |
| 8 | KBL-H (3/8) | CPU DDR ch 0+1 (DDR0_DQ/DDR1_DQ, DDR0_MA/DDR1_MA, DDR_A/B_DQS) | P3 |
| 9 | KBL-H (4/8) | CPU display: EDP_TXP/N, DDI2_TX*, DDI3_TX* | P4 display |
| 10 | KBL-H (5/8) | RSVD / RSVD_TP / VCCOPC / NCTF — reserved balls, test pads | — |
| 11 | KBL-H (6/8) | CPU power VCC* (121 refs) | P7 |
| 12 | KBL-H (7/8) | VCC / VCCGT / VCCGTX, VCC_SENSE / VSS_SENSE | P7 |
| 13 | KBL-H (8/8) | VSS / NCTFVSS (SKYLAKE_HALO footprint) | — |
| 14 | DDR4-SODIMM SLOT1 | JDIMM1 | P3 |
| 15 | DDR4-SODIMM SLOT2 | JDIMM2, SLOT2_CONFIG | P3 |
| 16 | KABYLAKE PCH-H (1/9) | PCIE_PRX/PTX ports, CLKOUT_PCIE_*, SRCCLKREQ | P0 lane budget, P4 |
| 17 | KABYLAKE PCH-H (2/9) | USB3/USB2, SATA lanes | P6 |
| 18 | KABYLAKE PCH-H (3/9) | GPP_A..GPP_H GPIO | P3 GPIO |
| 19 | KABYLAKE PCH-H (4/9) | GPIO cont., DDI/DP ctrl | P3 GPIO |
| 20 | KABYLAKE PCH-H (5/9) | SPI, eSPI/LPC, SMBus, straps (PCH_SPI_CLK_0/1/2_R) | P1 SPI, P2 |
| 21 | KABYLAKE PCH-H (6/9) | HDA, clocks, RTC | P5 |
| 22 | KABYLAKE PCH-H (7/9) | PCH power (VCC*) | P7 |
| 23 | KABYLAKE PCH-H (8/9) | PCH power/GND | P7 |
| 24 | KABYLAKE PCH-H (9/9) | PCH GND | — |
| 25 | DP SW1 PS8338 | PS8338, CPU_DP3_* → mux | P4 display |
| 26 | DP SW2 PS8338 | PS8338 | P4 display |
| 27 | HDMI CONN | HDMI conn, PS8407 level shifter | P4 display |
| 28 | DP to VGA & VGA Conn | DP→VGA bridge | P4 display |
| 29 | TBT-AR-SP(1/2) DP, PCIE | ALPINE-RIDGE_BGA337, TBT_CIO_PLUG_EVENT, TBT_RESET_N_EC, TBT_I2C_SDA/SCL, TBT_SRC_* | P4 TBT |
| 30 | TBT-AR-SP(2/2) PWR,VSS | TBT power, TBT_SVR_IND | P4 TBT, P7 |
| 31 | [Type C]PD Controller TI | TPS65982D, TBT_I2C, PD SPI (SPI_CLK/MOSI/MISO/SS_N — PD flash, NOT BIOS) | P4 TBT, P1 (exclude) |
| 32 | [Type C]PD Power | Type-C VBUS/power path | P7 |
| 33 | USB 3.0 CONN TYPE C | Type-C receptacle | P6 |
| 34 | eDP CONN & Touch screen | JEDP1, eDP x2 lanes | P4 display |
| 35 | LAN Clarkvillie & RJ45 | I219 (Clarkville), CLKREQ_PCIE#4, PCIE_PRX_C_DTX_P4/N4 (PCIE-4) | P6 |
| 36 | Card Reader | RTS5242, SD_UHS2_*, PCIE-3 | P6 |
| 37 | NGFF Card | JNGFF1 (WLAN), JNGFF2 (WWAN), JSIM1, PCIE_PRX_SW/PTX_SW, WWAN_PWR_EN | P6, P8 networks |
| 38 | Codec ALC3246 | ALC3246 HDA | P5 |
| 39 | EC MEC5105 `[ocr]` | MEC5105 (EC), GPU_SMDAT/SMCLK, VGA_ID, USB_PWR_SHR_VBUS_EN, +3.3V_ALW_UE1 | P2 EC |
| 40 | MEC5105 SUPPORT `[ocr]` | SPI_IO0..3 (EC flash), PCIE_WAKE, QE3..QE11/UE2..UE7 thermal diodes, LMBT3904 | P2 EC, P1 (EC flash chip) |
| 41 | USH & TPM | JUSH1, TPM_PIRQ, TPM_LPM, USH_PWR_STATE, PCH_SPI_CLK_* (TPM on SPI) | P1 SPI (TPM CS), P5 |
| 42 | M2 2280 Socket | JNGFF3, PCIE_PRX_DTX_N12/P12 (PCIE-9..12 x4), HDD_PWR_*, PCIE_WAKE | P6, P8 storage |
| 43 | HDD CONN | JSATA1 (SATA-2) | P6, P8 storage |
| 44 | USB SW | JUSB1, USB3_PRX/PTX_*1 | P6 |
| 45 | JUSB2&JUSB3 | JUSB2, JUSB3, USB3 lanes 3/4 | P6 |
| 46 | Keyboard | KB matrix conn | P2 EC |
| 47 | PAD, LED | touchpad, LEDs | P2 EC |
| 48 | Power control | WLAN_PWR_*, HDD_PWR_*, PCH_ALW_ON | P7 |
| 49 | N16S PCIE,I2C,DAC,GPIO | GM107-ES-A1_BGA908, PEG lanes, GPU_PEX_RST_HOLD, GPU I2C | P4 dGPU |
| 50 | N16S DP, STRAP, GND | GPU DP outputs, straps | P4 dGPU |
| 51 | N16S Power | GPU rails | P7 |
| 52 | N16S Power GFX Core | GPU_CORE decoupling | P7 |
| 53 | N16S Memory | GDDR5 interface | — |
| 54 | GDDR5 VRAM A `[ocr]` | +1.35V_MEM_GFX, VRAM A | — |
| 55 | GDDR5 VRAM B `[ocr]` | +1.35V_MEM_GFX, VRAM B | — |
| 56 | Power Seq `[ocr]` | EM5209VF, TLV62130, SYX198, +1.0V_PRIM, +5V_ALW/RUN, PCH_PWROK, SIO_SLP_* | P7 (power sequence) |
| 57 | +DCIN | +3.3V_VDD_DCIN, +3.3V_RTC_LDO | P7 |
| 58 | +5V_ALW/3.3V_ALW | +5V_ALW(P/2), +3.3V_ALW(P/2), +3.3V_RTC_LDO | P7, P1 (flash VCC rail) |
| 59 | +1.2V_MEN/+0.6V_DDR_VTT | +1.2V_DDR(P), +0.6V_DDR_VTT, +0.6VSP | P7 |
| 60 | +1VALWP | +1VALWP(_B/_C), +1.0V_PRIM | P7 |
| 61 | +1VS_VCCIO `[ocr]` | +1VS_VCCIO(P), +1.0VS_VCCIO | P7 |
| 62 | +1.8VALWP/+1.5VSP/2.5V_MEN `[ocr]` | +1.8VALWP, +1.8V_PRIM, +2.5V_MEM, +1.2V_RUN | P7 |
| 63 | VCORE_ISL95855 | ISL95855AHRTZ, PCH_PWROK | P7 |
| 64 | VCORE `[ocr]` | VCORE power stage | P7 |
| 65 | VGT_VSA `[ocr]` | ISL95808HRZ, AON6994 (VCC_GT / VCC_SA VR) | P7 |
| 66 | PWR_CHARGER_ISL9237 (Colay) | ISL9237 (colay ISL88738HRTZ) | P7 |
| 67 | PROCESSOR DECOUPLING `[ocr]` | 22U_0603 ×12 + 470u_D2 ×2 (CPU VCORE decoupling) | — |
| 68 | ParkCity_TypeC_PD `[ocr]` | +3.3V_VDD_PIC, +3.3V_VDD_DCIN (PD MCU power) | P4 TBT, P7 |
| 69 | +GPU_CORE `[ocr]` | RT8813DGQW, GPU_CORE, GPU_VREF, GPU_PWR_SRC, VGA_CORE, GPU_VSS_SENSE | P7 |
| 70 | GPU_VRAM(SYX198D) | SYX198D, GPU_VRAM, +1.35V_MEM_GFX | P7 |
| 71 | PROCESSOR DECOUPLING (GPU) `[ocr]` | GPU_CORE decoupling (PC1013…PC1189 22U/10U) | — |
| 72 | +1VALWP (`+1.05VALWP`) `[ocr]` | +1.05VALWP(_B/_C/1), +1.05V_PRIM | P7 |
| 73 | PWR P.I.R | power P.I.R (placement/inspection) | — |
| 74 | EE P.I.R (1/1) | MEC5105K, JLED1, JUSH1, DGPU_PWR_EN, PCH_DPWROK, WLAN/WWAN_COEX*, TBT_CIO_PLUG_EVENT | P2 EC, P4 |

Notes:
- p62 pdftotext title reads "1" (garbled); OCR gives `+1.8VALWP/+1.5VSP/2.5V_MEN`. p72 pdftotext says `+1VALWP` but the nets are `+1.05VALWP*` (a second 1.05 V rail; p60 is the real `+1VALWP`).
- p71 titled "PROCESSOR DECOUPLING" like p67 but the nets are `GPU_CORE` — it is the GPU core decoupling page.
- Two SPI flashes on the block diagram (p2): `W25Q128FVSIQ` (16 MiB, BIOS) and `W25Q64FVSSIQ` (8 MiB). Which is EC vs TBT NVM → Phase 1 (`spi-ec.md`). PD controller p31 has its own SPI bus (`SPI_CLK/MOSI/MISO/SS_N`) — do not confuse with PCH SPI (`PCH_SPI_CLK_*`, p20/p41).

## No-stuff / SKU notes (from text layer)
- Alpine Ridge / TBT (PCIE-5..8): "pop only on Precision SKU" (p3) — present on this board (kill-switch p29).
- N16S-GT1-KA vs N17M-Q3 on cover: two GPU SKUs share the PCB; `VGA_ID` (p39) tells EC which.
- WiGig (PCIE-1, M.2 3030) and WWAN (JNGFF2, M.2 3042) are populated-by-SKU; `WLAN_WIGIG60GHZ_DIS`, `WWAN_PWR_EN` in EC/PCH GPIO (p18/p37/p74).

## Lane budget skeleton (0.5) — from p3 PM table + p2 block diagram, all `[text]`
| PCH port | shared SATA | destination (p3) | connector / page | phase to confirm `[visual]` |
|---|---|---|---|---|
| PCIE-1 | — | M.2 3030 (WiGig) | JNGFF1? p37 | P6 |
| PCIE-2 | — | M.2 3030 (WLAN) | JNGFF1 p37 | P6 |
| PCIE-3 | — | Card Reader RTS5242 | p36 | P6 |
| PCIE-4 | — | LOM (I219 Clarkville) | p35 | P6 |
| PCIE-5 | — | Alpine Ridge x4 (pop only on Precision SKU) | p29 | P4 |
| PCIE-6 | — | Alpine Ridge x4 | p29 | P4 |
| PCIE-7 | — | Alpine Ridge x4 | p29 | P4 |
| PCIE-8 | — | Alpine Ridge x4 | p29 | P4 |
| PCIE-9 | SATA-0A | M.2 Socket 3 Key M 2280 (PCIe x4 or SATA) — merged cell 9..12, row 9 also shows "NA" | JNGFF3 p42 | P6 (check whether x4 = 9..12 or 10..12+?) |
| PCIE-10 | SATA-1A | M.2 2280 x4 | p42 | P6 |
| PCIE-11 | — | M.2 2280 x4 | p42 | P6 |
| PCIE-12 | — | M.2 2280 x4 (`PCIE_PRX_DTX_N12/P12` seen on p42) | p42 | P6 |
| PCIE-13 | SATA-0B | NA | — | free candidate |
| PCIE-14 | SATA-1B | NA | — | free candidate |
| PCIE-15 | SATA-2 | JSATA1 → HDD SATA | p43 | P6 |
| PCIE-16 | SATA-3 | NA | — | free candidate |
| PCIE-17 | SATA-4 | M.2 3042 (HCA or QCA LTE) / SSD Cache | JNGFF2 p37 | P6 |
| PCIE-18 | SATA-5 | M.2 3042 (HCA or QCA LTE) / SSD Cache (merged cell with 17) | JNGFF2 p37 | P6 |
| PCIE-19 | — | NA | — | free candidate |
| PCIE-20 | — | NA | — | free candidate |
| CPU PEG[0]~[15] | — | N16S (GM107) x16, GDDR5 x2 (2GB) | p6 / p49 | P4 |
| CPU DMI | — | PCH, x4 Gen3 | p6/p16 | — |
| CPU eDP | — | eDP Lane x2 → JEDP1 | p9/p34 | P4 |

Unused on paper: PCIE-13, 14, 16, 19, 20 (5 ports) + SATA-0B, 1B, 3. Whether their lanes / CLKOUT / CLKREQ are actually routed to test points or left NC is Phase 3 (`gpio.md` spare clock list) and Phase 8 (`mods.md`).

DIY: What fits here — nothing to buy; this is an index. Verdict: FIT (reading only).
