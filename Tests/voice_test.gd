extends SceneTree
## Tests the voice module against a fake TTS server on localhost: WAV
## reading, config types, caching, request shape and order, styles and tags,
## de-duplication, missing key, timeout, auth failure, offline backoff, stale
## failures, busy prefetches (429) and shutdown.

const CACHE := "user://voice_test_cache"
const CONFIG := "user://voice_test.cfg"

var _failures := 0


class FakeServer extends Node:
	var server := TCPServer.new()
	var port := 0
	var status := 200
	## False holds each request open without an answer.
	var respond := true
	var body := PackedByteArray()
	## Sent as a Retry-After header with every answer when not empty.
	var retry_after := ""
	var requests: Array[String] = []
	## When each request was read, in ticks ms.
	var times: Array[int] = []
	var _peers: Array = []  # [StreamPeerTCP, PackedByteArray]
	var _held: Array[StreamPeerTCP] = []

	func start() -> void:
		for p: int in range(18750, 18800):
			if server.listen(p, "127.0.0.1") == OK:
				port = p
				return

	## The "input" of every request received, in order.
	func inputs() -> Array[String]:
		var out: Array[String] = []
		for raw: String in requests:
			var json: Dictionary = JSON.parse_string(raw.substr(raw.find("\r\n\r\n") + 4))
			out.append(str(json.get("input")))
		return out

	## The JSON body of request [param index].
	func json(index: int) -> Dictionary:
		var raw := requests[index]
		return JSON.parse_string(raw.substr(raw.find("\r\n\r\n") + 4))

	## True when request [param index] carried [param header] ("Name: value").
	func has_header(index: int, header: String) -> bool:
		var raw := requests[index]
		return raw.substr(0, raw.find("\r\n\r\n")).to_lower().contains("\r\n" + header.to_lower())

	func _process(_delta: float) -> void:
		while server.is_connection_available():
			_peers.append([server.take_connection(), PackedByteArray()])
		for entry: Array in _peers.duplicate():
			var peer: StreamPeerTCP = entry[0]
			peer.poll()
			if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				_peers.erase(entry)  # the client gave up before sending it all
				continue
			var n := peer.get_available_bytes()
			if n > 0:
				entry[1].append_array(peer.get_data(n)[1])
			var raw: String = entry[1].get_string_from_utf8()
			var head_end := raw.find("\r\n\r\n")
			if head_end < 0:
				continue
			var length := 0
			for h: String in raw.substr(0, head_end).split("\r\n"):
				if h.to_lower().begins_with("content-length:"):
					length = h.substr(15).strip_edges().to_int()
			if entry[1].size() < head_end + 4 + length:
				continue
			requests.append(raw)
			times.append(Time.get_ticks_msec())
			_peers.erase(entry)
			if not respond:
				_held.append(peer)
				continue
			_answer(peer)

	## Waits until [param count] requests are held. The server reads only in
	## _process, so a request is not held in the frame it is asked for.
	func wait_held(count: int) -> void:
		while _held.size() < count:
			await get_tree().process_frame

	## Answers every held request with the current status and body.
	func release() -> void:
		for peer: StreamPeerTCP in _held:
			_answer(peer)
		_held.clear()

	## Answers the request held longest with the current status and body.
	func release_oldest() -> void:
		_answer(_held.pop_front())

	func _answer(peer: StreamPeerTCP) -> void:
		var extra := "" if retry_after == "" else "Retry-After: %s\r\n" % retry_after
		var reply := ("HTTP/1.1 %d X\r\nContent-Type: audio/pcm\r\n" % status + extra
				+ "Content-Length: %d\r\nConnection: close\r\n\r\n" % body.size()).to_utf8_buffer()
		reply.append_array(body)
		peer.put_data(reply)
		peer.disconnect_from_host()


func _initialize() -> void:
	_run()


func _check(ok: bool, what: String) -> bool:
	if not ok:
		_failures += 1
		push_error("FAIL: " + what)
	return ok


## Waits until [param line] waits out a 429, or is done (a failed test then
## reports at the next check instead of hanging).
func _wait_busy(line: VoiceLine) -> void:
	while not line._busy_wait and not line.done:
		await process_frame


## A service that ignores the developer's user://voice.cfg and environment.
func _service(url: String) -> VoiceService:
	var svc := VoiceService.new()
	root.add_child(svc)  # runs load_config(); everything it read is reset below
	svc.enabled = true
	svc.base_url = url
	svc.api_key = "test-key"
	svc.default_voice = ""
	svc.sample_rate = 24000
	svc.cache_limit_mb = 200
	svc.max_parallel = 2
	svc.cache_dir = CACHE
	svc.offline_backoff_min = 60.0
	svc.request_timeout = 5.0
	svc.clear_cache()
	return svc


func _wait_idle(svc: VoiceService) -> void:
	while svc.pending_count() > 0:
		await process_frame


func _run() -> void:
	await process_frame
	var pcm := _test_wav()
	_test_config()
	_test_style()
	_test_display_text()

	var fake := FakeServer.new()
	root.add_child(fake)
	fake.start()
	_check(fake.port != 0, "fake server listens")
	fake.body = pcm
	var url := "http://127.0.0.1:%d/" % fake.port
	var svc := _service(url)

	# keys
	_check(svc.cache_key("  Xin   chào ") == svc.cache_key("Xin chào"), "whitespace is normalized")
	_check(svc.cache_key("Xin chào", "A") != svc.cache_key("Xin chào", "B"), "voice is in the key")
	_check(svc.get_line("   ").error == "empty", "blank line resolves at once")
	_test_key_stability(svc)

	# first request goes to the server, duplicates share it
	var line := svc.get_line("Xin chào", "Mai Anh")
	var dup := svc.get_line("Xin   chào", "Mai Anh")
	_check(line == dup, "in-flight duplicates share one request")
	_check(not line.done, "uncached line is pending")
	var stream := await line.wait()
	_check(stream != null and is_equal_approx(stream.get_length(), 0.1), "stream from server")
	_check(fake.requests.size() == 1, "one request for duplicates")
	if not _check(fake.requests.size() == 1, "the first line made a request"):
		quit(1)
		return
	var req := fake.requests[0]
	_check(req.begins_with("POST /v1/audio/speech"), "endpoint")
	_check(req.contains("Authorization: Bearer test-key"), "auth header")
	var json: Dictionary = JSON.parse_string(req.substr(req.find("\r\n\r\n") + 4))
	_check(json.get("input") == "Xin chào" and json.get("voice") == "Mai Anh"
			and json.get("response_format") == "pcm" and int(json.get("sample_rate")) == 24000,
			"request body")
	_check(not json.has("speed") and not json.has("pitch") and not json.has("volume")
			and not json.has("effort"), "an unstyled request has no style fields")
	_check(not fake.has_header(0, "X-VieNeu-No-Wait: 1"), "a spoken line waits when busy")

	# second time comes from the cache, without the network
	var again := svc.get_line("Xin chào", "Mai Anh")
	_check(again.done and again.stream != null and again.stream.data == pcm, "cache hit")
	_check(fake.requests.size() == 1, "cache hit makes no request")

	# prefetch fills the cache in the background
	svc.prefetch(["Một", "Hai"], "Mai Anh")
	await _wait_idle(svc)
	_check(svc.get_line("Hai", "Mai Anh").done, "prefetched line is cached")
	_check(fake.requests.size() >= 3 and fake.has_header(1, "X-VieNeu-No-Wait: 1")
			and fake.has_header(2, "X-VieNeu-No-Wait: 1"),
			"prefetched lines ask not to wait")

	# no key: nothing goes to the network, cached lines still play
	svc.api_key = ""
	_check(svc.get_line("Không khóa").error == "no_key", "empty key is no_key")
	_check(svc.get_line("Hai", "Mai Anh").stream != null, "cached line plays without a key")
	_check(fake.requests.size() == 3, "empty key makes no request")
	svc.api_key = "test-key"

	await _test_styled_request(svc, fake)
	await _test_order(svc, fake)
	await _test_timeout(svc, fake)

	# a server error affects only that line
	fake.status = 429
	var busy := svc.get_line("Ba", "Mai Anh")
	await busy.wait()
	_check(busy.error == "http_429" and svc.is_online(), "429 fails the line only")

	# a refused key turns voice off for the session
	fake.status = 401
	var denied := svc.get_line("Bốn")
	await denied.wait()
	_check(denied.error == "unauthorized", "401 is unauthorized")
	_check(svc.get_line("Năm").error == "unauthorized", "no more requests after 401")
	_check(svc.pending_count() == 0, "nothing left pending")
	svc.queue_free()

	await _test_backoff(url, fake)
	await _test_slow_failure(url, fake)
	await _test_stale_after_recovery(url, fake)
	await _test_offline_reentrancy(url, fake)
	await _test_offline_again_in_handler(url, fake)
	_test_shutdown(url, fake)
	await _test_busy_requeue(url, fake)
	await _test_busy_exhausted(url, fake)
	await _test_busy_promoted(url, fake)
	await _test_busy_promoted_in_flight(url, fake)
	await _test_busy_unavailable(url, fake)
	await _test_busy_ends_offline(url, fake)
	await _test_busy_exit(url, fake)
	await _test_malformed_url()

	# unreachable server: offline, and later lines fail at once
	var off := _service("http://127.0.0.1:%d" % _unused_port())
	var went_offline: Array[bool] = []
	off.online_changed.connect(func(o: bool) -> void: went_offline.append(o))
	var lost := off.get_line("Sáu")
	await lost.wait()
	_check(lost.error == "offline" and not off.is_online(), "unreachable server is offline")
	_check(went_offline == [false], "online_changed fired")
	_check(off.get_line("Bảy").error == "offline", "offline lines resolve at once")
	off.clear_cache()
	off.queue_free()
	DirAccess.remove_absolute(CONFIG)

	if _failures == 0:
		print("Voice test passed")
	quit(1 if _failures > 0 else 0)


## A port nothing listens on: listen on one, then stop.
func _unused_port() -> int:
	var probe := TCPServer.new()
	for p: int in range(18800, 18900):
		if probe.listen(p, "127.0.0.1") == OK:
			probe.stop()
			return p
	return 0


func _test_wav() -> PackedByteArray:
	var pcm := PackedByteArray()
	pcm.resize(4800)  # 0.1 s at 24 kHz
	for i: int in pcm.size():
		pcm[i] = i % 251
	var wav_file := VoiceWav.wav_bytes(pcm, 24000)
	var wav := VoiceWav.read_wav(wav_file)
	_check(wav != null and wav.mix_rate == 24000 and wav.data == pcm, "wav round trip")
	for size: int in [0, 10, 43, 44, 50, 100, wav_file.size() - 1]:
		_check(VoiceWav.read_wav(wav_file.slice(0, size)) == null,
				"wav truncated to %d bytes is rejected" % size)
	# A "fmt " chunk cut short after a padding chunk must not be decoded.
	var cut := wav_file.slice(0, 12)
	cut.append_array("JUNK".to_ascii_buffer())
	var junk_size := PackedByteArray()
	junk_size.resize(30)
	junk_size.encode_u32(0, 26)
	cut.append_array(junk_size)
	cut.append_array(wav_file.slice(12, 24))
	_check(cut.size() > 44 and VoiceWav.read_wav(cut) == null, "cut fmt chunk is rejected")
	return pcm


func _test_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("voice", "sample_rate", "fast")
	cfg.set_value("voice", "cache_limit_mb", 50)
	cfg.save(CONFIG)
	var svc := VoiceService.new()
	print("(one warning about sample_rate is expected)")
	svc.load_config(CONFIG)
	_check(svc.sample_rate == 24000, "wrong config type keeps the default")
	_check(svc.cache_limit_mb == 50, "config value is read")
	svc.free()


## Spoken lines go in FIFO order, ahead of prefetched ones.
func _test_order(svc: VoiceService, fake: FakeServer) -> void:
	svc.max_parallel = 1
	var first := fake.requests.size()
	svc.prefetch(["P1", "P2", "P3"])  # P1 starts at once
	svc.get_line("S1")
	svc.get_line("P3")  # promoted: behind S1
	svc.get_line("S2")
	await _wait_idle(svc)
	var order := fake.inputs().slice(first)
	_check(order == ["P1", "S1", "P3", "S2", "P2"], "queue order %s" % [order])
	_check(svc.pending_count() == 0, "pending_count back to 0")
	svc.max_parallel = 2


## A timeout fails one line and leaves the service online.
func _test_timeout(svc: VoiceService, fake: FakeServer) -> void:
	svc.request_timeout = 0.5
	fake.respond = false
	var slow := svc.get_line("Chậm")
	await slow.wait()
	_check(slow.error == "timeout" and svc.is_online(), "timeout fails the line only")
	fake.respond = true
	svc.request_timeout = 5.0
	var next := svc.get_line("Nhanh")
	_check(await next.wait() != null, "line after a timeout is fetched")


## 502 marks the service offline once per outage, then it retries.
func _test_backoff(url: String, fake: FakeServer) -> void:
	var svc := _service(url)
	svc.offline_backoff_min = 0.3
	var changes: Array[bool] = []
	svc.online_changed.connect(func(o: bool) -> void: changes.append(o))
	fake.status = 502
	var first := fake.requests.size()
	var a := svc.get_line("Một trăm")
	var b := svc.get_line("Hai trăm")  # both in flight in one outage
	await a.wait()
	await b.wait()
	_check(a.error == "offline" and b.error == "offline" and not svc.is_online(), "502 is offline")
	_check(svc.get_line("Ba trăm").error == "offline", "line during backoff resolves at once")
	_check(fake.requests.size() == first + 2, "no request during backoff")
	await create_timer(0.4).timeout  # longer than one backoff, shorter than two
	fake.status = 200
	var back := svc.get_line("Bốn trăm")
	_check(await back.wait() != null and svc.is_online(), "request goes out after the backoff")
	_check(changes == [false], "online_changed(true) fires after the line resolves")
	await process_frame
	_check(changes == [false, true], "online_changed off then on")

	fake.status = 502
	await svc.get_line("Năm trăm").wait()
	await create_timer(0.4).timeout
	fake.status = 400
	var bad := svc.get_line("Sáu trăm")
	await bad.wait()
	_check(bad.error == "http_400" and svc.is_online(), "400 after offline is online again")
	fake.status = 200
	svc.clear_cache()
	svc.queue_free()


## Leaving the tree finishes every pending line, so no caller hangs.
func _test_shutdown(url: String, fake: FakeServer) -> void:
	var svc := _service(url)
	svc.max_parallel = 1
	fake.respond = false
	var running := svc.get_line("Đang chạy")
	var queued := svc.get_line("Đang chờ")
	var during: Array[VoiceLine] = []
	queued.finished.connect(func(_s: AudioStreamWAV) -> void: during.append(svc.get_line("Trong lúc thoát")))
	var http: HTTPRequest = svc.get_children().filter(func(c: Node) -> bool: return c is HTTPRequest)[0]
	var requests_before := fake.requests.size()
	root.remove_child(svc)
	_check(running.error == "disabled" and queued.error == "disabled", "exit resolves pending lines")
	_check(svc.pending_count() == 0, "nothing pending after exit")
	_check(during.size() == 1 and during[0].done and during[0].error == "disabled",
			"a line asked for during exit is disabled at once")
	_check(svc.get_children().filter(func(c: Node) -> bool: return c is HTTPRequest).size() == 1,
			"a line asked for during exit adds no request")
	_check(fake.requests.size() == requests_before, "exit sends no request")
	# A late answer must not reach the service: _active stays 0, nothing is cached.
	http.request_completed.emit(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), _test_pcm())
	_check(svc._active == 0, "late completion after exit leaves _active at 0")
	_check(not FileAccess.file_exists("%s/%s.wav" % [CACHE, svc.cache_key("Đang chạy")]),
			"late completion after exit writes no cache file")
	fake.respond = true
	svc.free()


## A request begun before the current retry window that fails while the retry
## is in flight fails its own line only: no backoff growth, no queue drop.
func _test_slow_failure(url: String, fake: FakeServer) -> void:
	var svc := _service(url)
	svc.offline_backoff_min = 0.3
	var changes: Array[bool] = []
	svc.online_changed.connect(func(o: bool) -> void: changes.append(o))
	fake._held.clear()
	fake.respond = false
	var slow := svc.get_line("Chậm hơn")
	await fake.wait_held(1)
	fake.respond = true
	fake.status = 502
	await svc.get_line("Nhanh hơn").wait()
	_check(not svc.is_online() and is_equal_approx(svc._backoff, 0.3), "first failure sets the backoff")
	await create_timer(0.4).timeout  # past the retry time
	var retry_at_ms := svc._retry_at_ms
	fake.respond = false
	var retry := svc.get_line("Thử lại")
	await fake.wait_held(2)
	var queued := svc.get_line("Xếp hàng")  # both slots are busy
	fake.release_oldest()  # the slow request, as a 502
	await slow.wait()
	_check(slow.error == "offline", "a stale failure fails its own line")
	_check(is_equal_approx(svc._backoff, 0.3) and svc._retry_at_ms == retry_at_ms,
			"a stale failure does not grow the backoff")
	_check(not queued.done and svc.pending_count() == 2, "a stale failure keeps the queue")
	_check(not retry.done, "the retry is still pending after a stale failure")
	_check(not svc.is_online() and changes == [false], "a stale failure leaves the state offline")
	await _finish_held(svc, fake)


## A request begun before the service came back that fails afterwards fails
## its own line only: the service stays online and keeps its queue.
func _test_stale_after_recovery(url: String, fake: FakeServer) -> void:
	var svc := _service(url)
	svc.offline_backoff_min = 0.3
	var changes: Array[bool] = []
	svc.online_changed.connect(func(o: bool) -> void: changes.append(o))
	fake._held.clear()
	fake.respond = false
	var old := svc.get_line("Dòng cũ")
	await fake.wait_held(1)
	fake.respond = true
	fake.status = 502
	await svc.get_line("Mất kết nối").wait()
	await create_timer(0.4).timeout  # past the retry time
	fake.status = 200
	_check(await svc.get_line("Trở lại").wait() != null and svc.is_online(),
			"a newer request brings the service back")
	fake.respond = false
	var running := svc.get_line("Đang chạy sau")
	await fake.wait_held(2)
	var queued := svc.get_line("Xếp hàng sau")  # both slots are busy
	fake.status = 502
	fake.release_oldest()  # the old request
	await old.wait()
	_check(old.error == "offline", "an old failure fails its own line")
	_check(svc.is_online() and changes == [false, true], "an old failure keeps the service online")
	_check(not queued.done and not running.done and svc.pending_count() == 2,
			"an old failure keeps the queue")
	_check(svc._backoff == 0.0, "an old failure does not start a backoff")
	await _finish_held(svc, fake)


## Answers every held and later request with 200, then frees the service.
func _finish_held(svc: VoiceService, fake: FakeServer) -> void:
	fake.status = 200
	fake.respond = true
	fake.release()
	await _wait_idle(svc)
	svc.clear_cache()
	svc.queue_free()


## A line asked for from the finished handler of a dropped line goes nowhere.
func _test_offline_reentrancy(url: String, fake: FakeServer) -> void:
	var svc := _service(url)
	svc.max_parallel = 1
	fake.status = 502
	var first := fake.requests.size()
	var a := svc.get_line("Dòng A")
	var b := svc.get_line("Dòng B")
	var from_handler: Array[VoiceLine] = []
	b.finished.connect(func(_s: AudioStreamWAV) -> void: from_handler.append(svc.get_line("Dòng C")))
	await a.wait()
	_check(a.error == "offline" and b.error == "offline", "A and B fail offline")
	_check(from_handler.size() == 1 and from_handler[0].done and from_handler[0].error == "offline",
			"a line asked for from a dropped line's handler is offline at once")
	_check(fake.requests.size() == first + 1, "no extra request for the line asked for in the handler")
	fake.status = 200
	svc.queue_free()


## A finished handler that takes the service offline again while its answer is
## settled must not make observers see online_changed(false) twice in a row.
func _test_offline_again_in_handler(url: String, fake: FakeServer) -> void:
	var svc := _service(url)
	svc.offline_backoff_min = 0.3
	var changes: Array[bool] = []
	svc.online_changed.connect(func(o: bool) -> void: changes.append(o))
	fake.status = 502
	await svc.get_line("Mất kết nối trước").wait()
	await create_timer(0.4).timeout  # past the retry time
	fake.status = 200
	var back := svc.get_line("Về rồi lại mất")
	back.finished.connect(func(_s: AudioStreamWAV) -> void: svc._set_offline(Time.get_ticks_msec()))
	await back.wait()
	await process_frame
	_check(not svc.is_online() and changes == [false],
			"going offline again in a handler emits no second false %s" % [changes])
	svc.clear_cache()
	svc.queue_free()


## A base_url the HTTP client rejects is reported and handled as offline.
func _test_malformed_url() -> void:
	var svc := _service("http://exa mple.com:99999999")
	print("(one warning about a request that cannot start is expected)")
	var line := svc.get_line("Hỏng")
	await line.wait()
	_check(line.error == "offline" and not svc.is_online(), "a rejected request is offline")
	svc.queue_free()


func _test_pcm() -> PackedByteArray:
	var pcm := PackedByteArray()
	pcm.resize(4800)
	return pcm


## Values are clamped to the server limits; speed and pitch are rounded as the
## server rounds them, volume and effort to 0.05.
func _test_style() -> void:
	var wild := VoiceStyle.create(9.0, -20.0, 0.0, 5.0)
	_check(wild.sent_speed() == 4.0 and wild.sent_pitch() == -12.0 and wild.sent_volume() == 0.1
			and wild.sent_effort() == 2.0, "style values are clamped")
	var odd := VoiceStyle.create(1.33, 0.74, 1.024, 1.5)
	_check(odd.sent_speed() == 1.35 and odd.sent_pitch() == 0.5 and odd.sent_volume() == 1.0,
			"style values are rounded to the server steps")
	_check(odd.request_fields() == {"speed": 1.35, "pitch": 0.5, "effort": 1.5},
			"request fields hold only non-default values %s" % [odd.request_fields()])
	_check(odd.key_text() == "speed=1.35 pitch=0.5 effort=1.50", "style key text %s" % odd.key_text())
	_check(VoiceStyle.new().is_default() and VoiceStyle.new().key_text() == "", "a new style is the default")
	_check(VoiceStyle.create(1.01, 0.2, 0.99, 0.02).is_default(), "a style that rounds to the default is the default")
	_check(not VoiceStyle.create(1.0, 0.0, 1.0, 1.0).is_default(), "effort alone is not the default")
	var broken := VoiceStyle.create(NAN, INF, -INF, NAN)
	_check(broken.sent_speed() == 1.0 and broken.sent_pitch() == 0.0 and broken.sent_volume() == 1.0
			and broken.sent_effort() == 0.0 and broken.is_default(),
			"NaN and infinite values are the field defaults")
	var half := VoiceStyle.create(NAN, 2.0, INF, 1.0)
	_check(half.request_fields() == {"pitch": 2.0, "effort": 1.0},
			"a NaN value does not hide the others %s" % [half.request_fields()])


## A null or default style keeps the key of an unstyled line, computed as it
## was before styles existed, so existing caches and bundled files still match.
func _test_key_stability(svc: VoiceService) -> void:
	var old_key := ("%d|%s|%s|%d|%s" % [VoiceService.CACHE_VERSION, VoiceService.MODEL, "Mai Anh",
			24000, "Xin chào"]).sha256_text()
	_check(svc.cache_key("Xin chào", "Mai Anh") == old_key, "unstyled key is unchanged")
	_check(svc.cache_key("Xin chào", "Mai Anh", null) == old_key, "a null style keeps the key")
	_check(svc.cache_key("Xin chào", "Mai Anh", VoiceStyle.new()) == old_key, "a default style keeps the key")
	_check(svc.cache_key("Xin chào", "Mai Anh", VoiceStyle.create(1.01)) == old_key,
			"a style rounding to the default keeps the key")
	var fast := svc.cache_key("Xin chào", "Mai Anh", VoiceStyle.create(1.3))
	_check(fast != old_key, "a style is in the key")
	_check(svc.cache_key("Xin chào", "Mai Anh", VoiceStyle.create(1.31)) == fast,
			"styles the server speaks alike share a key")
	_check(svc.cache_key("Xin chào", "Mai Anh", VoiceStyle.create(1.0, -2.0)) != fast,
			"different styles have different keys")
	_check(svc.cache_key("[speed=1.3] Xin chào", "Mai Anh") != old_key, "tags are in the key")


## A style goes in the body, tags stay in the input, and the styled line is
## cached under its own key.
func _test_styled_request(svc: VoiceService, fake: FakeServer) -> void:
	var first := fake.requests.size()
	var style := VoiceStyle.create(1.3, -2.0, 1.0, 2.0)
	var line := svc.get_line("[pitch=-1] Có kiểu [cười]", "Mai Anh", style)
	style.speed = 3.0  # a later change must not reach the request
	_check(await line.wait() != null, "styled line is fetched")
	if not _check(fake.requests.size() > first, "the styled line made a request"):
		return
	var json := fake.json(first)
	_check(json.get("speed") == 1.3 and json.get("pitch") == -2.0 and json.get("effort") == 2.0
			and not json.has("volume"), "styled request body %s" % [json])
	_check(json.get("input") == "[pitch=-1] Có kiểu [cười]", "tags are sent as they are")
	var unstyled := svc.get_line("[pitch=-1] Có kiểu [cười]", "Mai Anh")
	_check(not unstyled.done, "the unstyled line is not the styled one")
	await unstyled.wait()
	_check(svc.get_line("[pitch=-1] Có kiểu [cười]", "Mai Anh", VoiceStyle.create(1.3, -2.0, 1.0, 2.0)).done,
			"the styled line is cached")


## Tags are removed for display; other brackets are kept.
func _test_display_text() -> void:
	var cases := {
		"[speed=1.3] Xin chào": "Xin chào",
		"Ta [speed=0.85 pitch=-3] đã nói [reset] rồi.": "Ta đã nói rồi.",
		"[voice=Mai Anh]Ngươi [thở dài] đi đi [hắng giọng].": "Ngươi đi đi.",
		"[voice=Hải Đăng] [shout=2]Đứng lại! [cười]": "Đứng lại!",
		"Ha ha [cười], vui quá [volume=0.7 effort=1]!": "Ha ha, vui quá!",
		"[effort=2]Hét [voice=Mai Anh] to [speed=1.2 pitch=-1]": "Hét to",
		"Xin[cười]chào": "Xin chào",
		"Xin[voice=Mai Anh]chào [cười][thở dài]": "Xin chào",
		"(Ha [cười])": "(Ha)",
		"([cười]Ha)": "(Ha)",
		"Rồi «Ừ [thở dài]» và “Vâng [cười]” và ‘Ờ [cười]’": "Rồi «Ừ» và “Vâng” và ‘Ờ’",
		"Sao [cười]? Ôi [cười]! Ừ [hắng giọng]…": "Sao? Ôi! Ừ…",
		"Ha [cười] !": "Ha!",
		"Ha [cười]\t.": "Ha.",
		"Ha [cười]\n.": "Ha.",
		"[speed=1.2 voice=Mai Anh] Xin chào": "Xin chào",
		"[voice=Mai Anh speed=1.2] Xin chào": "Xin chào",
		"Ta[speed=1.2 pitch=-1 voice=Hải Đăng]đi": "Ta đi",
		"([thở dài] Thôi được)": "(Thôi được)",
		"«[cười] Vâng»": "«Vâng»",
		"‘[cười] Ừ’ và “[thở dài]\tÔi”": "‘Ừ’ và “Ôi”",
		"[cười] Ha": "Ha",
		"Nói [cười] \"Ha\"": "Nói \"Ha\"",
		"Nói \"Ha [cười]\" rồi": "Nói \"Ha \" rồi",
		"Dòng một  \t\nDòng [cười] hai\r\n  [thở dài] Dòng ba": "Dòng một\nDòng hai\nDòng ba",
		"Một [cười]\nHai": "Một\nHai",
		# Whitespace inside a tag is one space once the text is sent normalized.
		"Ta [thở  dài] đi": "Ta đi",
		"Ta [speed=1.2\npitch=-1] đi": "Ta đi",
		"Ta [hắng\tgiọng] đi": "Ta đi",
		"[speed=1.2  voice=Mai Anh] Xin chào": "Xin chào",
		"[speed = 1.3] [speed=1.3pitch=2] [Speed=1] [ reset ] [speed=1.3 pitch=2]":
				"[speed = 1.3] [speed=1.3pitch=2] [Speed=1] [ reset ]",
		# A tag alone on its line leaves no empty line; a blank line stays.
		"Một\n[cười]\nHai": "Một\nHai",
		"Một\n\u00a0[cười] \nHai": "Một\nHai",
		"Một\n[cười]\n\nHai": "Một\n\nHai",
		# Whitespace between an opening character and a tag goes too.
		"( [cười] Thôi)": "(Thôi)",
		"(\u00a0[cười]\u00a0Thôi)": "(Thôi)",
		# A no-break space counts as whitespace around a tag.
		"Ha\u00a0[cười]\u00a0.": "Ha.",
		"Ha\u00a0[cười]\u00a0Hai": "Ha Hai",
		"[cười]. Ha": ". Ha",
		"[voice= Mai] [voice=Mai ] [Reset] [Cười] [speed=] [speed=.] [pitch=1e3]":
				"[voice= Mai] [voice=Mai ] [Reset] [Cười] [speed=] [speed=.] [pitch=1e3]",
		"Chương [1] và [ghi chú] [speed=nhanh] [x=1] [voice=] [cười to]":
				"Chương [1] và [ghi chú] [speed=nhanh] [x=1] [voice=] [cười to]",
		"Không   có   thẻ ": "Không có thẻ",
	}
	for text: String in cases:
		var shown := VoiceService.display_text(text)
		_check(shown == cases[text], "display_text(%s) is \"%s\"" % [text, shown])
	_check(VoiceTags.is_tag("speed=1.2 voice=Mai Anh") and VoiceTags.is_tag("voice=Mai Anh speed=1.2")
			and VoiceTags.is_tag("speed=1.2  voice=Mai Anh") and VoiceTags.is_tag("thở\n dài")
			and not VoiceTags.is_tag("speed=1.2voice=Mai Anh") and not VoiceTags.is_tag(" reset"),
			"number pairs before or after a voice name form a tag")


## A prefetch answered 429 waits Retry-After seconds at the back of the queue
## without holding up other lines, then goes again.
func _test_busy_requeue(url: String, fake: FakeServer) -> void:
	var svc := _service(url)
	_check(VoiceService._retry_after_seconds(PackedStringArray()) == 2.0, "no Retry-After waits 2 s")
	_check(VoiceService._retry_after_seconds(PackedStringArray(["Retry-After: Wed, 21 Oct 2026 07:28:00 GMT"])) == 2.0,
			"an unparsable Retry-After waits 2 s")
	_check(VoiceService._retry_after_seconds(PackedStringArray(["retry-after: 100"])) == 30.0, "Retry-After is capped at 30 s")
	_check(VoiceService._retry_after_seconds(PackedStringArray(["Retry-After: 2"])) == 2.0, "Retry-After is read")
	fake.status = 429
	fake.retry_after = "1.0"
	var first := fake.requests.size()
	svc.prefetch(["Bận quá"])
	var line: VoiceLine = svc._pending[svc.cache_key("Bận quá")]
	await _wait_busy(line)
	_check(not line.done and svc.pending_count() == 1, "a busy prefetch is not failed")
	fake.status = 200
	var spoken := svc.get_line("Không đợi")
	_check(await spoken.wait() != null, "a waiting prefetch does not hold up a spoken line")
	_check(not line.done and fake.requests.size() == first + 2, "the prefetch is not sent again yet")
	_check(await line.wait() != null and line.busy_retries == 1, "the prefetch is sent again and served")
	if _check(fake.requests.size() == first + 3, "the prefetch went out three times in all"):
		_check(fake.has_header(first + 2, "X-VieNeu-No-Wait: 1"), "the retry also asks not to wait")
		var waited_ms := fake.times[first + 2] - fake.times[first]
		_check(waited_ms >= 980 and waited_ms < 5000, "the retry waits Retry-After (%d ms)" % waited_ms)
	_check(svc.pending_count() == 0, "nothing pending after the retry")
	fake.retry_after = ""
	svc.clear_cache()
	svc.queue_free()


## A prefetch still busy after prefetch_retries retries fails with http_429.
func _test_busy_exhausted(url: String, fake: FakeServer) -> void:
	var svc := _service(url)
	svc.prefetch_retries = 2
	fake.status = 429
	fake.retry_after = "0.05"
	var first := fake.requests.size()
	svc.prefetch(["Mãi bận"])
	var line: VoiceLine = svc._pending[svc.cache_key("Mãi bận")]
	await line.wait()
	_check(line.error == "http_429" and fake.requests.size() == first + 3,
			"retries used up fail with http_429 after %d requests" % (fake.requests.size() - first))
	_check(svc.pending_count() == 0 and svc.is_online(), "a used-up prefetch leaves nothing pending")
	fake.status = 200
	fake.retry_after = ""
	svc.queue_free()


## A waiting prefetch asked for as a spoken line goes out at once without the
## no-wait header.
func _test_busy_promoted(url: String, fake: FakeServer) -> void:
	var svc := _service(url)
	fake.status = 429
	fake.retry_after = "5"
	var first := fake.requests.size()
	svc.prefetch(["Cần ngay"])
	var line: VoiceLine = svc._pending[svc.cache_key("Cần ngay")]
	await _wait_busy(line)
	fake.status = 200
	var started := Time.get_ticks_msec()
	var spoken := svc.get_line("Cần ngay")
	_check(spoken == line, "the spoken line is the waiting prefetch")
	_check(await spoken.wait() != null and Time.get_ticks_msec() - started < 2000,
			"a promoted line does not wait out Retry-After")
	_check(fake.requests.size() == first + 2 and not fake.has_header(first + 1, "X-VieNeu-No-Wait: 1"),
			"a promoted line is sent without the no-wait header")
	fake.retry_after = ""
	svc.clear_cache()
	svc.queue_free()


## A prefetch asked for as a spoken line while its no-wait request is in
## flight is sent again at once without the header when that request gets 429.
func _test_busy_promoted_in_flight(url: String, fake: FakeServer) -> void:
	var svc := _service(url)
	fake._held.clear()
	fake.respond = false
	var first := fake.requests.size()
	svc.prefetch(["Đang bay"])
	await fake.wait_held(1)
	var spoken := svc.get_line("Đang bay")
	fake.respond = true
	fake.status = 429
	fake.retry_after = "5"
	fake.release_oldest()
	fake.status = 200
	_check(await spoken.wait() != null and spoken.busy_retries == 0,
			"a line promoted in flight is sent again after a 429")
	_check(fake.requests.size() == first + 2 and fake.has_header(first, "X-VieNeu-No-Wait: 1")
			and not fake.has_header(first + 1, "X-VieNeu-No-Wait: 1"),
			"the second request is a spoken one")
	fake.retry_after = ""
	svc.clear_cache()
	svc.queue_free()


## A prefetch answered 429 is not sent again once voice is unavailable: a 401
## on another line, voice turned off, or an offline backoff.
func _test_busy_unavailable(url: String, fake: FakeServer) -> void:
	var svc := _service(url)
	fake._held.clear()
	fake.respond = false
	var first := fake.requests.size()
	var spoken := svc.get_line("Bị từ chối")
	svc.prefetch(["Đang bay bận"])
	var line: VoiceLine = svc._pending[svc.cache_key("Đang bay bận")]
	await fake.wait_held(2)
	fake.status = 401
	_check(fake.inputs().slice(first) == ["Bị từ chối", "Đang bay bận"],
			"the spoken line is the oldest held request %s" % [fake.inputs().slice(first)])
	fake.release_oldest()  # the spoken line
	await spoken.wait()
	_check(spoken.error == "unauthorized", "401 fails the spoken line")
	fake.status = 429
	fake.retry_after = "0.2"
	fake.release_oldest()  # the prefetch, busy, after the key was refused
	await line.wait()
	_check(line.error == "unauthorized" and svc.pending_count() == 0,
			"a 429 after a 401 resolves the prefetch unauthorized, not requeued")
	await create_timer(0.4).timeout
	_check(fake.requests.size() == first + 2, "no request after a 401 and a 429")
	fake.respond = true
	svc.queue_free()

	# voice turned off while a line waits out its 429
	svc = _service(url)
	fake.retry_after = "0.3"
	first = fake.requests.size()
	svc.prefetch(["Chờ tắt"])
	line = svc._pending[svc.cache_key("Chờ tắt")]
	await _wait_busy(line)
	svc.enabled = false
	await line.wait()
	_check(line.error == "disabled" and svc.pending_count() == 0, "a waiting line is disabled when voice is off")
	_check(fake.requests.size() == first + 1, "a disabled waiting line is not sent again")
	svc.queue_free()

	# an offline backoff that started while a line waits
	svc = _service(url)
	first = fake.requests.size()
	svc.prefetch(["Chờ mất mạng"])
	line = svc._pending[svc.cache_key("Chờ mất mạng")]
	await _wait_busy(line)
	svc._online = false
	svc._retry_at_ms = Time.get_ticks_msec() + 60000
	await line.wait()
	_check(line.error == "offline" and svc.pending_count() == 0, "a waiting line resolves offline in a backoff")
	_check(fake.requests.size() == first + 1, "an offline waiting line is not sent again")
	svc.queue_free()
	fake.status = 200
	fake.retry_after = ""


## A 429 that arrives during an offline backoff proves the server is
## reachable: the prefetch is put back, and a handler of online_changed(true)
## asking for it gets the same pending line without a second request.
func _test_busy_ends_offline(url: String, fake: FakeServer) -> void:
	var svc := _service(url)
	var changes: Array[bool] = []
	svc.online_changed.connect(func(o: bool) -> void: changes.append(o))
	fake._held.clear()
	fake.respond = false
	var first := fake.requests.size()
	var spoken := svc.get_line("Mất mạng trước")
	svc.prefetch(["Bận sau"])
	var key := svc.cache_key("Bận sau")
	var line: VoiceLine = svc._pending[key]
	await fake.wait_held(2)
	_check(fake.inputs().slice(first) == ["Mất mạng trước", "Bận sau"],
			"the spoken line is the oldest held request %s" % [fake.inputs().slice(first)])
	fake.respond = true
	fake.status = 502
	fake.release_oldest()  # the spoken line
	await spoken.wait()
	_check(spoken.error == "offline" and not svc.is_online(), "502 on the spoken line is offline")
	var from_handler: Array[VoiceLine] = []
	var ask_again := func(online: bool) -> void:
		if online:
			svc.prefetch(["Bận sau"])
			from_handler.append(svc._pending.get(key))
	svc.online_changed.connect(ask_again)
	fake.status = 429
	fake.retry_after = "0.2"
	fake.release_oldest()  # the prefetch, busy, inside the backoff
	await _wait_busy(line)
	_check(not line.done and line.busy_retries == 1, "a 429 inside a backoff requeues the prefetch (%s)" % line.error)
	_check(svc.is_online() and changes == [false, true], "a 429 ends the offline period %s" % [changes])
	_check(from_handler.size() == 1 and from_handler[0] == line,
			"a handler of online_changed(true) gets the pending line")
	_check(svc._active == 0 and svc.pending_count() == 1, "the handler starts no extra request")
	await create_timer(0.1).timeout  # shorter than Retry-After
	_check(fake.requests.size() == first + 2, "no request reaches the server while the line waits")
	fake.status = 200
	fake.retry_after = ""
	_check(await line.wait() != null and fake.requests.size() == first + 3,
			"the prefetch is served after its wait")
	svc.clear_cache()
	svc.queue_free()


## Leaving the tree resolves a prefetch that waits out a 429, and its timer
## firing later does nothing.
func _test_busy_exit(url: String, fake: FakeServer) -> void:
	var svc := _service(url)
	fake.status = 429
	fake.retry_after = "0.2"
	var first := fake.requests.size()
	svc.prefetch(["Chờ thoát"])
	var line: VoiceLine = svc._pending[svc.cache_key("Chờ thoát")]
	await _wait_busy(line)
	root.remove_child(svc)
	_check(line.done and line.error == "disabled" and svc.pending_count() == 0,
			"exit resolves a waiting prefetch")
	fake.status = 200
	fake.retry_after = ""
	await create_timer(0.3).timeout  # the retry timer fires on a service out of the tree
	_check(fake.requests.size() == first + 1, "a waiting prefetch is not sent after exit")
	svc.free()
