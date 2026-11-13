extends SceneTree
## Tests the voice module against a fake TTS server on localhost:
## caching, request shape, de-duplication, auth failure and offline mode.

const CACHE := "user://voice_test_cache"

var _failures := 0


class FakeServer extends Node:
	var server := TCPServer.new()
	var port := 0
	var status := 200
	var body := PackedByteArray()
	var requests: Array[String] = []
	var _peers: Array = []  # [StreamPeerTCP, PackedByteArray]

	func start() -> void:
		for p in range(18750, 18800):
			if server.listen(p, "127.0.0.1") == OK:
				port = p
				return

	func _process(_delta: float) -> void:
		while server.is_connection_available():
			_peers.append([server.take_connection(), PackedByteArray()])
		for entry in _peers.duplicate():
			var peer: StreamPeerTCP = entry[0]
			peer.poll()
			var n := peer.get_available_bytes()
			if n > 0:
				entry[1].append_array(peer.get_data(n)[1])
			var raw: String = entry[1].get_string_from_utf8()
			var head_end := raw.find("\r\n\r\n")
			if head_end < 0:
				continue
			var length := 0
			for h in raw.substr(0, head_end).split("\r\n"):
				if h.to_lower().begins_with("content-length:"):
					length = h.substr(15).strip_edges().to_int()
			if entry[1].size() < head_end + 4 + length:
				continue
			requests.append(raw)
			var reply := ("HTTP/1.1 %d X\r\nContent-Type: audio/pcm\r\n" % status
					+ "Content-Length: %d\r\nConnection: close\r\n\r\n" % body.size()).to_utf8_buffer()
			reply.append_array(body)
			peer.put_data(reply)
			peer.disconnect_from_host()
			_peers.erase(entry)


func _initialize() -> void:
	_run()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		push_error("FAIL: " + what)


func _service(url: String) -> VoiceService:
	var svc := VoiceService.new()
	root.add_child(svc)
	svc.base_url = url
	svc.api_key = "test-key"
	svc.cache_dir = CACHE
	svc.offline_backoff_min = 60.0
	svc.request_timeout = 5.0
	svc.clear_cache()
	return svc


func _run() -> void:
	await process_frame

	# WAV round trip
	var pcm := PackedByteArray()
	pcm.resize(4800)  # 0.1 s at 24 kHz
	for i in pcm.size():
		pcm[i] = i % 251
	var wav := VoiceService.read_wav(VoiceService.wav_bytes(pcm, 24000))
	_check(wav != null and wav.mix_rate == 24000 and wav.data == pcm, "wav round trip")
	_check(VoiceService.read_wav(VoiceService.wav_bytes(pcm, 24000).slice(0, 100)) == null,
			"truncated wav is rejected")

	var fake := FakeServer.new()
	root.add_child(fake)
	fake.start()
	_check(fake.port != 0, "fake server listens")
	fake.body = pcm
	var svc := _service("http://127.0.0.1:%d/" % fake.port)

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
	while svc.pending_count() > 0:
		await process_frame
	_check(svc.get_line("Hai", "Mai Anh").done, "prefetched line is cached")

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
	svc.queue_free()

	# unreachable server: offline, and later lines fail at once
	var off := _service("http://127.0.0.1:%d" % (fake.port + 1000))
	var went_offline := []
	off.online_changed.connect(func(o: bool) -> void: went_offline.append(o))
	var lost := off.get_line("Sáu")
	await lost.wait()
	_check(lost.error == "offline" and not off.is_online(), "unreachable server is offline")
	_check(went_offline == [false], "online_changed fired")
	_check(off.get_line("Bảy").error == "offline", "offline lines resolve at once")
	off.clear_cache()
	off.queue_free()

	if _failures == 0:
		print("Voice test passed")
	quit(1 if _failures > 0 else 0)
