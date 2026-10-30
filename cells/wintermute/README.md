# wintermute

coreboot + edk2 for the Dell Precision 3520 (LA-E152P, Xeon E3-1505M v6, CM238):
pinned upstream trees plus the overlay in `coreboot/`. Build: `nix build .#coreboot-5580`.

## Where we differ from upstream

Board
- Standalone `dell/precision_3520`, not a `dell/sklkbl_desktops` variant: that
  dir is built around the SCH5555 Super I/O, this board has only the EC.
- `bootblock.c` drives `GPP_C15` (HDD_EN) high: FSP-S disables SATA port 2
  if the bay SSD is still unpowered when it probes.
- `gpio.h` is the inteltool dump, except `GPP_D12` (DGPU_PWR_EN) forced high;
  the OS leaves it low with the dGPU in D3.
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

Payload
- edk2 is MrChromebox `uefipayload_2605`, built as its own derivation:
  coreboot's edk2 Makefile clones into the tree, which the sandbox forbids.
- `PcdPs2KbdExtendedVerification=FALSE`: the EC answers the 8042 interface test
  with 0x08, so Ps2KeyboardDxe never binds and the boot menu has no keyboard.
- edk2 TPM and LVGL off: one of them reset-loops edk2 here, not bisected.
  Secure Boot off until own keys are enrolled.

ME / Boot Guard
- deguard has no PCH-H 5M target. The H/2M donor (ASRock H110M-DGS 7.30,
  ME 11.6.0.1126) padded with 0xFF fills the 5M region, as on the Supermicro
  X11SSH-F (deguard CL 91226). Delta: `deguard/precision_3520`.

Tools
- `patches/inteltool-cm238-gpio.patch`: stock inteltool has no CM238 GPIO dump.
