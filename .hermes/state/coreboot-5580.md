# coreboot-5580 — port coreboot to Dell Latitude 5580 / Precision 3520 (LA-E152P)

Status: PLANNING (2026-09). Owner: user; Claude = co-engineer.
Prereq: 5580 hardware upgrade finished and daily-driven on stock BIOS
(see ~/Documents/latitude-5580-upgrade.md). Do NOT touch the new board until Phase 3.

Target: coreboot + edk2 payload booting NixOS (penrose) on LA-E152P, first with
Kaby Lake-U i7 (old board, sacrificial), then Xeon E3-1505M v6 (new board). Stretch: upstream Gerrit, then Libreboot inclusion.
Source refs: `mainboard/dell/optiplex_3050` (same gen, Dell, Kaby Lake, ME/BootGuard precedent),
`ec/dell/mec5035` (Dell EC protocol, E7240/E7440), `soc/intel/skylake` (KBL FSP 2.0).
Hardware on hand: ESP-Prog (FT2232H, MPSSE → flashrom `ft2232_spi:type=2232H,port=A`), old i7-U board.
To buy: SOIC-8 clip (Pomona 5250 or 2× clone). Optional: 3.3 V LDO module, 1 kΩ pull-up.
Repo: `~/workspace/playground/coreboot-5580` (new flake: toolchain, build, `flashrom` wrapper, dumps NOT committed — `.gitignore` *.bin).
Naming: board dir `mainboard/dell/latitude_5580`, variants `latitude_5580` / `precision_3520` (same LA-E152P, differ in CPU/dGPU).

Invariants:
- Always two identical reads (`cmp`) before trusting a dump; keep `stock-<board>-<date>.bin` off-repo in KeePass-attached storage + osgiliath.
- Never flash with battery / CMOS cell / AC connected. Programmer supplies 3.3 V only.
- Never write descriptor/ME region until Phase 1 boots; only BIOS region (`--ifd -i bios`).
- Old board = only test subject through Phase 2. New board gets flashed only from a config that already booted on old.
- Boot Guard result is a kill-switch: verified-boot fused ⇒ project stops, fallback = me_cleaner + own SB keys.

## Phase 0 — Recon (kill-switch) ⏳
0.1 On the *live* laptop (before teardown), as root:
    `intelmetool -b` (Boot Guard: expect "not fused"/"disabled"), `intelmetool -m` (ME version/HAP),
    `rdmsr 0x13A` (BOOT_GUARD_SACM_INFO), `inteltool -a > inteltool.txt`, `acpidump -o acpi.dat && acpixtract -a acpi.dat`,
    `lspci -nnvvvxxxx > lspci.txt`, `dmidecode > dmi.txt`, `cat /proc/iomem`, `superiotool -dV`.
    Store everything in repo `recon/<board>/`.
0.2 Locate SPI chip(s) on LA-E152P: count (1 or 2), package (SOIC-8 vs WSON-8), marking (W25Q128/256?). Photo → repo.
0.3 Wire ESP-Prog → clip (TCK→CLK, TDI→MOSI, TDO→MISO, TMS→CS#, GND, 3.3V→VCC+WP#+HOLD#). Board fully unpowered.
0.4 `flashrom -p ft2232_spi:type=2232H,port=A,divisor=8 -r d1.bin`; repeat → `cmp d1.bin d2.bin`. If chip not detected: `-c <model>`, add ext 3.3 V, or pull CS# up.
0.5 `ifdtool -x`, `ifdtool -d` → regions map; `me_cleaner -c` → ME version, HAP state.
    Decompile DSDT/SSDTs (`iasl -d`) → grep EC (`\_SB.PCI0.LPCB.ECDV` / `EC0`), record EC RAM fields and SMBus/PMIO commands.
Exit criteria: Boot Guard not enforcing; full stock dump verified & backed up; SPI layout + chip known; DSDT EC map extracted.

## Phase 1 — Minimal boot on old board (i7-U) ⏳
1.1 Flake: coreboot toolchain (`nixpkgs#coreboot-toolchain.x86_64`), pinned coreboot src, edk2 payload (MrChromebox UefiPayload fork), `nix run .#flash-bios-region`.
1.2 Board skeleton copied from `optiplex_3050`; `devicetree.cb` from `lspci`+`inteltool`; GPIO via `intelp2m -p snr -fld cb inteltool.txt` → `gpio.h`.
1.3 FSP 2.0 KBL binaries from stock BIOS (`UEFIExtract`) or Intel FSP repo; `vbt.bin` from stock (`UEFIExtract` → VBT); ME region = stock (later: me_cleaner -S).
1.4 First build: `SOC_INTEL_KABYLAKE`, no EC, serial via USB debug (no UART on board) → rely on `cbmem -c` post-boot; if dead — SPI flash console (`CONSOLE_SPI_FLASH`).
1.5 Flash BIOS region only, keep stock descriptor+ME+GbE. Boot with external USB keyboard + HDMI. Reach edk2 → GRUB/systemd-boot → NixOS (penrose).
1.6 SeaBIOS/edk2 choice: edk2 (need UEFI for lanzaboote later).
Exit criteria: NixOS on ext display/keyboard, `cbmem -c` clean of fatal errors, memory training stable across 10 reboots.

## Phase 2 — EC / usability (old board) ⏳
2.1 EC identification (Microchip MEC16xx expected). Compare DSDT EC commands with `ec/dell/mec5035`; diff → new driver `ec/dell/mec16xx` or variant.
2.2 Internal keyboard + touchpad (PS/2 via EC, i8042), lid switch, power button.
2.3 Battery/AC (SBS via EC), fan control, thermal zone (needs ACPI: port EC ASL from stock DSDT, clean it).
2.4 eDP internal panel (VBT + IGD), brightness keys, backlight.
2.5 S3 / S0ix — likely S3 only first. Wake on lid.
2.6 SD reader, WWAN M.2 power, audio (HDA verbs from stock — `hda-verb` dump).
Exit criteria: usable as daily laptop on old board with coreboot; all above green in a checklist committed to repo.

## Phase 3 — New board (Xeon + M620 + TB3) ⏳
3.1 Recon repeat (0.1–0.5) on new board *before* first flash (its own dump, own BootGuard check, own SPD/ECC).
3.2 Variant `precision_3520`: CPU KBL-H, ECC SO-DIMM handling (FSP UPD), dGPU: PEG port on, Optimus — expect iGPU-only first; M620 power via GPIO.
3.3 Thunderbolt JHL6540 (Alpine Ridge): PCIe hotplug reservation in devicetree, TBT ACPI from stock; USB-C PD (TB controller firmware = stock, on its own SPI — don't touch).
3.4 me_cleaner -S on ME region; own Secure Boot keys via edk2 → lanzaboote.
Exit criteria: new board daily-driven; TB dock + eGPU work or documented as not-yet.

## Phase 4 — Upstream ⏳
4.1 Clean code, `checkpatch`, docs `Documentation/mainboard/dell/latitude_5580.md`.
4.2 Gerrit CL, review loop. 4.3 Libreboot board config PR (optional).

## Fallback at any phase
Stock BIOS + `me_cleaner -S` (HAP) + own SB keys (sbctl/lanzaboote). Achievable in one evening; gives most of the security benefit.

## Progress
- 2026-09: plan written. Waiting: 5580 upgrade completion, SOIC-8 clip.

Next: Phase 0.1 — run recon on the live laptop *before* teardown (free, 15 min). Then buy clip.
Blocked on: hardware upgrade in progress (user-curated).
