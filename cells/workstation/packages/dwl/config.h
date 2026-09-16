/* nix-rensa dwl config: copy of upstream config.def.h (dwl v0.8) with local
 * changes. On a dwl bump: diff against the new config.def.h and re-apply.
 * Changes vs upstream: MODKEY=Super, Super+Shift+Return terminal, fuzzel on
 * Mod+D/Mod+P, swaylock on Mod+L, waybar toggle on Mod+B, cliphist/grim
 * binds, XF86 media keys; displaced incnmaster-/setmfact+ moved to
 * Mod+Shift+D / Mod+Shift+L. Ported from wochap/nix-config dwl:
 * Super+Esc power menu, Super+C calc, Super+Alt+T terminal, Super+Alt+F
 * Thunar, Super+Alt+N notification mode, Super+R layout mode (modes patch,
 * packages/dwl/patches/modes-0.8.patch). */
/* Taken from https://github.com/djpohly/dwl/issues/466 */
#define COLOR(hex)    { ((hex >> 24) & 0xFF) / 255.0f, \
                        ((hex >> 16) & 0xFF) / 255.0f, \
                        ((hex >> 8) & 0xFF) / 255.0f, \
                        (hex & 0xFF) / 255.0f }
/* appearance */
static const int sloppyfocus               = 1;  /* focus follows mouse */
static const int bypass_surface_visibility = 0;  /* 1 means idle inhibitors will disable idle tracking even if it's surface isn't visible  */
static const unsigned int borderpx         = 2;  /* border pixel of windows */
/* @theme_*@ are filled from cells/theme at build time (packages.nix). */
static const float rootcolor[]             = COLOR(0x@theme_bg@ff);
static const float bordercolor[]           = COLOR(0x@theme_border@ff);
static const float focuscolor[]            = COLOR(0x@theme_focus@ff);
static const float urgentcolor[]           = COLOR(0x@theme_urgent@ff);
/* This conforms to the xdg-protocol. Set the alpha to zero to restore the old behavior */
static const float fullscreen_bg[]         = {0.0f, 0.0f, 0.0f, 1.0f}; /* You can also use glsl colors */

/* tagging - TAGCOUNT must be no greater than 31 */
#define TAGCOUNT (9)

/* modes patch: a prefix key enters a mode, the next key acts and (usually)
 * returns to NORMAL. dwl-status receives a "<output> mode <label>" status line
 * and ignores it. */
enum {
	LAYOUT,
	NOTIFICATION,
};
const char *modes_labels[] = {
	"layout",
	"notification",
};

/* logging */
static int log_level = WLR_ERROR;

static const Rule rules[] = {
	/* app_id             title       tags mask     isfloating   monitor */
	{ "Gimp_EXAMPLE",     NULL,       0,            1,           -1 }, /* Start on currently visible tags floating, not tiled */
	{ "firefox_EXAMPLE",  NULL,       1 << 8,       0,           -1 }, /* Start on ONLY tag "9" */
    /* default/example rule: can be changed but cannot be eliminated; at least one rule must exist */
};

/* layout(s) */
static const Layout layouts[] = {
	/* symbol     arrange function */
	{ "[]=",      tile },
	{ "><>",      NULL },    /* no layout function means floating behavior */
	{ "[M]",      monocle },
};

/* monitors */
/* (x=-1, y=-1) is reserved as an "autoconfigure" monitor position indicator
 * WARNING: negative values other than (-1, -1) cause problems with Xwayland clients due to
 * https://gitlab.freedesktop.org/xorg/xserver/-/issues/899 */
static const MonitorRule monrules[] = {
   /* name        mfact  nmaster scale layout       rotate/reflect                x    y
    * example of a HiDPI laptop monitor:
    { "eDP-1",    0.5f,  1,      2,    &layouts[0], WL_OUTPUT_TRANSFORM_NORMAL,   -1,  -1 }, */
	{ NULL,       0.5f,  1,      1,    &layouts[0], WL_OUTPUT_TRANSFORM_NORMAL,   -1,  -1 },
	/* default monitor rule: can be changed but cannot be eliminated; at least one monitor rule must exist */
};

/* keyboard: empty fields are filled by xkbcommon from XKB_DEFAULT_*, which
 * layer-session.nix puts in session.compositorEnvironment -- so the layout
 * toggle is a per-host knob and not baked into this binary. */
static const struct xkb_rule_names xkb_rules = {
	.options = NULL,
};

static const int repeat_rate = 50;
static const int repeat_delay = 300;

/* Trackpad */
static const int tap_to_click = 1;
static const int tap_and_drag = 1;
static const int drag_lock = 1;
static const int natural_scrolling = 0;
static const int disable_while_typing = 1;
static const int left_handed = 0;
static const int middle_button_emulation = 0;
/* You can choose between:
LIBINPUT_CONFIG_SCROLL_NO_SCROLL
LIBINPUT_CONFIG_SCROLL_2FG
LIBINPUT_CONFIG_SCROLL_EDGE
LIBINPUT_CONFIG_SCROLL_ON_BUTTON_DOWN
*/
static const enum libinput_config_scroll_method scroll_method = LIBINPUT_CONFIG_SCROLL_2FG;

/* You can choose between:
LIBINPUT_CONFIG_CLICK_METHOD_NONE
LIBINPUT_CONFIG_CLICK_METHOD_BUTTON_AREAS
LIBINPUT_CONFIG_CLICK_METHOD_CLICKFINGER
*/
static const enum libinput_config_click_method click_method = LIBINPUT_CONFIG_CLICK_METHOD_BUTTON_AREAS;

/* You can choose between:
LIBINPUT_CONFIG_SEND_EVENTS_ENABLED
LIBINPUT_CONFIG_SEND_EVENTS_DISABLED
LIBINPUT_CONFIG_SEND_EVENTS_DISABLED_ON_EXTERNAL_MOUSE
*/
static const uint32_t send_events_mode = LIBINPUT_CONFIG_SEND_EVENTS_ENABLED;

/* You can choose between:
LIBINPUT_CONFIG_ACCEL_PROFILE_FLAT
LIBINPUT_CONFIG_ACCEL_PROFILE_ADAPTIVE
*/
static const enum libinput_config_accel_profile accel_profile = LIBINPUT_CONFIG_ACCEL_PROFILE_ADAPTIVE;
static const double accel_speed = 0.0;

/* You can choose between:
LIBINPUT_CONFIG_TAP_MAP_LRM -- 1/2/3 finger tap maps to left/right/middle
LIBINPUT_CONFIG_TAP_MAP_LMR -- 1/2/3 finger tap maps to left/middle/right
*/
static const enum libinput_config_tap_button_map button_map = LIBINPUT_CONFIG_TAP_MAP_LRM;

/* If you want to use the windows key for MODKEY, use WLR_MODIFIER_LOGO */
#define MODKEY WLR_MODIFIER_LOGO

#define TAGKEYS(KEY,SKEY,TAG) \
	{ MODKEY,                    KEY,            view,            {.ui = 1 << TAG} }, \
	{ MODKEY|WLR_MODIFIER_CTRL,  KEY,            toggleview,      {.ui = 1 << TAG} }, \
	{ MODKEY|WLR_MODIFIER_SHIFT, SKEY,           tag,             {.ui = 1 << TAG} }, \
	{ MODKEY|WLR_MODIFIER_CTRL|WLR_MODIFIER_SHIFT,SKEY,toggletag, {.ui = 1 << TAG} }

/* helper for spawning shell commands in the pre dwm-5.0 fashion */
#define SHCMD(cmd) { .v = (const char*[]){ "/bin/sh", "-c", cmd, NULL } }

/* commands */
static const char *termcmd[] = { "foot", NULL };
static const char *menucmd[] = { "fuzzel", NULL };

static const Key keys[] = {
	/* Note that Shift changes certain key codes: 2 -> at, etc. */
	/* modifier                  key                  function          argument */
	{ MODKEY,                    XKB_KEY_p,           spawn,            {.v = menucmd} },
	/* Super+Shift+Return (upstream default). Was Ctrl+Shift+Return for the
	 * QEMU era; that chord is now tmux's split-window (dotfiles/tmux) and the
	 * compositor must not eat it. */
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_Return,      spawn,            {.v = termcmd} },
	{ MODKEY,                    XKB_KEY_d,           spawn,            {.v = menucmd} },
	{ MODKEY,                    XKB_KEY_v,           spawn,            SHCMD("cliphist list | fuzzel --dmenu | cliphist decode | wl-copy") },
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_s,           spawn,            SHCMD("slurp | grim -g - - | wl-copy") },
	{ 0,                         XKB_KEY_Print,       spawn,            SHCMD("grim - | wl-copy") },
	/* takeshot (home/desktop/screenshot.nix): full screen / frozen area, saved + notified */
	{ MODKEY,                    XKB_KEY_Print,       spawn,            SHCMD("takeshot --now") },
	{ MODKEY|WLR_MODIFIER_ALT,   XKB_KEY_s,           spawn,            SHCMD("takeshot --area") },
	/* recorder (home/desktop/recorder.nix): area screen recording, same key stops it */
	{ MODKEY|WLR_MODIFIER_ALT,   XKB_KEY_r,           spawn,            SHCMD("recorder --area") },
	{ MODKEY,                    XKB_KEY_l,           spawn,            SHCMD("swaylock -fF") },
	/* wochap ports (home/desktop/menus.nix): fuzzel-dmenu power menu and calc */
	{ MODKEY,                    XKB_KEY_Escape,      spawn,            SHCMD("powermenu") },
	{ MODKEY,                    XKB_KEY_c,           spawn,            SHCMD("calcmenu") },
	{ MODKEY|WLR_MODIFIER_ALT,   XKB_KEY_w,           spawn,            SHCMD("wifimenu") },
	/* wochap: Super+Alt+T second terminal bind, Super+Alt+F file manager */
	{ MODKEY|WLR_MODIFIER_ALT,   XKB_KEY_t,           spawn,            {.v = termcmd} },
	{ MODKEY|WLR_MODIFIER_ALT,   XKB_KEY_f,           spawn,            SHCMD("thunar") },
	/* modes (see modekeys[] below): Super+R layout, Super+Alt+N notifications */
	{ MODKEY,                    XKB_KEY_r,           entermode,        {.i = LAYOUT} },
	{ MODKEY|WLR_MODIFIER_ALT,   XKB_KEY_n,           entermode,        {.i = NOTIFICATION} },
	/* waybar (home/desktop/bar.nix) toggles on SIGUSR1 */
	{ MODKEY,                    XKB_KEY_b,           spawn,            SHCMD("pkill -USR1 waybar") },
	{ 0, XKB_KEY_XF86AudioRaiseVolume,  spawn, SHCMD("volumectl -u up") },
	{ 0, XKB_KEY_XF86AudioLowerVolume,  spawn, SHCMD("volumectl -u down") },
	{ 0, XKB_KEY_XF86AudioMute,         spawn, SHCMD("volumectl toggle-mute") },
	{ 0, XKB_KEY_XF86MonBrightnessUp,   spawn, SHCMD("lightctl up") },
	{ 0, XKB_KEY_XF86MonBrightnessDown, spawn, SHCMD("lightctl down") },
	{ MODKEY,                    XKB_KEY_j,           focusstack,       {.i = +1} },
	{ MODKEY,                    XKB_KEY_k,           focusstack,       {.i = -1} },
	/* movestack patch: swap the focused window up/down the stack */
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_j,           movestack,        {.i = +1} },
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_k,           movestack,        {.i = -1} },
	{ MODKEY,                    XKB_KEY_i,           incnmaster,       {.i = +1} },
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_d,           incnmaster,       {.i = -1} },
	{ MODKEY,                    XKB_KEY_h,           setmfact,         {.f = -0.05f} },
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_l,           setmfact,         {.f = +0.05f} },
	{ MODKEY,                    XKB_KEY_Return,      zoom,             {0} },
	{ MODKEY,                    XKB_KEY_Tab,         view,             {0} },
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_c,           killclient,       {0} },
	{ MODKEY,                    XKB_KEY_t,           setlayout,        {.v = &layouts[0]} },
	{ MODKEY,                    XKB_KEY_f,           setlayout,        {.v = &layouts[1]} },
	{ MODKEY,                    XKB_KEY_m,           setlayout,        {.v = &layouts[2]} },
	{ MODKEY,                    XKB_KEY_space,       setlayout,        {0} },
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_space,       togglefloating,   {0} },
	{ MODKEY,                    XKB_KEY_e,           togglefullscreen, {0} },
	{ MODKEY,                    XKB_KEY_0,           view,             {.ui = ~0} },
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_parenright,  tag,              {.ui = ~0} },
	{ MODKEY,                    XKB_KEY_comma,       focusmon,         {.i = WLR_DIRECTION_LEFT} },
	{ MODKEY,                    XKB_KEY_period,      focusmon,         {.i = WLR_DIRECTION_RIGHT} },
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_less,        tagmon,           {.i = WLR_DIRECTION_LEFT} },
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_greater,     tagmon,           {.i = WLR_DIRECTION_RIGHT} },
	TAGKEYS(          XKB_KEY_1, XKB_KEY_exclam,                        0),
	TAGKEYS(          XKB_KEY_2, XKB_KEY_at,                            1),
	TAGKEYS(          XKB_KEY_3, XKB_KEY_numbersign,                    2),
	TAGKEYS(          XKB_KEY_4, XKB_KEY_dollar,                        3),
	TAGKEYS(          XKB_KEY_5, XKB_KEY_percent,                       4),
	TAGKEYS(          XKB_KEY_6, XKB_KEY_asciicircum,                   5),
	TAGKEYS(          XKB_KEY_7, XKB_KEY_ampersand,                     6),
	TAGKEYS(          XKB_KEY_8, XKB_KEY_asterisk,                      7),
	TAGKEYS(          XKB_KEY_9, XKB_KEY_parenleft,                     8),
	{ MODKEY|WLR_MODIFIER_SHIFT, XKB_KEY_q,           quit,             {0} },

	/* Ctrl-Alt-Backspace and Ctrl-Alt-Fx used to be handled by X server */
	{ WLR_MODIFIER_CTRL|WLR_MODIFIER_ALT,XKB_KEY_Terminate_Server, quit, {0} },
	/* Ctrl-Alt-Fx is used to switch to another VT, if you don't know what a VT is
	 * do not remove them.
	 */
#define CHVT(n) { WLR_MODIFIER_CTRL|WLR_MODIFIER_ALT,XKB_KEY_XF86Switch_VT_##n, chvt, {.ui = (n)} }
	CHVT(1), CHVT(2), CHVT(3), CHVT(4), CHVT(5), CHVT(6),
	CHVT(7), CHVT(8), CHVT(9), CHVT(10), CHVT(11), CHVT(12),
};

/* Mode bindings. ONESHOT: run the action and drop back to NORMAL (two
 * entries, both match the same chord). Plain entries stay in the mode so
 * ratios can be nudged repeatedly; Escape leaves. Vanilla dwl has no
 * movecenter/setcfact/sizes, so wochap's c/1/2/3 and cfact keys are absent. */
#define ONESHOT(mode, mod, key, func, arg) \
	{ mode, { mod, key, func, arg } }, \
	{ mode, { mod, key, entermode, {.i = NORMAL} } }

static const Modekey modekeys[] = {
	/* mode          modifier                                 key            function        argument */
	/* Super+R: layout. Left/Right master count, Shift+Left/Right master ratio,
	 * t/f/m tile/float/monocle, Shift+F togglefloating the focused window. */
	{ LAYOUT,      { 0,                                       XKB_KEY_Left,   incnmaster,     {.i = +1} } },
	{ LAYOUT,      { 0,                                       XKB_KEY_Right,  incnmaster,     {.i = -1} } },
	{ LAYOUT,      { WLR_MODIFIER_SHIFT,                      XKB_KEY_Left,   setmfact,       {.f = -0.05f} } },
	{ LAYOUT,      { WLR_MODIFIER_SHIFT,                      XKB_KEY_Right,  setmfact,       {.f = +0.05f} } },
	ONESHOT(LAYOUT,  0,                                       XKB_KEY_t,      setlayout,      {.v = &layouts[0]}),
	ONESHOT(LAYOUT,  0,                                       XKB_KEY_f,      setlayout,      {.v = &layouts[1]}),
	ONESHOT(LAYOUT,  0,                                       XKB_KEY_m,      setlayout,      {.v = &layouts[2]}),
	ONESHOT(LAYOUT,  WLR_MODIFIER_SHIFT,                      XKB_KEY_f,      togglefloating, {0}),
	{ LAYOUT,      { 0,                                       XKB_KEY_Escape, entermode,      {.i = NORMAL} } },

	/* Super+Alt+N: notifications (mako; wochap has dunst). h restores the
	 * last dismissed one, a runs its default action, c/Shift+C dismiss one/all. */
	ONESHOT(NOTIFICATION, 0,                                  XKB_KEY_h,      spawn,          SHCMD("makoctl restore")),
	ONESHOT(NOTIFICATION, 0,                                  XKB_KEY_a,      spawn,          SHCMD("makoctl invoke")),
	ONESHOT(NOTIFICATION, 0,                                  XKB_KEY_c,      spawn,          SHCMD("makoctl dismiss")),
	ONESHOT(NOTIFICATION, WLR_MODIFIER_SHIFT,                 XKB_KEY_c,      spawn,          SHCMD("makoctl dismiss --all")),
	{ NOTIFICATION, { 0,                                      XKB_KEY_Escape, entermode,      {.i = NORMAL} } },
};

static const Button buttons[] = {
	{ MODKEY, BTN_LEFT,   moveresize,     {.ui = CurMove} },
	{ MODKEY, BTN_MIDDLE, togglefloating, {0} },
	{ MODKEY, BTN_RIGHT,  moveresize,     {.ui = CurResize} },
};
