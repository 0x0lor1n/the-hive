/* SPDX-License-Identifier: GPL-2.0-only */

#include <gpio.h>

/*
 * PEG root port and the M620 behind it, under the names soc_acpi_name() gives them,
 * so pci_rom_ssdt() can put the dGPU's _ROM into \_SB.PCI0.PEGP.DEV0.
 */
Device (PEGP)
{
	Name (_ADR, 0x00010000)

	/* 8086:1901 config space; offsets from the stock PegSsdt (OPG0) */
	OperationRegion (RPCS, SystemMemory, CONFIG_ECAM_MMCONF_BASE_ADDRESS + 0x8000, 0x1000)
	Field (RPCS, AnyAcc, NoLock, Preserve)
	{
		Offset (0x04),
		CMDR, 8,
		Offset (0x19),
		SBUS, 8,	/* secondary bus */
		Offset (0x84),
		D0ST, 2,	/* PMCSR power state */
		Offset (0xAA),
		CEDR, 1,	/* correctable error detected, RW1C */
		Offset (0xB0),
		, 4,
		LNKD, 1,	/* link disable */
		Offset (0xC9),
		, 2,
		LREN, 1,	/* LTR enable */
		Offset (0x11A),
		, 1,
		VCNP, 1,	/* VC0 negotiation pending */
		Offset (0x504),
		, 32,
		TREN, 1,
		Offset (0xC20),
		, 4,
		AFEP, 2,
		Offset (0xC38),
		, 3,
		RMOD, 1,
		Offset (0xC74),
		LTSM, 4,	/* LTSSM state, 8 = disabled */
	}

	Name (LTRS, 0)
	Name (GSID, 0)	/* dGPU subsystem ID, lost with its power */
	Name (GHDA, 0)	/* dGPU HDA function enable */

	/*
	 * Snapshot while coreboot has the GPU up: by the time _OFF runs, Linux has the
	 * port in D3hot and the GPU reads all-ones.
	 */
	Method (_INI, 0, NotSerialized)
	{
		Local0 = GCFG (0x2C)
		If (Local0 != 0xFFFFFFFF) {
			GSID = Local0
			GHDA = (GCFG (0x488) >> 25) & 1
		}
	}

	/* dGPU config dword at Arg0; reachable only while it is powered and linked */
	Method (GCFG, 1, Serialized)
	{
		OperationRegion (GPCS, SystemMemory,
			CONFIG_ECAM_MMCONF_BASE_ADDRESS + (SBUS << 20) + Arg0, 4)
		Field (GPCS, DWordAcc, NoLock, Preserve) { GDAT, 32 }
		Return (GDAT)
	}

	Method (SCFG, 2, Serialized)
	{
		OperationRegion (GPCS, SystemMemory,
			CONFIG_ECAM_MMCONF_BASE_ADDRESS + (SBUS << 20) + Arg0, 4)
		Field (GPCS, DWordAcc, NoLock, Preserve) { GDAT, 32 }
		GDAT = Arg1
	}

	/*
	 * Stock PGON/PGOF, pre-Windows 8 branch: link disable via 0xB0 instead of the
	 * L2/3 request at 0x248, which hangs nouveau behind a 0x1901 (nouveau_drm.c
	 * quirk_broken_nv_runpm). No GC6: the GPU goes fully off.
	 */
	PowerResource (PGPR, 0, 0)
	{
		Method (_STA, 0, NotSerialized)
		{
			Return (GTXS (GPP_D12))
		}

		Method (_ON, 0, Serialized)
		{
			If (!GTXS (GPP_D12)) {
				/* ungate SRC7 */
				PCRA (0xDC, 0x100C, ~0x100)
				Sleep (16)

				CTXS (GPP_D10)	/* DGPU_HOLD_RST# */
				STXS (GPP_D12)	/* DGPU_PWR_EN */
				Local0 = 0
				While (!GRXS (GPP_D18) && (Local0 < 300)) {	/* DGPU_PWROK */
					Sleep (16)
					Local0 += 16
				}
				STXS (GPP_D10)
				Sleep (100)

				AFEP = 0
				RMOD = 0
				LNKD = 0
				TREN = 1
				Local0 = 0
				While (VCNP && (Local0 < 300)) {
					Sleep (16)
					Local0 += 16
				}

				LREN = LTRS
				CEDR = 1

				/* the port forwards config cycles to the GPU only from D0 */
				CMDR |= 0x07
				D0ST = 0

				/* NVIDIA takes its subsystem ID through 0x40 */
				If (GSID) {
					SCFG (0x40, GSID)
				}
				Local1 = GCFG (0x488)
				If (Local1 != 0xFFFFFFFF) {
					If (GHDA) {
						Local1 |= 0x02000000
					} Else {
						Local1 &= ~0x02000000
					}
					SCFG (0x488, Local1)
				}
			}
		}

		Method (_OFF, 0, Serialized)
		{
			If (GTXS (GPP_D12)) {
				LTRS = LREN

				LNKD = 1
				Local0 = 0
				While ((LTSM != 8) && (Local0 < 300)) {
					Sleep (16)
					Local0 += 16
				}
				RMOD = 1
				AFEP = 3

				/* gate SRC7 */
				PCRO (0xDC, 0x100C, 0x100)
				Sleep (16)

				CTXS (GPP_D10)
				CTXS (GPP_D12)
			}
		}
	}

	Name (_PR0, Package () { PGPR })
	Name (_PR2, Package () { PGPR })
	Name (_PR3, Package () { PGPR })

	Method (_S0W, 0, NotSerialized)
	{
		Return (4)	/* D3cold */
	}

	Device (DEV0)
	{
		Name (_ADR, 0x00000000)

		/*
		 * Optimus _DSM, functions 0 and 0x1A only: nouveau enables runtime PM by
		 * default only when it finds this GUID; the power itself goes through _PR3.
		 */
		Method (_DSM, 4, Serialized)
		{
			If (Arg0 == ToUUID ("a486d8f8-0bda-471b-a72b-6042a6b5bee0")) {
				If (Arg1 != 0x0100) {
					Return (0x80000002)
				}
				If (Arg2 == 0) {
					Return (Buffer (4) { 0x01, 0x00, 0x00, 0x04 })
				}
				If (Arg2 == 0x1A) {
					/* Optimus on, dynamic power, HDA codec kept by the GPU */
					Name (CAPB, Buffer (4) { 0x41, 0x00, 0x00, 0x11 })
					CreateDWordField (CAPB, 0, CAPS)
					If (GTXS (GPP_D12)) {
						CAPS |= 0x18
					}
					Return (CAPB)
				}
				Return (0x80000002)
			}
			Return (Buffer (1) { 0 })
		}
	}
}
