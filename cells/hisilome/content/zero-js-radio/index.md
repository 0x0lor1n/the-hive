+++
title = "A Live Radio Page With Zero JavaScript"
date = 2026-09-15
description = "Progress bar, ticking clock, persistent player, a now-playing widget that refreshes every ten seconds, one-click copy, and no script-src in the CSP. Seven tricks: nginx SSI, Sec-Fetch-Dest, @property counters, :has(), and a liquidsoap that writes HTML."
[taxonomies]
tags = ["nojs", "html", "css", "nginx", "icecast", "liquidsoap", "zola", "nix", "nixos", "lain", "radio", "web"]
+++

The dedicated radio page on this site is showing: what's playing now, progress bar that is moving while the music is playing, growing clock, current number of listeners, broadcasting calendar. And the player keeps playing in the background while the visitor is going to other pages (blog for example). Usually couple hundred lines of javascript + webSocket connection would be needed for this.

Here the `Content-Security-Policy` is `default-src 'none'` plus fonts, styles,
images and media. No `script-src`, because there is nothing to allow.

> **KRITON.** Nothing to allow.
>
> **0x0lor1n.** Nothing. Zero. The browser is not permitted to run a single line of
> script on that page and it still ticks.
>
> **KRITON.** You sound like a man who has won something.

To be fair nobody forced me. I did not start my car with a position "fuck javascript man". I wanted to know how much live page you can pack on the server and CSS, so client will not have to run any code at all. For this site - it's possible. It uses seven tricks, but none of them is new - just never seen them together in one example.

Zola - builds static pages of site, liquidsoap + icecast - runs radio station + provides the stream to Icecast, nginx - serves all that stuff to end-users all is configured with just one nixos module and one process-compose.yaml for development loop.


> **KRITON.** Seven. You are going to walk me through seven.
>
> **0x0lor1n.** Yep. Nothing here is new, I want that on the record. I just had not
> seen them in one place before.
>
> **KRITON.** Then go.

## 1. The server renders HTML, because there is no client to render JSON

{{ d2(name="01-pipeline", alt="liquidsoap writes three HTML fragments into radio/state/ with atomic renames; nginx with ssi on includes them into live.html on every request; the browser shell embeds live.html in an iframe that refreshes every ten seconds while the audio element in the shell never reloads.") }}

Liquidsoap has functions to manipulate strings and write files. So you can make it on every track switch to write an HTML part containing only the paragraph inside nowplaying widget, without html/body tags around all atomically in a temporary directory so nobody reads a partially written file.

```liquidsoap
write = file.write.stream(atomic=true,
  temp_dir="radio/state/tmp-nowplaying",
  "radio/state/now-playing.txt")
```

It all comes down to nginx aggregating pieces of it with help of ssi, which is a module developed back in the 1990s and which nobody enables:

```html
<!--# include virtual="/state/now-playing.txt" -->
```

> **KRITON.** From the nineties.
>
> **0x0lor1n.** 1996 or so. It shipped, everyone moved on, it never left. It is sitting
> in every nginx build on earth doing nothing.
>
> **KRITON.** And this pleases you more than if it were new.
>
> **0x0lor1n.** Man, obviously.

## 2. The bar moves between refreshes

It's about one ~2KB request each ten seconds from each listener. For the abusive (~DoS) case just use limit_req and that's it.

> **KRITON.** Two kilobytes. Every ten seconds. Per person.
>
> **0x0lor1n.** Per person.
>
> **KRITON.** How many persons.
>
> **0x0lor1n.** We will get to that.

So 10sec interval is too big for a progress bar to look like it's moving However in css animations there is such thing animation-delay property and if you specify a negative value, then the animation starts partway through its cycle instead of from the beginning. Liquidsoap writes both the overall duration of current track + the offset time into the fragment as CSS custom properties.

```html
<span class="rc-fill" style="--dur:213s;--elapsed:-87s"></span>
```

So basically the bar starts at 87 seconds out of 213 and ends at the same moment when the track ends. Then once the frame gets reloaded ten seconds later it has new values for duration/elapsed time, so the bar falls within ~one frame accuracy on the place where it arrived by itself, so there is no visible jump.

> **KRITON.** The bar does not know what the music is doing.
>
> **0x0lor1n.** No. It is dead reckoning. It gets told where it is every ten seconds
> and guesses in between.
>
> **KRITON.** So it can be wrong.
>
> **0x0lor1n.** If the stream stutters it drifts, up to ten seconds, until the next
> fragment straightens it out.
>
> **KRITON.** And the listener sees a bar that is confidently in the wrong place.
>
> **0x0lor1n.** The listener sees a bar that is mostly right and does not cost them a
> WebSocket. Can you trash it a bit harder, I am taking notes.

## 3. The clock is the same trick, one level uglier

The clock is the same idea, except you cannot animate text. What you can animate is a registered custom property of type `<integer>`, and feed it to a CSS counter:

```css
@property --m { syntax: "<integer>"; initial-value: 0; inherits: false; }
@property --s { syntax: "<integer>"; initial-value: 0; inherits: false; }
.rc-m { counter-reset: m var(--m); }
.rc-m::after { content: counter(m); }
.rc-s { counter-reset: s var(--s); }
.rc-s::after { content: counter(s, decimal-leading-zero); }
@keyframes rc-min { from { --m: 0 } to { --m: var(--tm) } }
```

Minutes run with `steps(N)` over N*60 seconds, seconds with `steps(60)` over 60s infinite, both offset by the elapsed time. Liquidsoap writes the `animation:` shorthand into the style attribute per track. Because `@property` registers the type, the browser interpolates integers instead of flipping at 50%.

`prefers-reduced-motion: reduce` sets `animation-play-state: paused` on all of it. The bar still shows the right position, because a paused animation stays at its delayed start point.

> **KRITON.** You animate a number you cannot see, and then you show it.
>
> **0x0lor1n.** That is exactly it.
>
> **KRITON.** Is that clever or is that a workaround.

## 4. The widget reloads itself, and two details cost me an evening

It rly just reloads itself with a meta refresh in ten second interval. All the widget is residing within it own small html document, that's floating in an iframe, so the parent page does not get re-rendered or anything when the widget updates. It was setting up ~10min. The other part of the evening was for two more details:

- Styles are inlined, not `<link>`ed. With a linked stylesheet every reload
  painted one unstyled frame. Ten seconds apart. A flash, then nothing, then a
  flash.
- `background: transparent` on the frame body, so the console shows through and
  the frame is not a visible rectangle sitting on the page.

> **KRITON.** An evening for two lines.
>
> **0x0lor1n.** An evening for finding out it was two lines. I was staring at a flicker
> I could not reproduce on demand. You sit there refreshing and waiting to catch
> it, and it happens when you look away.
>
> **KRITON.** What did you do while you waited.
>
> **0x0lor1n.** Put on Nas. Illmatic, the whole thing. Did you know NY State of Mind
> was recorded on the first take? Goat level.

## 5. The player survives navigation

An HTML audio element gets destroyed with the page it resides in - thats why almost all of nearly every internet radio website is just a SPA. Without javascript there is nothing but a frame that remains after navigating between pages, so they have a frameset: an outer document with a player + iframe named content in center and all links on site are pointing to this frame.

The challenging part is the url. If you come from a visitor - he comes with /salt-fiber-bypass/ URL to our server, then we must return him the shell document with his post in it; then the frame will make the same URL request and must get just the post without the shell. Same URL - two different responses, nginx is choosing which one to respond based on a unique header set by browser: Sec-Fetch-Dest (document for top level navigation, iframe for frame).

{{ d2(name="02-sec-fetch-dest", alt="The same GET /salt-fiber-bypass/ arrives at nginx three ways: with Sec-Fetch-Dest document from a top-level navigation, with Sec-Fetch-Dest iframe from the shell's frame, or with no header from curl and crawlers. A map on the header routes the first to /listen/index.html, the shell, whose iframe then requests the same URL again; the other two get the bare post.") }}

```nginx
map "$http_sec_fetch_dest$uri" $shell_page {
  ~^document.*/$  /listen/index.html;
  default         /__none;
}
```

When a request comes from a curl like client, robot or rss reader, old safari versions: they don't send the custom header indicating modern browser, so no love and attention for them - just serve them the raw html page which is what they want anyway. Also note that pages generated by Zola are served with a trailing slash (/), meaning requests to assets and /stream.* will never match the map.

Sec-Fetch-Dest works like a server-side media query: same URL, different skin of the page, depending on where you include it from.

> **KRITON.** And the address in the window?
>
> **0x0lor1n.** Ah.
>
> **KRITON.** Ah.
>
> **0x0lor1n.** The address bar never changes. You navigate inside the frame, the bar
> stays where you came in. Reload gives you the right page, the shell reads the
> real request URI. But copy the address after a few clicks and you hand someone
> the wrong post.
>
> **KRITON.** You knew this and shipped it.
>
> **0x0lor1n.** I knew it and shipped it.
>
> **KRITON.** Why is that acceptable to you?

## 6. The files panel: the browser keeps the state, CSS reads it

The console has a "files: list" toggle that opens a panel. That is a `<details>`; the browser owns the open/closed state, no code of mine. What used to need JS is making *other* elements react to it, and `:has()` now does that:

```css
.frame:has(.sc-toggle[open]) .shell-content { margin-top: var(--panel-h); }
.console:has(.sc-toggle[open]) { border-bottom-left-radius: 0; border-bottom-right-radius: 0; }
```

The content frame slides down, the console squares its corners to meet the panel, the glow stops at the seam. One attribute the browser flips. The rest is selectors.

## Not one of the seven: diagrams as text

The d2 diagrams in fiber post are not "embedded" as images. It's a Zola shortcode that does load_data with path to svg + safe filter + inline it in page. Like that the labels on diagram are clickable/selectable, browser find (Ctrl+F) finds them and the theme font is used for diagram text. The .d2 sources live in same directory as post's index.md file. Build-site script builds d2's into svgs before running zola build command.

It's not exactly a no-JS trick, but it's the same spirit: do everything at build time, so what you ship is a document, not a viewer app.

> **KRITON.** You said seven.
>
> **0x0lor1n.** This one is not a trick, it is a habit. Do the work at build time, ship
> a document, not a viewer. Same church, different pew.
>
> **KRITON.** So eight.
>
> **0x0lor1n.** Seven and a habit.

## 7. Copy without a copy button

You need a copy button? Navigator.clipboard API! What you can have is: CSS property user-select: all; Which means one click - entire element gets selected; then Ctrl+C does the job. And CSS property cursor: copy; That basically means to the human: that's what this will do Look at the permalink under each post title on this site. Look at every code block on this site.

```css
pre code { user-select: all; cursor: copy; }
pre::after { content: "Copy"; }
pre:active::after { content: "Ctrl+C"; }
```

The "Copy" tab on a corner of a code block is just a CSS ::after pseudo element. It belongs to the block, so you can click it and it will select the entire block like anywhere else on the block. Meaning: it does not have any different behaviour on click. It's only informative indication for the user where to click. On mouseDown event "Ctrl+C" text is displayed as a feedback that there is one more step in copypaste process.

The lang tab on the left has similar approach - content: attr(data-lang) on ::before pseudo element to get the language name from the attribute that is set by default by Zola on `<code>` element.

> **KRITON.** So the button does not copy.
>
> **0x0lor1n.** The button selects. You copy. It says so on the button once you press
> it.
>
> **KRITON.** A button that tells you it is not going to do the thing.
>
> **0x0lor1n.** A button that tells you the truth!

## What it cost

- A shell load is about ten requests (page, CSS, two fonts, two frames, their fragments), then one 2 KB fragment every ten seconds per listener.
- `limit_conn` on `/stream.*` and `limit_req` on pages. The box has one vCPU and icecast is set to 100 clients; before the limits, one client with a few hundred stream connections took the station down.
- `<audio preload="none">`: no stream bytes until play is pressed.
- No bundle, no hydration. `zola build` and a d2 loop.

## What doesn't work

- Bar and clock are dead reckoning between refreshes. If the stream stutters they drift up to ten seconds until the next fragment.
- The address bar never changes. Navigating inside the frame leaves the bar at whatever URL you entered on. Reload still gives you the right page (the shell reads `request_uri`), but copying the address after a few clicks hands out the wrong post.
- `@property` and `:has()` need a 2023-ish browser. Older ones get a static clock (`.rc-static` fallback), the bar at its start, and a console that doesn't slide.

## Then the part I do not have an answer for

The console has a listener count on it. It is a real number, icecast reports it, liquidsoap writes it into the fragment every ten seconds.

> **KRITON.** You said we would get to how many persons.
>
> **0x0lor1n.** It varies.
>
> **KRITON.** What is it right now.
>
> **0x0lor1n.** One.
>
> **KRITON.** And that one is you.
>
> **0x0lor1n.** Yes.
>
> **KRITON.** So you built a page that tells you, every ten seconds, and precisely,
> that nobody is listening.

The station layout is a tribute to [lainonlife](https://github.com/barrucadu/lainonlife). The shell-prompt navigation (`$ cd ./archive ./series ./tags`) is lifted from [geanmar.com](https://geanmar.com/). The frame trick is nothing new, we did SPAs like that before the word existed.

I know what the counter is for. It is for the version of this where the number is not one. That is not an answer to what he asked.

Config, liquidsoap script and nginx module: [the-hive/cells/hisilome](https://github.com/0x0lor1n/the-hive/tree/main/cells/hisilome).
