/* SPDX-License-Identifier: GPL-2.0-only */

#include <bootblock_common.h>
#include <ec/dell/mec5035/mec5035.h>
#include <gpio.h>

/*
 * HDD_EN gates +5V_HDD to the bay; the SSD needs it long before FSP-S probes SATA.
 * The dGPU must be powered and out of reset before FSP-M trains PEG.
 */
static const struct pad_config early_gpio_table[] = {
	PAD_CFG_GPO(GPP_C15, 1, RSMRST),
	PAD_CFG_GPO(GPP_D12, 1, PLTRST),	/* DGPU_PWR_EN */
	PAD_CFG_GPO(GPP_D10, 1, PLTRST),	/* DGPU_HOLD_RST# */
	PAD_CFG_GPI(GPP_D18, NONE, PLTRST),	/* DGPU_PWROK */
};

void bootblock_mainboard_early_init(void)
{
	mec5035_early_init();
	gpio_configure_pads(early_gpio_table, ARRAY_SIZE(early_gpio_table));
}
