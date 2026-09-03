// somebar config: upstream src/config.def.hpp, colours from cells/theme
// (@theme_*@ filled in ../../packages.nix) and the same monospace font as
// foot/fuzzel.
#pragma once
#include "common.hpp"

constexpr bool topbar = true;

constexpr int paddingX = 10;
constexpr int paddingY = 3;

// Pango font description, not fontconfig syntax like foot's.
constexpr const char* font = "monospace 10";

// {foreground, background}
constexpr ColorScheme colorInactive = {Color(@theme_fg@), Color(@theme_bg@)};    // fg on bg
constexpr ColorScheme colorActive   = {Color(@theme_bg@), Color(@theme_focus@)}; // bg on focus
constexpr const char* termcmd[] = {"foot", nullptr};

static std::vector<std::string> tagNames = {
	"1", "2", "3",
	"4", "5", "6",
	"7", "8", "9",
};

constexpr Button buttons[] = {
	{ ClkStatusText,   BTN_RIGHT,  spawn,      {.v = termcmd} },
};
