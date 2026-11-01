# precision_3520 under coreboot — feature checklist

State as of flash #16 (87ec2bc). works / partial / no / deferred / dropped.

| item | state | evidence |
|---|---|---|
| EC driver | works | `ec/dell/mec5035` reused, no new mec5105 driver. Board code adds the MEC5105 extras: CPU id mailbox cmd 0xbf (fan loop), eSPI SMI → cmd 0x04 event fetch → SWGPE (`_L62`). |
| internal keyboard | works | edk2 menu, systemd-boot, Linux ("AT Translated Set 2"). coreboot sets 8042 XLATE; edk2 `PcdPs2KbdExtendedVerification=FALSE` (EC answers 0x08 to 0xAB). |
| touchpad | works | #32: HID over I2C1 (`DLL07A9`, 0x2c, GPP_B3 IRQ), binds at a cold boot with no I2C errors, pointer + two-finger scroll. Needs I2C0 on (else 15.1 is not scanned) and EC RAM 0x20 ← 0 in `ECDV._REG` (stock `ECTP(0)`: the EC frees the bus). |
| power button | works | powers on; short press reaches logind. |
| lid | works | `_LID` polls; "Lid closed."/"Lid opened." via eSPI SMI → SWGPE. One "[Firmware Bug] Unexpected lid state" at boot. |
| eDP panel / backlight / brightness keys | works | panel on from TianoCore (#18); backlight 0..937 via intel_backlight; brightness keys via ACPI Video Bus (#19), native intel_backlight kept by _OSI (#20). |
| HDMI | works | from TianoCore on; the one black boot in #4 was a misread (owner). |
| theming (bootsplash, edk2 colours) | works | splash from assets/bootsplash.png; console + setup colours from common/theme.nix (#22). |
| AC / battery | works | AC + BAT0 in power_supply, plug/unplug flips live. |
| charge limit 80 % | works | EC Peak Shift hold toggled by penrose `charge-hold.timer` (on ≥80, off ≤75); holds across AC replug, USB-C → AC, cold boot; `charge-mode full` until reboot. |
| fan | works | EC fan loop runs after cmd 0xbf; KDRT0 tracks pkg within 1–2 °C. RPM not visible to Linux (no Dell SMM 0xB2). Patched quiet set (EC region): 0 rpm idle, 3700 rpm / pkg 86–88 °C at 35 W sustained, cover on. Quiet mode set by coreboot at every boot (EC cmd 0xA6). |
| thermal zone `_TZ` | works | `acpitz` from EC CPU sensor (EC 0x33/0x34), 46 °C idle, 73→87 °C under 60 s stress-ng, critical 107 °C. No passive trip; EC drives the fan. |
| sleep | dropped | S0/S5 only by design (no `_S3`, `DISABLE_ACPI_HIBERNATE`). |
| ECC | deferred | 2×8 GB non-ECC DIMMs fitted; ie31200_edac loads, mode None. |
| dGPU M620 | works | PEG x16 8GT/s (= stock), 01:00.0 10de:13b4 enumerates, no AER (#23). VBIOS via ACPI `_ROM` from CBFS: nouveau reads bios 82.07.bb.00.11, no "Unable to load the VBIOS" (#24). Runtime D3cold via ACPI `_PR3`: suspends idle, wakes on access, nouveau binds from D3cold, no AER (#26). PRIME offload on nouveau: NV117, D3cold after. Proprietary 580.178.04 (closed, PRIME offload): `nvidia-offload glxinfo -B` = Quadro M620, plain = Intel P630; CUDA deviceQuery + vectorAdd PASS. No runtime D3 under nvidia (pre-Turing): idles in D0, P8. |
| Thunderbolt 3 | partial | #36: AR up at boot via early BOOT_ON, SL1; USB-C dock (USB/DP/LAN) hotplug works. TB PCIe tunnel untested (no TB device). BadDLLP under dock traffic at 8 GT/s (~4 per MB); RP5 capped at 5 GT/s since #38, 0 per 3 GiB. Idle +~0.5 W (AR has no runtime PM). |
| VT-d | works | `intel_iommu=on` (OS side): DMAR faults 0 with dock, M620 CUDA, i915, DisplayLink. `iommu_dma_protection` 0: the DMAR has no opt-in flag. |
| TPM 2.0 | works | NPCT650 via TIS MMIO 0xFED40000; ZFS unlock from PCR 15 unchanged. edk2 TPM off, no measured boot. |
| audio | works | #29: speakers (EC mailbox cmd 0x60 unmute), headphones, headset mic, internal DMIC (poor quality, the mic itself); Dell ALC3246 fixup by pin match from `hda_verb.c`. |
| Wi-Fi / Bluetooth | works | 8265 fitted, no firmware change (#26): RP2 trains, 02:00.0 8086:24fd iwlwifi fw 36 (iwlmvm), no AER; rfkill clear; `nmcli dev wifi list` sees 2.4 + 5 GHz; BT hci0 via USB2 port 5. |
| SD reader | works | RP3: 03:00.0 10ec:525a rtsx_pci; SDHC 32 GB at UHS-I SDR104, partitions seen, 200 MiB read 12.8 MB/s without I/O errors; remove/reinsert hotplug OK. |
| WWAN | not tested | no WWAN module fitted; RP17/18 off. |
| webcam | works | USB2 port 10, 0bda:5650 uvcvideo, `/dev/video0` streams (#30, no firmware change). |
| touch screen USB2 port 9 | dropped | port off (no touch panel), `error -71` gone. |
| daily drive ≥ 1 week | dropped | owner raises issues as they come. |
| `me_cleaner -S`, own SB keys | works | ME: deguarded + HAP, code modules removed offline (`me_cleaner -S --whitelist MFS`, `-i me` only): no HECI, BG off, TPM unlock, 30 min + 3 cold boots clean. #41 edk2 Secure Boot: PK/KEK/db = own `penrose.the-hive` keys only, no Microsoft (dbx only); `bootctl` enabled (user), setup mode off; an unsigned EFI from disk is refused; #42 UEFI Shell dropped from the payload (it ran from the FV past SB), setup behind an admin password (UserAuthenticationDxe); TPM unlock unchanged (PCR 15). |
| SPI write protection | works | #40 `BOOTMEDIA_SMM_BWP`: BIOS_CNTL 0xAA (EISS + BLE, BWE 0), BIOS interface lock-down; BootOrder change from Linux survives a reboot (SMMSTORE via SMM). No SPI flash console any more. |
| performance vs stock | works | bench-coreboot-20261030: 10 min all-core 3365 MHz / 75 °C / 35.24 W (stock 3385 / 76 / 35.24), sysbench +1.9 %, idle 1.74 W (stock 2.47, governor powersave vs performance). |
| 35 W sustained power limit | dropped | Board property, not a firmware setting: the EC sends `WrPkgConfig` index 0x1A = 35 W over PECI from a const table in its own flash (`flashregion_8_ec.bin`, apply at 0xE1010, tables at 0xF2168). No table row anywhere in the image exceeds 35 W, and PECI outranks the host's MSR 0x610, so no coreboot-side change raises it; lifting it needs an EC flash patch. |
