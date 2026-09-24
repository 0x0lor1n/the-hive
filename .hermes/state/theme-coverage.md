# theme-coverage — every installed GUI/TUI on elster paints from cells/common/theme.nix (Kanagawa Wave), or is on a written exceptions list

Status: PLANNING (2026-09). Owner: user; Claude = executor.
Prereq: the-hive at 0251f2f or later (palette in `cells/common/theme.nix`, read as `inputs.cells.common.theme`). User runs every rebuild; Claude only edits + evals.

Target: each row of the Matrix below is `themed` (colours trace to `cells/common/theme.nix`), `inherits` (verified to pick up foot ANSI / GTK / Qt without its own config), or `exception` (with the reason). No row stays `?`. Stretch: desktop consumers read `theme.roles.*` only, never `theme.colors.*` (58 refs in 8 files today), so switching the palette is one file.
Source refs: `cells/common/theme.nix` (colors/roles/ansi/name); GTK `home/desktop/gtk.nix` and Qt `home/desktop/qt.nix` (the two inherited toolkits); `deck/homeModules/*.nix` (shell/TUI tools); `home/dev/agents.nix` (claude settings.json :144, opencode tui :126); `profiles/agent-proxy.nix` (hermes install); `packages.nix` (nixpak Slack/Telegram, grayjay, horizon-gm FHS); `profiles/auth-entra.nix` (o365 PWAs via Edge); `dotfiles/nvim/lua/custom/plugins/colorscheme/` (catppuccin: 191 `C.*` refs in hl_overrides.lua, 24 lines in ui/editor/bufferline, + init.lua, lazy.lua, lazy-lock.json). Upstream themes: `rebelot/kanagawa.nvim` `extras/tmTheme/kanagawa.tmTheme` (bat/delta) and `lua/kanagawa/themes.lua` wave `diff = { add = winterGreen, delete = winterRed, change = winterBlue, text = winterYellow }`; opencode `packages/ui/src/theme/themes/kanagawa.json`; hermes skins = `~/.hermes/skins/<name>.yaml` + `display.skin` (schema in hermes_cli/skin_engine.py); Claude Code 2.1.239 lists "custom themes" in `--safe-mode` help (location unverified).
Repo: HM release-25.05 (`cells/workstation/flake.nix:34`): 25.05 option names (`programs.git.delta`). Format `nix run nixpkgs#alejandra`. Any `inputs.cells.common.*` read loads globals.nix.age: eval needs a warm TPM cache.
Naming: palette additions `colors.winterGreen = "2b3328"`, `winterRed = "43242b"`, `winterBlue = "252535"`, `winterYellow = "49443c"` (verbatim kanagawa.nvim); roles `diffAdd`, `diffDelete`, `diffChange`, `diffText`, `success`, `warning`, `info`. Upstream source `kanagawaSrc` (fetchFromGitHub rebelot/kanagawa.nvim, rev pinned in 2.1). Theme/skin name `kanagawa` everywhere a tool takes a name (bat, btop, hermes skin, claude, opencode, zathura).

Invariants:
- Existing palette values never change: `nix eval --impure --json --expr 'removeAttrs (import ./cells/common/theme.nix {}) ["name"]'` keeps every key/value from 0251f2f; additions only.
- `nix run nixpkgs#alejandra -- --check <touched .nix>` == exit 0.
- `nix eval --raw .#nixosConfigurations.elster.config.system.build.toplevel.drvPath` succeeds (user runs it when the TPM cache is cold).
- Tor Browser is never themed: any change to its look breaks the uniform fingerprint.
- One phase = one Conventional Commit with why-body + Co-Authored-By: Claude; nothing pushed by Claude.
- User acceptance gate: a row flips to `themed` only after the USER has tested it on the rebuilt system and said so. Claude's evals/screenshots are not acceptance. After every rebuild that touches a row, Claude stops and hands the user a per-app test checklist (what to open, which screen, what to look at: bg, fg, selection, diff/err colours, popups/dialogs), then waits. The phase is not ✅ and the next phase does not start while any of its rows is `awaiting user test`. The user's verdict + date goes into Progress; a failed test sets the row back to `wrong` with the note.

## Matrix (Phase 0 fills `status`; phases flip it)
Status flow for every row a phase changes: `wrong`/`default` → `awaiting user test` (after rebuild + checklist handed over) → `themed` (user said OK) or back to `wrong` (user said no, note why).
Inventory source: `.desktop` files in /run/current-system/sw, /etc/profiles/per-user/crookedmirror, ~/.nix-profile (Entra), plus TUIs from home.packages. Kind: G = GUI, T = TUI/CLI with colour.

| app | kind | mechanism | status | phase |
|---|---|---|---|---|
| dwl, waybar, fuzzel (+power/calc/wifi menus), mako, swaylock, swaybg, slurp, satty | G | palette in Nix | themed | – |
| foot, tmux, tuigreet + VT | T | palette in Nix | themed | – |
| Thunar, pwvucontrol, xdg-desktop-portal-gtk dialogs | G | GTK (gtk.nix) | inherits (0.2: Thunar bg #16161d/#1f1f28, pwvucontrol #1f1f28 + #7e9cd8 accent; portal = same GTK3 theme as Thunar, not opened) | – |
| qBittorrent, qt5ct/qt6ct | G | Qt (qt.nix) | inherits (0.2: qBt #1f1f28/#16161d, qt6ct #181820/#393946) | – |
| KeePassXC | G | own built-in theme (keepassxc.ini has no GUI/ApplicationTheme, "auto" = its dark style) | wrong (0.2: grey #3b3b3d, not the Qt palette) | 5 |
| Vial | G | PyInstaller Qt, xcb only (dies on Wayland), ignores qt5ct | wrong (0.2: Fusion dark #353535) | 5 or exception |
| Horizon (gm) | G | omnissa `horizon-client_wrapper:2` hard-sets `GTK_THEME=Adwaita`; horizon-gm also sets `XDG_CONFIG_HOME=~/.omnissa/xdg-gm` (no gtk-3.0 there) | wrong (0.3: light Adwaita) | 7 |
| Zathura | G | own zathurarc colours | default | 5 |
| mpv (OSD), umpv | G | own osd-* options | default | 5 |
| avizo (volume/brightness OSD) | G | own config.ini colours | default | 5 |
| Firefox, Microsoft Edge | G | Dark Reader forced; chrome = GTK? | partial | 7 |
| o365 PWAs (Teams, Outlook, Word, Excel, PowerPoint, OneNote, OneDrive, SharePoint) | G | NOT Edge: rust_o365 wraps teams-for-linux 2.17.1 (Electron), profiles in ~/.config/o365-profiles | wrong (web apps' own theme; not opened: would load the signed-in mailbox) | 7 |
| Slack, Telegram (nixpak) | G | own in-app themes | wrong (not screenshotted: single-instance, already running on the real session) | 7 |
| Mattermost | G | Electron, own theme | wrong (0.2: light default) | 7 |
| SimpleX | G | Compose/skiko, own theme | wrong (not observed: no GL context on headless X) | 7 |
| Grayjay | G | CEF, own theme | wrong (0.2: own dark #1b1b1b) | 7 |
| Tor Browser | G | – | exception | – |
| GVim | G | own GUI colorscheme; `vim` is only in base.nix as a rescue editor | exception (rescue tool, not used) | – |
| cups web UI, NixOS manual | G | web pages in the browser | exception (covered by Dark Reader, row Firefox/Edge) | – |
| vim | T | default colorscheme = 16 ANSI | inherits (by construction) | – |
| neovim | T | catppuccin in dotfiles | wrong | 4 |
| bat, delta, lazygit diffs | T | bat tmTheme + delta styles | themed (user OK 2026-09, Markdown after 2.4) | 2 |
| btop | T | themes/kanagawa.theme generated from palette | themed (user OK 2026-09) | 3 |
| Claude Code | T | custom theme file (0.4) | default | 6 |
| Hermes | T | skin yaml (~/.hermes/skins) | default | 6 |
| opencode | T | tui.json theme | wrong ("opencode") | 6 |
| rmpc, bluetui, eza, dircolors/ls, fast-syntax-highlighting, jq, rg | T | ANSI → foot | inherits (0.2: only 16-colour SGR / 256 idx < 16) | – |
| lazygit UI | T | ANSI → foot | themed (authorColors = info; user OK 2026-09) | 2 |
| p10k | T | dotfiles/zsh/.p10k.zsh, ANSI 1-7 | inherits, except 2 cube colours (67, 208) | 5 |
| skim, fzf | T | built-in 256-cube defaults (161, 168, 59, 144, 236, 110) | wrong (0.2) | 5 |
| nyx | T | curses, 16 ANSI | inherits (not observed: needs a Tor ControlPort, crookedmirror only) | – |
| nmtui (newt) | T | newt default blue/white bg via ANSI | wrong (0.2: bg16 44/47, newt's stock scheme) | 5 |
| man/less, fastfetch, git status/log, typst/tinymist, top | T | ANSI → foot | inherits (0.2: 16-colour only; man = bold/underline) | – |

## Phase 0 — Inventory + recon ✅
0.1 Regenerate the inventory (the `.desktop` scan for both accounts + `ls ~/.nix-profile/bin`) and diff against the Matrix; add missing rows, drop uninstalled ones. — DONE 2026-09, `ls` of the 5 applications dirs + both profiles' bin: GUI set = Matrix; split KeePassXC/Vial and the chat row, added vim/jq/rg/typst/top; no htop installed; `hermes` is system-wide (sw/bin), nyx/tor-browser crookedmirror only, horizon/Grayjay/Slack/Telegram vkokurin only.
0.2 For every `inherits?`/`?` row, one observation each, recorded in the row: GTK/Qt apps via screenshot (grim) of the window; TUIs via `script -qc '<tool>' | grep -o $'\e\[38;2;[0-9;]*m'` (truecolor escapes = own palette, not foot's) or a screenshot. — DONE 2026-09: GUIs on a headless dwl (`WLR_BACKENDS=headless dwl -s ...` → wayland-1, grim + imagemagick pixel/histogram; xcb-only apps via DISPLAY=:1); TUIs in a private `tmux -L tc0`, `capture-pane -e`, SGR histogram (fg16/256/#rgb). Results in the Matrix rows.
0.3 Horizon: `horizon-gm` then check `GTK_THEME`/`XDG_DATA_DIRS` inside the FHS env (`cat /proc/<pid>/environ`), screenshot. — DONE 2026-09: environ has `GTK_THEME=Adwaita` (from nixpkgs `omnissa-horizon-files-2605/bin/horizon-client_wrapper:2`, `export GTK_THEME='Adwaita'`) and `XDG_CONFIG_HOME=/home/vkokurin/.omnissa/xdg-gm` (our horizon-gm wrapper; no gtk-3.0 inside). Screenshot = light Adwaita. Phase 7.4 needs both: override GTK_THEME after the wrapper and give xdg-gm a gtk-3.0 (or the theme via GTK_THEME=Kanagawa:dark + XDG_DATA_DIRS).
0.4 Tool capabilities — DONE 2026-09:
  - bat: yes. HM pin 44831a7 `modules/programs/bat.nix:74` `themes = mkOption` ({src, file}).
  - btop: yes, `programs.btop.themes` (`btop.nix:63`, writes btop/themes/<name>.theme). rmpc also has `programs.rmpc` on this pin (the "no HM module" note in music/default.nix:9 is stale).
  - opencode 1.18.21: yes, built-in `kanagawa` (`strings .opencode-wrapped | grep -i kanagawa` → "kanagawa", kanagawa.json).
  - Claude Code 2.1.239: yes. `strings .claude-wrapped`: themes dir = `<config dir>/themes/*.json` (≤256KB, hot-reloaded), schema `{name, base: dark|light|…, overrides: {token: "#rrggbb"|"rgb()"|"ansi256(n)"|"ansi:<name>"}}`, selected as `theme: "custom:<slug>"` in settings.json; confirmed by a third-party blog (claudcod.com) + tinted-theming/tinted-claude-code README, not by official docs.
  - hermes v0.20.5: yes. skin_engine.py docstring: `~/.hermes/skins/<name>.yaml`, `display.skin: <name>` in config.yaml or `/skin`; `hermes config get display.skin` → `default`. config.yaml is Hermes-owned (agent-proxy.nix:56), so set it through `hermes config set` in the seed script, not a symlink.
Exit criteria: no `?` left in the Matrix `status` column; 0.4 answered yes/no with the command used; Matrix committed.

## Phase 1 — Palette additions ✅
1.1 `cells/common/theme.nix`: the four `winter*` colours and roles `diffAdd = winterGreen`, `diffDelete = winterRed`, `diffChange = winterBlue`, `diffText = winterYellow`, `success = springGreen`, `warning = roninYellow`, `info = springBlue`. — DONE 2026-09, hexes re-checked against upstream master `lua/kanagawa/colors.lua` + wave `diff` in `themes.lua` (match).
Exit criteria: old palette JSON is a subset of the new one; commit `feat(theme): diff and status roles`.
verified 1: `nix eval --impure --json --expr 'removeAttrs (import ./cells/common/theme.nix {}) ["name"]'` before/after + recursive subset check -> true @ 2026-09; `alejandra --check cells/common/theme.nix` -> 0; consumers read only named keys (`k = theme.colors`/`r = theme.roles` aliases, no attrValues/mapAttrs over them) so elster drvPath should be unchanged; drvPath eval NOT run (age-plugin-tpm died, cold TPM cache) — user to run. No app changes, nothing to user-test.

## Phase 2 — bat + delta (+ lazygit diffs) ✅
2.1 DONE 2026-09 `cells/deck/homeModules/bat.nix`: `programs.bat.themes.kanagawa` (HM `bat.nix:15`, `{src, file}`) from `kanagawaSrc` `extras/tmTheme/kanagawa.tmTheme` (exists upstream, bg #1F1F28 / fg #DCD7BA / selection #2D4F67 = palette); `config.theme = "kanagawa"`. `kanagawaSrc` = fetchFromGitHub rebelot/kanagawa.nvim rev bb85e4bfc8d89b0e62c8fa53ccdd13d12e2f77b3 (master @ audit), let-bound in bat.nix (only consumer; btop 3.1 does not need it). HM rebuilds the bat cache in `home.activation.batCache` (HM `bat.nix:210`); skim's preview calls `${pkgs.bat}` (skim.nix:19), same config/cache, no change.
2.2 DONE 2026-09 `cells/deck/homeModules/git.nix:30` delta (25.05 `programs.git.delta.options`): `syntax-theme = "kanagawa"`; minus/plus(-emph) styles from `diff*` roles; line-number styles from `urgent`/`accent`/`muted`. lazygit's delta renderer (lazygit.nix:18) reads the same `[delta]` git config, no lazygit change for diffs.
2.2b DONE 2026-09 `cells/deck/homeModules/lazygit.nix`: `settings.gui.authorColors."*"` = a palette role, so author names stop being hash-generated truecolor (Matrix row "lazygit UI"). Chose `info` (springBlue).
2.3 User test (after rebuild): `git diff` and `git log -p` in a dirty repo; lazygit → a file with changes, staged + unstaged, commits panel (author colour); `bat` on a .nix and a .md file; `help git | head`; skim Ctrl-T preview. Look at: added/removed line bg, changed-word emphasis, line numbers, syntax colours vs nvim.
  — DONE 2026-09: user "всё ок", one finding: skim Ctrl-T preview of .md has no highlighting.
2.4 DONE 2026-09 Markdown in bat. Cause (measured): upstream kanagawa.tmTheme has no `markup.*` scopes except diff ones (no heading/bold/italic/raw/link/quote/list), so a README renders ~all #dcd7ba + #54546d gutter; not a skim problem, plain `bat README.md` is the same. Fix (user chose option 1 of 3: patch upstream, not regenerate/not exception): bat.nix `runCommand` appends 7 rules before `</array>` of upstream's tmTheme, colours from `theme.colors` per kanagawa.nvim wave treesitter links (heading → crystalBlue, raw → springGreen, link url → springBlue underline, quote → oniViolet2, list marker → springViolet1, bold/italic font styles). Palette addition `oniViolet2 = "b8b4d0"` (verbatim colors.lua:38).
  2.4 user test: skim Ctrl-T on a .md (README.md of the-hive) and `bat` on one: headings, `code`, links, `>` quotes, list markers, **bold**. Italic stays plain: bat's `--italic-text` defaults to never (same for upstream comments), not a theme issue. — DONE 2026-09: user "всё ок".
verified 2.4: standalone HM build of bat.nix (pins as above) -> tmTheme parses (`bat cache --build` okay); sample .md SGR: `#` + heading #7e9cd8, `-`/`1.` #938aa9, `>` quote #b8b4d0, `**b**` bold, `` `c` `` #98bb6c, url underline #7fb4ca; README.md 60 lines now 7 colours (was 2 fgs); bat.nix itself unchanged set @ 2026-09.
Exit criteria: `delta --show-config` shows `syntax-theme = kanagawa` and palette hexes; lazygit diff has no #3f0001/#002800; user accepted 2.3.
verified 2: `kanagawaSrc` hash via `nix flake prefetch github:rebelot/kanagawa.nvim/bb85e4b…` -> sha256-fMP4NUCK…; HM 44831a7 + nixpkgs 34ab999 standalone `homeManagerConfiguration` of bat/git/lazygit modules (/tmp, TPM-free) builds; generated `[delta]` = syntax-theme kanagawa, minus #43242b, plus #2b3328, emph #49443c, line numbers #c34043/#98bb6c/#727169; lazygit `gui.authorColors."*"` = #7fb4ca; in a throwaway HOME `bat cache --build` + `bat --list-themes` lists kanagawa, `delta --show-config` syntax-theme = Kanagawa, a real diff's SGR = only those bgs + tmTheme fgs, 0 hits of 3f0001/002800 @ 2026-09. tmTheme fgs outside our palette subset (still Kanagawa Wave upstream: #b8b4d0 oniViolet2, #9cabca springViolet2, #717c7c katanaGray) accepted as upstream, same set nvim gets in Phase 4. `alejandra --check` on the 3 files -> 0. elster drvPath NOT evaluated (cold TPM cache) — user.

## Phase 3 — btop from the palette ✅
3.1 `deck/homeModules/btop.nix`: `programs.btop.themes.kanagawa` (HM `btop.nix:63`, `lines`) from roles/colours; `color_theme = "kanagawa"` (replaces `kanagawa-wave` at btop.nix:14); drop the now-false comment btop.nix:11-12 ("no file to derive").
  — DONE 2026-09: gradient families kept from btop's bundled kanagawa-wave, off-palette hexes swapped (#dca561 → roninYellow/carpYellow, #957fbb → oniViolet, #7e9cdb → crystalBlue, #9cabca → oniViolet2); main_bg = roles.bg #1f1f28 (bundled used #16161d); temp/cpu/process = success→warning→urgent; added graph_text = muted, meter_bg = border (bundled omitted both).
3.2 User test: btop main view, then the menu (Esc) and the process filter (f). Look at: graph gradients, box borders, selected row. Known, not a theme bug: the menu's BTOP logo is red #cd2121 + greys #cc/#aa/#80, hardcoded (btop 1.4.7 src/btop.cpp:91, btop_menu.cpp:1222).
  — DONE 2026-09: user "ок".
verified 3.1: `alejandra --check btop.nix` -> 0; standalone HM (44831a7 + nixpkgs 34ab999, /tmp/btop-hm/eval.nix) builds, btop.conf `color_theme = "kanagawa"`, themes/kanagawa.theme 45 keys all palette hexes; private `tmux -L tc3` btop 1.4.7 with XDG_CONFIG_HOME=copy: main view truecolor = palette + gradient interpolations only, bg #1f1f28, selected row bg #2d4f67, no btop.log (no theme error); menu = palette + the hardcoded logo colours @ 2026-09. elster drvPath NOT evaluated (cold TPM cache) — user.
Exit criteria: `grep color_theme ~/.config/btop/btop.conf` == kanagawa, no fallback on start; user accepted 3.2.

## Phase 4 — neovim to kanagawa.nvim ⏳
4.1 Replace the catppuccin spec in `plugins/colorscheme/init.lua` with `rebelot/kanagawa.nvim` (wave); terminal_color_* in `theme.ansi` order. Also `custom/lazy.lua` and `custom/init.lua` (1 catppuccin ref each: install fallback / colorscheme call) and `lazy-lock.json` (`:Lazy clean`, else the exit grep fails).
4.2 Port `hl_overrides.lua` (465 lines, 191 `C.*` refs over 23 catppuccin keys: base blue dark_purple green lavender mantle maroon mauve overlay0 peach pink red rosewater sapphire sky subtext0 sun surface0 surface1 teal text vibrant_green yellow) and ui.lua (8 lines) / editor.lua (6) / utils-plugins/bufferline.lua (10) to kanagawa `overrides(colors)`. Write the catppuccin→kanagawa key map first (one table, reviewed by the user). Two non-palette deps: `catppuccin.utils.colors` darken (hl_overrides ×3, editor ×1) → `kanagawa.lib.color`; `catppuccin.special.bufferline` (bufferline.lua) → plain bufferline highlights. Big enough to split: 4.2a map + hl_overrides, 4.2b ui/editor/bufferline.
4.3 User test (after `:Lazy sync`): a .nix and a .lua file, telescope/picker, completion popup, diagnostics (introduce an error), git signs, bufferline with 3 buffers, `:terminal`, a diff (`:Gitsigns diffthis` or nvimdiff). Look at: overrides that used catppuccin colours, floating window borders, terminal colours.
Exit criteria: `nvim --headless -c 'lua print(vim.g.colors_name)' -c qa` == kanagawa; `grep -rn catppuccin dotfiles/nvim` empty; `nvim --headless +qa 2>&1` empty; user accepted 4.3.

## Phase 5 — Standalone GUI/TUI configs ⏳
5.1 Zathura: today a bare package in `home/dev/languages.nix:50` (texlive forward-search). Move it to `programs.zathura.enable` (HM `zathura.nix:30,84` installs the package itself; drop the languages.nix entry) + `programs.zathura.options` (default-bg/fg, statusbar-*, inputbar-*, highlight-*, recolor-*) from roles; recolor off by default.
5.2 mpv: `osd-color`, `osd-border-color`, `osd-back-color` from roles in `programs.mpv.config` (`home/desktop/mpv/default.nix:33`).
5.3 avizo: `services.avizo.settings.default` (HM `services/avizo.nix:17`) background/border/bar colours from roles in `home/desktop/osd.nix:6`.
5.4 ANSI TUIs with their own colours (Phase 0): nmtui via `NEWT_COLORS` session var; fzf via `programs.fzf.colors` (HM `fzf.nix:152`); skim has NO `colors` option on this HM pin (only *Options lists) → `--color=...` in `programs.skim.defaultOptions`; check whether zsh-histdb-skim (Ctrl-R, `deck/packages/zsh-histdb-skim.nix`) honours SKIM_DEFAULT_OPTIONS, else note it; p10k cube colours 67/208 in `dotfiles/zsh/.p10k.zsh` → ANSI indices. man/less already ANSI-only, no change.
5.5 KeePassXC: `[GUI] ApplicationTheme=classic` so it takes the Qt palette. NOT via HM `programs.keepassxc.settings` (HM `keepassxc.nix:53` makes keepassxc.ini a read-only store symlink; KeePassXC writes last-opened DBs/geometry there and would lose them). keepass.nix today is only `home.packages`; set the one key with an idempotent activation edit of the persisted ini (~/.config/keepassxc, keepass.nix:7-10), both accounts. Vial (`profiles/input-vial.nix`): xcb-only PyInstaller Qt, ignores qt5ct; try `QT_STYLE_OVERRIDE`/palette env in its wrapper, else exception.
5.6 User test, one line per app: Zathura (open a PDF, `/` search → highlight, statusbar, `Ctrl+R` recolor); mpv (seek → OSD bar, `o`, pause text); avizo (volume and brightness keys); nmtui (main menu + a dialog); fzf and skim (Ctrl-T, Alt-C, Ctrl-R); p10k prompt in a git repo; KeePassXC (main window, entry edit dialog, settings; reopen: last DB still remembered); Vial if not an exception.
Exit criteria: screenshot of each tool shows palette bg/fg; user accepted 5.6 per app; Matrix rows flipped to themed.

## Phase 6 — Agent CLIs ⏳
6.1 Hermes: `~/.hermes/skins/kanagawa.yaml` from roles via HM `home.file` (both accounts; `.hermes` persisted: layer-users-local.nix:74, auth-entra.nix:290; skins/ is not one of the /srv/agents shared links, agent-proxy.nix:84, so per-home is right); `display.skin kanagawa` via `hermes config set` in `seedHermes` (agent-proxy.nix:67), same get-compare-set pattern as `model.*` there.
6.2 Claude Code: `~/.claude/themes/kanagawa.json` from roles via `home.file`; `theme = "custom:kanagawa"` in `claudeSettings` (agents.nix; settings schema accepts `startsWith("custom:")`, re-seen in 2.1.239 strings). settings.json is a store symlink (agents.nix `home.file.".claude/settings.json"`), so `/theme` cannot persist a change: expected, test only that it lists kanagawa.
6.3 opencode: `opencodeTui.theme = "kanagawa"` at agents.nix:126 (built-in, 0.4).
6.4 User test: hermes (banner, a tool call, a diff/patch preview, a clarify prompt); claude (prompt, tool call, diff, permission dialog, `/theme` lists kanagawa); opencode (session view, diff, command palette). Both accounts where the tool runs on both.
Exit criteria: each CLI's TUI shows bg #1f1f28 / accents from roles in a screenshot; user accepted 6.4 per tool; Matrix rows flipped.

## Phase 7 — Browsers, Electron, PWAs, Horizon ⏳
Sketch only; plan-audit rewrites from Phase 0 findings.
7.1 Firefox/Edge chrome: follow GTK dark (already prefer-dark) or a Kanagawa userChrome / Edge theme; content stays Dark Reader, optionally seeded with palette bg/fg via its managed policy.
7.2 o365 PWAs: they are teams-for-linux (Electron) windows via rust_o365, not Edge (Phase 0); look for a teams-for-linux theme/CSS option, else record exception if the web apps ignore it.
7.3 Slack/Telegram/Mattermost/SimpleX/Grayjay: each app's own theme import (Slack custom sidebar string, Telegram .tdesktop-theme generated from palette), else exception with reason.
7.4 Horizon: GTK theme visible inside the FHS env (bind the theme dir / set GTK_THEME), per 0.3.
7.5 User test per app, checklist written when 7.1–7.4 land (each app's main window, a dialog, a menu; browsers: new tab, settings page, a site under Dark Reader; Horizon: selector + disconnect dialog).
Exit criteria: every row in scope is themed (user accepted 7.5 for it) or exception with a one-line reason.

## Phase 8 — colors → roles (stretch) ⏳
8.1 Move the 58 `theme.colors` refs (via `k`/`c` aliases: default 6, bar 1, launcher 7, torrent 18, notify 3, screenshot 5, qt 4, lock 14) in home/default.nix and desktop/{bar,launcher,torrent,notify,screenshot,qt,lock}.nix onto roles.
8.2 User test only if drvPath changed: quick look at bar, launcher, lock screen, notifications, qBittorrent.
Exit criteria: `theme.colors` referenced only inside `cells/common/theme.nix`; elster drvPath unchanged across the phase (or user accepted 8.2).

## Fallback at any phase
Phases after 1 are independent; stop anywhere and what is merged stays coherent. Minimum useful slice = 0 + 1 + 2 (fixes delta/lazygit), one session.

## Progress
- 2026-09: plan written, then rewritten around a full app inventory after review ("нет keepass, horizon, claude, hermes"). Palette already in `cells/common/theme.nix` (0251f2f). Lazygit state persistence fixed separately, not part of this plan.
- 2026-09: added the user acceptance gate (invariant + per-phase test step): the user asked to be made to test every app after its theme lands.
- 2026-09: Phase 0 done, read-only (headless dwl + private tmux, nothing on the real session touched). Surprises: KeePassXC and Vial do NOT inherit Qt; Horizon is forced to Adwaita by the nixpkgs wrapper; o365 = teams-for-linux, not Edge; skim/fzf/nmtui use their own colours; all 0.4 capabilities = yes. Phase 0 changes no app, so there is nothing for the user to test.
- 2026-09: Phase 1 done: 4 winter* colours + diff*/success/warning/info roles, additions only. drvPath check pending on the user (TPM).
- 2026-09: plan-audit of phases 2-8 against live code: fixed skim `colors` (no such HM option), KeePassXC via HM settings (would make the ini read-only), zathura not an HM program yet, nvim counts/missed files, Claude theme = custom:kanagawa (was a conditional), added lazygit authorColors (2.2b), renumbered 5.5/5.6.
- 2026-09: Phase 2.1-2.2b code landed (bat tmTheme, delta styles from diff* roles, lazygit authorColors); verified off-host, awaiting rebuild + 2.3.
- 2026-09: user accepted 2.3 ("всё ок"); found no Markdown highlighting in skim preview → 2.4 (tmTheme lacks markup scopes).
- 2026-09: 2.4 landed (markup rules patched into upstream tmTheme, + oniViolet2); awaiting rebuild + 2.4 user test.
- 2026-09: user accepted 2.4 ("всё ок"); Phase 2 ✅. Phase 3 in a fresh session.
- 2026-09: 3.1 landed (btop theme generated from roles/colours); verified off-host, awaiting rebuild + 3.2.
- 2026-09: user accepted 3.2 ("ок"); Phase 3 ✅. Phase 4 in a fresh session.

Next: Phase 4.1 — nvim catppuccin → kanagawa.nvim (offer plan-audit first; 4.2 starts with the key map for user review).
Blocked on: nothing.
