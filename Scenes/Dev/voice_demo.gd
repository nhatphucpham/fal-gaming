extends Control
## Developer page for trying the voice module: type a line (inline tags
## allowed), pick a voice and a style, press Speak. Speaking the same line in
## the same style twice plays it from the cache.

@onready var _text: LineEdit = %Text
@onready var _shown: Label = %Shown
@onready var _voice: LineEdit = %VoiceName
@onready var _status: Label = %Status
@onready var _player: AudioStreamPlayer = %Player
## Style field name -> its slider; the value label is the slider's name + "Value".
@onready var _sliders: Dictionary[String, HSlider] = {
	"speed": %Speed, "pitch": %Pitch, "volume": %Volume, "effort": %Effort,
}


func _ready() -> void:
	%Speak.pressed.connect(_on_speak)
	%ResetStyle.pressed.connect(_reset_style)
	_text.text_submitted.connect(func(_t: String) -> void: _on_speak())
	_text.text_changed.connect(func(_t: String) -> void: _show_text())
	for slider: HSlider in _sliders.values():
		slider.value_changed.connect(func(_v: float) -> void: _show_value(slider))
		_show_value(slider)
	Voice.online_changed.connect(_on_online_changed)
	_show_text()
	_status.text = "Server: %s%s" % [Voice.base_url,
			"" if Voice.api_key != "" else " (no API key set)"]


func _style() -> VoiceStyle:
	return VoiceStyle.create(_sliders["speed"].value, _sliders["pitch"].value,
			_sliders["volume"].value, _sliders["effort"].value)


func _reset_style() -> void:
	var defaults := VoiceStyle.new()
	for field: String in _sliders:
		_sliders[field].value = defaults.get(field)


func _show_value(slider: HSlider) -> void:
	var label: Label = get_node("%" + slider.name + "Value")
	label.text = "%.2f" % slider.value


func _show_text() -> void:
	_shown.text = "Shown: " + VoiceService.display_text(_text.text)


func _on_online_changed(online: bool) -> void:
	_status.text = "Service is back online." if online else "Offline: text only."


func _on_speak() -> void:
	var line := Voice.get_line(_text.text, _voice.text, _style())
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
