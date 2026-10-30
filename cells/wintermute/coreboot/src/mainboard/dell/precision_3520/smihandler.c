/* SPDX-License-Identifier: GPL-2.0-only */

#include <arch/io.h>
#include <intelblocks/smihandler.h>
#include <soc/iomap.h>
#include <soc/pm.h>

#define MAILBOX_INDEX	0x910
#define MAILBOX_DATA	0x911
#define CMD_GET_EVENT	0x04

/* The EC holds its eSPI SMI until CMD_GET_EVENT; the OS sees the event via SWGPE (_L62). */
void mainboard_smi_espi_handler(void)
{
	int timeout = 100000;

	outb(0, MAILBOX_INDEX);
	outb(CMD_GET_EVENT, MAILBOX_DATA);
	do {
		outb(0, MAILBOX_INDEX);
	} while (inb(MAILBOX_DATA) && --timeout);

	outb(inb(ACPI_BASE_ADDRESS + GPE_CNTL) | SWGPE_CTRL, ACPI_BASE_ADDRESS + GPE_CNTL);
}
