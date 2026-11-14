class_name MuteButton
extends PressButton
## The sound switch: a drawn speaker with sound waves, or crossed out when
## muted. A press flips Audio's mute (saved in the settings). With
## `shows_text` it also says "Âm: Bật" / "Âm: Tắt" (the title screen).

var shows_text: bool = false:
	set(value):
		shows_text = value
		_update()


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(64, 56)
	pressed.connect(func() -> void:
		Sound.toggle_muted()
		Sound.play(&"ui_tap")
		_update())


func _ready() -> void:
	super()
	_update()


func _update() -> void:
	text = (tr("SOUND_OFF") if Sound.is_muted() else tr("SOUND_ON")) if shows_text else ""
	queue_redraw()


func _draw() -> void:
	var center := Vector2(32.0, size.y / 2.0) if shows_text else size / 2.0
	var ink := Palette.CREAM
	var body := PackedVector2Array([
		center + Vector2(-13, -5), center + Vector2(-6, -5), center + Vector2(3, -13),
		center + Vector2(3, 13), center + Vector2(-6, 5), center + Vector2(-13, 5),
	])
	draw_colored_polygon(body, ink)
	if Sound.is_muted():
		draw_line(center + Vector2(7, -7), center + Vector2(17, 7), Palette.VERMILION, 3.5, true)
		draw_line(center + Vector2(17, -7), center + Vector2(7, 7), Palette.VERMILION, 3.5, true)
	else:
		draw_arc(center + Vector2(3, 0), 7.0, -0.9, 0.9, 8, ink, 2.5, true)
		draw_arc(center + Vector2(3, 0), 13.0, -0.9, 0.9, 10, ink, 2.5, true)
