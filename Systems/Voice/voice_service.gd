class_name VoiceService
extends Node
## Spoken dialogue from the Falevon TTS service, registered as the "Voice"
## autoload. Requests are polled and never block a frame; lines baked into
## res://Assets/Voice come first, then the cache in user://voice_cache. When
## no voice can be had (offline, no key, web build) lines resolve to null at
## once and the game shows the text only. See Docs/systems/voice.md.
## [codeblock]
## var stream := await Voice.get_line("Ngươi đã phản bội ta.", "Mai Anh").wait()
## if stream: $Player.stream = stream; $Player.play()
## [/codeblock]

signal online_changed(online: bool)

## Bump when the request or the audio format changes, to invalidate caches.
const CACHE_VERSION := 1
const BUNDLED_DIR := "res://Assets/Voice"
const CONFIG_PATH := "user://voice.cfg"
const MODEL := "vieneu-v3-turbo"
## Server sample rates are 48000, 24000, 16000 and 8000. 24 kHz keeps the
## cache small enough for phones and is plenty for speech.
const SAMPLE_RATES: Array[int] = [48000, 24000, 16000, 8000]
const DEFAULT_SAMPLE_RATE := 24000
## Pruning stops once the cache is under this share of cache_limit_mb, so it
## does not run again on the next start.
const PRUNE_TARGET := 0.9

@export var enabled := true
@export var base_url := "https://tts.falevon.com"
## Sent as "Authorization: Bearer <key>". Never commit a key: set it in
## user://voice.cfg or the FALEMAG_TTS_KEY environment variable.
var api_key := ""
## Server preset voice used when a line names none; empty = server default.
@export var default_voice := ""
@export var sample_rate := DEFAULT_SAMPLE_RATE
## Seconds; a line that takes longer fails alone with error "timeout".
@export var request_timeout := 30.0
## The server shares a few stream slots with other clients; keep this low.
@export var max_parallel := 2
@export var cache_dir := "user://voice_cache"
@export var cache_limit_mb := 200
@export var offline_backoff_min := 15.0
@export var offline_backoff_max := 300.0

var _online := true
var _retry_at_ms := 0
## When the service last came back online; ticks in ms.
var _online_since_ms := 0
var _backoff := 0.0
var _auth_failed := false
var _cache_write_warned := false
var _request_warned := false
## True while leaving the tree, so lines asked for during exit resolve at once.
var _closing := false
## Spoken lines first in FIFO order, then prefetched lines.
var _queue: Array[VoiceLine] = []
## Lines queued or in flight, by cache key.
var _pending: Dictionary[String, VoiceLine] = {}
var _active := 0
var _space := RegEx.create_from_string("\\s+")


func _ready() -> void:
	load_config()
	_prune_cache.call_deferred()


func _enter_tree() -> void:
	_closing = false


func _exit_tree() -> void:
	# Set first: a caller that asks for a line from a finished handler below
	# must get "disabled", not a new request.
	_closing = true
	# Awaiting callers must never hang on a line nobody will finish.
	var lines := _pending.values()
	_pending.clear()
	_queue.clear()
	for child: Node in get_children():
		if child is HTTPRequest:
			# A late answer must not touch _active or the cache after exit.
			for connection: Dictionary in child.request_completed.get_connections():
				child.request_completed.disconnect(connection["callable"])
			child.queue_free()
	_active = 0
	for line: VoiceLine in lines:
		line._resolve(null, "disabled")


## Reads user://voice.cfg (section [voice]) and the FALEMAG_TTS_URL /
## FALEMAG_TTS_KEY environment variables, which win. Clears a refused key.
func load_config(path := CONFIG_PATH) -> void:
	_auth_failed = false
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		enabled = _config_value(cfg, path, "enabled", enabled)
		base_url = _config_value(cfg, path, "base_url", base_url)
		api_key = _config_value(cfg, path, "api_key", api_key)
		default_voice = _config_value(cfg, path, "default_voice", default_voice)
		sample_rate = _config_value(cfg, path, "sample_rate", sample_rate)
		cache_limit_mb = _config_value(cfg, path, "cache_limit_mb", cache_limit_mb)
	if OS.has_environment("FALEMAG_TTS_URL"):
		base_url = OS.get_environment("FALEMAG_TTS_URL")
	if OS.has_environment("FALEMAG_TTS_KEY"):
		api_key = OS.get_environment("FALEMAG_TTS_KEY")
	base_url = base_url.strip_edges().trim_suffix("/")
	api_key = api_key.strip_edges()
	if not sample_rate in SAMPLE_RATES:
		push_warning("Voice: unsupported sample_rate %d, using %d" % [sample_rate, DEFAULT_SAMPLE_RATE])
		sample_rate = DEFAULT_SAMPLE_RATE


func is_online() -> bool:
	return _online


## Returns a [VoiceLine] for [param text]. It is already done when the line is
## cached, or when no voice can be had right now.
func get_line(text: String, voice := "") -> VoiceLine:
	return _request(text, voice, false)


## Fetches lines in the background so they are cached before they are needed,
## for example the next dialogue scene. Spoken lines always go first.
func prefetch(texts: Array[String], voice := "") -> void:
	for text: String in texts:
		_request(text, voice, true)


## Plays [param text] on [param player]. Returns false if there is no voice.
func play(player: AudioStreamPlayer, text: String, voice := "") -> bool:
	var stream := await get_line(text, voice).wait()
	if stream == null or not is_instance_valid(player):
		return false
	player.stream = stream
	player.play()
	return true


## File name (without .wav) of a line in the cache and in [constant BUNDLED_DIR].
func cache_key(text: String, voice := "") -> String:
	var v := voice if voice != "" else default_voice
	var id := "%d|%s|%s|%d|%s" % [CACHE_VERSION, MODEL, v, sample_rate, normalize(text)]
	return id.sha256_text()


## [param text] trimmed, with every run of whitespace collapsed to one space.
func normalize(text: String) -> String:
	return _space.sub(text.strip_edges(), " ", true)


## Number of lines queued or in flight.
func pending_count() -> int:
	return _pending.size()


## Deletes every file in [member cache_dir]; bundled lines are kept.
func clear_cache() -> void:
	var dir := DirAccess.open(cache_dir)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)


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
			_promote(existing)
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
		_queue.insert(_spoken_end(), line)
	_pump()
	return line


## Index just after the last spoken line in the queue.
func _spoken_end() -> int:
	var index := 0
	while index < _queue.size() and not _queue[index].prefetch:
		index += 1
	return index


func _promote(line: VoiceLine) -> void:
	line.prefetch = false
	if _queue.has(line):
		_queue.erase(line)
		_queue.insert(_spoken_end(), line)


func _unavailable_reason() -> String:
	# Web: the service sends no CORS headers, so the browser would block it.
	if _closing or not enabled or base_url == "" or OS.has_feature("web") \
			or not is_inside_tree():
		return "disabled"
	if api_key == "":
		return "no_key"
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
	# A threaded request reads a blocking socket, and cancelling it (timeout,
	# shutdown) waits on the main thread until the server closes. Polled
	# requests never block a frame.
	http.use_threads = false
	add_child(http)
	_active += 1
	var started_ms := Time.get_ticks_msec()
	http.request_completed.connect(_on_completed.bind(http, line, started_ms))
	var body := {
		"model": MODEL,
		"input": line.text,
		"response_format": "pcm",
		"sample_rate": sample_rate,
	}
	if line.voice != "":
		body["voice"] = line.voice
	var headers := PackedStringArray(["Content-Type: application/json",
			"Authorization: Bearer " + api_key])
	var err := http.request(base_url.trim_suffix("/") + "/v1/audio/speech", headers,
			HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		if not _request_warned:
			_request_warned = true
			push_warning("Voice: cannot start a request to %s: error %d" % [base_url, err])
		_on_completed(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(),
				PackedByteArray(), http, line, started_ms)


func _on_completed(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray, http: HTTPRequest, line: VoiceLine, started_ms: int) -> void:
	http.queue_free()
	_active -= 1
	_pending.erase(line.key)
	if result == HTTPRequest.RESULT_TIMEOUT:
		# A long line or a busy server is slow, not gone: fail this line only.
		line._resolve(null, "timeout")
	elif result != HTTPRequest.RESULT_SUCCESS or code == 502 or code == 503 or code == 504:
		_set_offline(started_ms)
		line._resolve(null, "offline")
	else:
		# Any other answer, even an error, proves the service is reachable.
		_set_online()
		_handle_response(code, body, line)
	_pump()


func _handle_response(code: int, body: PackedByteArray, line: VoiceLine) -> void:
	if code == 200 and body.size() >= 2:
		if body.size() % 2 == 1:
			body.resize(body.size() - 1)
		_save(line.key, body)
		line._resolve(_pcm_stream(body, sample_rate), "")
	elif code == 401 or code == 403:
		if not _auth_failed:
			_auth_failed = true
			push_warning("Voice: the TTS service refused the API key; voice is off for this session")
		_fail_queue("unauthorized")
		line._resolve(null, "unauthorized")
	else:
		# 400 (bad voice or text), 429 (server busy) or 500: this line only.
		line._resolve(null, "http_%d" % code)


func _set_online() -> void:
	_backoff = 0.0
	if not _online:
		_online = true
		_online_since_ms = Time.get_ticks_msec()
		online_changed.emit(true)


## True when a request begun at [param started_ms] predates the latest state
## change: the current retry window while offline, or the last recovery while
## online. A newer request already settled the state, so it fails its line only.
func _is_stale_failure(started_ms: int) -> bool:
	if _online:
		return started_ms < _online_since_ms
	return started_ms < _retry_at_ms


## [param started_ms] is when the failed request began. A stale failure (see
## [method _is_stale_failure]) changes nothing; any other doubles the backoff,
## marks the service offline and drops the queue.
func _set_offline(started_ms: int) -> void:
	if _is_stale_failure(started_ms):
		return
	var was_online := _online
	_backoff = clampf(_backoff * 2.0, offline_backoff_min, offline_backoff_max)
	_retry_at_ms = Time.get_ticks_msec() + int(_backoff * 1000.0)
	# Update state before any signal or line callback: a caller may ask for a
	# new line from a handler and must see the service as offline.
	_online = false
	if was_online:
		push_warning("Voice: the TTS service at %s is unreachable; text only, retrying after %d s"
				% [base_url, int(_backoff)])
		online_changed.emit(false)
	# Queued lines would only time out one by one; drop them now.
	_fail_queue("offline")


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
	var err := DirAccess.make_dir_recursive_absolute(cache_dir)
	if err != OK:
		_warn_cache_write("make_dir", err)
		return
	var path := "%s/%s.wav" % [cache_dir, key]
	var tmp := path + ".part"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		_warn_cache_write("open", FileAccess.get_open_error())
		return
	var written := f.store_buffer(wav_bytes(pcm, sample_rate))
	f.close()
	if not written:
		DirAccess.remove_absolute(tmp)
		_warn_cache_write("write", ERR_FILE_CANT_WRITE)
		return
	# Rename last, so a crash never leaves a half-written line in the cache.
	err = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		DirAccess.remove_absolute(tmp)
		_warn_cache_write("rename", err)


## The line still plays; it is only fetched again next time. Once a session.
func _warn_cache_write(step: String, err: Error) -> void:
	if _cache_write_warned:
		return
	_cache_write_warned = true
	push_warning("Voice: cannot write the cache in %s (%s: %s); lines will be fetched again"
			% [cache_dir, step, error_string(err)])


## Keeps the cache under cache_limit_mb by deleting the oldest written files.
func _prune_cache() -> void:
	var dir := DirAccess.open(cache_dir)
	if dir == null:
		return
	var files: Array[Dictionary] = []
	var total := 0
	for file: String in dir.get_files():
		if file.ends_with(".part"):
			dir.remove(file)
			continue
		var path := cache_dir.path_join(file)
		var size := FileAccess.get_size(path)
		total += size
		files.append({"modified": FileAccess.get_modified_time(path), "size": size, "file": file})
	var limit := cache_limit_mb * 1024 * 1024
	if total <= limit:
		return
	files.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["modified"] < b["modified"])
	var target := int(limit * PRUNE_TARGET)
	for entry: Dictionary in files:
		if total <= target:
			break
		dir.remove(entry["file"])
		total -= int(entry["size"])


## Reads one [voice] value; a value of the wrong type keeps [param fallback].
func _config_value(cfg: ConfigFile, path: String, field: String, fallback: Variant) -> Variant:
	var value: Variant = cfg.get_value("voice", field, fallback)
	if typeof(value) == typeof(fallback):
		return value
	# Name the field and types only: the value may be the API key.
	push_warning("Voice: %s field %s must be %s, not %s; keeping the default"
			% [path, field, type_string(typeof(fallback)), type_string(typeof(value))])
	return fallback


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
		# Check the whole chunk is there before decoding any field in it.
		if pos + size > bytes.size():
			return null
		if id == 0x20746d66:  # "fmt "
			if size < 16 or bytes.decode_u16(pos) != 1 or bytes.decode_u16(pos + 14) != 16:
				return null
			channels = bytes.decode_u16(pos + 2)
			rate = bytes.decode_u32(pos + 4)
		elif id == 0x61746164:  # "data"
			if rate == 0 or channels < 1 or channels > 2:
				return null
			var stream := _pcm_stream(bytes.slice(pos, pos + size), rate)
			stream.stereo = channels == 2
			return stream
		pos += size + (size & 1)
	return null
