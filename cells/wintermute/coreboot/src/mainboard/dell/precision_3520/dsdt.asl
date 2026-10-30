/* SPDX-License-Identifier: GPL-2.0-only */

#include <acpi/acpi.h>
DefinitionBlock(
	"dsdt.aml",
	"DSDT",
	ACPI_DSDT_REV_2,
	OEM_ID,
	ACPI_TABLE_CREATOR,
	COREBOOT_OEM_REVISION
)
{
	#include <acpi/dsdt_top.asl>
	#include <soc/intel/common/block/acpi/acpi/globalnvs.asl>
	#include <cpu/intel/common/acpi/cpu.asl>

	Scope (\_SB)
	{
		/*
		 * As stock: query _OSI so Linux treats the firmware as Win8+ and keeps the native
		 * intel_backlight instead of acpi_video0 (GFX0.LCD0 exists only for the hotkey Notify).
		 */
		Method (_INI, 0, Serialized)
		{
			OSYS = 2000
			If (CondRefOf (\_OSI)) {
				If (_OSI ("Windows 2009")) {
					OSYS = 2009
				}
				If (_OSI ("Windows 2012")) {
					OSYS = 2012
				}
				If (_OSI ("Windows 2013")) {
					OSYS = 2013
				}
				If (_OSI ("Windows 2015")) {
					OSYS = 2015
				}
			}
		}

		Device (PCI0)
		{
			#include <soc/intel/skylake/acpi/systemagent.asl>
			#include <soc/intel/skylake/acpi/pch.asl>
			#include <drivers/intel/gma/acpi/default_brightness_levels.asl>
		}
	}

	#include <southbridge/intel/common/acpi/sleepstates.asl>
}
