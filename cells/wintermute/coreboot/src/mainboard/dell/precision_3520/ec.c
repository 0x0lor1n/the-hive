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

u8 ec_mailbox_read(u8 index)
{
	outb(index, MAILBOX_INDEX);
	return inb(MAILBOX_DATA);
}

int ec_property(u8 op, u16 pid, const u8 *data, u8 len)
{
	u8 args[6 + PROPERTY_MAX_LEN] = {op, pid & 0xff, pid >> 8, 0, 0, len};

	if (len > PROPERTY_MAX_LEN)
		return -1;
	for (u8 i = 0; i < len; i++)
		args[6 + i] = data[i];
	return ec_mailbox_cmd(CMD_PROPERTY, args, 6 + len);
}
