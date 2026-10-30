# precision_3520 under coreboot — feature checklist

State as of flash #16 (87ec2bc). works / partial / no / deferred / dropped.

| item | state | evidence |
|---|---|---|
| EC driver | works | `ec/dell/mec5035` reused, no new mec5105 driver. Board code adds the MEC5105 extras: CPU id mailbox cmd 0xbf (fan loop), eSPI SMI → cmd 0x04 event fetch → SWGPE (`_L62`). |
| internal keyboard | works | edk2 menu, systemd-boot, Linux ("AT Translated Set 2"). coreboot sets 8042 XLATE; edk2 `PcdPs2KbdExtendedVerification=FALSE` (EC answers 0x08 to 0xAB). |
| touchpad | works | PS/2 Generic Mouse in Linux; I2C 00:15.x not enabled. |
| power button | works | powers on; short press reaches logind. |
| lid | works | `_LID` polls; "Lid closed."/"Lid opened." via eSPI SMI → SWGPE. One "[Firmware Bug] Unexpected lid state" at boot. |
| eDP panel / backlight / brightness keys | works | panel on from TianoCore (#18); backlight 0..937 via intel_backlight; brightness keys via ACPI Video Bus (#19), native intel_backlight kept by _OSI (#20). |
| HDMI | works | from TianoCore on; the one black boot in #4 was a misread (owner). |
| theming (bootsplash, edk2 colours) | works | splash from assets/bootsplash.png; console + setup colours from common/theme.nix (#22). |
| AC / battery | works | AC + BAT0 in power_supply, plug/unplug flips live. |
| fan | works | EC fan loop runs after cmd 0xbf; KDRT0 tracks pkg within 1–2 °C. RPM not visible to Linux (no Dell SMM 0xB2). |
| thermal zone `_TZ` | works | `acpitz` from EC CPU sensor (EC 0x33/0x34), 46 °C idle, 73→87 °C under 60 s stress-ng, critical 107 °C. No passive trip; EC drives the fan. |
| sleep | dropped | S0/S5 only by design (no `_S3`, `DISABLE_ACPI_HIBERNATE`). |
| ECC | deferred | 2×8 GB non-ECC DIMMs fitted; ie31200_edac loads, mode None. |
| dGPU M620 | partial | PEG x16 8GT/s (= stock), 01:00.0 10de:13b4 enumerates, no AER (#23). VBIOS via ACPI `_ROM` from CBFS: nouveau reads bios 82.07.bb.00.11, no "Unable to load the VBIOS" (#24). Runtime D3cold via ACPI `_PR3`: suspends idle, wakes on access, nouveau binds from D3cold, no AER (#26). PRIME offload on nouveau: `nvidia-offload glxinfo -B` = NV117, iGPU stays scanout, back to D3cold after. Proprietary driver not tried. |
| Thunderbolt 3 | no | RP5 off. |
| TPM 2.0 | works | NPCT650 via TIS MMIO 0xFED40000; ZFS unlock from PCR 15 unchanged. edk2 TPM off, no measured boot. |
| audio | partial | HDA ALC256 + HDMI codec probe; no verb table, playback not tested. |
| Wi-Fi | deferred | no card fitted (RP2 empty). |
| SD reader | no | RP3 in devicetree, not tested. |
| WWAN | no | RP17/18 off. |
| webcam | no | not tested. |
| touch screen USB2 port 9 | dropped | port off (no touch panel), `error -71` gone. |
| daily drive ≥ 1 week | dropped | owner raises issues as they come. |
| `me_cleaner -S`, own SB keys | no | ME is deguarded + HAP; SB support off in edk2. |
| performance vs stock | works | bench-coreboot-20261030: 10 min all-core 3365 MHz / 75 °C / 35.24 W (stock 3385 / 76 / 35.24), sysbench +1.9 %, idle 1.74 W (stock 2.47, governor powersave vs performance). |
