/* SPDX-License-Identifier: GPL-2.0-only */

#include <device/azalia_device.h>

/* ALC3246 (ALC256): stock pin defaults and SSID; snd-hda picks the Dell fixup by pin match. */
static const u32 realtek_alc256_verbs[] = {
	AZALIA_RESET(1),
	AZALIA_SUBVENDOR(0, 0x102807a9),
	AZALIA_PIN_CFG(0, 0x12, 0x90a60140),	/* internal DMIC */
	AZALIA_PIN_CFG(0, 0x13, 0x40000000),
	AZALIA_PIN_CFG(0, 0x14, 0x90170110),	/* JSPK1 */
	AZALIA_PIN_CFG(0, 0x18, AZALIA_PIN_CFG_NC(0)),
	AZALIA_PIN_CFG(0, 0x19, AZALIA_PIN_CFG_NC(0)),
	AZALIA_PIN_CFG(0, 0x1a, AZALIA_PIN_CFG_NC(0)),
	AZALIA_PIN_CFG(0, 0x1b, AZALIA_PIN_CFG_NC(0)),
	AZALIA_PIN_CFG(0, 0x1d, 0x40700001),
	AZALIA_PIN_CFG(0, 0x1e, 0x421211f2),
	AZALIA_PIN_CFG(0, 0x21, 0x02211020),	/* JHP1 headset */
};

const u32 pc_beep_verbs[] = {};

struct azalia_codec mainboard_azalia_codecs[] = {
	{
		.name         = "Realtek ALC3246",
		.vendor_id    = 0x10ec0256,
		.subsystem_id = 0x102807a9,
		.address      = 0,
		.verbs        = realtek_alc256_verbs,
		.verb_count   = ARRAY_SIZE(realtek_alc256_verbs),
	},
};

AZALIA_ARRAY_SIZES;
