class_name VoiceLine
extends RefCounted
## One spoken line requested from [VoiceService]. Await [method wait] to get
## its audio; the result is null when no voice is available (offline, service
## disabled or an error), and the caller should then show the text only.

signal finished(stream: AudioStreamWAV)

var text := ""
var voice := ""
var key := ""
## Null until done, and still null if the line could not be voiced.
var stream: AudioStreamWAV
var done := false
## Empty on success; otherwise "offline", "timeout", "disabled", "no_key",
## "unauthorized", "empty" or "http_<code>" (see Docs/systems/voice.md).
var error := ""
## True while the line only waits in the background prefetch queue.
var prefetch := false


## Returns the audio, waiting for the network if needed. Safe to call after
## the line is already done.
func wait() -> AudioStreamWAV:
	if not done:
		await finished
	return stream


func _resolve(result: AudioStreamWAV, reason: String) -> void:
	if done:
		return
	stream = result
	error = reason
	done = true
	finished.emit(stream)
