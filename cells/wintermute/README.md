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
  does): until then the EC reads no PECI and the fan never spins.
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

Tools
- `patches/inteltool-cm238-gpio.patch`: stock inteltool has no CM238 GPIO dump.
