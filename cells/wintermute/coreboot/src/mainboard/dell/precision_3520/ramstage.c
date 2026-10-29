/* SPDX-License-Identifier: GPL-2.0-only */

#include <device/device.h>
#include <pc80/keyboard.h>
#include <soc/gpio.h>
#include <soc/ramstage.h>
#include "gpio.h"

void mainboard_silicon_init_params(FSP_SIL_UPD *params)
{
	gpio_configure_pads(gpio_table, ARRAY_SIZE(gpio_table));
}

static void mainboard_enable(struct device *dev)
{
	pc_keyboard_init(NO_AUX_DEVICE);
	/* EC sends Set 1 codes regardless; without XLATE atkbd decodes them as Set 2. */
	pc_keyboard_set_command_byte_bit(PC_KBC_TRANSLATE, 1);
}

struct chip_operations mainboard_ops = {
	.enable_dev = mainboard_enable,
};
