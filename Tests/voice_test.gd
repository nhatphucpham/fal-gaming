extends SceneTree
## Tests the voice module against a fake TTS server on localhost: WAV
## reading, config types, caching, request shape and order, de-duplication,
## missing key, timeout, auth failure, offline backoff, stale failures and
## shutdown.

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
	var requests: Array[String] = []
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
		var reply := ("HTTP/1.1 %d X\r\nContent-Type: audio/pcm\r\n" % status
				+ "Content-Length: %d\r\nConnection: close\r\n\r\n" % body.size()).to_utf8_buffer()
		reply.append_array(body)
		peer.put_data(reply)
		peer.disconnect_from_host()


func _initialize() -> void:
	_run()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		push_error("FAIL: " + what)


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

	# first request goes to the server, duplicates share it
	var line := svc.get_line("Xin chào", "Mai Anh")
	var dup := svc.get_line("Xin   chào", "Mai Anh")
	_check(line == dup, "in-flight duplicates share one request")
	_check(not line.done, "uncached line is pending")
	var stream := await line.wait()
	_check(stream != null and is_equal_approx(stream.get_length(), 0.1), "stream from server")
	_check(fake.requests.size() == 1, "one request for duplicates")
	var req := fake.requests[0]
	_check(req.begins_with("POST /v1/audio/speech"), "endpoint")
	_check(req.contains("Authorization: Bearer test-key"), "auth header")
	var json: Dictionary = JSON.parse_string(req.substr(req.find("\r\n\r\n") + 4))
	_check(json.get("input") == "Xin chào" and json.get("voice") == "Mai Anh"
			and json.get("response_format") == "pcm" and int(json.get("sample_rate")) == 24000,
			"request body")

	# second time comes from the cache, without the network
	var again := svc.get_line("Xin chào", "Mai Anh")
	_check(again.done and again.stream != null and again.stream.data == pcm, "cache hit")
	_check(fake.requests.size() == 1, "cache hit makes no request")

	# prefetch fills the cache in the background
	svc.prefetch(["Một", "Hai"], "Mai Anh")
	await _wait_idle(svc)
	_check(svc.get_line("Hai", "Mai Anh").done, "prefetched line is cached")

	# no key: nothing goes to the network, cached lines still play
	svc.api_key = ""
	_check(svc.get_line("Không khóa").error == "no_key", "empty key is no_key")
	_check(svc.get_line("Hai", "Mai Anh").stream != null, "cached line plays without a key")
	_check(fake.requests.size() == 3, "empty key makes no request")
	svc.api_key = "test-key"

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
	_test_shutdown(url, fake)
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
	var wav_file := VoiceService.wav_bytes(pcm, 24000)
	var wav := VoiceService.read_wav(wav_file)
	_check(wav != null and wav.mix_rate == 24000 and wav.data == pcm, "wav round trip")
	for size: int in [0, 10, 43, 44, 50, 100, wav_file.size() - 1]:
		_check(VoiceService.read_wav(wav_file.slice(0, size)) == null,
				"wav truncated to %d bytes is rejected" % size)
	# A "fmt " chunk cut short after a padding chunk must not be decoded.
	var cut := wav_file.slice(0, 12)
	cut.append_array("JUNK".to_ascii_buffer())
	var junk_size := PackedByteArray()
	junk_size.resize(30)
	junk_size.encode_u32(0, 26)
	cut.append_array(junk_size)
	cut.append_array(wav_file.slice(12, 24))
	_check(cut.size() > 44 and VoiceService.read_wav(cut) == null, "cut fmt chunk is rejected")
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
