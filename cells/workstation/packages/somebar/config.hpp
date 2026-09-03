// somebar config: upstream src/config.def.hpp with the Kanagawa Wave palette
// (see home/desktop/kanagawa.nix) and the same monospace font as foot/fuzzel.
// Passed to the nixpkgs derivation via `conf` in ../../packages.nix.
#pragma once
#include "common.hpp"

constexpr bool topbar = true;

constexpr int paddingX = 10;
constexpr int paddingY = 3;

// Pango font description, not fontconfig syntax like foot's.
constexpr const char* font = "monospace 10";

// {foreground, background}
constexpr ColorScheme colorInactive = {Color(0xdc, 0xd7, 0xba), Color(0x1f, 0x1f, 0x28)}; // fujiWhite on sumiInk3
constexpr ColorScheme colorActive   = {Color(0x1f, 0x1f, 0x28), Color(0x7e, 0x9c, 0xd8)}; // sumiInk3 on crystalBlue
constexpr const char* termcmd[] = {"foot", nullptr};

static std::vector<std::string> tagNames = {
	"1", "2", "3",
	"4", "5", "6",
	"7", "8", "9",
};

constexpr Button buttons[] = {
	{ ClkStatusText,   BTN_RIGHT,  spawn,      {.v = termcmd} },
};
