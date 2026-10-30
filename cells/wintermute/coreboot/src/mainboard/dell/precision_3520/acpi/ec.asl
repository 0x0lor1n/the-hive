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
	Name (PWSV, 0)

	OperationRegion (ECOR, EmbeddedControl, 0, 0xFF)
	Field (ECOR, ByteAcc, Lock, Preserve)
	{
		ST00, 8,
		Offset (0x03),
		BSEL, 8,	/* battery block select, 1 = BAT0 */
		Offset (0x06),
		PWST, 8,	/* bit 0 AC, bit 1 BAT0 present */
		EV07, 16,
		Offset (0x0B),
		EV0B, 16,
		Offset (0x10),
		BSTA, 8,
		Offset (0x12),
		BRAT, 16,
		BVOL, 16,
		BREM, 16,
		Offset (0x1E),
		BFCC, 16,
		BDCP, 16,
		BDVO, 16,
		Offset (0x26),
		BSER, 16,
		BOEM, 8,
		Offset (0x33),
		TSEL, 8,	/* sensor select: 0 CPU, 1 skin, 2 mem, 3 NGFF, 4 GPU */
		TVAL, 8,	/* °C, >= 0x80 invalid */
	}

	Method (_REG, 2)
	{
		If (Arg0 == 3) {
			ECOK = Arg1
			If (ECOK) {
				PWSV = PWST & 0x03
			}
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

	/* The fetched block has no clean event mask, so diff PWST as stock PWCH does. */
	Method (PWCH, 0, Serialized)
	{
		If (ECOK) {
			Local0 = PWST & 0x03
			Local1 = Local0 ^ PWSV
			PWSV = Local0
			If (Local1 & 0x01) {
				Notify (\_SB.AC, 0x80)
			}
			If (Local1 & 0x02) {
				Notify (\_SB.BAT0, 0x81)
			}
			Notify (\_SB.BAT0, 0x80)
		}
	}
}

/* Raised by the eSPI SMI handler for every EC event. */
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
		\_SB.PCI0.LPCB.ECDV.PWCH ()
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

	Device (AC)
	{
		Name (_HID, "ACPI0003")
		Name (_PCL, Package () { \_SB })
		Method (_PSR, 0)
		{
			If (\_SB.PCI0.LPCB.ECDV.ECOK) {
				Return (\_SB.PCI0.LPCB.ECDV.PWST & 0x01)
			}
			Return (1)
		}
	}

	/* Primary battery only; EC 0x03 = 2 does not select a second one. */
	Device (BAT0)
	{
		Name (_HID, EisaId ("PNP0C0A"))
		Name (_UID, 1)
		Name (_PCL, Package () { \_SB })
		Mutex (BMTX, 0)

		Method (_STA, 0)
		{
			If (\_SB.PCI0.LPCB.ECDV.ECOK) {
				If (\_SB.PCI0.LPCB.ECDV.PWST & 0x02) {
					Return (0x1F)
				}
			}
			Return (0x0F)
		}

		Method (_BIF, 0, Serialized)
		{
			Name (BIFP, Package () {
				1,		/* mA, mAh */
				0xFFFFFFFF,	/* design capacity */
				0xFFFFFFFF,	/* last full */
				1,		/* rechargeable */
				0xFFFFFFFF,	/* design voltage */
				0, 0, 0, 0,
				"DELL",
				"",
				"LION",
				"Unknown",
			})
			If (!\_SB.PCI0.LPCB.ECDV.ECOK) {
				Return (BIFP)
			}
			Acquire (BMTX, 0xFFFF)
			\_SB.PCI0.LPCB.ECDV.BSEL = 1
			Local0 = \_SB.PCI0.LPCB.ECDV.BDCP
			BIFP[1] = Local0
			BIFP[2] = \_SB.PCI0.LPCB.ECDV.BFCC
			BIFP[4] = \_SB.PCI0.LPCB.ECDV.BDVO
			BIFP[5] = Local0 / 10
			BIFP[6] = Local0 / 33
			BIFP[7] = Local0 / 100
			BIFP[8] = Local0 / 100
			BIFP[10] = ToDecimalString (\_SB.PCI0.LPCB.ECDV.BSER)
			Local1 = \_SB.PCI0.LPCB.ECDV.BOEM
			Release (BMTX)
			If (Local1 == 0x02) {
				BIFP[12] = "Sony"
			} ElseIf (Local1 == 0x03) {
				BIFP[12] = "Sanyo"
			} ElseIf (Local1 == 0x04) {
				BIFP[12] = "Panasonic"
			} ElseIf (Local1 == 0x06) {
				BIFP[12] = "Samsung SDI"
			} ElseIf (Local1 == 0x07) {
				BIFP[12] = "SMP"
			}
			Return (BIFP)
		}

		/* Rate sign rules from stock ECG6: discharge comes as a negative word. */
		Method (_BST, 0, Serialized)
		{
			Name (BSTP, Package () { 0, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF })
			If (!\_SB.PCI0.LPCB.ECDV.ECOK) {
				Return (BSTP)
			}
			Acquire (BMTX, 0xFFFF)
			\_SB.PCI0.LPCB.ECDV.BSEL = 1
			BSTP[0] = \_SB.PCI0.LPCB.ECDV.BSTA
			Local0 = \_SB.PCI0.LPCB.ECDV.BRAT
			If (Local0 == 0) {
				Local0 = 1
			} ElseIf (\_SB.PCI0.LPCB.ECDV.PWST & 0x01) {
				If (Local0 & 0x8000) {
					Local0 = 0xFFFFFFFF
				}
			} ElseIf (Local0 & 0x8000) {
				Local0 = (0 - Local0) & 0xFFFF
			} Else {
				Local0 = 0xFFFFFFFF
			}
			BSTP[1] = Local0
			BSTP[2] = \_SB.PCI0.LPCB.ECDV.BREM
			BSTP[3] = \_SB.PCI0.LPCB.ECDV.BVOL
			Release (BMTX)
			Return (BSTP)
		}
	}
}

/* The EC raises no temperature events, so the zone is polled. */
Scope (\_TZ)
{
	ThermalZone (THRM)
	{
		Name (_TZP, 50)

		/* 107 °C, stock THM */
		Name (_CRT, 3802)

		/* 27 °C while the EC is not up or its reading is invalid. */
		Method (_TMP, 0, Serialized)
		{
			If (!\_SB.PCI0.LPCB.ECDV.ECOK) {
				Return (3000)
			}
			Local1 = 2
			While (Local1) {
				\_SB.PCI0.LPCB.ECDV.TSEL = 0
				Local0 = \_SB.PCI0.LPCB.ECDV.TVAL
				If (Local0 < 0x80) {
					Return (2732 + Local0 * 10)
				}
				Local1--
			}
			Return (3000)
		}
	}
}
