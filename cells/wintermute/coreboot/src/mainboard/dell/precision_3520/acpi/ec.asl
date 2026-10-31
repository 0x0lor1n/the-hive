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

	/*
	 * Writing 0 here makes the EC let go of the touchpad's I2C bus so the PCH can master it
	 * (stock TPD1._STA, ECTP(0)). Reads back the battery block, not what was written.
	 */
	Field (ECOR, ByteAcc, Lock, Preserve)
	{
		Offset (0x20),
		TPRL, 8,
	}

	Method (_REG, 2)
	{
		If (Arg0 == 3) {
			ECOK = Arg1
			If (ECOK) {
				PWSV = PWST & 0x03
				TPRL = 0
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

	/* Event block left in the mailbox by the SMI handler's CMD_GET_EVENT. */
	OperationRegion (MBOX, SystemIO, 0x910, 2)
	Field (MBOX, ByteAcc, NoLock, Preserve)
	{
		MBIX, 8,
		MBDT, 8,
	}
	IndexField (MBIX, MBDT, ByteAcc, NoLock, Preserve)
	{
		Offset (0x11),
		EVB0, 8,	/* bit 1 = hotkey */
		, 8,
		EVB2, 8,	/* hotkey Set 1 code */
	}

	/*
	 * Fn+F12 / Fn+F11 arrive as hotkey events with the F-key scan code. Notify only: with a native
	 * backlight driver the OS never calls _BCL, and gma INCB/DECB would then write the PWM behind it.
	 */
	Method (HKEY, 0, Serialized)
	{
		If (EVB0 & 0x02) {
			Local0 = EVB2
			If (Local0 == 0x58) {
				Notify (\_SB.PCI0.GFX0.LCD0, 0x86)
			} ElseIf (Local0 == 0x57) {
				Notify (\_SB.PCI0.GFX0.LCD0, 0x87)
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
		\_SB.PCI0.LPCB.ECDV.HKEY ()
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
