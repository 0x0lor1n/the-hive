# theme-coverage — every themed tool on elster paints from cells/common/theme.nix (Kanagawa Wave)

Status: PLANNING (2026-09). Owner: user; Claude = executor.
Prereq: the-hive at 0251f2f or later (palette lives in `cells/common/theme.nix`, read as `inputs.cells.common.theme`). User runs every rebuild; Claude only edits + evals.

Target: bat, delta, lazygit diffs, btop, neovim and opencode render Kanagawa Wave with hexes that trace to `cells/common/theme.nix`, not to a tool's built-in default (today: bat/delta = Monokai Extended + delta's #3f0001/#002800 diff bgs, nvim = catppuccin mocha, opencode = "opencode", btop = by-name `kanagawa-wave`). Stretch: desktop consumers read `theme.roles.*` only, never `theme.colors.*` (57 refs in 8 files today), so switching the palette is one file.
Source refs: `cells/common/theme.nix` (palette: colors/roles/ansi/name), `cells/deck/homeModules/{bat,git,lazygit,btop}.nix` (consumers to change), `dotfiles/nvim/lua/custom/plugins/colorscheme/{init,hl_overrides}.lua` (catppuccin setup; hl_overrides has 171 `C.`/`U.` refs), `dotfiles/nvim/lua/custom/plugins/{ui,editor}.lua` + `utils-plugins/bufferline.lua` (further `catppuccin.palettes` calls, 36 refs), `cells/workstation/home/dev/agents.nix:126` (opencode tui theme), upstream `rebelot/kanagawa.nvim` `extras/tmTheme/kanagawa.tmTheme` (bat/delta syntax theme; bg #1F1F28, fg #DCD7BA match the palette) and `lua/kanagawa/themes.lua` wave `diff = { add = winterGreen, delete = winterRed, change = winterBlue, text = winterYellow }`, upstream opencode `packages/ui/src/theme/themes/kanagawa.json` (built-in theme exists).
Repo: HM is release-25.05 (`cells/workstation/flake.nix:34`), so HM option names follow 25.05 (`programs.git.delta`, not `programs.delta`). Format with `nix run nixpkgs#alejandra`. Eval needs the TPM-cached globals: any `inputs.cells.common.*` read loads globals.nix.age.
Naming: palette additions `colors.winterGreen = "2b3328"`, `colors.winterRed = "43242b"`, `colors.winterBlue = "252535"`, `colors.winterYellow = "49443c"` (verbatim from kanagawa.nvim colors.lua); new roles `diffAdd`, `diffDelete`, `diffChange`, `diffText`, `success`, `warning`, `info`; bat theme name `kanagawa` (HM `programs.bat.themes.kanagawa`); pinned upstream input = `fetchFromGitHub { owner = "rebelot"; repo = "kanagawa.nvim"; rev = <pinned in 2.1>; }` named `kanagawaSrc`.

Invariants:
- Existing palette values never change: `nix eval --impure --json --expr 'removeAttrs (import ./cells/common/theme.nix {}) ["name"]'` keeps every key/value from 0251f2f; only additions allowed.
- `nix run nixpkgs#alejandra -- --check <touched .nix>` == exit 0.
- `nix eval --raw .#nixosConfigurations.elster.config.system.build.toplevel.drvPath` succeeds (user runs it when the TPM cache is cold).
- One phase = one Conventional Commit with why-body + Co-Authored-By: Claude; nothing pushed by Claude.

## Phase 0 — Recon ⏳
0.1 Record current effective settings into the Progress section: `delta --show-config | grep -E 'syntax-theme|minus|plus|line-numbers'`, `bat --config-file; bat --list-themes | grep -i kanagawa`, `grep color_theme ~/.config/btop/btop.conf`, `nvim --headless -c 'lua print(vim.g.colors_name)' -c qa`.
0.2 Check that opencode's built-in theme list really has `kanagawa` in the version pinned by `cells/repo` (`opencode` binary: theme list or grep of the package's bundled themes). Record yes/no.
0.3 Check `programs.bat.themes` exists on HM 25.05 (`nix eval` the option's description via the elster config) and that HM rebuilds bat's cache on activation (`programs.bat` runs `bat cache --build`).
Exit criteria: Progress holds the four current values; 0.2 and 0.3 answered yes/no with the command used.

## Phase 1 — Palette additions ⏳
1.1 `cells/common/theme.nix`: add the four `winter*` colors and the roles `diffAdd = winterGreen`, `diffDelete = winterRed`, `diffChange = winterBlue`, `diffText = winterYellow`, `success = springGreen`, `warning = roninYellow`, `info = springBlue`.
1.2 Verify invariant 1 (old keys identical) and alejandra.
Exit criteria: old palette JSON is a subset of the new one; commit `feat(theme): diff and status roles`.

## Phase 2 — bat + delta ⏳
2.1 `cells/deck/homeModules/bat.nix`: `kanagawaSrc` pinned by rev + hash; `programs.bat.themes.kanagawa = { src = kanagawaSrc; file = "extras/tmTheme/kanagawa.tmTheme"; }`; `programs.bat.config.theme = "kanagawa"`.
2.2 `cells/deck/homeModules/git.nix` delta options: `syntax-theme = "kanagawa"`; `minus-style = "syntax #${roles.diffDelete}"`, `plus-style = "syntax #${roles.diffAdd}"`, `minus-emph-style`/`plus-emph-style` from `diffText` (or a brighter pair, user picks at review); `line-numbers-minus-style = "#${roles.urgent}"`, `line-numbers-plus-style = "#${roles.accent}"`, `line-numbers-zero-style = "#${roles.muted}"`. Theme arrives via `inputs.cells.common.theme` (deck has no `theme` module arg).
2.3 Lazygit needs no change: its diffRenderers call delta, which reads the same git config.
Exit criteria: after user rebuild, `delta --show-config` shows `syntax-theme = kanagawa` and the palette hexes; `bat --list-themes | grep kanagawa` non-empty; lazygit diff screenshot has no pure red/green bgs.

## Phase 3 — btop from the palette ⏳
3.1 `cells/deck/homeModules/btop.nix`: write `~/.config/btop/themes/kanagawa.theme` (btop `theme[...]` keys) from `theme.roles`/`colors`, set `color_theme = "kanagawa"`; drop the by-name `kanagawa-wave`.
Exit criteria: `grep color_theme ~/.config/btop/btop.conf` == kanagawa; btop starts with no "theme not found" fallback.

## Phase 4 — neovim to kanagawa.nvim ⏳
4.1 Replace the catppuccin spec in `dotfiles/nvim/lua/custom/plugins/colorscheme/init.lua` with `rebelot/kanagawa.nvim` (theme "wave"), terminal_color_* from the same ANSI order as `theme.ansi`.
4.2 Port `hl_overrides.lua` (171 catppuccin refs) to kanagawa's `overrides(colors)` hook; port the 36 `catppuccin.palettes` calls in `ui.lua`, `editor.lua`, `utils-plugins/bufferline.lua`.
4.3 `lazy-lock.json` updated by `:Lazy sync` (user), catppuccin entry removed.
Exit criteria: `nvim --headless -c 'lua print(vim.g.colors_name)' -c qa` == `kanagawa`; `grep -rn catppuccin dotfiles/nvim` == empty; no Lua errors on start (`nvim --headless +qa 2>&1` empty).

## Phase 5 — opencode ⏳
5.1 If 0.2 == yes: `cells/workstation/home/dev/agents.nix` `opencodeTui.theme = "kanagawa"`. Else: generate a custom theme JSON from the palette into `~/.config/opencode/themes/`.
Exit criteria: opencode TUI starts with the Kanagawa bg #1F1F28.

## Phase 6 — colors → roles (stretch, only if a palette switch is planned) ⏳
6.1 Move the 57 `theme.colors.*` refs in `home/default.nix`, `desktop/{bar,launcher,torrent,notify,screenshot,qt,lock}.nix` onto roles, adding roles where none fits.
Exit criteria: `grep -rnE 'theme\.colors|\bc\.(sumi|fuji|wave|spring|...)' cells --include=*.nix` hits only `cells/common/theme.nix`; elster drvPath unchanged vs before the phase.

## Fallback at any phase
Phases are independent after Phase 1: stop anywhere and what is merged stays coherent. Minimum useful slice = Phase 1 + 2 (fixes the delta/lazygit colours), roughly one session.

## Progress
- 2026-09: plan written. Palette already moved to `cells/common/theme.nix` (0251f2f). Lazygit state persistence (`.local/state/lazygit`) fixed separately, not part of this plan.

Next: Phase 0.1 — read-only recon on elster (minutes). Then 0.2/0.3 → Phase 1.
Blocked on: nothing.
