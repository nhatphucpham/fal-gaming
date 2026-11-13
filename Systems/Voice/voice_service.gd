class_name VoiceService
extends Node
## Spoken dialogue from the Falevon TTS service (VieNeu-TTS,
## OpenAI-compatible POST /v1/audio/speech), registered as the "Voice"
## autoload.
##
## - Asynchronous: requests run on HTTPRequest threads, never on the frame.
## - Cached: every line is stored once under user://voice_cache and never
##   requested again. Lines baked into res://Audio/Voice are used first.
## - Offline-safe: when the service is unreachable, lines resolve to null at
##   once and the game goes on without voice; it retries with a backoff.
##
## [codeblock]
## var stream := await Voice.get_line("Ngươi đã phản bội ta.", "Mai Anh").wait()
## if stream:
##     $Player.stream = stream
##     $Player.play()
## [/codeblock]

signal online_changed(online: bool)

## Bump when the request or the audio format changes, to invalidate caches.
const CACHE_VERSION := 1
const BUNDLED_DIR := "res://Audio/Voice"
const CONFIG_PATH := "user://voice.cfg"
const MODEL := "vieneu-v3-turbo"
## Server sample rates are 48000, 24000, 16000 and 8000. 24 kHz keeps the
## cache small enough for phones and is plenty for speech.
const SAMPLE_RATES: Array[int] = [48000, 24000, 16000, 8000]

@export var enabled := true
@export var base_url := "https://tts.falevon.com"
## Sent as "Authorization: Bearer <key>". Never commit a key: set it in
## user://voice.cfg or the FALEMAG_TTS_KEY environment variable.
var api_key := ""
## Server preset voice used when a line names none; empty = server default.
@export var default_voice := ""
@export var sample_rate := 24000
@export var request_timeout := 30.0
## The server shares a few stream slots with other clients; keep this low.
@export var max_parallel := 2
@export var cache_dir := "user://voice_cache"
@export var cache_limit_mb := 200
@export var offline_backoff_min := 15.0
@export var offline_backoff_max := 300.0

var _online := true
var _retry_at_ms := 0
var _backoff := 0.0
var _auth_failed := false
var _queue: Array[VoiceLine] = []
var _pending := {}  # key -> VoiceLine, queued or in flight
var _active := 0
var _space := RegEx.create_from_string("\\s+")


func _ready() -> void:
	load_config()
	_prune_cache.call_deferred()


## Reads user://voice.cfg (section [voice]) and the FALEMAG_TTS_URL /
## FALEMAG_TTS_KEY environment variables, which win.
func load_config(path := CONFIG_PATH) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		enabled = cfg.get_value("voice", "enabled", enabled)
		base_url = cfg.get_value("voice", "base_url", base_url)
		api_key = cfg.get_value("voice", "api_key", api_key)
		default_voice = cfg.get_value("voice", "default_voice", default_voice)
		sample_rate = cfg.get_value("voice", "sample_rate", sample_rate)
		cache_limit_mb = cfg.get_value("voice", "cache_limit_mb", cache_limit_mb)
	if OS.has_environment("FALEMAG_TTS_URL"):
		base_url = OS.get_environment("FALEMAG_TTS_URL")
	if OS.has_environment("FALEMAG_TTS_KEY"):
		api_key = OS.get_environment("FALEMAG_TTS_KEY")
	base_url = base_url.strip_edges().trim_suffix("/")
	if not sample_rate in SAMPLE_RATES:
		push_warning("Voice: unsupported sample_rate %d, using 24000" % sample_rate)
		sample_rate = 24000


func is_online() -> bool:
	return _online


## Returns a [VoiceLine] for [param text]. It is already done when the line is
## cached, or when no voice can be had right now.
func get_line(text: String, voice := "") -> VoiceLine:
	return _request(text, voice, false)


## Fetches lines in the background so they are cached before they are needed,
## for example the next dialogue scene. Spoken lines always go first.
func prefetch(texts: Array, voice := "") -> void:
	for t in texts:
		_request(str(t), voice, true)


## Plays [param text] on [param player]. Returns false if there is no voice.
func play(player: AudioStreamPlayer, text: String, voice := "") -> bool:
	var stream := await get_line(text, voice).wait()
	if stream == null or not is_instance_valid(player):
		return false
	player.stream = stream
	player.play()
	return true


func cache_key(text: String, voice := "") -> String:
	var v := voice if voice != "" else default_voice
	var id := "%d|%s|%s|%d|%s" % [CACHE_VERSION, MODEL, v, sample_rate, normalize(text)]
	return id.sha256_text()


func normalize(text: String) -> String:
	return _space.sub(text.strip_edges(), " ", true)


## Number of lines queued or in flight.
func pending_count() -> int:
	return _pending.size()


func clear_cache() -> void:
	var dir := DirAccess.open(cache_dir)
	if dir == null:
		return
	for f in dir.get_files():
		dir.remove(f)


# --- requests ---------------------------------------------------------------

func _request(text: String, voice: String, background: bool) -> VoiceLine:
	var line := VoiceLine.new()
	line.text = normalize(text)
	line.voice = voice if voice != "" else default_voice
	line.key = cache_key(text, voice)
	if line.text == "":
		line._resolve(null, "empty")
		return line
	var cached := _load_cached(line.key)
	if cached != null:
		line._resolve(cached, "")
		return line
	if _pending.has(line.key):
		var existing: VoiceLine = _pending[line.key]
		if not background and existing.prefetch:
			existing.prefetch = false
			if _queue.has(existing):
				_queue.erase(existing)
				_queue.push_front(existing)
		return existing
	var reason := _unavailable_reason()
	if reason != "":
		line._resolve(null, reason)
		return line
	line.prefetch = background
	_pending[line.key] = line
	if background:
		_queue.push_back(line)
	else:
		_queue.push_front(line)
	_pump()
	return line


func _unavailable_reason() -> String:
	if not enabled or base_url == "":
		return "disabled"
	if _auth_failed:
		return "unauthorized"
	if not _online and Time.get_ticks_msec() < _retry_at_ms:
		return "offline"
	return ""


func _pump() -> void:
	while _active < max_parallel and not _queue.is_empty():
		_start(_queue.pop_front())


func _start(line: VoiceLine) -> void:
	var http := HTTPRequest.new()
	http.timeout = request_timeout
	http.use_threads = true
	add_child(http)
	_active += 1
	http.request_completed.connect(_on_completed.bind(http, line))
	var body := {
		"model": MODEL,
		"input": line.text,
		"response_format": "pcm",
		"sample_rate": sample_rate,
	}
	if line.voice != "":
		body["voice"] = line.voice
	var headers := PackedStringArray(["Content-Type: application/json"])
	if api_key != "":
		headers.append("Authorization: Bearer " + api_key)
	var err := http.request(base_url.trim_suffix("/") + "/v1/audio/speech", headers,
			HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_on_completed(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(),
				PackedByteArray(), http, line)


func _on_completed(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray, http: HTTPRequest, line: VoiceLine) -> void:
	http.queue_free()
	_active -= 1
	_pending.erase(line.key)
	if result != HTTPRequest.RESULT_SUCCESS:
		_set_offline()
		line._resolve(null, "offline")
	elif code == 200 and body.size() >= 2:
		_set_online()
		if body.size() % 2 == 1:
			body.resize(body.size() - 1)
		_save(line.key, body)
		line._resolve(_pcm_stream(body, sample_rate), "")
	elif code == 401 or code == 403:
		_auth_failed = true
		push_warning("Voice: the TTS service refused the API key; voice is off for this session")
		_fail_queue("unauthorized")
		line._resolve(null, "unauthorized")
	elif code == 502 or code == 503 or code == 504:
		_set_offline()
		line._resolve(null, "offline")
	else:
		# 400 (bad voice or text), 429 (server busy) or 500: this line only.
		line._resolve(null, "http_%d" % code)
	_pump()


func _set_online() -> void:
	_backoff = 0.0
	if not _online:
		_online = true
		online_changed.emit(true)


func _set_offline() -> void:
	_backoff = clampf(_backoff * 2.0, offline_backoff_min, offline_backoff_max)
	_retry_at_ms = Time.get_ticks_msec() + int(_backoff * 1000.0)
	# Queued lines would only time out one by one; drop them now.
	_fail_queue("offline")
	if _online:
		_online = false
		online_changed.emit(false)


func _fail_queue(reason: String) -> void:
	var dropped := _queue.duplicate()
	_queue.clear()
	for line: VoiceLine in dropped:
		_pending.erase(line.key)
		line._resolve(null, reason)


# --- cache ------------------------------------------------------------------

func _load_cached(key: String) -> AudioStreamWAV:
	var bundled := "%s/%s.wav" % [BUNDLED_DIR, key]
	if ResourceLoader.exists(bundled):
		return load(bundled) as AudioStreamWAV
	var path := "%s/%s.wav" % [cache_dir, key]
	if not FileAccess.file_exists(path):
		return null
	var stream := read_wav(FileAccess.get_file_as_bytes(path))
	if stream == null:
		DirAccess.remove_absolute(path)  # truncated or corrupt: fetch again
	return stream


func _save(key: String, pcm: PackedByteArray) -> void:
	if DirAccess.make_dir_recursive_absolute(cache_dir) != OK:
		return
	var path := "%s/%s.wav" % [cache_dir, key]
	var tmp := path + ".part"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(wav_bytes(pcm, sample_rate))
	f.close()
	# Rename last, so a crash never leaves a half-written line in the cache.
	DirAccess.rename_absolute(tmp, path)


## Keeps the cache under cache_limit_mb by deleting the oldest files.
func _prune_cache() -> void:
	var dir := DirAccess.open(cache_dir)
	if dir == null:
		return
	var files: Array = []
	var total := 0
	for name in dir.get_files():
		var path := cache_dir.path_join(name)
		if name.ends_with(".part"):
			dir.remove(name)
			continue
		var size := FileAccess.get_size(path)
		total += size
		files.append([FileAccess.get_modified_time(path), size, name])
	var limit := cache_limit_mb * 1024 * 1024
	if total <= limit:
		return
	files.sort_custom(func(a, b): return a[0] < b[0])
	for entry in files:
		if total <= int(limit * 0.9):
			break
		dir.remove(entry[2])
		total -= entry[1]


# --- audio ------------------------------------------------------------------

static func _pcm_stream(pcm: PackedByteArray, rate: int) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = pcm
	return stream


## A mono 16-bit PCM WAV file around [param pcm].
static func wav_bytes(pcm: PackedByteArray, rate: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(44)
	out.encode_u32(0, 0x46464952)  # "RIFF"
	out.encode_u32(4, 36 + pcm.size())
	out.encode_u32(8, 0x45564157)  # "WAVE"
	out.encode_u32(12, 0x20746d66)  # "fmt "
	out.encode_u32(16, 16)
	out.encode_u16(20, 1)  # PCM
	out.encode_u16(22, 1)  # mono
	out.encode_u32(24, rate)
	out.encode_u32(28, rate * 2)
	out.encode_u16(32, 2)
	out.encode_u16(34, 16)
	out.encode_u32(36, 0x61746164)  # "data"
	out.encode_u32(40, pcm.size())
	out.append_array(pcm)
	return out


## Reads a mono or stereo 16-bit PCM WAV file. Returns null if it is not one
## or is truncated.
static func read_wav(bytes: PackedByteArray) -> AudioStreamWAV:
	if bytes.size() < 44 or bytes.decode_u32(0) != 0x46464952 \
			or bytes.decode_u32(8) != 0x45564157:
		return null
	var pos := 12
	var channels := 0
	var rate := 0
	while pos + 8 <= bytes.size():
		var id := bytes.decode_u32(pos)
		var size := bytes.decode_u32(pos + 4)
		pos += 8
		if id == 0x20746d66:  # "fmt "
			if size < 16 or bytes.decode_u16(pos) != 1 or bytes.decode_u16(pos + 14) != 16:
				return null
			channels = bytes.decode_u16(pos + 2)
			rate = bytes.decode_u32(pos + 4)
		elif id == 0x61746164:  # "data"
			if rate == 0 or channels < 1 or channels > 2 or pos + size > bytes.size():
				return null
			var stream := _pcm_stream(bytes.slice(pos, pos + size), rate)
			stream.stereo = channels == 2
			return stream
		pos += size + (size & 1)
	return null
