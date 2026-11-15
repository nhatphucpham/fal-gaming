# Voice (TTS)

## Purpose

Speaks dialogue lines with the Falevon TTS service (VieNeu-TTS, an
OpenAI-compatible `POST /v1/audio/speech` at `https://tts.falevon.com`) and
keeps every line it gets in a cache. Voice is optional: when a line has no
voice, the game shows the text only. It does not decide what is said or
when; dialogue and cutscenes call it.

## Layer and files

- Layer: bridge (an autoload service; conventions §1 lists voice as a true
  global service).
- Code: `Systems/Voice/voice_service.gd` (`VoiceService`, autoload
  `Voice`), `voice_line.gd` (`VoiceLine`, one requested line),
  `voice_style.gd` (`VoiceStyle`, how a line is spoken), `voice_tags.gd`
  (`VoiceTags`, the inline tags), `voice_wav.gd` (`VoiceWav`, WAV encode
  and decode).
- Data: `user://voice.cfg` (settings), `user://voice_cache/` (the cache),
  `res://Assets/Voice/` (lines baked into the build; none yet), and
  `VoiceStyle` resources (`.tres`) for shared styles (none yet).
- Developer page: `Scenes/Dev/voice_demo.tscn` (not exported).
- Depends on: nothing in the game; the network and `user://`.

## Data

Settings come from `user://voice.cfg`, then the environment:

```ini
[voice]
enabled=true
base_url="https://tts.falevon.com"
api_key="..."
default_voice="Mai Anh"
sample_rate=24000
cache_limit_mb=200
```

`FALEMAG_TTS_URL` and `FALEMAG_TTS_KEY` override the file. `base_url` and
`api_key` lose leading and trailing whitespace. A value of the
wrong type keeps the default and warns with the field name (never the
value). `sample_rate` must be one the server offers (48000, 24000, 16000 or
8000); anything else warns and uses 24000. Never commit an API key.
Without a `voice` (and no `default_voice`) the server speaks "Hải Đăng"
(`VoiceService.SERVER_DEFAULT_VOICE`); the request still names none.

**Cache.** Each line is saved once as a mono 16-bit WAV in
`user://voice_cache/<key>.wav`, and is not requested again until pruning
deletes it. The key is a SHA-256 of `CACHE_VERSION`, the model, the voice,
the sample rate and the text with whitespace collapsed (inline tags
included); `Voice.cache_key(text, voice, style)` gives it. A non-default
style puts its key text (such as `speed=1.30 pitch=-2.0`) in front; a null
or default style gives exactly the key of an unstyled line, so caches and
bundled files from before styles stay valid. Files are written to `.part` and renamed, so a crash
never leaves a broken line; a file that does not read back is deleted and
fetched again. If the cache cannot be written (folder, open, write or
rename fails), one warning is given per session and lines are fetched
again next time. At start-up the cache is trimmed to `cache_limit_mb`
(200 MB), deleting the oldest written files until it is under 90%.
Generation is random (sampling), so the cache also keeps a line's voice the
same every time it is played.

**Styles.** A `VoiceStyle` resource says how a line is spoken. Values
outside the server limits are clamped. Speed and pitch are rounded as the
server rounds them; volume and effort are rounded to 0.05 (the server
accepts finer values such as effort 1.5 or volume 1.15) so near-equal
styles share a cached line. A NaN or infinite value counts as the field's
default. Only values that differ from the default go in the request body.

| Field | Range | Default | Step | Meaning |
| --- | --- | --- | --- | --- |
| `speed` | 0.25 to 4 | 1.0 | 0.05 (server) | Speaking rate. |
| `pitch` | -12 to 12 | 0 | 0.5 (server) | Semitones. |
| `volume` | 0.1 to 4 | 1.0 | 0.05 (ours) | Loudness. |
| `effort` | 0 to 2 | 0 | 0.05 (ours) | 0 normal, 1 raised voice, 2 shouting. |

The server answers a value out of range with 400; clamping means the game
never sends one.

**Inline tags.** Tags inside the text change the voice from the tag on.
They stay in the text sent and in the cache key; `VoiceService.display_text`
gives the line without them for the screen.

| Tag | Effect |
| --- | --- |
| `[speed=1.3]`, `[pitch=-2]`, `[volume=0.7]`, `[effort=2]` | Set one style value from here on. |
| `[shout=2]` | Same as `effort`. |
| `[speed=0.85 pitch=-3]` | Several values in one tag, split by whitespace. |
| `[voice=Mai Anh]` | Another voice from here on; an unknown name is a 400. |
| `[speed=1.2 voice=Mai Anh]`, `[voice=Mai Anh speed=1.2]` | A voice and values in one tag; the values may come before or after the name. |
| `[reset]` | Undoes the tags before it. |
| `[cười]`, `[thở dài]`, `[hắng giọng]` | Laugh, sigh, clear the throat. |

`display_text` removes exactly these written forms and nothing else. The
server may read more than is hidden (other letter case, padding inside the
brackets, or aliases of the cues), so write tags exactly as in the table or
they can be spoken as cues and still show in the caption. The forms: lowercase
keys with a number value and no spaces around `=` or inside the brackets,
a `voice` name that may hold spaces and Vietnamese letters, and the cues.
Whitespace inside a tag (between pairs, before `voice=`, inside a cue) counts
as one space, since the text is sent normalized: `[thở  dài]`,
`[speed=1.2` + line break + `pitch=-1]` and `[hắng` + tab + `giọng]` are
tags. `[speed = 1.3]`, `[speed=1.3pitch=2]`, `[Reset]` and
`[speed=fast]` stay in the text, like any other bracketed text such as `[1]`
or `[ghi chú]`. A removed tag leaves one space, so `Xin[cười]chào` shows
`Xin chào`. Whitespace of any kind around a removed tag right before closing
punctuation (`) ] } ” » ’ , . ; : ! ? …`) is dropped, so `Ha ha [cười].`
shows `Ha ha.` and `(Ha [cười])` shows `(Ha)`. A removed tag at the start
or right after an opening `( [ { “ « ‘` (whitespace between them is dropped
too) takes the whitespace after it along, so `( [thở dài] Thôi)` shows
`(Thôi)` and `[cười] Ha` shows `Ha`. A tag alone on its line leaves no empty
line: `Một`, line break, `[cười]`, line break, `Hai` shows two lines. Every
no-break space (U+00A0) in the caption becomes a plain space, with or
without a tag near it.
Straight quotes `"` and `'` both open and close, so they are in neither
set: a tag next to one is treated as if it were next to a letter
(`Nói [cười] "Ha"` shows `Nói "Ha"`, `"Ha [cười]"` shows `"Ha "`). Runs of spaces and tabs are then collapsed to one space,
but line breaks are kept (without spaces around them), since a caption may
have several lines.

**Bundled lines.** A file at `res://Assets/Voice/<key>.wav` is used before
the cache and the network, so shipped lines work offline and on the web.

## Public API

| Member | Kind | Description |
| --- | --- | --- |
| `get_line(text, voice := "", style: VoiceStyle = null) -> VoiceLine` | method | Requests a line. Already done when it is bundled or cached (a cache hit reads the file synchronously) or when no voice can be had now. |
| `play(player: AudioStreamPlayer, text, voice := "", style: VoiceStyle = null) -> bool` | method (await) | Gets the line and plays it; false when there is no voice. |
| `prefetch(texts: Array[String], voice := "", style: VoiceStyle = null)` | method | Fetches lines in the background, behind every spoken line. |
| `cache_key(text, voice := "", style: VoiceStyle = null) -> String` | method | The cache file name of a line. |
| `VoiceService.normalize(text) -> String`, `VoiceService.display_text(text) -> String` | static | The text as it is sent; the text as it is shown (tags removed). |
| `is_online() -> bool`, `pending_count() -> int`, `clear_cache()`, `load_config(path)` | methods | `pending_count` includes prefetches waiting out a 429; `load_config` also lets voice try again after a refused key. |
| `online_changed(online: bool)` | signal | The service went offline or came back; never the same value twice in a row. |
| `enabled`, `base_url`, `api_key`, `default_voice`, `sample_rate`, `request_timeout` (30 s), `max_parallel` (2), `prefetch_retries` (3), `cache_dir`, `cache_limit_mb`, `offline_backoff_min` (15 s), `offline_backoff_max` (300 s) | properties | Settings. |
| `SERVER_DEFAULT_VOICE` ("Hải Đăng"), `NO_WAIT_HEADER`, `BUSY_RETRY_DEFAULT` (2 s), `BUSY_RETRY_MAX` (30 s) | constants | See **Busy server**. |
| `VoiceStyle`: `speed`, `pitch`, `volume`, `effort`, `VoiceStyle.create(speed, pitch, volume, effort)`, `sent_speed()` (and `sent_pitch`, `sent_volume`, `sent_effort`), `is_default()`, `request_fields() -> Dictionary`, `key_text() -> String` | `Resource` | A style; the `sent_*` values are clamped and rounded. |
| `VoiceTags.display_text(text)`, `VoiceTags.is_tag(inner) -> bool` | static | The tag parser behind `display_text`. |
| `VoiceWav.wav_bytes(pcm, rate)`, `VoiceWav.read_wav(bytes)`, `VoiceWav.pcm_stream(pcm, rate)` | static | Write and read a 16-bit PCM WAV; `read_wav` returns null for anything else or a truncated file. |
| `VoiceLine.wait() -> AudioStreamWAV`, `stream`, `done`, `error`, `text`, `voice`, `style`, `key`, `prefetch`, `busy_retries`, `finished(stream)` | `VoiceLine` | `wait()` returns the audio or null; `error` says why. |

```gdscript
var stream := await Voice.get_line("Ngươi đã phản bội ta.", "Mai Anh").wait()
if stream:
	$Player.stream = stream
	$Player.play()
await Voice.play($Player, "Ngươi đã phản bội ta.", "Mai Anh")
Voice.prefetch(["Câu một.", "Câu hai."], "Mai Anh")  # the next scene
var shout := VoiceStyle.create(1.1, 0.0, 1.5, 2.0)  # or load() a saved .tres
await Voice.play($Player, "[thở dài] Đứng lại!", "Mai Anh", shout)
$Caption.text = VoiceService.display_text("[thở dài] Đứng lại!")  # "Đứng lại!"
```

`line.error` is empty on success, otherwise:

| Error | Meaning | Effect |
| --- | --- | --- |
| `empty` | Blank text. | This line. |
| `disabled` | `enabled` is false, no `base_url`, a web build, or the service is leaving the tree (pending lines resolve so no caller hangs, and a line asked for during exit is `disabled` at once). | Every uncached line. |
| `no_key` | `api_key` is empty; nothing is sent. | Every uncached line. |
| `unauthorized` | 401/403: the key was refused. | Voice is off until `load_config()`. |
| `offline` | Connection failure or 502/503/504. | The service goes offline: queued lines fail, and new lines fail at once until the retry time (15 s, doubling up to 5 min). A stale failure (see **Going offline**) fails this line only. |
| `timeout` | No answer within `request_timeout`. | This line only; the online state does not change. |
| `http_<code>` | Any other answer, such as 400 (unknown voice, also in a tag), 429 (busy; a prefetch first retries, see **Busy server**) or 500. | This line only; the service counts as online. |

**Requests.** At most `max_parallel` requests run at once. They are polled
HTTPRequests (not threaded: a threaded request reads a blocking socket and
cancelling it on timeout or shutdown blocks the main thread until the
server closes). A request that cannot even start (for example a malformed
`base_url`) counts as offline and warns once per session. Spoken lines run in the order they were asked, ahead of
prefetched lines; asking for a line that is only prefetched moves it to the
end of the spoken lines. The same line asked twice shares one request. Any
answer other than 502/503/504 proves the service is reachable and ends an
offline period.

**Busy server.** The server serves six streams at once; beyond that a
request waits up to 10 s, then gets 429 with a `Retry-After` header. A
spoken line waits like that and a 429 fails it with `http_429`. Prefetched
lines send `X-VieNeu-No-Wait: 1`, so the server answers 429 at once
instead of holding a slot. A prefetch answered 429 is not failed: it goes
to the back of the queue and is not started again for `Retry-After`
seconds (2 s when the header is missing or not a number, at most 30 s),
up to `prefetch_retries` times; then it fails with `http_429`. A one-shot
timer ends the wait, so the line goes out even when nothing else happens,
and other lines keep going meanwhile. A waiting line asked for as a spoken
line goes out at once without the header; one asked for while its no-wait
request is in flight is sent again at once, without the header, if that
request gets 429. A line is put back, and sent again when its wait ends,
only while voice is still available; after a 401, a cleared key or
`enabled = false`, or when an offline backoff starts while it waits, it
resolves with that error (`unauthorized`, `no_key`, `disabled`, `offline`)
instead. A 429 itself ends an offline period, so a line answered 429
during a backoff is put back. Leaving the tree
resolves waiting lines like any other.
503 (the engine restarting) still counts as offline with the backoff.

**Going offline.** The service is marked offline before `online_changed(false)`
and the dropped lines' `finished` handlers run, so a line asked for from a
handler also fails at once. **Coming back** is the other way round: the
service is marked online before the answered line is put back or resolved,
and `online_changed(true)` fires only after that, so its handler finds the
line cached, pending or failed rather than half-handled and does not send
it again. Code awaiting that line therefore resumes before the signal.
A failure is **stale** when its request began
before the latest state change: before the current retry time while the
service is offline, or before it last came back online. A newer request has
already settled the state, so a stale failure fails its own line only; it
does not grow the backoff, emit `online_changed`, or drop the queue.

## Log events

None yet. Warnings, each once per session or per cause: `Voice: the TTS
service refused the API key`, `Voice: cannot write the cache in ...`,
`Voice: cannot start a request to <base_url>: error N`,
`Voice: the TTS service at <base_url> is unreachable` (once per outage),
`Voice: unsupported sample_rate`, `Voice: <file> field <name> must be
<type>`. The API key is never logged.

## How to extend

- Speak a line: call `Voice.get_line` or `Voice.play` from presentation
  code, with the text from the translation files.
- Ship a line: save its WAV as `res://Assets/Voice/<Voice.cache_key(text,
  voice, style)>.wav`, leaving out `style` for an unstyled line (for
  example copy it from `user://voice_cache/`).
- A new request or audio format: bump `CACHE_VERSION` so old caches are
  not used.
- A shared style: save a `VoiceStyle` as a `.tres` file and pass it to
  `get_line`, `play` or `prefetch`.
- Try it by hand: run `Scenes/Dev/voice_demo.tscn` (F6) with a key set,
  type a line (tags allowed; the page shows it as the player would read
  it), set speed, pitch, volume and effort, and press **Speak**; pressing
  it again plays it from the cache. Android exports need the **Internet** permission for live voice.

## Tests

`Tests/voice_test.gd`, against a fake server on localhost with no network
and no effect from a developer's `voice.cfg` or environment: WAV round trip
and truncated files, config types, style clamping and rounding,
style values that are NaN or infinite, `display_text` (several keys in one
tag, number pairs before or after a voice name, a voice name with spaces
and Vietnamese letters, a tag between two words, closing punctuation and
quotes, a tag at the start or after an opening character, straight quotes,
line breaks, a tag alone on its line, whitespace inside a tag, no-break
spaces, near-miss tags and other brackets kept), cache key (a null or
default style matching the key computed the pre-style way, styles and tags
in the key), caching and prefetch, request shape with and without a style,
the no-wait header on prefetches only, de-duplication, the missing key,
queue order (spoken FIFO before prefetched), timeout, 429 on a spoken line,
a prefetch 429 (requeued behind a spoken line that is served meanwhile,
sent again after `Retry-After`, `Retry-After` parsing and its cap, retries
used up, promoted while waiting, promoted while in flight, leaving the
tree while waiting, a 429 arriving after a 401, voice turned off or an
offline backoff while a line waits, a 429 arriving inside a backoff that
puts the line back and ends the offline period before `online_changed(true)`
fires), 401, 502 with its backoff and retry, a 400
ending an offline period, stale failures (a request begun before the outage
failing while the retry is in flight, and one failing after the service
came back: each fails its own line and keeps the backoff, the state and the
queue), a line asked for from a dropped line's handler, a handler that takes the service offline again while an answer is settled (no second `false`), shutdown (including
a line asked for during exit and a late completion), a malformed `base_url`
and an unreachable server.

```sh
godot --headless --path . --script res://Tests/voice_test.gd
```

## Known limits

- **Checked against the real service (2026-11-14).** A short line (1 to 2 s
  of audio) comes back in about 2 s; an 18 s paragraph took 11 s, so keep
  lines short or prefetch them. Eight requests at once were all served, the
  last after 12 s. An unknown voice is a 400 (`http_400`) and is not cached;
  `GET /v1/voices` lists the valid names. An unknown `model` is accepted.
- **Checked against the real service (2026-11-15).** The style fields and
  the inline tags work; a styled line took about 3 s. An out-of-range
  `speed` and an unknown voice in a tag each return 400. With ten no-wait
  requests at once, six were served and four got 429 with `Retry-After: 2`.
- **Web.** The service sends no CORS headers (a preflight `OPTIONS` gets
  405), so a browser build cannot call it: web builds send no requests
  (`disabled`) and get voice only from bundled lines. The cache lookup
  still runs first, but nothing fills the cache on the web.
- **Key exposure.** A key built into a released game can be extracted, so
  a public release should ship baked lines in `res://Assets/Voice` or call
  the service through a proxy that holds the key.
- Nothing in the game speaks yet.
