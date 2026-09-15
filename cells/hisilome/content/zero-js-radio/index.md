+++
title = "A Live Radio Page With Zero JavaScript"
date = 2026-10-01
description = "Progress bar, ticking clock, persistent player, a now-playing widget that refreshes every ten seconds, one-click copy, and no script-src in the CSP. Seven tricks: nginx SSI, Sec-Fetch-Dest, @property counters, :has(), and a liquidsoap that writes HTML."
[taxonomies]
tags = ["nojs", "html", "css", "nginx", "icecast", "liquidsoap", "zola", "nix", "nixos", "lain", "radio", "web"]
+++

This site's [radio page](/listen/) shows the current track, a progress bar that moves, a clock that counts up, the listener count, the schedule, and the player keeps playing while you read the blog. Normally that's a few hundred lines of JavaScript and a WebSocket.

Here the `Content-Security-Policy` is `default-src 'none'` plus fonts, styles, images and media. No `script-src`, because there is nothing to allow.

I didn't set out to avoid JS on principle. I wanted to know how much of a live page the server and CSS can carry before the client has to run code. For a page this size the answer is all of it. Seven tricks. None of them new, I just had not seen them together.

Stack: [Zola](https://www.getzola.org/) renders the static pages, [liquidsoap](https://www.liquidsoap.info/) runs the station and feeds icecast, nginx serves everything. One NixOS module, one `process-compose.yaml` for the dev loop.

## 1. liquidsoap writes HTML, nginx SSI includes it

{{ d2(name="01-pipeline", alt="liquidsoap writes three HTML fragments into radio/state/ with atomic renames; nginx with ssi on includes them into live.html on every request; the browser shell embeds live.html in an iframe that refreshes every ten seconds while the audio element in the shell never reloads.") }}

Without a client to render JSON, the server renders HTML. liquidsoap has string functions and a file writer, so on every track change it writes a fragment: the `<p>`s that go inside the widget, with no `<html>` around them.

```liquidsoap
write = file.write.stream(atomic=true,
  temp_dir="radio/state/tmp-nowplaying",
  "radio/state/now-playing.txt")
```

`atomic=true` renames the file into place, so nginx never serves a half-written fragment. One gotcha: liquidsoap hardcodes the temp filename to `atomic.write`, so each writer needs its own `temp_dir` or two threads clobber each other. There are three writers: now-playing per track, the console every second, the schedule every ten.

nginx assembles them with [SSI](https://nginx.org/en/docs/http/ngx_http_ssi_module.html), a module from the 90s that most people have never turned on:

```html
<!--# include virtual="/state/now-playing.txt" -->
```

`ssi on;` in the server block, a location for `/state/` pointing at liquidsoap's directory. That's the whole plumbing.

## 2. A ten-second `<meta refresh>` inside an iframe

The widget has to update. `<meta http-equiv="refresh" content="10">` is the oldest way and it works fine when the reloading document is small and isolated. So the now-playing block is its own document, `live.html`, in an `<iframe>` inside the console. It reloads itself. The page around it doesn't move.

Two details cost me an evening:

- Styles are inlined, not `<link>`ed. With a linked stylesheet each reload painted an unstyled frame for a moment. With `<style>` in `<head>` the reload is invisible.
- `background: transparent` on the frame body, so the console's background shows through and the frame isn't a visible rectangle.

Cost: one ~2 KB request per listener every ten seconds. `limit_req` for the abusive case, that's it.

## 3. Progress bar and clock between refreshes: negative `animation-delay`

Ten seconds is too coarse for a progress bar. CSS animations have an `animation-delay`, and a negative delay starts the animation partway through. liquidsoap writes, per track, the duration and how much had elapsed at write time:

```html
<span class="rc-fill" style="--dur:213s;--elapsed:-87s"></span>
```

```css
.rc-fill {
  animation: rc-fill var(--dur, 0s) linear var(--elapsed, 0s) forwards;
}
@keyframes rc-fill { from { width: 0 } to { width: 100% } }
```

The bar starts at 87/213 and reaches the end when the track does. When the frame reloads it gets fresh numbers and lands within a frame of where it already was.

The clock is the same idea, except you cannot animate text. What you can animate is a registered custom property of type `<integer>` and feed it to a CSS counter:

```css
@property --m { syntax: "<integer>"; initial-value: 0; inherits: false; }
@property --s { syntax: "<integer>"; initial-value: 0; inherits: false; }
.rc-m { counter-reset: m var(--m); }
.rc-m::after { content: counter(m); }
.rc-s { counter-reset: s var(--s); }
.rc-s::after { content: counter(s, decimal-leading-zero); }
@keyframes rc-min { from { --m: 0 } to { --m: var(--tm) } }
```

Minutes run with `steps(N)` over `N*60` seconds, seconds with `steps(60)` over `60s` infinite, both offset by the elapsed time. liquidsoap writes the `animation:` shorthand into the `style` attribute per track. Because `@property` registers the type, the browser interpolates integers instead of flipping at 50 %.

`prefers-reduced-motion: reduce` sets `animation-play-state: paused` on all of it. The bar still shows the right position, because a paused animation stays at its delayed start point.

## 4. The player survives navigation: `Sec-Fetch-Dest` picks the page

An `<audio>` element dies with its page. That is why every radio site ends up an SPA. Without JS the only thing that survives navigation is a frame, so a frame it is.

So there is a shell: topbar, console with the player, footer, and an `<iframe name="content">` in the middle. Every link in the shell has `target="content"`. Blog pages load into the frame; the audio element in the shell is never touched.

The hard part is the URL.

Land on `/salt-fiber-bypass/` directly and you should get the shell with that post in the frame, and the frame should request the same URL and get the bare post. Same URL, two responses, decided by nginx from one header:

{{ d2(name="02-sec-fetch-dest", alt="The same GET /salt-fiber-bypass/ arrives at nginx three ways: with Sec-Fetch-Dest document from a top-level navigation, with Sec-Fetch-Dest iframe from the shell's frame, or with no header from curl and crawlers. A map on the header routes the first to /listen/index.html, the shell, whose iframe then requests the same URL again; the other two get the bare post.") }}

```nginx
map "$http_sec_fetch_dest$uri" $shell_page {
  ~^document.*/$  /listen/index.html;
  default         /__none;
}
```

[`Sec-Fetch-Dest`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Sec-Fetch-Dest) is set by the browser: `document` for a top-level navigation, `iframe` for a frame load. A top-level navigation to any `/`-terminated page gets the shell. The shell's frame does `src="<!--# echo var="request_uri" -->"`, SSI again; `$request_uri` is never rewritten, so it is the URL the user typed. That request carries `Sec-Fetch-Dest: iframe` and falls through to the real page.

curl, crawlers, RSS readers, old Safari: no header, bare page. Which is what they wanted anyway. Zola pages end in `/`, so assets and `/stream.*` never match the map.

`Sec-Fetch-Dest` works like a server-side media query: the same URL renders differently depending on where it is embedded.

## 5. `<details>` as state, `:has()` to react to it

The console has a "files: list" toggle that opens a panel. That is a `<details>`; the browser owns the open/closed state. What used to need JS is making *other* elements react to it, and `:has()` now does that:

```css
.frame:has(.sc-toggle[open]) .shell-content { margin-top: var(--panel-h); }
.console:has(.sc-toggle[open]) { border-bottom-left-radius: 0; border-bottom-right-radius: 0; }
```

The content frame slides down, the console squares its corners to meet the panel, the glow stops at the seam. One attribute the browser flips. The rest is selectors.

## 6. Diagrams inlined, so they're text

The d2 diagrams in the fiber post aren't `<img>`. A Zola shortcode does `load_data(path=…svg) | safe` and inlines the SVG into the page. Labels on the diagram are selectable, Ctrl+F finds them, the theme's fonts apply. The `.d2` sources live next to the post's `index.md` and `build-site` compiles them before `zola build`.

Not a no-JS trick as such. Same habit though: do the work at build time, ship a document, not a viewer.

## 7. One-click copy without a button

A copy button needs `navigator.clipboard`. What you can have instead is `user-select: all`: one click selects the whole element, Ctrl+C does the rest. `cursor: copy` tells the reader that's what will happen. The permalink under each post title works like that, and so does every code block on this site.

The "Copy" tab in the corner of a block is a `::after` pseudo-element. It is part of the block, so clicking it selects the block like clicking anywhere else would; it only tells the reader where to click. While the mouse is down it says `Ctrl+C`, which is the one thing left to do:

```css
pre code { user-select: all; cursor: copy; }
pre code[data-lang]::after { content: "Copy"; }
pre code[data-lang]:active::after { content: "Ctrl+C"; }
```

The cost: you can't drag one line out of a block. I tried two behaviours, normal selection on multi-line blocks and one-click on one-liners via `:has(> .giallo-l:only-of-type)` on the highlighter's line spans. It worked. It also confused me, on my own site, because two identical-looking blocks behaved differently. Snippets here are meant to be taken whole. One behaviour.

The language tab on the left is the same idea, `content: attr(data-lang)` on `::before`, from the attribute Zola already puts on `<code>`.

## What it cost

- A shell load is about ten requests (page, CSS, two fonts, two frames, their fragments), then one 2 KB fragment every ten seconds per listener.
- `limit_conn` on `/stream.*` and `limit_req` on pages. The box has one vCPU and icecast is set to 100 clients; before the limits, one client with a few hundred stream connections took the station down.
- `<audio preload="none">`: no stream bytes until play is pressed.
- No bundle, no hydration. `zola build` and a d2 loop.

## What doesn't work

- Bar and clock are dead reckoning between refreshes. If the stream stutters they drift up to ten seconds until the next fragment.
- The address bar never changes. Navigating inside the frame leaves the bar at whatever URL you entered on. Reload still gives you the right page (the shell reads `request_uri`), but copying the address after a few clicks hands out the wrong post.
- `@property` and `:has()` need a 2023-ish browser. Older ones get a static clock (`.rc-static` fallback), the bar at its start, and a console that doesn't slide.
- Shell and `live.html` share a stylesheet by copy. The comment says "keep in sync". It will drift.

## Credits

The station layout is a tribute to [lainonlife](https://github.com/barrucadu/lainonlife). The shell-prompt navigation (`$ cd ./archive ./series ./tags`) is lifted from [geanmar.com](https://geanmar.com/). The frame trick is nothing new, we did SPAs like that before the word existed.

Config, liquidsoap script and nginx module: [the-hive/cells/hisilome](https://github.com/0x0lor1n/the-hive/tree/main/cells/hisilome).
