# One temp dir per writer: liquidsoap hardcodes the temp name to "atomic.write",
# so writers sharing a temp_dir collide and land content in the wrong file.
ignore(file.mkdir(perms=0o755, "radio/state/tmp-nowplaying"))
ignore(file.mkdir(perms=0o755, "radio/state/tmp-console"))
ignore(file.mkdir(perms=0o755, "radio/state/tmp-schedule"))

# How far behind the encoder a listener is. source.elapsed() is the ENCODER's
# position, so without this the console runs ahead of what anyone hears: icecast
# hands each new client <burst-size> bytes at once and they stay that far back
# for the session. Keep in sync with radio/icecast.xml.
#
# Only the burst is corrected. Liquidsoap's output queue and the browser's own
# jitter buffer put the listener a further ~1.5s back, but that is not
# derivable - the browser sizes its buffer itself and differently per client -
# so it is left alone rather than tuned to one browser and wrong for every
# other. The burst was worth correcting because it is the same for everyone.
stream_latency = 131072. / (128000. / 8.)   # 128 KiB at 128 kbps = 8.192s

# "[Album] - NN Artist - Title.ext" or "kebab-case-name.ext". Fallback for
# untagged files; keeps the artist/title split as an em dash.
def derive_title(filename) =
  name = path.basename(path.remove_extension(filename))
  name = string.replace(pattern="^\\[[^]]*\\][ ]*-[ ]*", fun (_) -> "", name)
  name = string.replace(pattern="^[0-9]+[ ]*-?[ ]*", fun (_) -> "", name)
  name = string.replace(pattern="[ ]+-[ ]+", fun (_) -> " — ", name)
  name = string.replace(pattern="[-_]", fun (_) -> " ", name)
  name = string.replace(pattern=" +", fun (_) -> " ", name)
  name = string.trim(name)
  string.capitalize(space_sensitive=true, name)
end

def html_escape(t) =
  t = string.replace(pattern="&", fun (_) -> "&amp;", t)
  t = string.replace(pattern="<", fun (_) -> "&lt;", t)
  string.replace(pattern=">", fun (_) -> "&gt;", t)
end

def mmss(t) =
  total = int_of_float(t)
  mins = total / 60
  secs = total mod 60
  pad = if secs < 10 then "0" else "" end
  "#{mins}:#{pad}#{secs}"
end

current_title = ref("")
current_album = ref("")
current_index = ref(-1)

# "<seconds>\t<path>\t<album>" in play order, written by bin/build-queue.
def queue_rows() =
  if file.exists("radio/state/queue.tsv") then
    list.filter(fun (l) -> l != "",
      string.split(separator="\n", file.contents("radio/state/queue.tsv")))
  else
    []
  end
end

def row_secs(row) =
  parts = string.split(separator="\t", row)
  try float_of_string(list.nth(parts, 0)) catch _ do 0. end
end

def row_path(row) =
  parts = string.split(separator="\t", row)
  try list.nth(parts, 1) catch _ do "" end
end

# Added after the fact, so a two-column queue.tsv is normal rather than an error.
def row_album(row) =
  parts = string.split(separator="\t", row)
  try list.nth(parts, 2) catch _ do "" end
end

# Fallback for the album line: mksafe's silence source has no metadata, and a
# blank line there would collapse the console by a row mid-outage.
channel_name = "cyberia"

def write_now_playing(m) =
  tagged = m["title"]
  artist = m["artist"]
  title =
    if tagged == "" then derive_title(m["filename"])
    elsif artist == "" then tagged
    else "#{artist} — #{tagged}"
    end
  current_title := title
  album = m["album"]
  current_album := if album == "" then channel_name else album end
  # Cursor, not a path search: the queue holds several shuffled rounds, so every
  # path appears more than once and a scan finds the last copy. Confirm against
  # the filename and only search forward on disagreement, so a skipped track
  # re-syncs on the next one.
  fn = m["filename"]
  rows = queue_rows()
  n = list.length(rows)
  if n > 0 and fn != "" then
    guess = (current_index() + 1) mod n
    matches = fun (i) -> string.contains(substring=fn, list.nth(rows, i))
    if matches(guess) then
      current_index := guess
    else
      found = ref(-1)
      list.iter(
        fun (k) ->
          if found() < 0 then
            i = (guess + k) mod n
            if matches(i) then found := i end
          end,
        list.init(n, fun (k) -> k))
      current_index := found()
    end
  end
  # NOT public/ -- zola build wipes it, breaking the atomic temp write.
  write = file.write.stream(atomic=true, temp_dir="radio/state/tmp-nowplaying", "radio/state/now-playing.txt")
  write(title)
  write(null)
end

# mode="normal" over a pre-shuffled queue, NOT mode="randomize": randomize
# decides one track ahead, leaving no future to put in the schedule.
radio = playlist(prefix="replaygain:", mode="normal", reload_mode="watch",
                 "radio/state/queue.m3u")

# Per-track, not album-level: the library spans 9.0 LU and Silent Hill 2 alone
# spans 8.8. Tags are pre-written by `tag-replaygain`, so this reads a value
# (~2ms) rather than analysing the file (~5s).
radio = normalize_track_gain(radio)

radio = mksafe(radio)
radio.on_metadata(synchronous=true, write_now_playing)

# Production supplies ICECAST_SOURCE_PASSWORD via systemd EnvironmentFile; the
# default matches radio/icecast.xml for the loopback-only dev stack.
source_password = environment.get(default="hackme", "ICECAST_SOURCE_PASSWORD")

output.icecast(%mp3, host="127.0.0.1", port=8000,
               password=source_password, mount="/stream.mp3", radio)

# Opus at 96 kbps: better than the mp3 at 128, but no Safari/iOS. Listed second
# in the <audio> elements so those fall through to mp3. Its per-mount burst in
# icecast.xml is sized to the same 8.192 s so stream_latency holds for both.
output.icecast(%opus(bitrate=96), format="audio/ogg", host="127.0.0.1", port=8000,
               password=source_password, mount="/stream.opus", radio)

# Where the LISTENER is: queue index and seconds into that track. While the
# encoder is less than stream_latency into a track, the listener is still
# hearing the tail of the previous one, so report that instead of clamping to
# zero - otherwise the title changes 8s early and the bar sits at 0 meanwhile.
def listener_pos() =
  rows = queue_rows()
  here = current_index()
  adj = source.elapsed(radio) - stream_latency
  behind = adj < 0. and here > 0 and list.length(rows) > here - 1
  if behind then
    prev = list.nth(rows, here - 1)
    e = row_secs(prev) + adj
    (here - 1, if e < 0. then 0. else e end, row_secs(prev))
  else
    (here, if adj < 0. then 0. else adj end, source.duration(radio))
  end
end

# HTML rather than plain values because the progress bar carries its position in
# a style attribute: a NEGATIVE animation-delay starts the CSS animation partway
# through, so the bar renders already-advanced and then moves on its own.
def write_console() =
  # Load-bearing: thread.run does not restart a thread whose body raised, so one
  # transient error would silently kill this writer for the life of the process.
  try
    let (idx, el, du) = listener_pos()
    rows = queue_rows()
    on_prev = idx >= 0 and idx != current_index() and list.length(rows) > idx

    # The refs hold real tag metadata; the queue row only has a filename, so
    # prefer the refs whenever the listener is on the current track.
    title =
      if on_prev then html_escape(derive_title(row_path(list.nth(rows, idx))))
      else html_escape(current_title()) end
    album =
      if on_prev then
        a = row_album(list.nth(rows, idx))
        html_escape(if a == "" then channel_name else a end)
      else html_escape(current_album()) end

    fill =
      if du > 0. then
        '<span class="rc-fill" style="--dur:' ^ string_of(du) ^ 's;--elapsed:-' ^ string_of(el) ^ 's"></span>'
      else
        ''
      end
    # Two CSS-animated counters so the digits tick without reloading the frame;
    # reloading at 1Hz is what caused visible flicker. Step counts are literals
    # because var() inside steps() does not reliably parse.
    esec = int_of_float(el)
    tmin = int_of_float(du) / 60
    smod = esec mod 60

    elapsed_html =
      if du <= 0. then
        ''
      elsif tmin < 1 then
        # under a minute: no minute steps to animate, so the digit is static
        '<span class="rc-m rc-static">0</span>:<span class="rc-s" style="animation: rc-sec 60s steps(60) -' ^ string(smod) ^ 's infinite"></span>'
      else
        '<span class="rc-m" style="--tm:' ^ string(tmin) ^ ';animation: rc-min ' ^ string(tmin * 60) ^ 's steps(' ^ string(tmin) ^ ') -' ^ string(esec) ^ 's forwards"></span>' ^
        ':<span class="rc-s" style="animation: rc-sec 60s steps(60) -' ^ string(smod) ^ 's infinite"></span>'
      end

    clock_text = if du > 0. then elapsed_html ^ ' / ' ^ mmss(du) else '' end

    # Spliced in here so the whole volatile block is ONE include and the values
    # cannot disagree.
    listeners =
      if file.exists("radio/state/listeners.txt") then
        file.contents("radio/state/listeners.txt")
      else
        ""
      end
    sep = if listeners == "" then "" else " · " end

    html =
      '<p class="rc-title">' ^ title ^ '</p>' ^
      '<p class="rc-sub">' ^ album ^ '</p>' ^
      '<div class="rc-bar">' ^ fill ^ '</div>' ^
      '<p class="rc-clock">' ^ clock_text ^ sep ^ html_escape(listeners) ^ '</p>'

    write = file.write.stream(atomic=true, temp_dir="radio/state/tmp-console", "radio/state/console.html")
    write(html)
    write(null)
  catch _ do
    log.important(label="write_console", "write failed; will retry next tick")
  end
end

# 1s sets the clock's resolution; the frame reload rate is irrelevant if the
# file behind it is stale.
thread.run(every=1., write_console)

# ---- schedule -------------------------------------------------------------
# Offsets are arithmetic over queue.tsv durations, re-anchored to the listener
# position every cycle so error cannot accumulate.

def mins_word(t) =
  m = int_of_float(t / 60.)
  if m <= 0 then
    "now"
  else
    # nested quotes inside a #{...} interpolation do not parse
    plural = if m == 1 then "" else "s" end
    string_of(m) ^ " min" ^ plural
  end
end

def write_schedule() =
  try
    rows = queue_rows()
    n = list.length(rows)
    let (here, el, _) = listener_pos()

    if n == 0 or here < 0 then
      ()
    else
      # Clamp rather than wrap (a reshuffle invalidates the earlier order), but
      # SLIDE rather than truncate: the panel is a fixed height, so a short list
      # leaves a gap above its border. rows_wanted must match --sc-rows in
      # static/style.css.
      rows_wanted = 11
      lo_raw = here - 2
      hi_raw = lo_raw + rows_wanted - 1
      up = if lo_raw < 0 then 0 - lo_raw else 0 end
      lo_a = lo_raw + up
      hi_a = hi_raw + up
      down = if hi_a > n - 1 then hi_a - (n - 1) else 0 end
      lo_b = lo_a - down
      hi_b = hi_a - down
      lo = if lo_b < 0 then 0 else lo_b end
      hi = if hi_b > n - 1 then n - 1 else hi_b end

      def row_html(i) =
        row = list.nth(rows, i)
        title = html_escape(derive_title(row_path(row)))
        album = row_album(row)
        title =
          if album == "" then
            title
          else
            title ^ ' <span class="sc-a">[' ^ html_escape(album) ^ ']</span>'
          end
        if i == here then
          '<li class="sc-now"><span class="sc-t">' ^ title ^ '</span><span class="sc-w">now</span></li>'
        elsif i < here then
          ago = ref(el)
          list.iter(fun (j) -> ago := ago() + row_secs(list.nth(rows, j)), list.init(here - i, fun (k) -> i + k))
          '<li><span class="sc-t">' ^ title ^ '</span><span class="sc-w">' ^ mins_word(ago()) ^ ' ago</span></li>'
        else
          until = ref(row_secs(list.nth(rows, here)) - el)
          list.iter(fun (j) -> until := until() + row_secs(list.nth(rows, j)), list.init(i - here - 1, fun (k) -> here + 1 + k))
          '<li><span class="sc-t">' ^ title ^ '</span><span class="sc-w">in ' ^ mins_word(until()) ^ '</span></li>'
        end
      end

      items = list.fold(fun (acc, i) -> acc ^ row_html(i), "",
                        list.init(hi - lo + 1, fun (k) -> lo + k))
      html = '<ul class="sc-list">' ^ items ^ '</ul>'
      write = file.write.stream(atomic=true, temp_dir="radio/state/tmp-schedule", "radio/state/schedule.html")
      write(html)
      write(null)
    end
  catch _ do
    log.important(label="write_schedule", "write failed; will retry next tick")
  end
end

thread.run(every=10., write_schedule)
