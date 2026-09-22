# coreboot-5580 — port coreboot to Dell Latitude 5580 / Precision 3520 (LA-E152P)

Status: PLANNING (2026-09). Owner: user; Claude = co-engineer.
Prereq: none for Phase 0 (runs on the live laptop as is). Phase 1+ needs the SOIC-8 clip.
Target: coreboot + edk2 payload booting NixOS (penrose) on LA-E152P.
Order of operations (fixed): old i7-U board is the test bench for the *whole* cycle
(dump → build → flash → boot → EC). New Xeon board is checked on stock BIOS once (Phase A),
then goes back in the box and is not opened until old board runs coreboot daily (Phase 5).
Source refs: `mainboard/dell/optiplex_3050` (same gen, Dell, Kaby Lake, ME/BootGuard precedent),
`ec/dell/mec5035` (Dell EC protocol, E7240/E7440), `soc/intel/skylake` (KBL FSP 2.0).
Hardware on hand: ESP-Prog (FT2232H, MPSSE → flashrom `ft2232_spi:type=2232H,port=A,divisor=8`),
old i7-U board (in the laptop now), new Precision 3520 board (E3-1505M v6 + M620), dGPU heatsink,
130 W DA130PE1-00 charger. SOIC-8 clip: ordered — confirm arrival in Progress.
Optional: 3.3 V LDO module, 1 kΩ pull-up.
Repo: rensa cell `cells/wintermute`. Own `flake.nix`+`flake.lock` pin upstream coreboot as non-flake input.
`dev wintermute` → devshell with flashrom/flashprog, coreboot-utils, intelp2m, me_cleaner, uefitool, msr-tools,
acpica, coreboot-toolchain.i386+x64, scripts `recon` / `dump` / `inspect` / `flash-bios`.
`BOARD=i7u|xeon` selects `cells/wintermute/recon/<board>/`; *.bin/*.rom/*.dat/flashregion_* gitignored, text reports committed.
Naming: board dir `mainboard/dell/latitude_5580`, variants `latitude_5580` (i7u) / `precision_3520` (xeon).
Recon dirs: `recon/i7u/`, `recon/xeon/`. Dumps: `stock-<board>-<yyyymmdd>.bin` (+`.sha256`), never in git.
Build output: `result/coreboot.rom`. Boot log: `recon/<board>/cbmem-<n>.txt` per attempt.

Invariants:
- Two identical reads (`cmp`) before trusting a dump; `dump` script refuses otherwise.
- Dump copied to KeePass attachment + osgiliath before any write to the chip.
- Never flash with battery / CMOS cell / AC connected. Programmer supplies 3.3 V only.
- `flash-bios` writes only `-i bios` via `layout.txt`; descriptor/ME/GbE stay stock until Phase 4.4.
- Old board only, through Phase 4. New board gets flashed only from a config that already booted on old (Phase 5).
- Boot Guard kill-switch: `intelmetool -b` shows verified boot fused ⇒ project stops, ship Fallback.
- One change per flash. Every flash attempt gets a numbered `cbmem-<n>.txt` (or "dead: <symptom>") in Progress.

## Phase 0 — Live recon on old board (no hardware, ~15 min) ⏳
0.1 `dev wintermute && sudo --preserve-env=BOARD recon` (BOARD unset = i7u). Produces in `recon/i7u/`:
    intelmetool-b.txt, intelmetool-m.txt, msr-0x13a.txt, inteltool.txt, superiotool.txt, dsdt.dsl, ssdt*.dsl,
    lspci.txt (-nnvvvxxxx), lsusb.txt, dmi.txt, iomem.txt, bios_version.txt, ec-map.txt.
0.2 Boot Guard verdict: read intelmetool-b.txt + msr-0x13a.txt. Record in Progress as one line:
    `BG i7u: <not fused | measured | verified>`. Verified ⇒ STOP, go to Fallback.
0.3 ME state: from intelmetool-m.txt — ME version, HAP bit, region locks. One line in Progress.
0.4 Panel + ports: `edid-decode /sys/class/drm/card*-eDP-1/edid` → recon/i7u/edid.txt; `lspci -nn | grep -i thunder`
    (JHL6540 present = TB3 on this board) → note in Progress.
0.5 Commit text reports: `git add cells/wintermute/recon/i7u && git commit -m "wintermute: i7u live recon"`.
Exit criteria: `recon/i7u/` committed; Progress has BG/ME/TB lines for i7u; BG ≠ verified.

## Phase A — New board acceptance on stock BIOS (before old board goes back in) ⏳
Purpose: prove the new board is not DOA and get its recon while it is convenient. No flashing.
A.1 Swap in new board + M620 heatsink + 130 W charger. Boot stock BIOS (F2). Photo of BIOS main page → recon/xeon/.
A.2 In BIOS: Service Tag, BIOS version, CPU = E3-1505M v6, RAM seen (both slots), dGPU present, TB3 tab present. Write to
    `recon/xeon/acceptance.md`.
A.3 Boot NixOS live USB (penrose ISO or any). `BOARD=xeon sudo --preserve-env=BOARD recon` → recon/xeon/ (same file set as 0.1).
A.4 Boot Guard verdict for xeon: `BG xeon: <...>` in Progress. This is the real kill-switch for the end goal.
A.5 ECC check: `dmesg | grep -i edac`, `dmidecode -t memory | grep -i 'error correction'` → recon/xeon/ecc.txt.
A.6 TB3 check: `boltctl list` with dock attached; `lspci -nn` shows JHL6540 → recon/xeon/tb3.txt.
A.7 15 min stress: `stress-ng --cpu 8 --timeout 900` + `sensors` — no throttling below base clock, fan spins. Note temps.
A.8 Commit recon/xeon text. Remove new board, back in antistatic bag. Old board back in. Confirm old board boots stock.
Exit criteria: `recon/xeon/` committed with acceptance.md; new board boxed; laptop runs old board on stock again.

## Phase 1 — Physical access: chip, clip, first dump (old board) ⏳
Waits on: SOIC-8 clip arrival.
1.1 Teardown to bare board. Locate SPI flash: count (1 or 2), package (SOIC-8 vs WSON-8), marking. Photo → recon/i7u/spi-chip.jpg.
    WSON-8 ⇒ clip useless; STOP, order WSON probe / plan hot-air to SOIC socket. Note in Blocked on.
1.2 Wire ESP-Prog → clip: TCK→CLK, TDI→MOSI, TDO→MISO, TMS→CS#, GND→GND, 3.3V→VCC+WP#+HOLD#.
    Board: no AC, no battery, no CMOS cell. Multimeter: 3.3 V on VCC pin with programmer plugged in, 0 V without.
1.3 Detect: `flashrom -p "$FLASHROM_PROGRAMMER"` — expect exactly one chip name. Several ⇒ set `CHIP=`. None ⇒
    check clip seating, then add external 3.3 V LDO, then pull CS# up. Record which fix worked.
1.4 `dump` → `recon/i7u/stock-i7u-<date>.bin` + `.sha256`. Copy to KeePass + osgiliath *now*.
1.5 `inspect stock-i7u-<date>.bin` → ifd.txt, layout.txt, flashregion_*.bin, me_cleaner-c.txt. Commit text files.
1.6 Round-trip proof: `flash-bios` the *stock* BIOS region back (`flashregion_1_bios.bin` — check number in layout.txt),
    reassemble laptop, boot stock. Proves clip+write path works before any coreboot image touches the chip.
Exit criteria: dump verified & backed up; layout.txt committed; stock re-flash boots. Chip write path is trusted.

## Phase 2 — Build a coreboot image (no flashing) ⏳
2.1 `cells/wintermute/packages.nix`: `coreboot-5580` derivation from `inputs.coreboot` + board dir overlay + `defconfig`.
    `nix build .#coreboot-5580` must fail *only* on the missing board dir at this point.
2.2 Board skeleton: copy `mainboard/dell/optiplex_3050` → `mainboard/dell/latitude_5580`. Rename, Kconfig, board_info.txt.
2.3 `devicetree.cb` from recon/i7u/lspci.txt + inteltool.txt: PCI devices on/off, PCIe root ports, USB ports (xHCI OC map).
2.4 GPIO: `intelp2m -p snr -fld cb recon/i7u/inteltool.txt` → `gpio.h`. Review against DSDT for EC/lid/power lines.
2.5 Blobs from stock dump: `UEFIExtract flashregion_1_bios.bin` → FSP-M/FSP-S (or Intel FSP repo KBL), `vbt.bin`, microcode.
    Put under `3rdparty/blobs/mainboard/dell/latitude_5580/` in the overlay (gitignored binaries, hashes committed).
2.6 defconfig: `SOC_INTEL_KABYLAKE`, `VENDOR_DELL`, `BOARD_DELL_LATITUDE_5580`, no EC driver yet, payload = edk2 (MrChromebox
    UefiPayload, second cell input), `CONSOLE_CBMEM`, `CONSOLE_SPI_FLASH` on (post-mortem log if it never reaches cbmem).
2.7 `nix build .#coreboot-5580` green → `result/coreboot.rom`. `cbfstool result/coreboot.rom print` shows fsp, vbt, payload.
2.8 Size sanity: `ifdtool -f layout.txt` bios region size == `stat -c %s` of the BIOS part we will write. Pad/trim explicitly.
Exit criteria: reproducible `result/coreboot.rom`; cbfstool listing committed as recon/i7u/cbfs-v1.txt.

## Phase 3 — First boots on old board ⏳
Each step = one flash + one observation. Log every attempt in Progress as `flash #n: <config change> → <result>`.
3.1 `flash-bios result/coreboot.rom`. Power on with ext keyboard + HDMI. Observe: fan spin, any HDMI signal, 60 s.
3.2 Dead (no fan / no signal): `dump` again, `cbfstool` the SPI-flash console region → recon/i7u/spiconsole-1.txt.
    Look for last POST code. Fix one thing, back to 3.1. If nothing at all in SPI console ⇒ romstage never ran ⇒ suspect
    descriptor/FSP-M placement (2.8) or memory init.
3.3 Alive to romstage but no display: expected — edk2 needs VBT + IGD. Check `cbmem -c` after booting NixOS from USB via
    ext HDMI once ramstage runs; save recon/i7u/cbmem-<n>.txt.
3.4 edk2 menu on HDMI ⇒ boot NixOS USB, then internal NVMe (systemd-boot). Save `cbmem -c`, `cbmem -t` (boot times), `dmesg`.
3.5 Stability: 10 cold boots in a row, memory training passes each time (`cbmem -c | grep -i 'MRC\|training'`). Log count.
Exit criteria: NixOS (penrose) boots from NVMe on old board via coreboot+edk2; 10/10 cold boots; cbmem-*.txt committed.

## Phase 4 — Usability on old board (EC, panel, power) ⏳
Each step ends with a line in `recon/i7u/checklist.md` (works / partial / no).
4.1 EC identification: chip marking on board + DSDT EC OperationRegion. Expect Microchip MEC16xx. Compare command set
    with `ec/dell/mec5035`. Decision line in Progress: reuse mec5035 / new `ec/dell/mec16xx`.
4.2 Internal keyboard + touchpad (PS/2 via EC, i8042). Lid switch, power button.
4.3 eDP panel: VBT from stock, IGD enabled in devicetree; edk2 shows on internal panel. Backlight + brightness keys.
4.4 Battery/AC (SBS via EC), fan control, thermal zone — port EC ASL from stock DSDT into `acpi/ec.asl`, trim.
4.5 S3 suspend/resume; wake on lid. S0ix deferred.
4.6 SD reader, WWAN M.2 power, audio (HDA verbs from stock `hda-verb` dump), webcam, Wi-Fi.
4.7 Daily-drive old board on coreboot for ≥ 1 week. Then me_cleaner -S on ME region (first descriptor/ME write) + own SB
    keys via edk2 → lanzaboote. Requires fresh dump + backup before.
Exit criteria: checklist.md all green or explicitly "deferred"; 1 week daily use; ME neutered and booting.

## Phase 5 — Transfer to new board (Xeon + M620 + TB3) ⏳
Precondition: Phase 4 exit met. New board recon already in recon/xeon/ (Phase A).
5.1 Swap boards. Repeat 1.1–1.6 with `BOARD=xeon` (chip may differ; own dump; own stock re-flash round-trip).
5.2 Variant `precision_3520`: KBL-H CPU, ECC SO-DIMM (FSP UPD), PEG port for M620 (iGPU-only first, dGPU off in devicetree).
5.3 Flash the *exact* image that booted old board with only variant diff. Repeat 3.1–3.5.
5.4 Enable PEG/M620; verify `lspci` sees it, NixOS nvidia/nouveau loads. Power via GPIO from stock DSDT.
5.5 Thunderbolt JHL6540: PCIe hotplug reservation in devicetree, TBT ACPI from stock DSDT. TB firmware on its own SPI — never touch.
5.6 me_cleaner -S + SB keys as in 4.7. Daily-drive.
Exit criteria: new board daily-driven on coreboot; TB dock + ECC confirmed (`edac`) or documented as not-yet.

## Phase 6 — Upstream ⏳
6.1 Clean code, `checkpatch`, `Documentation/mainboard/dell/latitude_5580.md`.
6.2 Gerrit CL, review loop. 6.3 Libreboot board config PR (optional).

## Fallback at any phase
Stock BIOS + `me_cleaner -S` (HAP) + own SB keys (sbctl/lanzaboote). One evening; most of the security benefit.
If Boot Guard verified on xeon but not on i7u: coreboot stays on old board as a hobby target, new board = Fallback only.

## Progress
- 2026-09: plan written. Cell `wintermute` created (flake+lock, devshell, scripts), root flake wired.
- 2026-09: ORDERED — SOIC-8 clip (clone), Precision 3520 board (LA-E152P, E3-1505M v6 + M620), dGPU heatsink+pipes, 130 W DA130PE1-00 charger.
- Side note: CWWK S8 (i3-N305, ADL-N) firewall — coreboot NOT feasible (no public ADL-N FSP, no port, no Dasharo). Not pursued.
- 2026-09: ARRIVED — new board, cooler, charger. Clip: unconfirmed.
- 2026-09: plan rewritten granular. Sequence fixed: Phase 0 (live recon, old) → A (new board acceptance on stock, then boxed)
  → 1–4 full coreboot cycle on old board → 5 new board → 6 upstream. Old board = polygon for every first-time step.

Next: 0.1 — `dev wintermute && sudo --preserve-env=BOARD recon` on the live laptop, now, before any teardown.
Then A.1 (new board acceptance) whenever you open the chassis; then 1.1 on clip arrival.
Blocked on: SOIC-8 clip (Phase 1 only). Nothing blocks 0 or A.
