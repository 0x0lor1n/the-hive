# hisilome-feedback — a11y / SEO / caching fixes for hisilo.me, zero-JS preserved

Status: PLANNING (2026-09). Owner: user; Claude = executor.
Prereq: `cells/hisilome` builds (`nix build .#hisilome-site` or `dev hisilome && build-site`); zero-js-radio post committed (fd85e32). Do NOT touch the palette variable `--muted` before Phase 2 (25 call sites, decor vs text not yet split).

Target: hisilo.me passes the external feedback (WCAG AA text contrast, focus rings, aria on decor, canonical/OG, font/CSS caching, 404 page, favicon) with `script-src 'none'` unchanged and `live.html` no longer hand-synced with `style.css`.
Source refs: `cells/hisilome/templates/macros.html` (topbar/console/footer — every aria change lands here), `cells/hisilome/templates/base.html` (head), `cells/hisilome/static/style.css` (palette lines 40–60, `.summary` line 386, `--muted` 25×), `cells/hisilome/static/live.html` (two "keep in sync" comments, lines 63/71), `cells/hisilome/packages.nix` (`nginxLocations` line 142, `$shell_page` map line 123, `devNginxConf` line 188, `build-site` line 42), `cells/hisilome/nixosModules/nginx.nix` (prod `ssi on` line 47).
Repo: `cells/hisilome`; devshell `dev hisilome` → zola, d2, nginx, liquidsoap; `process-compose up` for the dev loop (port 8080 is the PC UI, `PC_PORT_NUM=8081` if busy); prod via `colmena apply --on osgiliath --verbose`.
Naming: CSS var `--meta` (readable grey for informational text; `--muted` stays for decor); nginx location names `= /style.css`, `~ ^/fonts/`; templates `templates/404.html`, `templates/live.html`, `templates/_live.css` (Tera include shared by `style.css` and `live.html`); per-post fragment `meta.html` (title+description, SSI-included by `/listen/index.html`); favicon `static/favicon.svg`.

Invariants:
- `curl -sI https://hisilo.me/ | grep -i content-security-policy` contains `script-src 'none'` (or no `script-src` at all with `default-src 'none'`) — never add one.
- `grep -c '<script' cells/hisilome/public -r` == 0 after `build-site`.
- `nix build .#colmenaHive.toplevel.osgiliath` succeeds before any `colmena apply`.
- `git -C cells/hisilome diff --stat content/` is empty inside Phases 1–3 except the commit in 1.1 — post text is not edited by this task.
- `vnu`/`validator.w3.org` errors on `/` and `/zero-js-radio/`: 0 (the h1 outline *warning* on index is accepted, see `templates/index.html` comment).

## Phase 1 — Quick wins, no design decisions ⏳
1.1 Commit the user's pending edits: `git -C cells/hisilome diff` = dash normalisation (— → -) in `content/zero-js-radio/index.md`, 6 lines. `git commit -m "hisilome: zero-js-radio — plain dashes"`.
1.2 `static/style.css` line 386: `.summary { color: var(--carp-yellow); }` → `color: var(--fg);` — post summary on the index reads in the same colour as body text inside a post. Check `--carp-yellow` is not orphaned elsewhere before removing anything (it isn't: `.sc-toggle[open]` uses it).
1.3 `templates/macros.html` `shell_topbar`: merge the two `<nav>` into one `<nav aria-label="Main">`; `$ cd`, `&& cd`, `.cursor` → `aria-hidden="true"`; social `<a title=...>` gets `aria-label` with the same string; every inline `<svg>` in topbar and `post_meta` gets `aria-hidden="true"`.
1.4 `shell_console`: `rc-br` bracket spans → `aria-hidden="true"`; `<audio ... aria-label="Cyberia radio stream">`.
1.5 `templates/base.html` head: `<link rel="canonical" href="{{ current_url | safe }}">`; `<link rel="preload" href="/fonts/iosevka-regular.woff2" as="font" type="font/woff2" crossorigin>`; `<meta name="theme-color" content="#16161d">`; replace `href="data:,"` with `<link rel="icon" type="image/svg+xml" href="/favicon.svg">`.
1.6 `static/favicon.svg`: 32×32, `--bg-dim` square, `_` or `][` in `--carp-yellow`, Iosevka not embeddable — use a path or generic monospace. No apple-touch-icon (PNG) in this phase.
1.7 `static/style.css`: global `:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px }` and `:focus:not(:focus-visible) { outline: none }` near the top of the reset; keep the existing `.prompt:focus-visible` / `.console-audio:focus` rules.
1.8 `packages.nix` `nginxLocations`: add `"= /style.css"` and `"~ ^/fonts/"` with `${pageLimit}` + `add_header Cache-Control "public, max-age=31536000, immutable";` + `${extraHeaders}`; add `error_page 404 /404.html;` at the `/` location (or server level in both `devNginxConf` and `nixosModules/nginx.nix`).
1.9 `templates/404.html`: extends `base.html`, prompt-styled body (`$ cd ./<path>` / `cd: no such file or directory`), link back to `/`. Zola emits `public/404.html` automatically.
1.10 Verify: `build-site`, `process-compose up`, `curl -sI localhost:8099/style.css | grep -i cache-control`, `curl -s -o /dev/null -w '%{http_code}' localhost:8099/nope/` == 404 with themed body, `curl -s localhost:8099/ | grep -c aria-hidden` ≥ 10. Screenshot index + a post via `browser_exec` for the summary colour.
Exit criteria: 1.1 committed on its own; one further commit `hisilome: feedback phase 1 — aria, canonical, preload, favicon, cache headers, 404`; `curl -sI /fonts/iosevka-regular.woff2` shows `immutable`; `/nope/` returns themed 404; index summary colour == `--fg`; invariants hold; deployed with `colmena apply --on osgiliath --verbose`.

## Phase 2 — Text contrast: split `--muted` into decor / `--meta` ⏳
2.1 Inventory the 25 `var(--muted)` sites in `static/style.css` (`grep -n 'var(--muted)'`) and classify each as decor (brackets, separators, tribute footer, tagcloud bg, `.sc-a`, svg fills) or text (dates, reading time, `.rc-clock`, listener count, `del`, "files:" label, meta line under titles). Write the table into this file under Progress.
2.2 Add `--meta: #9c9b93;` next to `--muted` (fujiGray lightened; 5.86:1 on `--bg`). Alternative if user prefers in-palette: `springViolet1 #938aa9` (4.3:1, fails AA by 0.2). Decision recorded in Progress before editing.
2.3 Replace `var(--muted)` → `var(--meta)` on the text sites only. `live.html` has its own copies of `.rc-clock` colours — patch there too (until Phase 3 removes the duplication).
2.4 Verify contrast: `browser_exec` computed colours on `.meta`, `.rc-clock`, `.rc-listeners`; ratio via a 10-line script (WCAG luminance formula) ≥ 4.5 for every text site; decor sites unchanged.
2.5 Screenshot before/after of `/` and `/zero-js-radio/` at 1280 and 390 px; user signs off on the look.
Exit criteria: every text-bearing `--muted` site ≥ 4.5:1 (table in Progress with measured ratios); no decor site changed; one commit `hisilome: feedback phase 2 — --meta for informational text`; deployed.

## Phase 3 — Build-time live.html + shell `<title>` from the post ⏳
3.1 Move `static/live.html` → `templates/live.html`; extract the shared rules (`@font-face` ×2, `.rc-*`, `.rc-clock`, track/fill colours — the two "keep in sync" blocks) into `templates/_live.css`; `templates/live.html` does `<style>{% include "_live.css" %}</style>`. Make `style.css` a template too (`templates/style.css` with `{% include "_live.css" %}` at the shared spot) rendered by a Zola page with `template = "style.css"` and `path = "/style.css"`, or keep static and have `build-site` concatenate — pick the one that keeps `get_hash(path="style.css")` working; record choice in Naming.
3.2 Remove the "keep in sync" comments and the line "Shell and `live.html` share a stylesheet by copy" from `content/zero-js-radio/index.md` `### What doesn't work` — this is the single allowed post edit; note it in Progress.
3.3 Per-post `meta.html`: Zola page template writes a sibling fragment (`templates/page.html` cannot emit two files — use a second output via `build-site`: for each `public/*/index.html` extract `<title>` and `<meta name=description>` with `sed`/`pup` into `public/*/meta.html`). Shell `/listen/index.html` head: `<!--# include virtual="${request_uri}meta.html" -->` guarded by `<!--# if expr="$request_uri = /^\/[^.]+\/$/" -->`, fallback `<title>{{ config.title }}</title>`. Prod `ssi on` already covers `/listen/` (nginx.nix line 47); check `devNginxConf` line 218 does the same.
3.4 OG tags into the same `meta.html`: `og:title`, `og:description`, `og:url`, `og:type=article`; no `og:image`.
3.5 Verify: `curl -s -H 'Sec-Fetch-Dest: document' localhost:8099/zero-js-radio/ | grep '<title>'` == post title; `curl -s localhost:8099/zero-js-radio/` (no header) unchanged; `diff <(sed -n '/rc-clock/,/}/p' public/style.css) <(... public/live.html)` empty.
Exit criteria: `static/live.html` gone; `grep -r 'keep in sync' cells/hisilome` == 0; shell document `<title>` == post title for every post in `public/*/`; one commit `hisilome: feedback phase 3 — live.css shared, shell title via SSI`; deployed.

## Not doing (decided 2026-09)
brotli (gzip is enough for 60 KB of HTML), JSON-LD, skip-link (no target inside the frame without JS), `aria-current` (shell does not know the page), hidden `<h1>` on index (see `templates/index.html` comment), apple-touch-icon PNG, `security.txt` (no contact decided).

## Fallback at any phase
Phase 1 alone closes 9 of 17 feedback items with no visual change; ship it and stop. Phase 2 can be shipped as the single line `--muted: #9c9b93` (all 25 sites lighter) if the split is not worth it.

## Progress
- 2026-09: plan written. Pending in worktree: 6-line dash edit in `content/zero-js-radio/index.md` (goes in 1.1). Feedback source: external reviewer, 17 items; 8 accepted into Phases 1–3, rest in "Not doing".

Next: Phase 1.1 — `git -C cells/hisilome commit content/zero-js-radio/index.md`, then 1.2 → 1.10 in the same session.
Blocked on: nothing.
