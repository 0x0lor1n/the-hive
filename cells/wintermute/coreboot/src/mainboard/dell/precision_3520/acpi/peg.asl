/* SPDX-License-Identifier: GPL-2.0-only */

/*
 * PEG root port and the M620 behind it, under the names soc_acpi_name() gives them,
 * so pci_rom_ssdt() can put the dGPU's _ROM into \_SB.PCI0.PEGP.DEV0.
 */
Device (PEGP)
{
	Name (_ADR, 0x00010000)

	Device (DEV0)
	{
		Name (_ADR, 0x00000000)
	}
}
