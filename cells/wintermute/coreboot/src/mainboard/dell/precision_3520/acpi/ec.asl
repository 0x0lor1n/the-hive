/* SPDX-License-Identifier: GPL-2.0-only */

/* MEC5105 ACPI EC; offsets and event bits from the stock Dell DSDT. */
Device (ECDV)
{
	Name (_HID, EisaId ("PNP0C09"))
	Name (_UID, 0)
	/* eSPI SCI, GPE0_EN_127_96 bit 14 */
	Name (_GPE, 0x6E)
	Name (_CRS, ResourceTemplate ()
	{
		IO (Decode16, 0x930, 0x930, 1, 1)
		IO (Decode16, 0x934, 0x934, 1, 1)
	})

	Name (ECOK, 0)

	OperationRegion (ECOR, EmbeddedControl, 0, 0xFF)
	Field (ECOR, ByteAcc, Lock, Preserve)
	{
		ST00, 8,
		Offset (0x07),
		EV07, 16,
		Offset (0x0B),
		EV0B, 16,
	}

	Method (_REG, 2)
	{
		If (Arg0 == 3) {
			ECOK = Arg1
		}
	}

	/* Both event words are read on every query, as stock NEVT does. */
	Method (_Q66, 0, Serialized)
	{
		If (ECOK) {
			Local0 = EV07 | (EV0B << 16)
			If (Local0 & 0x04) {
				Notify (\_SB.LID0, 0x80)
			}
		}
	}
}

/* Raised by the eSPI SMI handler; the EC's only event so far is the lid. */
Scope (\_GPE)
{
	OperationRegion (SWGC, SystemIO, ACPI_BASE_ADDRESS + 0x42, 1)
	Field (SWGC, ByteAcc, NoLock, Preserve)
	{
		, 1,
		SWGP, 1,
	}

	Method (_L62, 0)
	{
		SWGP = 0
		Notify (\_SB.LID0, 0x80)
	}
}

Scope (\_SB)
{
	Device (LID0)
	{
		Name (_HID, EisaId ("PNP0C0D"))
		Method (_LID, 0)
		{
			If (\_SB.PCI0.LPCB.ECDV.ECOK) {
				Return ((\_SB.PCI0.LPCB.ECDV.ST00 >> 4) & 1)
			}
			Return (1)
		}
	}
}
