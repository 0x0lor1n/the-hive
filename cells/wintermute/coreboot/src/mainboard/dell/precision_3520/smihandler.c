/* SPDX-License-Identifier: GPL-2.0-only */

#include <arch/io.h>
#include <cpu/x86/smm.h>
#include <intelblocks/smihandler.h>
#include <soc/iomap.h>
#include <soc/pm.h>
#include "ec.h"

#define CMD_GET_EVENT	0x04

/* Peak Shift, the one EC charge control the pack obeys (PIDs as Linux wilco-charger). */
#define PID_PEAK_SHIFT_ENABLE	0x4ea
#define PID_PEAK_SHIFT_SUNDAY	0x4ee
#define PEAK_SHIFT_SLOT_LEN	4	/* start, end, charge-start (hour << 2 | quarter), unknown */
#define PEAK_SHIFT_23_45	0x5f

/* The EC holds its eSPI SMI until CMD_GET_EVENT; the OS sees the event via SWGPE (_L62). */
void mainboard_smi_espi_handler(void)
{
	/* The SMI can land between the OS writing the index and using the data port. */
	const u8 index = inb(MAILBOX_INDEX);

	ec_mailbox_cmd(CMD_GET_EVENT, NULL, 0);
	outb(index, MAILBOX_INDEX);

	outb(inb(ACPI_BASE_ADDRESS + GPE_CNTL) | SWGPE_CTRL, ACPI_BASE_ADDRESS + GPE_CNTL);
}

static u8 ec_hold_service(u8 request)
{
	u8 data[PEAK_SHIFT_SLOT_LEN] = {0};
	int status;

	if (request == EC_HOLD_GET) {
		status = ec_property(PROPERTY_GET, PID_PEAK_SHIFT_ENABLE, data, 1);
		if (status == 0)
			return ec_mailbox_read(PROPERTY_DATA) == 1 ? EC_HOLD_RESULT_ON
								 : EC_HOLD_RESULT_OFF;
	} else if (request == EC_HOLD_ON || request == EC_HOLD_OFF) {
		data[0] = request == EC_HOLD_ON;
		status = ec_property(PROPERTY_SET, PID_PEAK_SHIFT_ENABLE, data, 1);
	} else if (request >= EC_HOLD_DAY && request < EC_HOLD_DAY + EC_HOLD_DAYS) {
		const u16 pid = PID_PEAK_SHIFT_SUNDAY + request - EC_HOLD_DAY;

		/* 00:00-00:00, charge from 23:45 = "on AC, not charging" all day; byte 3 kept as read. */
		status = ec_property(PROPERTY_GET, pid, data, PEAK_SHIFT_SLOT_LEN);
		if (status == 0) {
			data[2] = PEAK_SHIFT_23_45;
			data[3] = ec_mailbox_read(PROPERTY_DATA + 3);
			status = ec_property(PROPERTY_SET, pid, data, PEAK_SHIFT_SLOT_LEN);
		}
	} else {
		return request;
	}

	if (status < 0)
		return EC_HOLD_RESULT_TIMEOUT;
	if (status > 0)
		return EC_HOLD_RESULT_ERROR;
	return EC_HOLD_RESULT_ON;
}

int mainboard_smi_apmc(u8 data)
{
	if (data != APM_CNT_EC_HOLD)
		return 0;

	const u8 index = inb(MAILBOX_INDEX);

	outb(ec_hold_service(inb(APM_STS)), APM_STS);
	outb(index, MAILBOX_INDEX);
	return 1;
}
