# wintermute

coreboot + edk2 for the Dell Precision 3520 (LA-E152P, Xeon E3-1505M v6, CM238):
pinned upstream trees plus the overlay in `coreboot/`. Build: `nix build .#coreboot-5580`.

## Where we differ from upstream

Board
- Standalone `dell/precision_3520`, not a `dell/sklkbl_desktops` variant: that
  dir is built around the SCH5555 Super I/O, this board has only the EC.
- `bootblock.c` drives `GPP_C15` (HDD_EN) high: FSP-S disables SATA port 2
  if the bay SSD is still unpowered when it probes.
- `gpio.h` is the inteltool dump, except `GPP_D12` (DGPU_PWR_EN) and `GPP_D10`
  (DGPU_HOLD_RST#) forced high; the OS leaves both low with the dGPU in D3.
  `bootblock.c` sets them already, so the M620 is up when FSP-M trains PEG.
- `ramstage.c` sets the 8042 XLATE bit: the EC sends Set 1 scancodes, which
  Linux misreads as Set 2 and keys stick.
- `ramstage.c` sends mailbox cmd 0xbf (CPU class | TDP code, as Dell's DXE
  does): until then the EC reads no PECI and the fan never spins. Then cmd
  0x60 arg 1: the EC keeps the speakers muted until the BIOS unmutes them
  (headphones play either way).
- `hda_verb.c`: stock pin defaults + codec SSID, so the kernel picks the Dell
  ALC3246 fixup by pin match (headset mic). Dell's PEIM coef writes are left
  out: the kernel fixup programs the codec itself.
- Touchpad: HID over I2C1 (`DLL07A9` at 0x2c, as stock TPD1); the EC's PS/2
  mouse alone has no gestures. I2C0 is on with nothing on it: without
  function 0 nobody scans 15.1. The EC masters the pad's bus until EC RAM
  0x20 is written 0 (stock `ECTP(0)`); `acpi/ec.asl` does that in `_REG`.
- TPM: the NPCT650 sits on SPI CS#2 behind the PCH's TIS MMIO window
  (0xfed40000, stock `MSFT0101`), so `MEMORY_MAPPED_TPM` + `drivers/pc80/tpm`,
  not the SPI TPM driver. USB2 port 8 (touchscreen, not fitted) is off.
- `smihandler.c` answers the EC's eSPI SMI with mailbox cmd 0x04 (fetch +
  ack, as Dell's SMM does) and raises SWGPE; `_L62` in `acpi/ec.asl` notifies
  LID0 and diffs EC 0x06 for AC/BAT0. The EC never raises its ACPI SCI on its own.
- Own `acpi/ec.asl` (EC at 0x930/0x934, GPE 0x6E, LID0, AC, BAT0, `\_TZ.THRM`
  from the EC CPU sensor at 0x33/0x34): upstream
  `ec/dell/mec5035/acpi` is newer than the pin, and its SCI switch does not stop
  the eSPI SMIs on MEC5105.
- igpu `panel_cfg` (delays and 200 Hz PWM from the VBT): without it the PCH
  backlight PWM stays off and the panel is dark until i915 loads. i915 inherits
  the period, so `intel_backlight` runs 0..937.
- Brightness keys: the EC reports Fn+F11/F12 in the SMI event block (byte 0
  bit 1, byte 2 = Set 1 code 0x57/0x58); `HKEY` in `acpi/ec.asl` notifies
  `GFX0.LCD0` (from `GMA_STATIC_DISPLAYS`) with 0x87/0x86. Notify only, no
  `_BCM` writes, so the OS backlight driver stays the only PWM writer.
- `\_SB._INI` queries `_OSI` as stock does: without "Windows 2012" Linux takes
  `acpi_video0` and skips `intel_backlight`.
- `ME_CLEANER_ARGS "-S --whitelist MFS"`: the deguarded ME does not boot
  without MFS.
- M620 VBIOS: the board has no GPU ROM chip, so stock serves the image via
  ACPI `_ROM`. We ship it as CBFS `pci10de,13b4.rom` (`VGA_BIOS`, not run:
  libgfxinit is pinned in the defconfig) and coreboot's `pci_rom_ssdt()` writes
  `_ROM` under `\_SB.PCI0.PEGP.DEV0`; `acpi/peg.asl` declares that scope, which
  the Skylake ASL lacks. The image is not in git: `extract-vbios <stock.bin>`
  pulls it from your own dump into the store (`requireFile`, sha256 pinned).
- M620 runtime power: `acpi/peg.asl` gives `PEGP` a `_PR0/_PR3` power resource
  (D12/D10 with a PWROK wait, SRC7 clock gate, link disable via 0xB0), ported
  from Dell's PegSsdt pre-Windows 8 branch. Dell's Win8+ branch uses the L2/3
  request at 0x248, which hangs nouveau behind a 0x1901 port. `DEV0._DSM`
  answers only Optimus functions 0 and 0x1A, so nouveau turns runtime PM on;
  no GC6.
- SMBIOS BIOS date = the coreboot pin's commit date, not the 01/01/1970 of
  `BUILD_TIMELESS`: Linux keeps root ports of pre-2015 firmware out of runtime
  D3, so the M620 would never reach D3cold.
- Core+cache undervolt −90 mV via the OC mailbox driver, values as CBFS
  `option/oc_undervolt_*` integers (`mkRom` `options`): the board has no CFR
  menu, so they are fixed per build. Measured live: all-core holds the 3.6 GHz
  ratio ceiling inside the EC's 35 W limit.
- Thunderbolt 3 (Alpine Ridge 2C on RP5) via upstream `drivers/intel/dtbt`,
  with `TBT_FORCE_PWR` (`GPP_D4`) held high and PCIe hotplug padding. With D4
  low the controller powers off and comes back on a plug masked again, with
  nobody to send BOOT_ON; stock re-runs it from the plug event. Two
  patches on dtbt.c: SL1 (user authorisation, bolt on the OS side) where
  upstream hardcodes SL0; and BOOT_ON/USB_ON sent before enumeration over a
  temporary bus on the root port. This controller reads VID 0xffff until
  BOOT_ON, so upstream's per-device `.enable` never runs, and its BOOT_ON
  sets no DONE bit, so the VID unmask is the success signal. After a warm
  reset with nothing plugged in the first BOOT_ON is dropped; it is resent
  until the VID unmasks.
- RP5 capped at Gen2 (`PcieRpPcieSpeed[4] = 2` in `ramstage.c`): at 8 GT/s
  the Alpine Ridge upstream port logs ~4 BadDLLP per MB of host-to-dock
  traffic, none at 5 GT/s. FSP's Gen3 software EQ search did not change it.
  Lifts when a Gen3 EQ setting is found that runs clean.

Payload
- edk2 is MrChromebox `uefipayload_2605`, built as its own derivation:
  coreboot's edk2 Makefile clones into the tree, which the sandbox forbids.
- `PcdPs2KbdExtendedVerification=FALSE`: the EC answers the 8042 interface test
  with 0x08, so Ps2KeyboardDxe never binds and the boot menu has no keyboard.
- edk2 TPM and LVGL off: one of them reset-loops edk2 here, not bisected.
  Secure Boot off until own keys are enrolled.
- Bootsplash = `assets/bootsplash.png`, faded into the palette black and scaled
  to 400x400, swapped into `MdeModulePkg/Logo/Logo.bmp`: coreboot's `logo`
  target sits in the edk2 Makefile we bypass. BootLogoLib skips a logo taller
  than the screen.
- Console colours: GraphicsConsoleDxe's 16-colour table is rewritten from
  `cells/common/theme.nix` `ansi`. The setup browser's `Colors.h` and field PCDs
  are flipped to a dark body: its stock light-grey body would be the palette's
  tan, with blue text on it. Setup-form title/footer are outlines on that body,
  as the front page has none.
- BootLogoLib and the boot prompt fill with a hard-coded `#000`, which outlives
  the splash in the bottom rows of a 1080 px mode (56 text rows = 1064 px);
  both take palette colour 0 (prompt text colour 15).
- `coreboot-qemu` runs without SMMSTORE: `-bios` maps the ROM read-only and
  edk2 hangs on a black screen.

ME / Boot Guard
- deguard has no PCH-H 5M target. The H/2M donor (ASRock H110M-DGS 7.30,
  ME 11.6.0.1126) padded with 0xFF fills the 5M region, as on the Supermicro
  X11SSH-F (deguard CL 91226). Delta: `deguard/precision_3520`.

EC firmware
- The EC region (0x700000–0x74FFFF) on this board is not stock: the quiet
  mode's fan tables are rewritten. CPU: 2500 rpm above 75 °C (off below 60),
  3000 above 84, 3700 above 94, 4400 above 96; memory and M.2 sensors start
  the fan at 48 °C instead of 40, so it stops at idle. Skin and GPU tables are
  stock. Stock quiet runs 2300 rpm at idle on the memory/M.2 steps.
  Measured cover on: 0 rpm idle, 3700 rpm at 35 W sustained, pkg 86–88 °C.
  The quiet mode is lost with the RTC cell (default balanced), so `ramstage.c`
  sets it at every boot (mailbox cmd 0xA6 sub 1, mask 4); a mode picked from
  the OS lasts until the next boot. The patch tool
  is not in this repo yet; restore the EC region only from a dump taken after
  the patch.

Tools
- `patches/inteltool-cm238-gpio.patch`: stock inteltool has no CM238 GPIO dump.

OS side (penrose)
- Charge limit: stock does it with Dell SMBIOS tokens through its SMM, which
  coreboot lacks, and the pack ignores the EC's custom start/stop (PIDs
  0x710..0x712). `cells/workstation/profiles/battery-charge-hold.nix` toggles
  the EC's Peak Shift hold (mailbox cmd 0x1C, PIDs 0x4EA/0x4EE..0x4F4) from a
  timer: on at 80 %, off at 75 %. `charge-mode full` until reboot.

## Known, untested

- Thunderbolt 3 PCIe tunnel: nothing TB-native has been plugged in yet (no
  eGPU, NVMe enclosure or TB dock on hand). What works is the USB-C side of
  Alpine Ridge (USB 3.1 Gen 2 xHCI, DP alt mode, a DisplayLink dock). Unknown:
  boltd enrolment of a real device (SL1), PCIe hotplug of a tunnelled bridge
  into the hotplug padding, and whether the RP5 Gen2 cap holds for one. With
  the cap a tunnel gets ~16 Gb/s instead of ~32 Gb/s.
