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
## $Caption.text = VoiceService.display_text(line_text)  # without inline tags
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
## The voice the server speaks when a request names none.
const SERVER_DEFAULT_VOICE := "Hải Đăng"
## Asks a busy server to answer 429 at once instead of holding the request up
## to 10 s; sent with prefetched lines only.
const NO_WAIT_HEADER := "X-VieNeu-No-Wait: 1"
## Seconds a prefetch waits after a 429 without a usable Retry-After, and the
## longest wait whatever the header says.
const BUSY_RETRY_DEFAULT := 2.0
const BUSY_RETRY_MAX := 30.0

@export var enabled := true
@export var base_url := "https://tts.falevon.com"
## Sent as "Authorization: Bearer <key>". Never commit a key: set it in
## user://voice.cfg or the FALEMAG_TTS_KEY environment variable.
var api_key := ""
## Server preset voice used when a line names none; empty = server default
## ([constant SERVER_DEFAULT_VOICE]).
@export var default_voice := ""
@export var sample_rate := DEFAULT_SAMPLE_RATE
## Seconds; a line that takes longer fails alone with error "timeout".
@export var request_timeout := 30.0
## The server shares a few stream slots with other clients; keep this low.
@export var max_parallel := 2
## Times a prefetched line answered 429 is put back in the queue before it
## fails with "http_429".
@export var prefetch_retries := 3
@export var cache_dir := "user://voice_cache"
@export var cache_limit_mb := 200
@export var offline_backoff_min := 15.0
@export var offline_backoff_max := 300.0

var _online := true
## The last value [signal online_changed] was emitted with, so it never fires
## the same value twice in a row.
var _last_emitted_online := true
var _retry_at_ms := 0
## When the service last came back online; ticks in ms.
var _online_since_ms := 0
var _backoff := 0.0
var _auth_failed := false
var _cache_write_warned := false
var _request_warned := false
## True while leaving the tree, so lines asked for during exit resolve at once.
var _closing := false
## Spoken lines first in FIFO order, then prefetched lines (some of them
## waiting out a 429; see [method _pump]).
var _queue: Array[VoiceLine] = []
## Lines queued or in flight, by cache key.
var _pending: Dictionary[String, VoiceLine] = {}
var _active := 0
static var _space := RegEx.create_from_string("\\s+")


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


## Returns a [VoiceLine] for [param text], spoken in [param style] (null is
## the default). It is already done when the line is cached, or when no voice
## can be had right now. Inline tags in the text are sent as they are.
func get_line(text: String, voice := "", style: VoiceStyle = null) -> VoiceLine:
	return _request(text, voice, style, false)


## Fetches lines in the background so they are cached before they are needed,
## for example the next dialogue scene. Spoken lines always go first.
func prefetch(texts: Array[String], voice := "", style: VoiceStyle = null) -> void:
	for text: String in texts:
		_request(text, voice, style, true)


## Plays [param text] on [param player]. Returns false if there is no voice.
func play(player: AudioStreamPlayer, text: String, voice := "",
		style: VoiceStyle = null) -> bool:
	var stream := await get_line(text, voice, style).wait()
	if stream == null or not is_instance_valid(player):
		return false
	player.stream = stream
	player.play()
	return true


## File name (without .wav) of a line in the cache and in [constant BUNDLED_DIR].
## A null or default [param style] gives the same key as before styles existed.
func cache_key(text: String, voice := "", style: VoiceStyle = null) -> String:
	var v := voice if voice != "" else default_voice
	var id := "%d|%s|%s|%d|%s" % [CACHE_VERSION, MODEL, v, sample_rate, normalize(text)]
	# An unstyled id starts with the version number and a styled one with a
	# field name, so the two can never collide.
	if style != null and not style.is_default():
		id = "%s|%s" % [style.key_text(), id]
	return id.sha256_text()


## [param text] trimmed, with every run of whitespace collapsed to one space.
static func normalize(text: String) -> String:
	return _space.sub(text.strip_edges(), " ", true)


## [param text] as the player reads it: inline control tags ([speed=1.3],
## [voice=Mai Anh], [reset]) and non-verbal cues ([cười]) removed, spaces
## collapsed, line breaks kept. Any other bracketed text is kept.
static func display_text(text: String) -> String:
	return VoiceTags.display_text(text)


## Number of lines queued, in flight or waiting out a 429.
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

func _request(text: String, voice: String, style: VoiceStyle, background: bool) -> VoiceLine:
	var line := VoiceLine.new()
	line.text = normalize(text)
	line.voice = voice if voice != "" else default_voice
	# A copy, so a caller changing its style later cannot split key and body.
	if style != null and not style.is_default():
		line.style = style.duplicate() as VoiceStyle
	line.key = cache_key(text, voice, line.style)
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
			_pump()
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


## A line asked for while it waits out a 429 goes out at once, without the
## no-wait header.
func _promote(line: VoiceLine) -> void:
	line.prefetch = false
	line._busy_wait = false
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


## Starts queued lines while slots are free, skipping prefetches that wait out
## a 429. Rescans from the front after each start: a failed start may change
## the queue.
func _pump() -> void:
	var index := 0
	while _active < max_parallel and index < _queue.size():
		var line := _queue[index]
		if line._busy_wait:
			index += 1
			continue
		_queue.remove_at(index)
		_start(line)
		index = 0


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
	var is_no_wait := line.prefetch
	http.request_completed.connect(_on_completed.bind(http, line, started_ms, is_no_wait))
	var headers := PackedStringArray(["Content-Type: application/json",
			"Authorization: Bearer " + api_key])
	if is_no_wait:
		headers.append(NO_WAIT_HEADER)
	var err := http.request(base_url.trim_suffix("/") + "/v1/audio/speech", headers,
			HTTPClient.METHOD_POST, JSON.stringify(_request_body(line)))
	if err != OK:
		if not _request_warned:
			_request_warned = true
			push_warning("Voice: cannot start a request to %s: error %d" % [base_url, err])
		_on_completed(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(),
				PackedByteArray(), http, line, started_ms, is_no_wait)


## The JSON body of the request for [param line]: style fields only when not
## the default, so an unstyled request is unchanged.
func _request_body(line: VoiceLine) -> Dictionary:
	var body := {
		"model": MODEL,
		"input": line.text,
		"response_format": "pcm",
		"sample_rate": sample_rate,
	}
	if line.voice != "":
		body["voice"] = line.voice
	if line.style != null:
		body.merge(line.style.request_fields())
	return body


## [param is_no_wait] is true when the request carried [constant NO_WAIT_HEADER].
func _on_completed(result: int, code: int, headers: PackedStringArray,
		body: PackedByteArray, http: HTTPRequest, line: VoiceLine, started_ms: int,
		is_no_wait: bool) -> void:
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
		_on_answered(code, headers, body, line, is_no_wait)
	_pump()


## Any answer other than 502/503/504, even an error, proves the service is
## reachable: the state is online before this line is requeued or resolved,
## and [signal online_changed] fires only after that.
func _on_answered(code: int, headers: PackedStringArray, body: PackedByteArray,
		line: VoiceLine, is_no_wait: bool) -> void:
	var came_online := _mark_online()
	var is_busy := code == 429 and is_no_wait
	# A busy line is put back only while voice is still available: a 401, a
	# cleared key or enabled = false since the request began ends it here.
	var busy_reason := _unavailable_reason() if is_busy else ""
	if busy_reason != "":
		line._resolve(null, busy_reason)
	elif not (is_busy and _requeue_busy(line, headers)):
		_handle_response(code, body, line)
	# A finished handler above may have taken the service offline again.
	if came_online and _online:
		_emit_online_changed(true)


## A no-wait request was refused as busy. A line asked for since it was sent
## goes again at once without the header; a prefetch goes to the back of the
## queue for Retry-After seconds. False once prefetch_retries are used up.
func _requeue_busy(line: VoiceLine, headers: PackedStringArray) -> bool:
	if line.prefetch:
		if line.busy_retries >= prefetch_retries:
			return false
		line.busy_retries += 1
		line._busy_wait = true
		_queue.push_back(line)
		# A timer, not a check in _pump: nothing else may pump before then.
		get_tree().create_timer(_retry_after_seconds(headers), true, false, true) \
				.timeout.connect(_end_busy_wait.bind(line))
	else:
		_queue.insert(_spoken_end(), line)
	_pending[line.key] = line
	return true


## A promoted line (no longer waiting) was already sent; leave it alone. A line
## whose voice became unavailable meanwhile is resolved instead of sent.
func _end_busy_wait(line: VoiceLine) -> void:
	if not line._busy_wait:
		return
	line._busy_wait = false
	var reason := _unavailable_reason()
	if reason != "":
		_queue.erase(line)
		if _pending.get(line.key) == line:
			_pending.erase(line.key)
		line._resolve(null, reason)
	_pump()


## Seconds from the Retry-After header in [param headers]; the default when it
## is missing or not a number of seconds, and never more than the maximum.
static func _retry_after_seconds(headers: PackedStringArray) -> float:
	for header: String in headers:
		if not header.to_lower().begins_with("retry-after:"):
			continue
		var value := header.substr(12).strip_edges()
		if value.is_valid_float() and value.to_float() >= 0.0:
			return minf(value.to_float(), BUSY_RETRY_MAX)
		break
	return BUSY_RETRY_DEFAULT


func _handle_response(code: int, body: PackedByteArray, line: VoiceLine) -> void:
	if code == 200 and body.size() >= 2:
		if body.size() % 2 == 1:
			body.resize(body.size() - 1)
		_save(line.key, body)
		line._resolve(VoiceWav.pcm_stream(body, sample_rate), "")
	elif code == 401 or code == 403:
		if not _auth_failed:
			_auth_failed = true
			push_warning("Voice: the TTS service refused the API key; voice is off for this session")
		_fail_queue("unauthorized")
		line._resolve(null, "unauthorized")
	else:
		# 400 (bad voice, tag or style), 429 (server busy) or 500: this line only.
		line._resolve(null, "http_%d" % code)


## Updates the state only; true when the service was offline, and the caller
## then emits [signal online_changed] once the answered line is settled.
func _mark_online() -> bool:
	_backoff = 0.0
	if _online:
		return false
	_online = true
	_online_since_ms = Time.get_ticks_msec()
	return true


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
	# new line from a handler and must see the service as offline. Lines still
	# pending then fail offline too, so the signal may go before they resolve.
	_online = false
	if was_online:
		push_warning("Voice: the TTS service at %s is unreachable; text only, retrying after %d s"
				% [base_url, int(_backoff)])
		_emit_online_changed(false)
	# Queued lines would only time out one by one; drop them now.
	_fail_queue("offline")


## Emits [signal online_changed] only when [param online] differs from the last
## emitted value: a handler that took the service offline again while an answer
## was settled must not make observers see two false in a row.
func _emit_online_changed(online: bool) -> void:
	if online == _last_emitted_online:
		return
	_last_emitted_online = online
	online_changed.emit(online)


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
	var stream := VoiceWav.read_wav(FileAccess.get_file_as_bytes(path))
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
	var written := f.store_buffer(VoiceWav.wav_bytes(pcm, sample_rate))
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
