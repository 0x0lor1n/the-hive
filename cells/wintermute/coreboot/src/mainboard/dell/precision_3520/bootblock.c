/* SPDX-License-Identifier: GPL-2.0-only */

#include <bootblock_common.h>
#include <ec/dell/mec5035/mec5035.h>
#include <gpio.h>

/* HDD_EN gates +5V_HDD to the bay; the SSD needs it long before FSP-S probes SATA. */
static const struct pad_config early_gpio_table[] = {
	PAD_CFG_GPO(GPP_C15, 1, RSMRST),
};

void bootblock_mainboard_early_init(void)
{
	mec5035_early_init();
	gpio_configure_pads(early_gpio_table, ARRAY_SIZE(early_gpio_table));
}
