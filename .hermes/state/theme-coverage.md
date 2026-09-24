# theme-coverage — every installed GUI/TUI on elster paints from cells/common/theme.nix (Kanagawa Wave), or is on a written exceptions list

Status: PLANNING (2026-09). Owner: user; Claude = executor.
Prereq: the-hive at 0251f2f or later (palette in `cells/common/theme.nix`, read as `inputs.cells.common.theme`). User runs every rebuild; Claude only edits + evals.

Target: each row of the Matrix below is `themed` (colours trace to `cells/common/theme.nix`), `inherits` (verified to pick up foot ANSI / GTK / Qt without its own config), or `exception` (with the reason). No row stays `?`. Stretch: desktop consumers read `theme.roles.*` only, never `theme.colors.*` (57 refs in 8 files today), so switching the palette is one file.
Source refs: `cells/common/theme.nix` (colors/roles/ansi/name); GTK `home/desktop/gtk.nix` and Qt `home/desktop/qt.nix` (the two inherited toolkits); `deck/homeModules/*.nix` (shell/TUI tools); `home/dev/agents.nix` (claude settings.json :144, opencode tui :126); `profiles/agent-proxy.nix` (hermes install); `packages.nix` (nixpak Slack/Telegram, grayjay, horizon-gm FHS); `profiles/auth-entra.nix` (o365 PWAs via Edge); `dotfiles/nvim/lua/custom/plugins/colorscheme/` (catppuccin, 171 refs in hl_overrides.lua + 36 in ui/editor/bufferline). Upstream themes: `rebelot/kanagawa.nvim` `extras/tmTheme/kanagawa.tmTheme` (bat/delta) and `lua/kanagawa/themes.lua` wave `diff = { add = winterGreen, delete = winterRed, change = winterBlue, text = winterYellow }`; opencode `packages/ui/src/theme/themes/kanagawa.json`; hermes skins = `~/.hermes/skins/<name>.yaml` + `display.skin` (schema in hermes_cli/skin_engine.py); Claude Code 2.1.239 lists "custom themes" in `--safe-mode` help (location unverified).
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
| bat, delta, lazygit diffs | T | bat tmTheme + delta styles | wrong (Monokai) | 2 |
| btop | T | by-name kanagawa-wave, not palette | partial (0.2: #dcd7ba/#727169/#16161d match, #de8954/#bab067 off-palette) | 3 |
| Claude Code | T | custom theme file (0.4) | default | 6 |
| Hermes | T | skin yaml (~/.hermes/skins) | default | 6 |
| opencode | T | tui.json theme | wrong ("opencode") | 6 |
| rmpc, bluetui, eza, dircolors/ls, fast-syntax-highlighting, jq, rg | T | ANSI → foot | inherits (0.2: only 16-colour SGR / 256 idx < 16) | – |
| lazygit UI | T | ANSI → foot | inherits, except hash-generated author colours (truecolor, e.g. #7fc60b) | 2 |
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

## Phase 1 — Palette additions ⏳
1.1 `cells/common/theme.nix`: the four `winter*` colours and roles `diffAdd = winterGreen`, `diffDelete = winterRed`, `diffChange = winterBlue`, `diffText = winterYellow`, `success = springGreen`, `warning = roninYellow`, `info = springBlue`.
Exit criteria: old palette JSON is a subset of the new one; commit `feat(theme): diff and status roles`.

## Phase 2 — bat + delta (+ lazygit diffs) ⏳
2.1 `deck/homeModules/bat.nix`: `programs.bat.themes.kanagawa` from `kanagawaSrc` `extras/tmTheme/kanagawa.tmTheme`; `config.theme = "kanagawa"`.
2.2 `deck/homeModules/git.nix` delta: `syntax-theme = "kanagawa"`; minus/plus(-emph) styles from `diff*` roles; line-number styles from `urgent`/`accent`/`muted`.
2.3 User test (after rebuild): `git diff` and `git log -p` in a dirty repo; lazygit → a file with changes, staged + unstaged; `bat` on a .nix and a .md file; `help git | head`. Look at: added/removed line bg, changed-word emphasis, line numbers, syntax colours vs nvim.
Exit criteria: `delta --show-config` shows `syntax-theme = kanagawa` and palette hexes; lazygit diff has no #3f0001/#002800; user accepted 2.3.

## Phase 3 — btop from the palette ⏳
3.1 `deck/homeModules/btop.nix`: generate `~/.config/btop/themes/kanagawa.theme` from roles/colours; `color_theme = "kanagawa"`.
3.2 User test: btop main view, then the menu (Esc) and the process filter (f). Look at: graph gradients, box borders, selected row.
Exit criteria: `grep color_theme ~/.config/btop/btop.conf` == kanagawa, no fallback on start; user accepted 3.2.

## Phase 4 — neovim to kanagawa.nvim ⏳
4.1 Replace the catppuccin spec with `rebelot/kanagawa.nvim` (wave); terminal_color_* in `theme.ansi` order.
4.2 Port `hl_overrides.lua` + the 36 `catppuccin.palettes` calls (ui.lua, editor.lua, utils-plugins/bufferline.lua) to kanagawa `overrides(colors)`.
4.3 User test (after `:Lazy sync`): a .nix and a .lua file, telescope/picker, completion popup, diagnostics (introduce an error), git signs, bufferline with 3 buffers, `:terminal`, a diff (`:Gitsigns diffthis` or nvimdiff). Look at: overrides that used catppuccin colours, floating window borders, terminal colours.
Exit criteria: `nvim --headless -c 'lua print(vim.g.colors_name)' -c qa` == kanagawa; `grep -rn catppuccin dotfiles/nvim` empty; `nvim --headless +qa 2>&1` empty; user accepted 4.3.

## Phase 5 — Standalone GUI/TUI configs ⏳
5.1 Zathura: `programs.zathura.options` (default-bg/fg, statusbar-*, inputbar-*, highlight-*, recolor-*) from roles; recolor off by default.
5.2 mpv: `osd-color`, `osd-border-color`, `osd-back-color` from roles in `home/desktop/mpv/default.nix`.
5.3 avizo: `services.avizo.settings.default` background/border/bar colours from roles in `home/desktop/osd.nix`.
5.4 Whatever Phase 0 marked wrong among ANSI TUIs that use their own env (NEWT_COLORS for nmtui, LESS_TERMCAP_* for man): one line each from `theme.ansi` names. Phase 0 result: nmtui (NEWT_COLORS), skim + fzf (`programs.{skim,fzf}.colors` from roles), p10k cube colours 67/208 → ANSI indices; man/less already ANSI-only, no change.
5.6 KeePassXC: `[GUI] ApplicationTheme=classic` in keepassxc.ini so it takes the Qt palette (the file is user-writable, settings persist; check how keepass.nix handles it first). Vial: xcb-only PyInstaller Qt, ignores qt5ct; try `QT_STYLE_OVERRIDE`/palette env in its wrapper, else exception.
5.5 User test, one line per app: Zathura (open a PDF, `/` search → highlight, statusbar, `Ctrl+R` recolor); mpv (seek → OSD bar, `o`, pause text); avizo (volume and brightness keys); each 5.4 TUI (nmtui main menu + a dialog, `man git`).
Exit criteria: screenshot of each tool shows palette bg/fg; user accepted 5.5 per app; Matrix rows flipped to themed.

## Phase 6 — Agent CLIs ⏳
6.1 Hermes: generate `~/.hermes/skins/kanagawa.yaml` from roles via HM (both accounts; `.hermes` is persisted, the file is a store symlink); `display.skin: kanagawa` via `hermes config set` or the managed config, per 0.4.
6.2 Claude Code: custom theme file from roles if 0.4 found the format, else `theme = "dark-ansi"` in settings.json so it renders with foot's Kanagawa ANSI.
6.3 opencode: `opencodeTui.theme = "kanagawa"` (built-in) or palette-generated JSON if 0.4 == no.
6.4 User test: hermes (banner, a tool call, a diff/patch preview, a clarify prompt); claude (prompt, tool call, diff, permission dialog, `/theme`); opencode (session view, diff, command palette). Both accounts where the tool runs on both.
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
8.1 Move the 57 `theme.colors.*` refs in home/default.nix and desktop/{bar,launcher,torrent,notify,screenshot,qt,lock}.nix onto roles.
8.2 User test only if drvPath changed: quick look at bar, launcher, lock screen, notifications, qBittorrent.
Exit criteria: `theme.colors` referenced only inside `cells/common/theme.nix`; elster drvPath unchanged across the phase (or user accepted 8.2).

## Fallback at any phase
Phases after 1 are independent; stop anywhere and what is merged stays coherent. Minimum useful slice = 0 + 1 + 2 (fixes delta/lazygit), one session.

## Progress
- 2026-09: plan written, then rewritten around a full app inventory after review ("нет keepass, horizon, claude, hermes"). Palette already in `cells/common/theme.nix` (0251f2f). Lazygit state persistence fixed separately, not part of this plan.
- 2026-09: added the user acceptance gate (invariant + per-phase test step): the user asked to be made to test every app after its theme lands.
- 2026-09: Phase 0 done, read-only (headless dwl + private tmux, nothing on the real session touched). Surprises: KeePassXC and Vial do NOT inherit Qt; Horizon is forced to Adwaita by the nixpkgs wrapper; o365 = teams-for-linux, not Edge; skim/fzf/nmtui use their own colours; all 0.4 capabilities = yes. Phase 0 changes no app, so there is nothing for the user to test.

Next: Phase 1.1 — palette additions in `cells/common/theme.nix` (offer plan-audit first: phases 1+ were written before Phase 0).
Blocked on: nothing.
