# schematic-e152p — read the LA-E152P schematic and decide, page-cited, what can be plugged into this board and where

Status: PLANNING (2026-09). Owner: user; Claude = executor + proposer (reads pages, checks DIY community, writes verdicts; user picks).
Prereq: `~/.hermes/cache/web/Dell-3520-LA-E152P-schematic.pdf` present, 74 pages, sha256 `551d1fe540b2bdf81eba78962f06d3868bf629ea963b434fd92cd56c2fb1a9cb`.
Do NOT edit `coreboot-5580.md` phases from here; this task only feeds it facts via `recon/xeon/sch/*.md` and Progress notes.

Target: `cells/wintermute/recon/xeon/sch/mods.md` answers three questions with page cites and a DIY precedent for each option:
(1) eGPU — which physical path (TB3 port / M.2 Key M → OCuLink / other lanes) with lane count, power, and what it displaces;
(2) networks — cellular (WWAN slot), Wi-Fi/BT (Key A/E slot), anything extra (Smart Card / USH / WiGig / spare PCIe or USB) — what fits, what it needs;
(3) storage — where the system disk lives in every eGPU variant (M.2 NVMe / SATA bay / M.2 3042 SSD-cache slot), no variant leaves it homeless.
Side product: `recon/xeon/sch/*.md` facts (GPIO, SPI/EC, dGPU, TB3, power, display) so coreboot-5580 Phase 2/5 never open the PDF again.
Source refs: `~/.hermes/cache/web/Dell-3520-LA-E152P-schematic.pdf` (Compal CDP80/CDP81 "Breckenridge 15 DSC (TBT), Kabylake H", REV 1.0 A00, 2016-11-10 — the board),
`~/.hermes/cache/web/Dell-5580-LA-E151P-schematic.pdf` (UMA non-TBT sibling, 61 p. — already mined for backlog B1; diff only),
`.hermes/state/coreboot-5580-backlog.md` (B1 WWAN, B3 OCuLink, B4 wifi/SSD — claims to re-verify), coreboot `src/mainboard/dell/sklkbl_desktops/variants/optiplex_3050` (moved upstream from `dell/optiplex_3050`), `src/ec/dell/mec5035`.
DIY sources to check per phase (search, cite URL in note, never paste bodies): egpu.io forum + implementations table (Dell 5580/3520/7520, Alpine Ridge, M.2 OCuLink, ADT-Link R43SG/UT3G),
r/eGPU, badcaps + vinafix (LA-E152P threads: TPM/ME/BIOS quirks), Dell community + notebookreview archive (5580/3520 WWAN whitelist, M.2 lane, 4 lanes vs 2),
coreboot mailing list / gerrit (dell KBL ports, mec5035), r/thinkpad & r/Dell "m.2 wwan slot nvme/2.5GbE" threads, techinferno (WiGig slot reuse), openwrt/linux-wireless (MT7925/BE200 on KBL PCH).
Preliminary page map (from grep, Phase 0 makes it authoritative): p1 cover, p2 block diagram, p3 PM/USB/PCIe/SATA destination tables, p6 CPU PEG,
p11–12 VCCGT, p16 PCH PCIe/SATA lanes, p18/p20–21 PCH GPIO, p25–28 eDP/HDMI/VGA, p29–33 Alpine Ridge + TPS65982, p35 WWAN, p37 M.2 Key M,
p39 EC, p42–43 SATA/SSD, p47 KB/TP, p49–55 GM107 + GDDR5, p56 ISL95857/RT8207/SYX198, p57 batteries, p69 +VGA_CORE, p73–74 rev history.
Hardware on hand: LA-E152P (E3-1505M v6 + M620), 1 TB Samsung 970-class NVMe in M.2 Key M, no 2.5" drive, no WWAN, stock Wi-Fi (no WPA3), lid antennas 2×Wi-Fi + 2×WWAN.
To buy (decided elsewhere, this plan only says where they go): 68 Wh battery + SATA caddy, Fanxiang S660 2 TB, MT7925 Key E, RM520N-GL or EM9191, M.2→OCuLink adapter, PSU for eGPU, WD19TB.

Repo: rensa cell `cells/wintermute`; output dir `cells/wintermute/recon/xeon/sch/` (text only, committed). Devshell `wintermute` not required — every step runs with
`nix-shell -p poppler-utils`. Scratch: `/tmp/sch/e152/` (`pNN.txt` from `pdftotext -layout`, `pNN.png` from `pdftoppm -r 200`), disposable.
Naming: `SCH=~/.hermes/cache/web/Dell-3520-LA-E152P-schematic.pdf`; `SCRATCH=/tmp/sch/e152`; `OUT=cells/wintermute/recon/xeon/sch`.
Files in `OUT`: `pages.md`, `spi-ec.md`, `gpio.md`, `dgpu.md`, `tb3.md`, `m2-storage.md`, `power.md`, `display.md`, `mods.md`. Commit prefix `recon(xeon/sch): `.
Page cite format inside notes: `(p.NN)`; ref-des as on sheet (`RH349`, `UZ2`); net names verbatim (`DGPU_PWR_EN`, `+3.3V_WWAN`).
Verdict format (every "what fits here" line, in any file): `FIT: <what> | needs: <parts/mod> | lanes/bus: <x> | power: <rail, A> | displaces: <what> | DIY: <url or "none found"> | risk: L/M/H (p.NN)`.
Slot names: `KEYM` (M.2 2280 Key M, JSSD), `WWAN` (M.2 3042 Key B, JNGFF2), `WLAN` (M.2 2230 Key A/E, JNGFF1), `SATA` (2.5" bay, JSATA1), `TB3` (USB-C Alpine Ridge), `USH` (Smart Card / USH board conn), `SD` (RTS5242).

Invariants:
- `git ls-files | grep -i -E 'schematic|\.pdf$'` == empty. The PDF is "Compal Secret Data" — never in git, only derived text.
- `sha256sum $SCH` == `551d1fe5…1a9cb` before each session; if it differs, stop (wrong file).
- Every factual line in `OUT/*.md` carries a `(p.NN)`; `grep -L 'p\.[0-9]' $OUT/*.md` == empty.
- A net name goes into a note only after it is seen on ≥2 sheets (source sheet + one `<NN>` cross-ref) or visually confirmed on a rendered page; note says `[text]` or `[visual]`.
- Layout text from `pdftotext` is a hint, not truth. Anything used for coreboot code (GPIO number, strap, pull) or for a soldering decision (lane, rail, cap) is `[visual]`.
- Every `FIT:` line has both a page cite and a `DIY:` field. "none found" is allowed; an unsourced "people do this" is not. A FIT with `DIY: none found` gets `risk: H` unless the schematic alone proves it (rail + lanes + no strap).
- Every phase 1–7 ends with a `## What fits here` section in its `OUT` file (≥1 FIT line or the explicit line `FIT: nothing — <why> (p.NN)`). Phase 8 only collects them; it may not invent new ones.
- No edits to `coreboot-5580.md` / `-backlog.md` except appending a dated line to their Progress pointing at the new `OUT` file.
- One `OUT` file per session; each session ends with a commit of that file only.

## Phase 0 — Page index (kill-switch) ✅
0.1 `mkdir -p $SCRATCH && cd $SCRATCH && for i in $(seq 1 74); do pdftotext -layout -f $i -l $i $SCH p$i.txt; done`. Confirm `sha256sum $SCH` invariant.
0.2 For each page pull the title block: `grep -A2 -E '^\s*Title' p$i.txt` + first 3 distinctive net/part names. Where the title is empty (Compal
    puts it in a drawing box that pdftotext drops), render `pdftoppm -r 100 -f $i -l $i -png $SCH pg` and read the bottom-right box with vision.
0.3 Write `OUT/pages.md`: table `page | sheet title | key parts/nets | feeds (phase of this plan / coreboot-5580 step / backlog item)`. Also a "no-stuff on this
    board" list from p1 legend (`@` = nopop, `N16@`/`N17@` = GPU-variant only) — nopop connectors/caps are exactly where DIY lanes hide.
0.4 Kill-switch check: cover says `LA-E152P` + `DSC (TBT)`; p49 has GM107; p29 has Alpine Ridge. If any is missing this is not the Xeon board → stop, keep E151P only.
0.5 Lane budget skeleton from p2 + p3 + p16 `[text]`: list all PCH PCIe ports 1..20 and CPU PEG with their destination as the table says
    (`NA`, nopop, slot). This is the raw material for every FIT verdict later; goes at the bottom of `pages.md` as `## Lane budget (unverified)`.
Exit criteria: `OUT/pages.md` committed, 74 rows, no row with empty title; 0.4 all three present; lane budget has 20 PCH rows + PEG; Progress line in `coreboot-5580.md` pointing to `pages.md`.

## Phase 1 — SPI flash, EC and boot path (feeds coreboot-5580 Phase 1/2) ✅
1.1 Find the SPI ROM sheet (grep `W25Q|SPI_CS|SPI_CLK|BIOS_REC` across `p*.txt`): part number(s), size, voltage rail, whether EC shares the flash
    (EC `SPI_CS#` on same bus?) and whether there is a second flash for EC. Render page `[visual]`.
1.2 EC sheet (p39 per grep, verify): EC part number (expect MEC5035-class — confirm, do not assume), EC↔PCH buses (LPC/eSPI? SMBus? which GPIOs),
    `EC_RST#`, `RSMRST#`, `PCH_PWROK`, `SYS_PWROK`, `SLP_S3/4/5`, power-button path, `LID_CL#_PCH` — list each net with source/sink and page.
1.3 Straps: `BIOS_REC`, `GPP_F10/SCLOCK`-class multiplexed pins seen on p16, top-swap / flash-descriptor-security strap, TPM bus (LPC or SPI).
1.4 Programmer notes: the clip target chip, what rails the chip needs, what else sits on `+3.3V_ALW` that a 3.3 V programmer would back-power
    (EC? PD controller?) → decides "battery + RTC cell + PD-cable disconnected" wording for `dump`.
1.5 What fits here: does the EC/BIOS whitelist anything (WWAN/WLAN ID strap, `SLOT2_CONFIG_0..3` → EC)? DIY check: badcaps/vinafix LA-E152P threads,
    Dell 5580 whitelist reports. Verdict lines for "modem/wifi card X rejected by BIOS?" — this decides whether coreboot is a prerequisite for a network mod.
1.6 Write `OUT/spi-ec.md` (sections: flash, EC, power-sequence nets, straps, programmer caveats, What fits here). Commit.
Exit criteria: `spi-ec.md` committed; every net `[visual]`; flash chip + EC part number with page; whitelist verdict present; `coreboot-5580.md` Progress
gets "SPI/EC facts from E152P: see recon/xeon/sch/spi-ec.md" and any contradiction with its step 1.1 flagged.

## Phase 2 — PCH GPIO map (feeds coreboot gpio.c / intelp2m cross-check) ✅
2.1 Render p18, p20, p21 (and any page whose title contains `PCH`/`GPIO`) at 200 dpi; for each `GPP_x##` read: net name, direction, pull (`RHxxx`),
    `@` nopop, `<NN>` destination. Cross-check net name on destination page `[text]`.
2.2 Cover note "GPIO MAP: Dell GPIO map EC16 062416 Compal Only" is a Dell doc we lack; GPIOs with no readable function stay `?`, never invented.
2.3 What fits here: list every GPIO/CLKREQ/`PCIE_WAKE#` that is routed to a nopop pad or unused connector pin — these are free sidebands for an extra
    slot (spare `CLKREQ_PCIE#n`, `SRCCLKREQ`, spare `CLK_PCIE_Pn`). DIY: coreboot gerrit for how other Dell ports enabled hidden root ports.
2.4 Write `OUT/gpio.md`: table `GPP | net | dir | pull | page | function | coreboot pad-config guess` + What fits here. Mark `DGPU_PWR_EN` (GPP_D12,
    RH346 pop / RH349 nopop per p74) and `DGPU_PWROK`. Commit.
Exit criteria: `gpio.md` committed with all GPP_A…GPP_H + GPD rows (unused say `NC`/`?`); spare clock/clkreq list present; note in `coreboot-5580.md` Progress.
2.1–2.4 DONE 2026-09 → `OUT/gpio.md`: 204/204 pads (GPP_A..I + GPD; GPIO spans p.16–p.21, not only 18/20/21), 94 NC, every row `[visual]` 400 dpi; balls re-matched vs `pdftotext -bbox` = 0 mismatches.

## Phase 3 — dGPU / PEG (feeds coreboot devicetree, backlog B2 thermal, eGPU option "steal PEG") ✅
3.1 p6 (CPU PEG) + p49–55 (GM107, GDDR5) + p53 (`DGPU_PWR_EN`, `GPU_GC6_FB_EN`) + p69 (`+VGA_CORE`, `NVVDD_PSI`, `GPU_PWM_VID`): lane width `[visual]`
    (x16? x8? — count `PEG_CRX_GTX_P[0..n]` pairs actually AC-coupled on p49), reset, `GPU_HOT#`, `GC6_EVENT#`, `DGPU_PWROK <20,40,53>` chain, power sequence (p74 rev entries 21/34/45).
3.2 Rails: `+VGA_CORE` regulator part, current design (p69 `Ivalley=27A…`), `FBVDD`, `1.8V`, which EC/PCH nets gate them.
3.3 What fits here — objective take on the "remove M620, bring PEG out" idea: which pairs are on which BGA balls, are the AC caps on the CPU side
    (then a GM107-lift exposes clean pads) or GPU side, is the VGA DAC on the same sheet (the VGA-port-removal idea from chat). DIY: egpu.io
    "dGPU removal PEG breakout" threads, any Compal-board PEG-tap precedent. Expected verdict `risk: H`; write it anyway with the reason.
3.4 Write `OUT/dgpu.md` (lanes, sequence, rails, coreboot-vs-EC duties, What fits here). Commit.
Exit criteria: `dgpu.md` committed; ordered power-on sequence with cites; PEG width `[visual]`; PEG-tap verdict present with DIY field.
3.1–3.4 DONE 2026-09 → `OUT/dgpu.md`: PEG x16 `[visual]`, 64 AC caps (CC34..65 CPU side, CV427..458 GPU side), board lane-reversed; 7-step power-on; 3 FIT lines.

## Phase 4 — Thunderbolt 3 / USB-C PD (eGPU option A: dock or direct) ✅
4.1 p29–33: Alpine Ridge part (`JHL6540`/`DSL6340`? `[visual]`), PCH root port used (block diagram says PCIe[5..8]), `TBT_FORCE_PWR`, `TBT_RST#`,
    `TBT_WAKE#`, `TBT_CIO_PLUG_EVENT`, `TBT_DP0/1` sources, TPS65982 (`Port A`) I2C/GPIO to EC, `USB POWER SHARE`.
4.2 Power: which rail feeds Alpine Ridge (always-on vs S0), current budget, PD sink path for 130 W input (charger p57 side) — does WD19TB 130 W
    actually reach the charger or is it capped by the PD controller strap.
4.3 What fits here: FIT lines for (a) eGPU on the laptop USB-C directly (TB3 x4 Gen3, ~22 Gb/s usable), (b) eGPU through WD19TB's downstream TB3
    (shares the same x4 with dock USB/LAN/DP — quantify), (c) 2.5/10 GbE TB3 adapters. DIY: egpu.io implementations table filtered to
    Alpine Ridge KBL-H Dells (7520/5520/3520/5580), r/eGPU "WD19TB eGPU" threads; note Dell TB3 firmware "PCIe x2" quirk reports if any.
4.4 Write `OUT/tb3.md`. Commit.
Exit criteria: `tb3.md` committed; Alpine Ridge part + root port `[visual]`; three FIT lines (a/b/c) with DIY URLs or "none found".
4.1–4.4 DONE 2026-09 → `OUT/tb3.md`: PCH PCIE5..8 x4 + SRC6 `[visual]`; SKU not on sheet, port B unwired → 2C, field probes say JHL6340; 4 FIT lines (a/b/c + WD19TB power).

## Phase 5 — M.2 / SATA / WWAN slots (eGPU option B: OCuLink; networks; disk homes) ✅
5.1 p16 (PCH lanes), p37 (`KEYM`, `m3042_PCIE#_SATA`), p42–43 (`SATA`, SSD conn), p35 (`WWAN`), p2/p3 (`WLAN` Key A: PCIe port 2 + USB 6/7 + WiGig lane):
    per slot — lanes, clock (`CLK_PCIE_Pn`), `CLKREQ`, power rail + load switch + its current rating, sideband, mechanical length (3042/2242/2230/2280).
    Re-check every "Verified from schematic" bullet of backlog B1 against E152P; note any ref-des change.
5.2 Answer the OCuLink premise: `KEYM` is PCH PCIe 9..12 x4 (p3 "PCIex4 or SATA") — and does `SATA-0A` share those lanes (then SATA HDD + M.2-SATA exclusive,
    NVMe + SATA HDD fine)? Is `SATA` bay on `SATA-2` (p3 "JSATA1-->HDD") — independent? `[visual]` on p16/p37/p42.
5.3 What fits here — one FIT line per (slot × candidate), candidates fixed by chat: `KEYM` → {NVMe 2 TB, OCuLink adapter → eGPU}; `SATA` → {Fanxiang/any 2.5" SSD, nothing (92 Wh battery)};
    `WWAN` → {RM520N-GL, EM9191, M.2-2242 NVMe as boot disk (needs PCIe port 17 caps CZ10/CZ11 stuffed — cite), 2.5GbE i225 card};
    `WLAN` → {MT7925, BE200 (Intel Key E: CNVi vs PCIe — which does this slot give?), WiGig second lane → anything?}. Each line: `displaces:` and `power:` filled from 5.1.
    DIY: egpu.io "M.2 OCuLink Dell" threads, r/thinkpad "nvme in wwan slot" (which Dells have port 17 lanes stuffed), linux-wireless for MT7925/BE200 on 200-series PCH.
5.4 Storage decision matrix (draft, finalised in Phase 8): rows = eGPU path {TB3, OCuLink-in-KEYM, none}; cols = where the system disk lives {KEYM NVMe, SATA SSD, WWAN-slot NVMe}; cell = OK / needs X / impossible (p.NN).
5.5 Write `OUT/m2-storage.md`; patch backlog B1/B3 bullets that changed (cites now E152P). Commit both.
Exit criteria: `m2-storage.md` committed; 5.2 answered `[visual]`; ≥8 FIT lines across the four slots; matrix present; backlog B1 says "re-verified on E152P (p.NN)".
5.1–5.5 DONE 2026-09 → `OUT/m2-storage.md`: KEYM RP9..12 x4, bay SATA2 separate [visual] p.16; WWAN x2-capable via `UZ29` mux, CZ10/11 drawn fitted; 12 FIT lines; matrix; backlog B1/B3 patched.

## Phase 6 — Power tree, charger, batteries (budget for every FIT above; backlog B2, B4 battery 68/92 Wh) ✅
6.1 Power-tree sheet (E151P p47 equivalent; grep `Power Tree|TDC|Peak Current`): rails → regulator part → TDC/peak → loads.
6.2 p56 (ISL95857 `+VCC_CORE`, RT8207MZ DDR, SYX198 battery/charger) + p57 (primary battery connector, `PBAT_*` SMBus, coin cell): charger IC, input
    current limit strap (`ILIM` 8/12/16 A `[visual]`), adapter-ID (`DA-2` / 130 W PSID) path, does the charger accept >130 W if the ID says so.
6.3 `+VCC_CORE` phase count / current design → ceiling for B2 tuning.
6.4 What fits here: per FIT line from Phases 4–5, check its `power:` against the rail's TDC minus stock load (`+3.3V_ALW` for WWAN/WLAN, `+3.3V_RUN`
    or `+3.3V_SSD` for KEYM, `+5V`/`+3.3V` for TB3). Mark any FIT that exceeds it `risk: H` with the number. Also: does an eGPU PSU need to be
    ground-bonded to the laptop's DC-in ground (OCuLink adapter power scheme) — cite the charger ground topology.
6.5 Write `OUT/power.md`. Commit.
Exit criteria: `power.md` committed; rail table with TDC per rail; charger ILIM + adapter-ID `[visual]`; every Phase 4–5 FIT has a power verdict.
6.1–6.5 DONE 2026-09 → `OUT/power.md`: 13 rails with TDC (no loads page on E152P, p.56 stale BOM); charger ISL88738 (ISL9237 colay), no ILIM strap, `PL901` 6.6 A caps input ≈129 W; PSID 1-wire → EC [visual]; 12 FIT power verdicts; 5 FIT lines.

## Phase 7 — Display / eDP / HDMI demux / panel (coreboot Phase 4; eGPU output path) ✅
7.1 p25–28 + p2: eDP lanes (block diagram says eDP x2), `EDP CONN` pinout, backlight (`LCD_BKLT_PWM`, `EN`), panel VDD switch, touch/camera on eDP cable
    (p3 USB dest 9/11), PS8338 DP demux `SW1/SW2`, HDMI level shifter, VGA DAC part and what board area frees up if it goes (ties to 3.3).
7.2 What fits here: with an eGPU, how does the image get back — internal panel over eDP from iGPU (Optimus-style, PCIe copy) vs external monitor on the eGPU;
    does the M620 own any display output (the demux says whether HDMI/DP-alt is iGPU or dGPU driven). FIT lines for "eGPU → internal panel" with DIY (egpu.io "internal display" loss numbers on x4).
7.3 Write `OUT/display.md`; note GPIOs coreboot must drive for backlight/panel power. Commit.
Exit criteria: `display.md` committed; backlight/panel-power nets `[visual]`; eDP lane count stated; display-path verdict for eGPU present.
7.1–7.3 DONE 2026-09 → `OUT/display.md`: eDP x2 (lanes 2/3 NC at CPU and on JEDP1) [visual]; DDI1 HDMI/PS8407, DDI2 AR P0, DDI3 → 2×PS8338 auto-HPD demux (AR > WiGig > VGA); panel/BL power [visual]; 8 FIT lines.

## Phase 8 — Mod map: the three answers ⏳
8.1 Collect every `FIT:` line from `OUT/*.md` (`grep -h '^FIT:' $OUT/*.md`), dedupe, keep page cites. No new FITs here (invariant).
8.2 Section **eGPU**: rank TB3-direct / TB3-via-WD19TB / OCuLink-in-KEYM / PEG-tap by: usable lanes & Gen, hot-plug, what it displaces, coreboot dependency,
    parts list with prices already in chat (ADT-Link, PSU), risk. One recommendation + one fallback.
8.3 Section **networks**: cellular (`WWAN` slot: modem pick already made in chat — confirm it fits electrically, antenna count, SIM path, whitelist status from 1.5),
    Wi-Fi/BT (`WLAN` slot: MT7925 vs BE200, PCIe vs CNVi, BT over USB port 6, WPA3/6 GHz limits), extras (`USH`/Smart Card USB port 10 → nRF54L15 / other dongle,
    WiGig lane → ?, `SD` reader → ?). Each with `needs:` and `risk:`.
8.4 Section **storage**: final matrix from 5.4 with Phase 6 power applied; a single sentence per eGPU variant: "system disk lives in ___, data disk in ___".
8.5 Section **order of operations**: which mods are safe before coreboot, which need coreboot (whitelist / hidden root port), which need soldering; map each to backlog B-item.
8.6 Write `OUT/mods.md`; append to `coreboot-5580-backlog.md` Progress: "mods.md is the source of truth for B1/B3/B4 slot decisions". Commit both.
Exit criteria: `mods.md` committed; three sections each end with a one-line recommendation; every recommendation traces to a FIT line with `(p.NN)` and `DIY:`; backlog Progress updated.

## Fallback at any phase
`pages.md` + lane budget (Phase 0) already give the raw slot/lane answer; the E151P-derived backlog notes cover WWAN and M.2. eGPU falls back to
TB3-direct (no schematic needed, egpu.io precedent), disk stays in KEYM, networks stay stock until coreboot. Effort to that point: one session.

## Progress
- 2026-09: plan written. PDF found (indiafix.in → Google Drive RAR, same 2.8 MB file as t.me/schematicslaptop), cached, sha256 recorded;
  chinafix.tech copy is a 5-page teaser — discarded. Backlog header updated with both schematics + preliminary page map. Nothing extracted yet.
  Plan revised same day: every phase carries a "What fits here" DIY-checked verdict; Phase 8 = mods.md (eGPU / networks / storage).

- 2026-09: Phase 0 DONE → `cells/wintermute/recon/xeon/sch/pages.md`. sha256 invariant. 74/74 titles (13 via tesseract OCR of the title block,
  pdftotext drops them on image-titled sheets: p7,39,40,54-56,61,62,64,65,67-69,71,72). Kill-switch 0.4 PASSED (p1 `LA-E152P`+`DSC (TBT)`, p29 `ALPINE-RIDGE_BGA337`,
  p49 `GM107-ES-A1_BGA908`). Lane budget: PCIE-1..20 + PEG + DMI + eDP from p3/p2 `[text]`; free on paper: PCIE-13,14,16,19,20.
  Findings for later phases: two flashes on p2 (W25Q128FVSIQ + W25Q64FVSSIQ) → P1; PD controller p31 has its own SPI → exclude in P1; EC = MEC5105 (p39/40/74).

- 2026-09: Phase 1 DONE → `cells/wintermute/recon/xeon/sch/spi-ec.md`. SPI sheet is p19, not p20. One flash `UC5` W25Q128FVSIQ on CS#0;
  `@UC6` W25Q64 nopop (Phase 0 "two flashes" corrected). EC MEC5105 on eSPI (`ESPI@ RH78`), `UE9`/SHD path is `LPC@` → EC fw in `UC5`.
  TPM NPCT650 on SPI0 CS#2. Straps: BIOS_REC=GPP_F10 (RH76 PU), top swap @RH86 off, ME_FWP←EC `ME_FW_EC` via QH4 → HDA_SDO.
  Whitelist verdict: only M.2 CONFIG_0..3 module-type detect → EC, no ID strap; coreboot not a prereq for network mods.
  Open: E152P draws RH37/RH177–185 as `@` while E151P pops them — DMM on board. EC ball numbers on p39 still [text].
  Invariant grep `schematic` hits this state file (name), not a PDF — false positive; pages.md uses `pN` cites (Phase 0 style).

- 2026-09: Phase 2 DONE → `cells/wintermute/recon/xeon/sch/gpio.md`. `DGPU_PWR_EN`=GPP_D12: RH346 100K PU `+3.3V_RUN` pop, @RH349 PD nopop
  → dGPU on by default. SRCCLKREQ0..7# = B5..B10,H0,H1 (WWAN, WLAN, WiGig, KEYM, LAN, MMI, TBT, dGPU); device-side links `@RF@RH10..17` drawn nopop
  (E151P: pop) → DMM, meanwhile `PcieRpClkReqSupport=false`. PCIE-13/14/16/19/20 + CLKOUT_PCIE_8..15 are ball-only NC → no spare slot without BGA work.
  JUART1 (nopop 6-pin, PCH UART2 C20/C21) = coreboot console candidate. TBT_FORCE_PWR=D4, RTD3_CIO_PWR_EN=C13, CIO_PLUG_EVENT#=G2.
  Invariants: `grep -L 'p\.[0-9]'` flags only pages.md (known), ls-files grep = this file only (known), gitleaks clean.

- 2026-09: Phase 3 DONE → `cells/wintermute/recon/xeon/sch/dgpu.md`. PEG x16, all pairs capped at TX (CPU side CC34..65 p6, GPU side CV427..458 p49),
  CPU lane k = GPU lane 15-k. Refclk = PCH SRC7, CLKREQ via QV10 gated by VRAM_EN. M620 has NO display outputs (IFPA..F NC) and NO VBIOS ROM
  (p50) → muxless, coreboot needs ACPI `_ROM`. Rails: +3.3V_GFX_AON (QV14, DGPU_PWR_EN) → GPU GPIO5 3V3_MAIN_EN → RT8813A +GPU_CORE
  (TDC 26.5 A) + UV15 EM5209 (+3.3V_RUN_GFX, +1.05V_PEX_VDD) → PGOOD=DGPU_PWROK → VRAM_EN (OR GC6_FB_EN) → SYX198D +1.35V_MEM_GFX (TDC 9 A).
  PERST = PLTRST# AND GPP_D10 AND GPU GPIO21. EC sees DGPU_PWROK on UE2 MCP23008 (0x40) GP2. p50 class strap self-contradicts (table→302h, cell→300h).
  Stale-BOM `@` in path: RH195, RV269, RV204/RV206, PR1302/PR1305 → DMM list. PEG-tap verdict risk H; D12-off risk L.

- 2026-09: Phase 4 DONE → `cells/wintermute/recon/xeon/sch/tb3.md`. `UT1` ALPINE-RIDGE_BGA337 (SKU not printed; port B + DP source NC → 2C;
  probes: JHL6340 `8086:15da`), NVM `UT2` W25Q80 with supply via `@RT9`/`@RT10` (both nopop → DMM). PCH PCIE5..8 x4, SRC6, PERST=`PCH_PLTRST#_AND` (shared).
  DPSNK0=DDI2 direct, DPSNK1=PS8338 SW1. RTD3 unwired (`@RT392`); `+3.3V_TBT`=`+3.3V_RUN` via PJP5 → no TB wake from S3. PD TPS65982 config 7
  (policy in its own flash `UT6`); Type-C sink path p.68: 2×5 A beads → S3/S4/S5 AON7409 → `+SDC_IN`, S4 by `EN_PD_HV_1`, S5 by EC `VBUS1_ECOK`, no strap cap.
  Error in gpio.md: `GPP_H0` pull-up is `RH132`, not `RH133` (that's #7). Left unedited (one OUT file per session); fix with Phase 5 commit.
  Dell KB 000060905: 3520 = four lanes. Open: `+3.3V_TBT_LC` source, WD19TB row for 3520 in the Dell dock matrix.

- 2026-09: Phase 5 DONE → `cells/wintermute/recon/xeon/sch/m2-storage.md`. KEYM = PCIE9..12 x4 (lane k = 9+k, CN65..72 0.22u, SRC3), power
  `+3.3V_HDD_M2` = `+3.3V_RUN` via PJP31 "2.8A", no switch. Bay = PCIE15/SATA2 → UN7 PI3EQX6741 redriver, `+5V_HDD` via UZ23 AOZ1336 (`HDD_EN`=C15)
  → SATA and KEYM never share lanes; SATA0B/1B/3 NC. WWAN: lane0 PCIE17 (CZ10/11 drawn fitted on E152P, `@` on E151P), lane1 = UZ29 PI3PCIE3212
  USB3-2 vs PCIE18 selected by SLOT2_CONFIG_1 → x2 SSD capable; lane-1 TX through `@RZ1/@RZ2` nopop → DMM. `m3042_PCIE#_SATA` driven by EC J12.
  `+3.3V_WWAN` PJP41 "2.5A"; `+3.3V_WLAN` PJP38 "2A", enable via `@RZ70`/`@RZ71` both nopop → DMM. WLAN = PCIE2/SRC1 + WiGig PCIE1/SRC2, no CNVi.
  Wrong page map: NGFF is p.37 (not p.35 = LAN), SATA/SSD p.42–43 as planned. Phase 4 claim "gpio.md RH133→RH132" was only half: all CLKREQ PUs were
  shifted one row (#0 RH123 … #7 RH133) — fixed in gpio.md; tb3.md link ref `@RF@RH13`→`RH16` fixed. Invariant "one OUT file per session"
  bent on purpose: gpio.md/tb3.md fixes ride along (planned in Phase 4 Next).
  DIY: no 5580/3520 NVMe-in-WWAN precedent; mattmillman: Dell 7x80 BIOS disables the WWAN root port. Dell manual: 92 Wh → no 2.5" drive.

- 2026-09: Phase 6 DONE → `cells/wintermute/recon/xeon/sch/power.md`. No E151P-style power-tree page; p.56 block diagram is stale (ISL95857/RT8207MZ
  vs ISL95855/SY8210A on the sheets) → rail table from per-sheet TDC boxes. `+3.3V_ALW` SY8288B 6.8 A TDC feeds WWAN/WLAN/LAN/RUN switches (pad labels sum 11.3 A).
  VCORE 2-ph 50/68 A, GT 25/55, SA 10/11.1. Charger `PU901` ISL88738, Rs1 `PR901` 10 mΩ, `PROG` `PR932` 105 K (outside ISL9237 Table 18 → Dell code);
  no ILIM strap, limit = SMBus register set by EC from PSID; `EMC@PL901` 1 µH 6.6 A in series = 129 W → 180 W brick buys nothing. PSID: `PQ2` FDV301N pass + `PQ3` OV clamp.
  Barrel minus → GND directly, all sense high-side → eGPU PSU ground bond harmless. RM520N-GL needs 3.0 A (Quectel) / EM9191 2.7 A vs `PJP41` "2.5A" → risk H.
  Correction: WLAN pad is `PJP36`, not `PJP38` (fixed in m2-storage.md). DMM: charger SMBus `@PR920/@PR922`, `@PR936`, `@PR926`, `@RZ64/@RZ65`.
  Not done: battery 68/92 Wh (no sheet data beyond the connector; mechanics in m2-storage.md).

- 2026-09: Phase 7 DONE → `cells/wintermute/recon/xeon/sch/display.md`. Panel sheet is p.34 (JEDP1 ACES 50398-04041 40p), not p.25–28. eDP x2: CPU lanes 2/3
  `X` NC (p.9) → no UHD panel. DDI1 → PS8407 HDMI 1.4 (EQ H, passive DDC); DDI2 → AR DPSNK0; DDI3 → PS8338 SW1 (OUT1 AR DPSNK1 / OUT2 → SW2 → WLAN Key A DP x4
  or RTD2166 VGA x2). Both PS8338 CFG0=H auto-HPD, SW low, no GPIO control → priority AR > WiGig > VGA. All outputs iGPU; no mux → eGPU reaches panel only by PCIe copy.
  Panel VDD `UV24` G524B1T11U on `+3.3V_ALW`, EN = diode-OR(ENVDD_PCH F19, EC LCD_VCC_TEST_EN); BKEN/PWM diode-OR PCH F20/F21 + EC PWM7/PWM4;
  backlight supply `QV1` AO6405 from `+PWR_SRC` gated by EC `EN_INVPWR` ONLY → coreboot first-boot test item. p.56 block diagram says AP2821K (stale again).
  `FIT: nothing` lines got a `DIY:` field too (invariant 38 vs Phase-plan wording).

Next: Phase 8 — `mods.md` (collect `grep -h '^FIT:' $OUT/*.md`, three sections + order of operations; backlog Progress line).
Blocked on: nothing.
