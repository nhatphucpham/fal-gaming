extends Control
## Developer page for trying the voice module: type a line, pick a voice,
## press Speak. Speaking the same line twice plays it from the cache.

@onready var _text: LineEdit = %Text
@onready var _voice: LineEdit = %VoiceName
@onready var _status: Label = %Status
@onready var _player: AudioStreamPlayer = %Player


func _ready() -> void:
	%Speak.pressed.connect(_on_speak)
	_text.text_submitted.connect(func(_t: String) -> void: _on_speak())
	Voice.online_changed.connect(func(online: bool) -> void:
		_status.text = "Service is back online." if online else "Offline: text only.")
	_status.text = "Server: %s%s" % [Voice.base_url,
			"" if Voice.api_key != "" else " (no API key set)"]


func _on_speak() -> void:
	var line := Voice.get_line(_text.text, _voice.text)
	var started := Time.get_ticks_msec()
	_status.text = "Cached." if line.done else "Generating..."
	var stream := await line.wait()
	if stream == null:
		_status.text = "No voice (%s). The game shows the text only." % line.error
		return
	_status.text = "%.1f s of audio, ready after %d ms." % [
			stream.get_length(), Time.get_ticks_msec() - started]
	_player.stream = stream
	_player.play()
