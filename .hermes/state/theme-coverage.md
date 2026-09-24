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

## Matrix (Phase 0 fills `status`; phases flip it)
Inventory source: `.desktop` files in /run/current-system/sw, /etc/profiles/per-user/crookedmirror, ~/.nix-profile (Entra), plus TUIs from home.packages. Kind: G = GUI, T = TUI/CLI with colour.

| app | kind | mechanism | status | phase |
|---|---|---|---|---|
| dwl, waybar, fuzzel (+power/calc/wifi menus), mako, swaylock, swaybg, slurp, satty | G | palette in Nix | themed | – |
| foot, tmux, tuigreet + VT | T | palette in Nix | themed | – |
| Thunar, pwvucontrol, xdg-desktop-portal-gtk dialogs | G | GTK (gtk.nix) | inherits? | 0 |
| qBittorrent, KeePassXC, Vial, qt5ct/qt6ct | G | Qt (qt.nix) | inherits? (qBt themed) | 0 |
| Horizon (gm) | G | GTK3 inside buildFHSEnv: does it see ~/.config/gtk-3.0 + theme dir? | ? | 0 → 7 |
| Zathura | G | own zathurarc colours | default | 5 |
| mpv (OSD), umpv | G | own osd-* options | default | 5 |
| avizo (volume/brightness OSD) | G | own config.ini colours | default | 5 |
| Firefox, Microsoft Edge | G | Dark Reader forced; chrome = GTK? | partial | 7 |
| o365 PWAs (Teams, Outlook, Word, Excel, PowerPoint, OneNote, OneDrive, SharePoint) | G | Edge app windows, web content | ? | 7 |
| Slack, Telegram (nixpak), Mattermost, SimpleX, Grayjay | G | Electron/Qt/CEF own themes | ? | 7 |
| Tor Browser | G | – | exception | – |
| GVim, vim, cups web UI, NixOS manual | G | – | exception? | 0 |
| neovim | T | catppuccin in dotfiles | wrong | 4 |
| bat, delta, lazygit diffs | T | bat tmTheme + delta styles | wrong (Monokai) | 2 |
| btop | T | by-name kanagawa-wave, not palette | partial | 3 |
| Claude Code | T | /theme or custom theme file | ? | 6 |
| Hermes | T | skin yaml (~/.hermes/skins) | default | 6 |
| opencode | T | tui.json theme | wrong ("opencode") | 6 |
| rmpc, nyx, bluetui, lazygit UI, skim, fzf, eza, dircolors/ls, p10k, zsh-syntax-highlighting | T | ANSI → foot | inherits? | 0 |
| nmtui (newt), man/less, fastfetch, git status/log colours, typst/tinymist, htop-likes | T | ANSI → foot, or own env (NEWT_COLORS, LESS_TERMCAP_*) | ? | 0 → 5 |

## Phase 0 — Inventory + recon ⏳
0.1 Regenerate the inventory (the `.desktop` scan for both accounts + `ls ~/.nix-profile/bin`) and diff against the Matrix; add missing rows, drop uninstalled ones.
0.2 For every `inherits?`/`?` row, one observation each, recorded in the row: GTK/Qt apps via screenshot (grim) of the window; TUIs via `script -qc '<tool>' | grep -o $'\e\[38;2;[0-9;]*m'` (truecolor escapes = own palette, not foot's) or a screenshot.
0.3 Horizon: `horizon-gm` then check `GTK_THEME`/`XDG_DATA_DIRS` inside the FHS env (`cat /proc/<pid>/environ`), screenshot.
0.4 Tool capabilities: `programs.bat.themes` on HM 25.05; opencode's pinned version ships `kanagawa`; where Claude Code 2.1.239 reads custom themes (docs or `strings` of the bundle); hermes `display.skin` accepted by `hermes config`.
Exit criteria: no `?` left in the Matrix `status` column; 0.4 answered yes/no with the command used; Matrix committed.

## Phase 1 — Palette additions ⏳
1.1 `cells/common/theme.nix`: the four `winter*` colours and roles `diffAdd = winterGreen`, `diffDelete = winterRed`, `diffChange = winterBlue`, `diffText = winterYellow`, `success = springGreen`, `warning = roninYellow`, `info = springBlue`.
Exit criteria: old palette JSON is a subset of the new one; commit `feat(theme): diff and status roles`.

## Phase 2 — bat + delta (+ lazygit diffs) ⏳
2.1 `deck/homeModules/bat.nix`: `programs.bat.themes.kanagawa` from `kanagawaSrc` `extras/tmTheme/kanagawa.tmTheme`; `config.theme = "kanagawa"`.
2.2 `deck/homeModules/git.nix` delta: `syntax-theme = "kanagawa"`; minus/plus(-emph) styles from `diff*` roles; line-number styles from `urgent`/`accent`/`muted`.
Exit criteria: `delta --show-config` shows `syntax-theme = kanagawa` and palette hexes; lazygit diff has no #3f0001/#002800.

## Phase 3 — btop from the palette ⏳
3.1 `deck/homeModules/btop.nix`: generate `~/.config/btop/themes/kanagawa.theme` from roles/colours; `color_theme = "kanagawa"`.
Exit criteria: `grep color_theme ~/.config/btop/btop.conf` == kanagawa, no fallback on start.

## Phase 4 — neovim to kanagawa.nvim ⏳
4.1 Replace the catppuccin spec with `rebelot/kanagawa.nvim` (wave); terminal_color_* in `theme.ansi` order.
4.2 Port `hl_overrides.lua` + the 36 `catppuccin.palettes` calls (ui.lua, editor.lua, utils-plugins/bufferline.lua) to kanagawa `overrides(colors)`.
Exit criteria: `nvim --headless -c 'lua print(vim.g.colors_name)' -c qa` == kanagawa; `grep -rn catppuccin dotfiles/nvim` empty; `nvim --headless +qa 2>&1` empty.

## Phase 5 — Standalone GUI/TUI configs ⏳
5.1 Zathura: `programs.zathura.options` (default-bg/fg, statusbar-*, inputbar-*, highlight-*, recolor-*) from roles; recolor off by default.
5.2 mpv: `osd-color`, `osd-border-color`, `osd-back-color` from roles in `home/desktop/mpv/default.nix`.
5.3 avizo: `services.avizo.settings.default` background/border/bar colours from roles in `home/desktop/osd.nix`.
5.4 Whatever Phase 0 marked wrong among ANSI TUIs that use their own env (NEWT_COLORS for nmtui, LESS_TERMCAP_* for man): one line each from `theme.ansi` names.
Exit criteria: screenshot of each tool shows palette bg/fg; Matrix rows flipped to themed.

## Phase 6 — Agent CLIs ⏳
6.1 Hermes: generate `~/.hermes/skins/kanagawa.yaml` from roles via HM (both accounts; `.hermes` is persisted, the file is a store symlink); `display.skin: kanagawa` via `hermes config set` or the managed config, per 0.4.
6.2 Claude Code: custom theme file from roles if 0.4 found the format, else `theme = "dark-ansi"` in settings.json so it renders with foot's Kanagawa ANSI.
6.3 opencode: `opencodeTui.theme = "kanagawa"` (built-in) or palette-generated JSON if 0.4 == no.
Exit criteria: each CLI's TUI shows bg #1f1f28 / accents from roles in a screenshot; Matrix rows flipped.

## Phase 7 — Browsers, Electron, PWAs, Horizon ⏳
Sketch only; plan-audit rewrites from Phase 0 findings.
7.1 Firefox/Edge chrome: follow GTK dark (already prefer-dark) or a Kanagawa userChrome / Edge theme; content stays Dark Reader, optionally seeded with palette bg/fg via its managed policy.
7.2 o365 PWAs: inherit Edge; record exception if web apps ignore it.
7.3 Slack/Telegram/Mattermost/SimpleX/Grayjay: each app's own theme import (Slack custom sidebar string, Telegram .tdesktop-theme generated from palette), else exception with reason.
7.4 Horizon: GTK theme visible inside the FHS env (bind the theme dir / set GTK_THEME), per 0.3.
Exit criteria: every row in scope is themed or exception with a one-line reason.

## Phase 8 — colors → roles (stretch) ⏳
8.1 Move the 57 `theme.colors.*` refs in home/default.nix and desktop/{bar,launcher,torrent,notify,screenshot,qt,lock}.nix onto roles.
Exit criteria: `theme.colors` referenced only inside `cells/common/theme.nix`; elster drvPath unchanged across the phase.

## Fallback at any phase
Phases after 1 are independent; stop anywhere and what is merged stays coherent. Minimum useful slice = 0 + 1 + 2 (fixes delta/lazygit), one session.

## Progress
- 2026-09: plan written, then rewritten around a full app inventory after review ("нет keepass, horizon, claude, hermes"). Palette already in `cells/common/theme.nix` (0251f2f). Lazygit state persistence fixed separately, not part of this plan.

Next: Phase 0.1 — regenerate the inventory on elster (read-only, minutes). Then 0.2–0.4.
Blocked on: nothing.
