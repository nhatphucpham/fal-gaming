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
  `Voice`), `voice_line.gd` (`VoiceLine`, one requested line).
- Data: `user://voice.cfg` (settings), `user://voice_cache/` (the cache),
  `res://Assets/Voice/` (lines baked into the build; none yet).
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

**Cache.** Each line is saved once as a mono 16-bit WAV in
`user://voice_cache/<key>.wav`, and is not requested again until pruning
deletes it. The key is a SHA-256 of `CACHE_VERSION`, the model, the voice,
the sample rate and the text with whitespace collapsed; `Voice.cache_key(text,
voice)` gives it. Files are written to `.part` and renamed, so a crash
never leaves a broken line; a file that does not read back is deleted and
fetched again. If the cache cannot be written (folder, open, write or
rename fails), one warning is given per session and lines are fetched
again next time. At start-up the cache is trimmed to `cache_limit_mb`
(200 MB), deleting the oldest written files until it is under 90%.
Generation is random (sampling), so the cache also keeps a line's voice the
same every time it is played.

**Bundled lines.** A file at `res://Assets/Voice/<key>.wav` is used before
the cache and the network, so shipped lines work offline and on the web.

## Public API

| Member | Kind | Description |
| --- | --- | --- |
| `get_line(text, voice := "") -> VoiceLine` | method | Requests a line. Already done when it is bundled or cached (a cache hit reads the file synchronously) or when no voice can be had now. |
| `play(player: AudioStreamPlayer, text, voice := "") -> bool` | method (await) | Gets the line and plays it; false when there is no voice. |
| `prefetch(texts: Array[String], voice := "")` | method | Fetches lines in the background, behind every spoken line. |
| `cache_key(text, voice := "") -> String`, `normalize(text) -> String` | methods | The cache file name of a line; the text as it is sent. |
| `is_online() -> bool`, `pending_count() -> int`, `clear_cache()`, `load_config(path)` | methods | `load_config` also clears a refused key. |
| `online_changed(online: bool)` | signal | The service went offline or came back. |
| `enabled`, `base_url`, `api_key`, `default_voice`, `sample_rate`, `request_timeout` (30 s), `max_parallel` (2), `cache_dir`, `cache_limit_mb`, `offline_backoff_min` (15 s), `offline_backoff_max` (300 s) | properties | Settings. |
| `VoiceService.wav_bytes(pcm, rate)`, `VoiceService.read_wav(bytes)` | static | Write and read a 16-bit PCM WAV; `read_wav` returns null for anything else or a truncated file. |
| `VoiceLine.wait() -> AudioStreamWAV`, `stream`, `done`, `error`, `text`, `voice`, `key`, `prefetch`, `finished(stream)` | `VoiceLine` | `wait()` returns the audio or null; `error` says why. |

```gdscript
var stream := await Voice.get_line("Ngươi đã phản bội ta.", "Mai Anh").wait()
if stream:
	$Player.stream = stream
	$Player.play()
await Voice.play($Player, "Ngươi đã phản bội ta.", "Mai Anh")
Voice.prefetch(["Câu một.", "Câu hai."], "Mai Anh")  # the next scene
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
| `http_<code>` | Any other answer, such as 400 (unknown voice), 429 (busy) or 500. | This line only; the service counts as online. |

**Requests.** At most `max_parallel` requests run at once. They are polled
HTTPRequests (not threaded: a threaded request reads a blocking socket and
cancelling it on timeout or shutdown blocks the main thread until the
server closes). A request that cannot even start (for example a malformed
`base_url`) counts as offline and warns once per session. Spoken lines run in the order they were asked, ahead of
prefetched lines; asking for a line that is only prefetched moves it to the
end of the spoken lines. The same line asked twice shares one request. Any
answer other than 502/503/504 proves the service is reachable and ends an
offline period.

**Going offline.** The service is marked offline before `online_changed(false)`
and the dropped lines' `finished` handlers run, so a line asked for from a
handler also fails at once. A failure is **stale** when its request began
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
  voice)>.wav` (for example copy it from `user://voice_cache/`).
- A new request or audio format: bump `CACHE_VERSION` so old caches are
  not used.
- Try it by hand: run `Scenes/Dev/voice_demo.tscn` (F6) with a key set,
  type a line and press **Speak**; pressing it again plays it from the
  cache. Android exports need the **Internet** permission for live voice.

## Tests

`Tests/voice_test.gd`, against a fake server on localhost with no network
and no effect from a developer's `voice.cfg` or environment: WAV round trip
and truncated files, config types, cache key, caching and prefetch, request
shape, de-duplication, the missing key, queue order (spoken FIFO before
prefetched), timeout, 429, 401, 502 with its backoff and retry, a 400
ending an offline period, stale failures (a request begun before the outage
failing while the retry is in flight, and one failing after the service
came back: each fails its own line and keeps the backoff, the state and the
queue), a line asked for from a dropped line's handler, shutdown (including
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
- **Web.** The service sends no CORS headers (a preflight `OPTIONS` gets
  405), so a browser build cannot call it: web builds send no requests
  (`disabled`) and get voice only from bundled lines. The cache lookup
  still runs first, but nothing fills the cache on the web.
- **Key exposure.** A key built into a released game can be extracted, so
  a public release should ship baked lines in `res://Assets/Voice` or call
  the service through a proxy that holds the key.
- Nothing in the game speaks yet.
