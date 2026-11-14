/* SPDX-License-Identifier: GPL-2.0-only */

#ifndef MAINBOARD_DELL_PRECISION_3520_EC_H
#define MAINBOARD_DELL_PRECISION_3520_EC_H

#include <types.h>

#define MAILBOX_INDEX	0x910
#define MAILBOX_DATA	0x911

/*
 * Returns index 0x11 once the EC clears index 0, -1 on timeout. Index 0x11 is each command's
 * own reply (0x1c status, 0x04 first event byte, 0xa6 get mode mask), not a common status.
 */
int ec_mailbox_cmd(u8 cmd, const u8 *args, size_t n);

/*
 * Charge hold for the OS: request byte to APM_STS, APM_CNT_EC_HOLD to APM_CNT, result read from
 * APM_STS. A request that reads back unchanged means firmware without the service.
 */
#define APM_CNT_EC_HOLD		0x5a
#define EC_HOLD_GET		0xc0	/* result EC_HOLD_RESULT_OFF / _ON */
#define EC_HOLD_ON		0xc1
#define EC_HOLD_OFF		0xc2
#define EC_HOLD_DAY		0xc8	/* +0..6: Peak Shift slot Sunday..Saturday = no charging all day */
#define EC_HOLD_DAYS		7
#define EC_HOLD_RESULT_OFF	0x00
#define EC_HOLD_RESULT_ON	0x01	/* also "done" for the set requests */
#define EC_HOLD_RESULT_TIMEOUT	0xe0
#define EC_HOLD_RESULT_ERROR	0xe1	/* EC status != 0 */

#endif
