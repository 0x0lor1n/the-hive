# hisilome-feedback — a11y / SEO / caching fixes for hisilo.me, zero-JS preserved

Status: PHASE 3 COMMITTED (c5a3d37, 2026-09-21), NOT YET DEPLOYED — user runs colmena. Owner: user; Claude = executor.
Prereq: `cells/hisilome` builds (`nix build .#hisilome-site` or `dev hisilome && build-site`); zero-js-radio post committed (fd85e32). Do NOT touch the palette variable `--muted` before Phase 2 (25 call sites, decor vs text not yet split).

Target: hisilo.me passes the external feedback (WCAG AA text contrast, focus rings, aria on decor, canonical/OG, font/CSS caching, 404 page, favicon) with `script-src 'none'` unchanged and `live.html` no longer hand-synced with `style.css`.
Source refs: `cells/hisilome/templates/macros.html` (topbar/console/footer — every aria change lands here), `cells/hisilome/templates/base.html` (head), `cells/hisilome/static/style.css` (palette lines 40–60, `.summary` line 386, `--muted` 25×), `cells/hisilome/static/live.html` (two "keep in sync" comments, lines 63/71), `cells/hisilome/packages.nix` (`nginxLocations` line 142, `$shell_page` map line 123, `devNginxConf` line 188, `build-site` line 42), `cells/hisilome/nixosModules/nginx.nix` (prod `ssi on` line 47).
Repo: `cells/hisilome`; devshell `dev hisilome` → zola, d2, nginx, liquidsoap; `process-compose up` for the dev loop (port 8080 is the PC UI, `PC_PORT_NUM=8081` if busy); prod via `colmena apply --on osgiliath --verbose`.
Naming: CSS var `--meta` (readable grey for informational text; `--muted` stays for decor); nginx location names `= /style.css`, `~ ^/fonts/`; templates `templates/404.html`, `templates/live.html` (frame document with a `<!--@css@-->` marker; NOT a Tera template), `templates/_live.css` (frame-only rules; NOT a Tera include). Decision 3.1: `style.css` stays static (so `get_hash(path="style.css")` keeps working); `build-site` assembles `public/live.html` = `templates/live.html` with `@font-face`×2 + the `:root` colour tokens sed'd out of `public/style.css` + `templates/_live.css` spliced at the marker. Per-page fragment `<page>/meta.html` (title, description, og:title/description/url/type) = the lines between `<!--meta-->`/`<!--/meta-->` in `base.html` (block `head_meta`), cut by `build-site` from every `index.html`; SSI-included by `/listen/index.html`, nginx location `~ /meta\.html$` (`ssi off`, `log_not_found off`); favicon `static/favicon.svg`.

Invariants:
- `curl -sI https://hisilo.me/ | grep -i content-security-policy` contains `script-src 'none'` (or no `script-src` at all with `default-src 'none'`) — never add one.
- `grep -c '<script' cells/hisilome/public -r` == 0 after `build-site`.
- `nix build .#colmenaHive.toplevel.osgiliath` succeeds before any `colmena apply`.
- `git -C cells/hisilome diff --stat content/` is empty inside Phases 1–3 except the commit in 1.1 — post text is not edited by this task.
- `vnu`/`validator.w3.org` errors on `/` and `/zero-js-radio/`: 0 (the h1 outline *warning* on index is accepted, see `templates/index.html` comment).

## Phase 1 — Quick wins, no design decisions ✅ (97ac3cc, deployed 2026-09-21)
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

## Phase 2 — Text contrast: split `--muted` into decor / `--meta` ✅ (b6876d9, deployed 2026-09-22)
2.1 Inventory the 25 `var(--muted)` sites in `static/style.css` (`grep -n 'var(--muted)'`) and classify each as decor (brackets, separators, tribute footer, tagcloud bg, `.sc-a`, svg fills) or text (dates, reading time, `.rc-clock`, listener count, `del`, "files:" label, meta line under titles). Write the table into this file under Progress.
2.2 Add `--meta: #9c9b93;` next to `--muted` (fujiGray lightened; 5.86:1 on `--bg`). Alternative if user prefers in-palette: `springViolet1 #938aa9` (4.3:1, fails AA by 0.2). Decision recorded in Progress before editing.
2.3 Replace `var(--muted)` → `var(--meta)` on the text sites only. `live.html` has its own copies of `.rc-clock` colours — patch there too (until Phase 3 removes the duplication).
2.4 Verify contrast: `browser_exec` computed colours on `.meta`, `.rc-clock`, `.rc-listeners`; ratio via a 10-line script (WCAG luminance formula) ≥ 4.5 for every text site; decor sites unchanged.
2.5 Screenshot before/after of `/` and `/zero-js-radio/` at 1280 and 390 px; user signs off on the look.
Exit criteria: every text-bearing `--muted` site ≥ 4.5:1 (table in Progress with measured ratios); no decor site changed; one commit `hisilome: feedback phase 2 — --meta for informational text`; deployed.

## Phase 3 — Build-time live.html + shell `<title>` from the post ✅ code (c5a3d37), deploy pending
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

- 2026-09-21: Phase 1 done. 1.1 committed separately (dash edit); 1.2–1.9 in `97ac3cc` (5 files + 2 new: `static/favicon.svg`, `templates/404.html`). Deviations from plan: `<link rel=canonical>` guarded with `{% if current_url %}` (404 template has no `current_url`); `.topbar nav` became `display:flex; gap:0.5rem` after the two-nav merge (replaces the margin-right/:last-child rules). Verified on dev-nginx :8099: vnu `--errors-only` = 0 on `/`, `/zero-js-radio/`, `/nope/`, shell; `Cache-Control: public, max-age=31536000, immutable` on `/style.css` and `/fonts/iosevka-regular.woff2`; `/nope/` → 404 themed in the frame, shell wraps it with 200; `.summary` == `--fg`; 18 `aria-hidden` on index; 0 `<script` in public/. Screenshots `.scratch/p1-{index,post,404}.png` (untracked; delete when done). Note: `mcp__browser_exec` harness is broken on this host (daemon won't start) — used headless chromium via `nix shell nixpkgs#chromium` instead.

- 2026-09-21: Phase 1 deployed by user (colmena → osgiliath). Prod verified: `immutable` on `/style.css` and `/fonts/iosevka-regular.woff2`; `/favicon.svg` 200 `image/svg+xml`; `/nope/` → 404 themed (`<code>./nope/</code>`), shell 200; head has icon/canonical/preload/theme-color; `nav aria-label="Main"`; `.summary` = `--fg`; 0 `<script`; CSP unchanged (`default-src 'none'`). aria-hidden count is 15 on prod vs 18 on dev — dev index includes a draft post (3 post_meta svgs), not a diff in markup.

- 2026-09-22: Phase 2.1 done — inventory of the 25 `var(--muted)` sites (24 in `static/style.css` + 1 in `static/live.html`). Base `--muted` = `--fuji-gray #727169`: 3.33:1 on `--bg #1f1f28`, 3.67 on `--bg-dim #16161d` — fails AA everywhere.

| line | selector | prop | class | what |
|---|---|---|---|---|
| 172 | `.cmd` | color | text | `$ cd` / `$ link:` prompt words (topbar copy is aria-hidden, but page.html/404 copies are read) |
| 205/210/215 | `h1/h2/h3:before` | color | decor | `# ` `## ` `### ` markers |
| 336 | `.meta` | color | text | date, reading time under titles |
| 355 | `.meta svg` | fill | decor | icons beside meta text |
| 359 | `.meta a` | color | text | links in meta line |
| 370 | `.permalink` | color | text | copyable URL line |
| 382 | `.permalink a` | color | text | open-in-tab link in permalink |
| 472 | `del` | color | text | struck prose |
| 480 | `.footnotes` | color | text | footnote prose |
| 530 | `pre code[data-lang]::before` | color | text | language label on code blocks |
| 575 | `.ident` | color | text | `0x0lor1n@` in topbar |
| 625 | `.socials svg` | fill | decor | social icons (hover → `--hover`) |
| 633 | `footer` | color | text | footer prose |
| 689 | `.lain-tribute-text` | color | decor | tribute line ("tribute footer" per plan; *judgement call*, see below) |
| 704 | `.lain-tribute-quote` | color | decor | tribute quote (same) |
| 869 | `.console-meta` | color | text | `channel:` / `link:` labels under player |
| 911 | `.sc-toggle > summary` | color | text | `files: list` toggle |
| 1013 | `.sc-body` | color | text | schedule list body |
| 1037 | `.sc-w` | color | text | schedule time column |
| 1047 | `.sc-a` | color | decor | schedule album column (per plan `.sc-a` = decor; *judgement call*) |
| 1269 | `figure.pair figcaption` | color | text | captions |
| 1476 | `.tag-n` | color | text | post count on tags ("the exact count … not readable" comment — meant to be read) |
| live.html:95 | `.rc-clock` | color | text | clock in live frame (style.css `.rc-clock` at 1132 is already `--boat-yellow`) |

Totals: 17 text → `--meta`, 8 decor stay `--muted`. Note: `.rc-listeners` from plan 2.4 does not exist in the repo — drop from the check list. Contrast candidates (WCAG, on `--bg` / `--bg-dim`): `#9c9b93` 5.86 / 6.45; `springViolet1 #938aa9` 5.02 / 5.53 (plan's "4.3" figure was measured on a lighter surface; on the real backgrounds it passes AA too).

- 2026-09-22: Phase 2.2–2.5 done, commit `b6876d9` (2 files: `static/style.css`, `static/live.html`; `content/` untouched). Decision: `--meta: #9c9b93` (user). Tribute lines and `.sc-a` left decor (user did not answer the second question; plan default). Measured via CDP on dev-nginx :8099 inside the content iframe (`.scratch/cdp.mjs`, headless chromium from `nix shell nixpkgs#chromium`): every text site `rgb(156,155,147)` on `rgb(31,31,40)` = **5.86:1** (`.cmd .ident footer .console-meta .sc-toggle>summary .meta .meta a .permalink .permalink a pre code[data-lang]::before`; `del .footnotes figcaption .tag-n` have no instance on the two pages — same rule, same value); live-frame `.rc-clock` = `rgb(156,155,147)`. Decor unchanged at 3.33 (`h1/h2::before .meta svg .socials svg .lain-tribute-*`). `build-site` OK, 0 `<script` in public/, 16 `var(--meta)` + 8 `var(--muted)` in style.css. Screenshots `.scratch/p2-{index,post,live}-{1280,390}.png` (untracked); p1 screenshots deleted. Look: grey meta now reads clearly, no layout change.

- 2026-09-22: deployed; prod verified: style.css 16 `var(--meta)` / 8 `var(--muted)`, live.html has `#9c9b93`.

- 2026-09-21: Phase 3 done, commit `c5a3d37` (8 files: `static/live.html` deleted; `static/style.css` −118 lines (the dead `/* inside live.html */` `.rc-*` block — nothing in the shell used it; `.rc-br`/`.rc-on` stay); new `templates/_live.css`, `templates/live.html`; `templates/base.html` (`head_meta` block + og:*), `templates/listen.html` (SSI include), `packages.nix` (build-site post-step, `volatile` on the `$shell_page` map, `~ /meta\.html$` location); `content/zero-js-radio/index.md` −1 line = the allowed edit). Deviations from plan: (a) style.css NOT made a Zola template — a `content/style.md` with `path="style.css"` breaks `get_hash` and lands in sitemap.xml; static file + build-site splice instead. (b) og:* on all pages, not only posts (`website` for index/tags, `article` for posts; og:description only where a description exists — tag pages have none). (c) Two nginx fixes the plan did not foresee: the SSI subrequest for `<page>/meta.html` inherited the parent's cached `$shell_page` (= `/listen/index.html`) → "subrequests cycle"; fixed with `volatile;` in the map. And a bare `$` in the SSI regex is read by nginx as a variable → `\$`. Guard regex: `^(?<meta_page>\/([^?.]+\/)?)(\?|\$)` — captures the path before any `?`, so `/post/?x=1` still gets the post's title and no query can redirect the include. (d) `--meta` in live.html is now the same token as style.css (5.86:1), and `.rc-clock` colour comes from `_live.css` only.
  Verified on dev-nginx :8099 (restarted — the conf is a derivation): shell `<title>` for `/`, `/zero-js-radio/`, `/salt-fiber-bypass/`, `/tags/css/`, `/tags/`, `/zero-js-radio/?x=1` == the page's own title + og:*; `/nope/` and `/listen/` fall to the stub `Hísilómë — radio`; bare `curl` (no Sec-Fetch-Dest) unchanged; `grep -c '<script' public -r` == 0; `grep -r 'keep in sync' cells/hisilome` == 0; normalised CSS diff old `static/live.html` vs new `public/live.html`: only additions (`font-style: normal` on @font-face, full palette in `:root`) — no rule lost; vnu `--errors-only` = 0 on `/`, `/zero-js-radio/`, `/nope/`, bare post (live.html reports `@property` unknown to vnu's CSS parser — same as before, ignore). `nix build` of `cell.packages.site` OK (`/nix/store/9lgc37yr27gsyqs2s8syr98wxq7yipzr-hisilome-site`), live.html byte-identical to dev. `nix build .#colmenaHive.toplevel.osgiliath` NOT run: eval needs the TPM-PIN secrets cache, which the agent cannot create — user must run it before `colmena apply`.

Next: user: `nix build .#colmenaHive.toplevel.osgiliath && colmena apply --on osgiliath --verbose`; then prod check: `curl -s -H 'Sec-Fetch-Dest: document' https://hisilo.me/zero-js-radio/ | grep '<title>'` == post title; `curl -s https://hisilo.me/live.html | grep -c rc-clock` == 2; `curl -sI https://hisilo.me/zero-js-radio/meta.html` 200 (no SSI, plain). Then Phase 4 (if any in the external feedback list) or close.
Blocked on: deploy (TPM PIN, user-only).
