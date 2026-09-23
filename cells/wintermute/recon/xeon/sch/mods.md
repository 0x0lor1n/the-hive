# LA-E152P — mod map: eGPU / networks / storage (Phase 8)

Source: `Dell-3520-LA-E152P-schematic.pdf` sha256 `551d1fe5…1a9cb`. No new facts and no new FIT lines here: this file only ranks and merges the 38 `FIT:` lines from `spi-ec.md`, `gpio.md`, `dgpu.md`, `tb3.md`, `m2-storage.md`, `power.md`, `display.md` (p.NN cites carried over).
Merge rule: one subject with several FIT lines (slot fit, power, whitelist) takes the **highest** risk of them.
IDs below (`F1..F38`) number the FIT lines in file order (`grep -h '^FIT:' dgpu display gpio m2-storage power spi-ec tb3`), so each recommendation traces back to its source line.

## FIT index (8.1)
| ID | file | subject | risk | cite |
|---|---|---|---|---|
| F1 | dgpu | PEG tap via GM107 removal | H | (p.6, p.49) |
| F2 | dgpu | dGPU forced off (`GPP_D12` low) for an eGPU | L | (p.21, p.53) |
| F3 | dgpu | M620 under Linux with coreboot (`_ROM`) | M | (p.50) |
| F4 | display | eGPU → external monitor on the eGPU | L | (p.9, p.34) |
| F5 | display | eGPU → internal panel via PRIME copy | L | (p.9, p.34) |
| F6 | display | eGPU DP → panel via DP→eDP board | H | (p.34) |
| F7 | display | nothing: M620 as display adapter | - | (p.50, p.9) |
| F8 | display | nothing: VGA removal frees PCIe | - | (p.28, p.26) |
| F9 | display | DP monitor from WLAN Key A breakout | H | (p.26, p.37) |
| F10 | display | FHD 120/144 Hz 40-pin panel | H | (p.9, p.34) |
| F11 | display | nothing: 4K internal panel | - | (p.9, p.34) |
| F12 | gpio | new PCIe slot on PCIE-13/14/16/19/20 | H | (p.16, p.18) |
| F13 | gpio | serial console on `JUART1` | L | (p.21) |
| F14 | gpio | spare GPIO test pads | H | (p.19, p.20, p.21) |
| F15 | gpio | slot sidebands complete (WWAN/WLAN/WiGig) | L | (p.18, p.21, p.37) |
| F16 | m2-storage | NVMe 2280 system disk in KEYM | L | (p.42, p.16) |
| F17 | m2-storage | M.2 → OCuLink → eGPU in KEYM | M | (p.42, p.16) |
| F18 | m2-storage | 2.5" SATA SSD in bay | L el. / M mech. | (p.43, p.16) |
| F19 | m2-storage | empty bay, 92 Wh battery | L | (p.43) |
| F20 | m2-storage | RM520N-GL in WWAN | M | (p.37, p.48) |
| F21 | m2-storage | EM9191 in WWAN | M | (p.37, p.48) |
| F22 | m2-storage | 2242 B+M NVMe in WWAN | H | (p.37, p.16) |
| F23 | m2-storage | 2242 B+M SATA in WWAN | H | (p.37, p.39, p.16) |
| F24 | m2-storage | 2.5 GbE B+M card in WWAN | H | (p.37) |
| F25 | m2-storage | MT7925 in WLAN | L | (p.37, p.48) |
| F26 | m2-storage | BE200 in WLAN | M | (p.37) |
| F27 | m2-storage | nothing on WLAN second lane | H | (p.37) |
| F28 | power | 180 W barrel adapter (buys nothing) | L | (p.66, p.57) |
| F29 | power | RM520N-GL on `+3.3V_WWAN` | H | (p.48, p.58) |
| F30 | power | EM9191 on `+3.3V_WWAN` | H | (p.48) |
| F31 | power | eGPU PSU ground shared with laptop | L | (p.57, p.66) |
| F32 | power | CPU PL/IccMax tuning within VR limits | L | (p.64, p.65) |
| F33 | spi-ec | third-party WWAN modem not BIOS-blocked | M | (p.37) |
| F34 | spi-ec | third-party Wi-Fi not BIOS-blocked | M | (p.37) |
| F35 | tb3 | eGPU on laptop USB-C (TB3 direct) | L | (p.17, p.29) |
| F36 | tb3 | eGPU behind WD19TB downstream TB3 | M | (p.29, p.68) |
| F37 | tb3 | 10/2.5 GbE over TB3 | L | (p.29, p.31) |
| F38 | tb3 | WD19TB 130 W as only power source | M → L by F28/power table | (p.68, p.31, p.66) |

Merged subjects: modem RM520N-GL = F20+F29+F33 → **H**; modem EM9191 = F21+F30+F33 → **H**; MT7925 = F25+F34 → **M**; WD19TB power = F38 re-rated L in `power.md` power table (`PL901` 6.6 A vs 6.5 A) (p.66, p.68).
Missing: no phase wrote a FIT for the `USH` / Smart Card connector `JUSH1` (p.41) or the `SD` reader RTS5242 on PCIE-3 (p.36). Phase 8 may not invent one, so both stay unanswered (see Open) (p.36, p.41).

## eGPU (8.2)
| path | lanes / Gen | hot-plug | displaces | coreboot dependency | parts (prices from backlog B3.1) | risk | FIT |
|---|---|---|---|---|---|---|---|
| OCuLink in KEYM | PCH PCIE9..12 x4 Gen3 native, 31.5 Gb/s, behind DMI 3.0 x4 (also ~31.5 Gb/s, shared with bay SATA, WLAN, LAN, card reader) | no: cold-plug, `PCH_PLTRST#_AND` shared, no hot-plug sideband | KEYM NVMe → system disk moves to the SATA bay → 68 Wh battery mandatory | none to start (5580 + R43SG works on Ubuntu with Dell BIOS); on coreboot a plain RP9 x4, SRC3/`GPP_B8` | M.2→SFF-8612 board ~15 CHF, 0.5 m cable, DEG1-class dock ~100 CHF, DA-2 220 W or ATX PSU | M | F17, F31 (p.42, p.16, p.57) |
| TB3 direct | PCH PCIE5..8 x4 Gen3 via Alpine Ridge, ≈22 Gb/s PCIe tunnel, same DMI | yes (`GPP_G2` plug event, `boltctl`) | the only USB-C/TB3 port | none on Dell BIOS; on coreboot it is the hardest part (RP5 hot-plug, bus/mem padding, `GPP_D4` FORCE_PWR; RTD3 unwired, no TB wake from S3) | TB3 enclosure + PSU (no price in chat) | L | F35 (p.17, p.29, p.30) |
| TB3 via WD19TB | same x4 tunnel, shared with the dock's USB hub, NIC, audio, DP; ≈10 % per hop | yes | nothing extra, dock traffic competes | as TB3 direct | WD19TB (on the buy list) + enclosure | M | F36 (p.29, p.68) |
| PEG tap (M620 lift) | CPU PEG Gen3, x4 realistic on GPU pads 15..12 (board lane-reversed), x16 routed | no | M620 forever + BGA908 rework | Dell BIOS may hide PEG with no dGPU → coreboot | none (no successful precedent) | H | F1 (p.6, p.49) |

Common to all eGPU paths: every output is iGPU-owned, so best frames = monitor on the eGPU card (F4, L), internal panel only via PRIME copy at ~20–35 % loss (F5, L); the M620 can never drive a port (F7) (p.9, p.34, p.50). Force the M620 off with `GPP_D12` low (F2, L) to hand its power budget (`+GPU_CORE` 26.5 A TDC off `+PWR_SRC`) to charging while the eGPU runs (p.21, p.53, p.69). The eGPU PSU sharing ground with the barrel is harmless: `-DCIN_JACK` = GND, all sense high-side (F31, L) (p.57, p.66).
Mechanical checks before buying OCuLink parts (not on the sheet): KEYM vs SATA caddy overlap (F18 M mech.) and the cable exit through the VGA opening (backlog B3.2) (p.42, p.43).

Recommendation: OCuLink in KEYM (F17, M: native x4 Gen3, no TB tunnel, no TB3-under-coreboot dependency; costs the NVMe slot), gated on the two mechanical checks. Fallback: TB3 direct (F35, L: zero mods, works on Dell BIOS today, hot-plug, ≈22 Gb/s) (p.42, p.16, p.17, p.29).

## Networks (8.3)
### Cellular (`WWAN`, `JNGFF2`)
- Electrical path for a modem: USB3 port 2 through `UZ29` PI3PCIE3212 (SEL = `SLOT2_CONFIG_1` low = USB3) + USB2 port 8; lane-1 TX crosses `@RZ1/@RZ2` drawn nopop, so if they are really open the modem runs on USB2 480 Mb/s only → DMM before judging throughput (p.37).
- Power: `+3.3V_WWAN` from `UZ2` EM5209VF ch1 (6 A) behind pad `PJP41` "2.5A", EC-enabled `3.3V_WWAN_EN`, off `+3.3V_ALW` (6.8 A TDC buck, the biggest single load on it). EM9191 wants up to 2.7 A, RM520N-GL 3.0 A continuous with VCC ≥ 3.135 V vs ≈3.17 V at the slot at 3 A → both **H** (F29, F30) (p.48, p.58).
- Whitelist: none on the sheet; only the M.2 `CONFIG_0..3` module-type detect to the EC (state 8 = WWAN). A Lenovo EM7455 enumerated in a 3520 (F33) (p.37, p.39).
- SIM: push-push `JSIM1` on the WWAN sheet. Antennas: no RF parts on the board; the lid has 2 WWAN pigtails (inventory, not schematic) → 2×2 MIMO, no dedicated GNSS (p.37).
- Mechanics: EM9191 is 3042 = drop-in; RM520N-GL is 3052 → standoff 42→52 mm, clearance unchecked (F20) (p.37).

| module | slot fit | power | whitelist | effective | FIT |
|---|---|---|---|---|---|
| Sierra EM9191 | 3042 drop-in, USB3/USB2 | 2.7 A > 2.5 A label | none | H | F21, F30, F33 (p.37, p.48) |
| Quectel RM520N-GL | 3052, standoff move | 3.0 A > 2.5 A label, VCC margin ~35 mV | none | H | F20, F29, F33 (p.37, p.48, p.58) |

Recommendation: EM9191 (F21/F30/F33, H on power only: drop-in length, smaller overshoot than RM520N-GL); DMM `@RZ1/@RZ2` first, then bench-measure `+3.3V_WWAN` at the slot during an upload before relying on it (p.37, p.48).

### Wi-Fi / BT (`WLAN`, `JNGFF1`)
- Slot = Key A 2230, PCIE2 x1 / SRC1, BT on USB2 port 6; 200-series PCH has no CNVi → only PCIe cards (AX201/AX211/BE201 dead) (p.37, p.16).
- `+3.3V_WLAN` pad `PJP36` "2A"; MT7925 module ≤ 0.5–1.5 A → OK. Rail enable goes through `@RZ70/@RZ71` (drawn nopop, one is fitted on a working board) (p.48).
- No ID whitelist on the sheet (F34 M: evidence is a generic Dell statement) (p.37).
- WPA3 / 6 GHz / 320 MHz are card + firmware + regdom (CH: lower 6 GHz only, backlog B4), nothing on the board limits them (p.37).
- WiGig second lane (PCIE1/SRC2 + PS8338 `SW2_DP1` DP x4): no card uses it (F27); a Key A→DP breakout would give an extra monitor but loses Wi-Fi and the 2nd TB3 DP stream (F9 H) (p.26, p.37).

Recommendation: MT7925 (Fenvi WF-M925-MPA1) in `WLAN` (F25 L + F34 M → M; no coreboot dependency); BE200 is the M fallback (F26: Intel CPU check passes, no Kaby Lake report) (p.37, p.48).

### Extras
| option | effective | FIT |
|---|---|---|
| 10/2.5 GbE adapter on TB3 (AQC107/113, `atlantic`), or the WD19TB NIC | L | F37 (p.29, p.31) |
| 2.5 GbE B+M card in WWAN (needs coreboot RP17, displaces the modem, RJ45 pigtail out of the chassis) | H | F24 (p.37) |
| serial console on `JUART1` (PCH UART2 `GPP_C20/C21`, 3 wires + 3.3 V USB-UART) | L | F13 (p.21) |
| extra PCIe slot on PCIE-13/14/16/19/20 (ball-only NC) | H → no | F12 (p.16, p.18) |
| spare GPIO test pads (`GPP_D20`, `A23`, `A18`, `A11`) for DIY resets/enables | H | F14 (p.19, p.20, p.21) |
| `USH`/Smart Card (`JUSH1`, nRF54L15-style dongle idea) | no FIT → open | - (p.41) |
| `SD` reader RTS5242 on PCIE-3 | no FIT → open | - (p.36) |

Recommendation (networks overall): EM9191 in `WWAN` + MT7925 in `WLAN`; fast wired Ethernet over TB3/WD19TB (F37), never in the WWAN slot (F21, F25, F37) (p.37, p.29).

## Storage (8.4)
Power applied from `power.md`: KEYM `+3.3V_HDD_M2` "2.8A" OK (L); bay `+5V_HDD` "1.5A" via `UZ23` OK (L); WWAN-slot SSD power adds nothing to its H (p.42, p.43, p.48).

| eGPU path | KEYM NVMe | SATA SSD in bay (68 Wh + caddy + `JSATA1` cable) | NVMe/SATA 2242 in WWAN |
|---|---|---|---|
| OCuLink in KEYM | impossible, slot = eGPU (F17) | **system disk** (F18, L el. / M mech.) | coreboot RP17(+18) + DMM `@RZ1/@RZ2`; displaces the modem (F22/F23, H) |
| TB3 (direct or WD19TB) | **system disk** (F16, L) | data disk (F18) or empty with 92 Wh (F19) | as above, H |
| none | **system disk** (F16, L) | data disk (F18) or empty with 92 Wh (F19) | as above, H |

Cites: (p.42, p.43, p.16, p.37).
- OCuLink: system disk lives in the SATA bay (2.5" SSD, 68 Wh battery), data disk nowhere unless the WWAN slot gives up the modem after coreboot (F17, F18, F22) (p.42, p.43, p.37).
- TB3: system disk lives in KEYM NVMe, data disk in the SATA bay with the 68 Wh battery, or none with the 92 Wh (F16, F18, F19) (p.42, p.43).
- None: system disk lives in KEYM NVMe, data disk in the SATA bay (68 Wh) or none (92 Wh) (F16, F18, F19) (p.42, p.43).
- KEYM and the bay never share lanes (SATA0A vs SATA2), so NVMe + 2.5" is fine in every variant (p.16).

Recommendation: 68 Wh battery + 2.5" SATA SSD in the bay in every variant (F18): it is the system disk for OCuLink and the data disk otherwise, and no variant is left without a disk (p.43, p.16).

## Order of operations (8.5)
| # | mod | when | pre-req | FIT | backlog |
|---|---|---|---|---|---|
| 1 | MT7925 in `WLAN` | now, Dell BIOS | none | F25, F34 | B4 |
| 2 | 68 Wh + caddy + cable + 2.5" SATA SSD | now | check KEYM/caddy overlap on the board | F18 | B4, B3.3 |
| 3 | DMM list: `@RZ1/@RZ2`, `CZ10/CZ11`, `@RZ70/@RZ71`, `@RF@RH10..17`, `@PR920/@PR922` | with the next board-out session | none; read-only | F20–F24 | B1.5 |
| 4 | EM9191 in `WWAN` (USB mode) | after 3 | bench `+3.3V_WWAN` under upload | F21, F30, F33 | B1.1–B1.2 |
| 5 | eGPU TB3 direct (fallback path, also a way to test the card) | now | enclosure | F35, F4, F5 | B3 (fallback) / B5 |
| 6 | eGPU OCuLink in KEYM | after 2 (system disk moved) | mechanical exit (VGA opening, no solder, shell cut) | F17, F31 | B3.1–B3.3 |
| 7 | M620 forced off (`GPP_D12` low) | coreboot, or resistor swap `@RH349`/`RH346` | coreboot gpio.c or solder | F2 | B3.5 |
| 8 | TB3 under coreboot, RP9 OCuLink devicetree (CLKREQ/ASPM/hot-plug off) | coreboot | coreboot-5580 port | F17, F35 | B3.4 |
| 9 | CPU PL/IccMax tuning ≤ 68/55/11.1 A peak | coreboot | coreboot | F32 | B2.3–B2.4 |
| 10 | M620 under coreboot (`_ROM`) | coreboot | VBIOS from the Dell image | F3 | coreboot-5580 |
| 11 | `JUART1` header | before first coreboot flash | solder 3 wires | F13 | coreboot-5580 |
| 12 | WWAN-slot NVMe / 2.5 GbE | coreboot, only if the modem is dropped | RP17(+18), DMM `@RZ1/@RZ2` | F22, F24 | B4 (storage) |
| - | never: PEG tap, new PCIe slot, 4K panel, DP→eDP rewire | - | BGA work / NC lanes | F1, F12, F11, F6 | B5 |

Cites: (p.37, p.42, p.43, p.21, p.6, p.16).
Recommendation: networks and storage first on the Dell BIOS (1–4), eGPU on OCuLink once the disk has moved (6), everything that touches PEG/RP17/TB3 power management waits for coreboot (7–12) (p.37, p.42, p.43).

## Backlog text that the FIT lines contradict (not edited here, invariant 40)
- B1: "RM520N-GL peak ~2.5 A → fine", "+3.3V_ALW SY8288B TDC 5.9 A" → power.md: 3.0 A required, TDC 6.8 A, risk H (F29) (p.48, p.58).
- B4 screen: "30-pin eDP" → board side `JEDP1` is 40-pin ACES 50398-04041; the panel side of the lid cable is not on the sheet, so check the cable before buying a panel (F10) (p.34).
- B4 storage: "WWAN slot takes 2242 B+M (x1)" → x2-capable via `UZ29`, but needs coreboot and DMM, risk H (F22) (p.37).
- B5 "eGPU over TB3: No" → kept as the L fallback here (F35) (p.29).
- B4 names the fitted NVMe "PC801 1 TB"; this plan's header says "Samsung 970-class" — inventory question, not a schematic one (p.42).

## Open
- `USH`/Smart Card (`JUSH1`, p.41) and SD reader (RTS5242, p.36): no phase produced a FIT line, so they have no verdict. Needs one more read (p.41 + p.3 USB destination table) if the nRF54L15/dongle idea matters (p.3, p.36, p.41).
