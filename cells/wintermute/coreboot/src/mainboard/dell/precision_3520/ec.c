/* SPDX-License-Identifier: GPL-2.0-only */

#include <arch/io.h>
#include <console/console.h>
#include "ec.h"

int ec_mailbox_cmd(u8 cmd, const u8 *args, size_t n)
{
	int timeout = 100000;

	for (size_t i = 0; i < n; i++) {
		outb(0x12 + i, MAILBOX_INDEX);
		outb(args[i], MAILBOX_DATA);
	}
	outb(0, MAILBOX_INDEX);
	outb(cmd, MAILBOX_DATA);
	do {
		outb(0, MAILBOX_INDEX);
	} while (inb(MAILBOX_DATA) && --timeout);
	if (!timeout) {
		printk(BIOS_ERR, "EC: mailbox cmd %#x timed out\n", cmd);
		return -1;
	}

	outb(0x11, MAILBOX_INDEX);
	return inb(MAILBOX_DATA);
}
