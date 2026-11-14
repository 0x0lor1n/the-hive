/* SPDX-License-Identifier: GPL-2.0-only */

#include <arch/cpu.h>
#include <console/console.h>
#include <device/device.h>
#include <intelblocks/cpulib.h>
#include <pc80/keyboard.h>
#include <soc/gpio.h>
#include <soc/ramstage.h>
#include "ec.h"
#include "gpio.h"

#define CMD_CPU_ID	0xbf
#define CMD_HW_MUTE	0x60
#define CMD_THERMAL_MODE	0xa6
#define THERMAL_MODE_SET	1
#define THERMAL_MODE_QUIET	(1 << 2)

/*
 * The EC polls PECI and runs the fan only after the BIOS names the CPU: one byte,
 * CPU class | TDP code, as the stock DXE next to AmiCpuSetupFeatures sends it.
 * Without it every EC sensor reads 0xff and the fan never spins.
 */
static void ec_send_cpu_id(void)
{
	const u32 model = cpu_get_cpuid() & 0x0fff0ff0;
	const u32 tdp = (cpu_get_power_max() + 500) / 1000;
	u8 arg;

	switch (model) {
	case 0x506e0: arg = 0x0b; break;	/* Skylake-H */
	case 0x906e0: arg = 0x0d; break;	/* Kaby Lake-H */
	default:
		printk(BIOS_ERR, "EC: unknown CPU %#x, fan stays off\n", model);
		return;
	}

	switch (tdp) {
	case 15: arg |= 0x40; break;
	case 35: arg |= 0x50; break;
	case 37: arg |= 0x10; break;
	case 45: arg |= 0x60; break;
	case 47: arg |= 0x20; break;
	case 57: arg |= 0x30; break;
	}

	printk(BIOS_INFO, "EC: CPU id %#x (TDP %u W)\n", arg, tdp);
	ec_mailbox_cmd(CMD_CPU_ID, &arg, 1);
}

void mainboard_silicon_init_params(FSP_SIL_UPD *params)
{
	gpio_configure_pads(gpio_table, ARRAY_SIZE(gpio_table));
	/* RP5 -> Alpine Ridge: BadDLLP at AR under load at 8 GT/s, none at 5 GT/s. */
	params->PcieRpPcieSpeed[4] = 2;		/* Gen2 */
}

static void mainboard_enable(struct device *dev)
{
	const u8 quiet[] = {THERMAL_MODE_SET, THERMAL_MODE_QUIET};
	const u8 unmute = 1;

	pc_keyboard_init(NO_AUX_DEVICE);
	/* EC sends Set 1 codes regardless; without XLATE atkbd decodes them as Set 2. */
	pc_keyboard_set_command_byte_bit(PC_KBC_TRANSLATE, 1);
	ec_send_cpu_id();
	/* The EC keeps its thermal mode in VBAT and falls back to balanced when the cell is out. */
	ec_mailbox_cmd(CMD_THERMAL_MODE, quiet, sizeof(quiet));
	/* The EC keeps the speakers muted until the BIOS sends unmute. */
	ec_mailbox_cmd(CMD_HW_MUTE, &unmute, 1);
}

struct chip_operations mainboard_ops = {
	.enable_dev = mainboard_enable,
};
