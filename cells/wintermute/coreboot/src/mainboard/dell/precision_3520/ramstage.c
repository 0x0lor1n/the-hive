/* SPDX-License-Identifier: GPL-2.0-only */

#include <arch/cpu.h>
#include <arch/io.h>
#include <console/console.h>
#include <device/device.h>
#include <intelblocks/cpulib.h>
#include <pc80/keyboard.h>
#include <soc/gpio.h>
#include <soc/ramstage.h>
#include "gpio.h"

#define MAILBOX_INDEX	0x910
#define MAILBOX_DATA	0x911
#define CMD_CPU_ID	0xbf

/*
 * The EC polls PECI and runs the fan only after the BIOS names the CPU: one byte,
 * CPU class | TDP code, as the stock DXE next to AmiCpuSetupFeatures sends it.
 * Without it every EC sensor reads 0xff and the fan never spins.
 */
static void ec_send_cpu_id(void)
{
	const u32 model = cpu_get_cpuid() & 0x0fff0ff0;
	const u32 tdp = (cpu_get_power_max() + 500) / 1000;
	int timeout = 100000;
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
	outb(0x12, MAILBOX_INDEX);
	outb(arg, MAILBOX_DATA);
	outb(0, MAILBOX_INDEX);
	outb(CMD_CPU_ID, MAILBOX_DATA);
	do {
		outb(0, MAILBOX_INDEX);
	} while (inb(MAILBOX_DATA) && --timeout);
}

void mainboard_silicon_init_params(FSP_SIL_UPD *params)
{
	gpio_configure_pads(gpio_table, ARRAY_SIZE(gpio_table));
}

static void mainboard_enable(struct device *dev)
{
	pc_keyboard_init(NO_AUX_DEVICE);
	/* EC sends Set 1 codes regardless; without XLATE atkbd decodes them as Set 2. */
	pc_keyboard_set_command_byte_bit(PC_KBC_TRANSLATE, 1);
	ec_send_cpu_id();
}

struct chip_operations mainboard_ops = {
	.enable_dev = mainboard_enable,
};
