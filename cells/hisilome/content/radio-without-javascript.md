+++
title = "A Radio That Survives Navigation, Without JavaScript"
date = 2026-08-30
description = "Keeping an audio stream alive across page loads using a frame, nginx SSI, and the plain HTML5 audio element. No script tags."

[taxonomies]
tags = ["no-js", "nginx", "radio"]
+++
There is a radio playing on this page. Click a link — any link — and it keeps playing. No script runs to make that happen.

This is the part everyone reaches for a single-page app to solve. You don't need one.

## The problem

A page load destroys the document. The `<audio>` element goes with it, along with its buffer and its open connection to the stream. Click a link, the music stops. That is why every web radio you have used is either a single-page app or a popup window from 2003.

The usual fix is to stop navigating: intercept every click, fetch the new content, swap it into the DOM, and keep the audio element alive because the document never changed. That is a framework, a router, and a few hundred kilobytes of JavaScript to avoid reloading a page.

The other fix is to not put the audio in the document that navigates.

## The backend is a real radio

Worth stating first, because it changes what the frontend has to do.

[Liquidsoap](https://www.liquidsoap.info/) reads a playlist and encodes it into [Icecast](https://icecast.org/), continuously, whether or not anyone is listening. Icecast fans that one stream out to every listener. The music plays to an empty room at 4am.

```liquidsoap
radio = playlist(mode="randomize", "music/")
radio = amplify(0.5, radio)
radio = mksafe(radio)

output.icecast(
  %mp3,
  host="127.0.0.1", port=8000,
  mount="/stream.mp3",
  radio
)
```

Nothing the browser does can pause it, skip it, or rewind it. There is no message a client can send that would. Pressing stop only closes your own socket — the broadcast carries on without you, and when you come back you rejoin wherever it has got to. That is what makes it a radio rather than a playlist with a shuffle button.

## The player is one HTML tag

```html
<audio controls preload="none">
  <source src="/stream.mp3" type="audio/mpeg">
</audio>
```

That is the entire player. `preload="none"` is doing real work: without it every page load opens a stream connection for every visitor, whether or not they ever press play.

No custom controls, no volume slider, no seek bar worth showing — seeking is meaningless on a live stream, so the timeline gets hidden in CSS and the browser's own play button does the rest.

## Keeping it alive: a frame

The shell document holds the chrome and the player. The blog loads into a frame in the middle. Only the frame ever navigates.

```html
<body class="shell-body">
  <header class="topbar">
    <a href="/" target="content">Hísilómë</a>
    <nav><a href="/tags/" target="content">./tags</a></nav>
  </header>

  <iframe class="shell-content" src="/" name="content"></iframe>

  <footer>
    <audio controls preload="none">
      <source src="/stream.mp3" type="audio/mpeg">
    </audio>
  </footer>
</body>
```

Links in the top bar carry `target="content"` so they drive the frame instead of replacing the page. Links *inside* the frame need nothing at all — a link in a frame navigates its own frame by default. Click through the whole site and the `<audio>` element is never touched.

This is not a clever new technique. Netscape 2.0 shipped frames in 1996, and persistent chrome around a swapping content area was how the web did this for years before JavaScript could drive navigation. Single-page apps reinvented the pattern mainly to win back the URL bar.

## The recursion problem

If the shell lives at `/` and frames `/`, it frames itself, forever.

You need to answer the same URL two different ways depending on who is asking. Browsers already tell you: every request carries a `Sec-Fetch-Dest` header, and for a frame it is `iframe`.

```nginx
map $http_sec_fetch_dest $root_document {
    iframe  /index.html;
    default /listen.html;
}

server {
    location = / {
        try_files $root_document =404;
    }
}
```

A person typing your domain gets the shell. The shell's own frame asks for the same `/`, gets the index, and the recursion is cut. No cookie, no query parameter, no redirect.

The same header solves the duplicate-chrome problem. The blog template already has a top bar and a footer; inside the frame you want neither, because the shell provides them:

```
<!--# if expr="$http_sec_fetch_dest != iframe" -->
<header class="topbar">...</header>
<!--# endif -->
```

Unlike a query parameter, this survives navigation — the header is on *every* request, including links clicked inside the frame five pages later. Browsers too old to send it just get the top bar twice, which is ugly rather than broken.

## Updating the page without JavaScript

The track title changes every few minutes. Server-Side Includes can put it in the page, but SSI runs at *render* time — the title would be stale the moment the page finished loading.

A `<meta http-equiv="refresh">` would fix that by reloading the page, which would kill the audio. Unless you scope it to a frame that isn't holding the audio.

Liquidsoap writes the title to a file whenever the track changes:

```liquidsoap
def write_now_playing(m) =
  title = m["title"]
  write = file.write.stream(atomic=true, temp_dir="radio/state",
                            "radio/state/now-playing.txt")
  write(title)
  write(null)
end

radio.on_metadata(synchronous=true, write_now_playing)
```

nginx serves that file — deliberately from outside the site's output directory, because the static site generator wipes that on every build:

```nginx
location = /now-playing.txt {
    alias radio/state/now-playing.txt;
    default_type text/plain;
    add_header Cache-Control "no-store, no-cache, must-revalidate";
}
```

And a tiny page includes it and reloads itself every twenty seconds:

```
<meta http-equiv="refresh" content="20">
<p class="track"><!--#include virtual="/now-playing.txt" --></p>
```

Drop that in an iframe next to the player. The frame reloads; the audio element beside it never does. A self-updating region of a static page, with no script and no polling code.

One footnote for anyone writing this up on their own site: these pages are served with `ssi on`, so SSI directives in prose get executed rather than displayed. Inside a fenced code block Markdown escapes `<` to `&lt;`, which nginx doesn't match — that is the only reason the examples above are visible instead of silently running.

## What it costs

Three real things, stated plainly.

**The URL stops following you.** The address bar shows `/` no matter which post you are reading. Deep links still work when someone arrives at one, but copying the address while browsing shares the front page. This is the frameset bargain and it has not changed since 1996.

**Stop is not disconnect.** Pausing an `<audio>` element does not close the socket — the browser keeps buffering, and resuming continues from the buffer, so you drift behind the broadcast. Fixing that requires `removeAttribute('src')` and `load()`, which requires JavaScript. Reloading the page rejoins the live edge, and ordinary browsing already does that for you.

**No default volume.** `volume` is a scriptable property with no HTML attribute. You cannot set it in markup. The stream is broadcast at half amplitude instead, which is a different thing and everybody's problem rather than one listener's.

None of these are worth a framework to me.

## What's next

The channel above is **cyberia**, after the club in *Serial Experiments Lain* — which is the whole reason this station exists. It is the only one for now. A second is not much work, mostly another Liquidsoap output and another mount, but it needs a second library worth listening to before it needs any code.

After that, listener count. Icecast already tracks it and exposes it on the admin status endpoint, so it costs nothing but the same self-refreshing frame the title uses. That matters more than it sounds: right now the stream is shared in the technical sense and private in every sense that counts. A number showing that someone else is out there is the difference between a broadcast and a room.

In memory of [lainon.life](https://github.com/barrucadu/lainonlife), 2017–2023.
