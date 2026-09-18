# sherpa-onnx VAD+ASR prints "  12.345 -- 67.890: text" per segment; turn that
# into the same txt/srt/vtt/json whisper-cli writes. Output format in `fmt`.
function ts(t, sep,   h, m, s, ms) {
  h = int(t / 3600)
  m = int((t % 3600) / 60)
  s = int(t % 60)
  ms = int((t - int(t)) * 1000 + 0.5)
  return sprintf("%02d:%02d:%02d%s%03d", h, m, s, sep, ms)
}

function esc(s) {
  gsub(/\\/, "\\\\", s)
  gsub(/"/, "\\\"", s)
  return s
}

BEGIN {
  n = 0
  if (fmt == "vtt") print "WEBVTT\n"
  if (fmt == "json") print "["
}

match($0, /^[ \t]*[0-9]+\.[0-9]+ -- [0-9]+\.[0-9]+:/) {
  text = substr($0, index($0, ":") + 1)
  sub(/^[ \t]+/, "", text)
  start = $1 + 0
  end = $3 + 0
  n++

  if (fmt == "srt") {
    printf "%d\n%s --> %s\n%s\n\n", n, ts(start, ","), ts(end, ","), text
  } else if (fmt == "vtt") {
    printf "%s --> %s\n%s\n\n", ts(start, "."), ts(end, "."), text
  } else if (fmt == "json") {
    printf "%s  {\"start\": %.3f, \"end\": %.3f, \"text\": \"%s\"}", \
      (n > 1 ? ",\n" : ""), start, end, esc(text)
  } else {
    print text
  }
}

END {
  if (fmt == "json") print (n ? "\n]" : "]")
}
