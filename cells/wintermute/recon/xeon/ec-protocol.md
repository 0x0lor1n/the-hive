# EC protocol, LA-E152P (stock BIOS 1.16.0)

EC: SMSC/Microchip MEC5105 on eSPI (sch/spi-ec.md 18–22), no own flash.
Sources: `dsdt.dsl` (ECDV at 37111, helpers at 37738), `inteltool.txt` eSPI
block (line 150), coreboot `src/ec/dell/mec5035` at the cell's pinned rev.

## Host I/O decode

PCH eSPI generic I/O ranges as the stock BIOS leaves them (`inteltool.txt`):

| reg   | raw        | range         | use                         |
|-------|------------|---------------|-----------------------------|
| LGIR1 | 0x0094cc30 | disabled      |                             |
| LGIR2 | 0x001c07e1 | 0x7e0–0x7ff   | unknown, keep               |
| LGIR3 | 0x007c0901 | 0x900–0x97f   | EC: mailbox + ACPI EC       |
| LGIR4 | 0x000c0081 | 0x80–0x8f     | port 80 to the EC (likely)  |

LGIR3 is the same window `haswell_latitude` opens with
`gen4_dec = LPC_IO(0x900, 0x80)`. Port it as `gen3_dec`/`gen4_dec` in the
devicetree; without it the EC is unreachable from bootblock.

## Two interfaces in 0x900–0x97f

1. ACPI EC, `ECDV._CRS`: data 0x930, command/status 0x934. Standard
   ACPI EC protocol, 0xFF-byte `EmbeddedControl` region, `_GPE` 0x6E on
   eSPI. Only the OS uses it (after `_REG`).
2. Dell mailbox, index 0x910 / data 0x911: what `ec/dell/mec5035` drives
   (`MAILBOX_INDEX = 0x910`). Not referenced in the DSDT — the stock BIOS
   uses it from SMM/DXE. Its presence on MEC5105 is inferred from the
   decode window, not yet observed.

## BIOS → EC before the OS

Before `_REG` (`ECRD == 0`) every EC access in ASL goes through
`EISC` → `GENS(0x08, …)` → software SMI (`ASMI`, write 0xE0 to the SMI
command port). Read is EISC cmd 0x80, write is 0x81. coreboot has no
handler for these, so any ASL path that runs before `_REG` returns garbage
under coreboot. Ported DSDT must keep EC access behind `ECRD`, as stock does.

`ECIN` (run from `_REG`): lid = EC byte 0 bit 4, AC/battery via
`ECS2/ECS3`, then `GENS(0x1C)` and `GENS(0x2D)` — two more SMI services
coreboot will not have. Losing them costs features, not boot.

EC events: one query, `_Q66` → `NEVT`, which reads event words at EC 0x07
and 0x0B and dispatches. A second, `_QF1` in ECDV scope, comes from the DPTF table (ssdt7); thermal only.

## What decides "EC killed it" vs "romstage never ran"

On older Dell Latitudes the EC powers the board off ~15 s after power-on
with the "processor failure" LED pattern unless the BIOS sends
`CMD_CPU_OK` (0xC2) through the mailbox; coreboot does it in bootblock
(`mec5035_early_init`, haswell_latitude/bootblock.c). Assume the MEC5105
behaves the same until a boot shows otherwise.

First-boot triage:

- Off after ~15 s, LED pattern, no POST codes on 0x80 beyond bootblock →
  EC watchdog: CPU_OK not sent or 0x900 window not decoded.
- Off immediately or never on → not the EC handshake; power sequencing,
  descriptor/ME, or Boot Guard (Phase D).
- Port 80 decodes to the EC (LGIR4), not to a card slot: POST codes are
  only visible via cbmem/serial (JUART1), never on a port-80 card.

Port order: open the 0x900 window and send CPU_OK in bootblock, then add
the mec5035 chip for keyboard/touchpad/radio init. Mailbox register
layout for MEC5105 is to be confirmed against the stock image
(1.5 dump, search the DXE for writes to 0x910).
