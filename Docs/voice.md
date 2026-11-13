# Voice (TTS)

Dialogue is spoken by the Falevon TTS service (VieNeu-TTS, an
OpenAI-compatible `POST /v1/audio/speech` at `https://tts.falevon.com`). The
`Voice` autoload (`Systems/Voice/voice_service.gd`) requests, caches and plays
lines. Voice is optional: when it is missing, the game shows the text only.

## Using it

```gdscript
# Speak a line; the result is null when no voice is available.
var stream := await Voice.get_line("Ngươi đã phản bội ta.", "Mai Anh").wait()
if stream:
	$Player.stream = stream
	$Player.play()

# Or in one call:
await Voice.play($Player, "Ngươi đã phản bội ta.", "Mai Anh")

# Warm the cache for the next scene while the player reads this one.
Voice.prefetch(["Câu một.", "Câu hai."], "Mai Anh")
```

`get_line` never blocks a frame. A cached line is ready at once
(`line.done` is true). `line.error` says why a line has no voice: `offline`,
`disabled`, `unauthorized`, `empty` or `http_<code>`.

## Behaviour

- **Cache.** Each line is saved once as a 24 kHz mono WAV in
  `user://voice_cache/<key>.wav` and never requested again. The key is a
  SHA-256 of the model, voice, sample rate and the text with whitespace
  collapsed. The cache is trimmed to `cache_limit_mb` (200 MB) at start-up,
  oldest first. Files are written to `.part` and renamed, so a crash never
  leaves a broken line.
- **Bundled lines.** A file at `res://Audio/Voice/<key>.wav` is used before
  the cache and the network, so shipped lines work offline. Use
  `Voice.cache_key(text, voice)` to name it.
- **Concurrency.** At most `max_parallel` (2) requests run at once, on
  HTTPRequest threads. Spoken lines go before prefetched ones, and the same
  line requested twice shares one request.
- **Offline.** A connection failure, timeout or 502/503/504 marks the
  service offline: queued lines resolve to null at once, and new lines do too
  until a retry time passes (15 s, doubling up to 5 min). `online_changed`
  reports the change. A 401/403 turns voice off for the session. Other errors
  (400, 429, 500) fail only that line.
- Generation is random (sampling), so the cache also keeps a line's voice the
  same every time it is played.

## Configuration

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

`FALEMAG_TTS_URL` and `FALEMAG_TTS_KEY` override the file. Never commit an
API key. A key built into a released game can be extracted, so a public
release should ship baked lines in `res://Audio/Voice` or call the service
through a proxy that holds the key.

## Trying it

Run `Scenes/Dev/voice_demo.tscn` (F6 in the editor) with a key set, type a
line and press **Speak**. Pressing it again plays the line from the cache.
`Tests/voice_test.gd` checks caching, request shape, de-duplication, 401 and
offline handling against a fake server on localhost, with no network needed.

Android exports need the **Internet** permission for live voice.
