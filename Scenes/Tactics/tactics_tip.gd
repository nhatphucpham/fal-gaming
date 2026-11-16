class_name TacticsTip
extends Control
## First-time tips on the tactics map: one short line in a gold-edged box
## just above the bottom panel, the first time the player selects a
## leader, moves one, spends a leader's last move point, changes an order
## and sees a soldier waver. Each tip
## slides up with a sound, stays a few seconds and fades; one shown is
## remembered in the settings (RunSettings) and never shown again. A tip
## that comes while another shows waits for it. It never catches taps.
## [codeblock]
## var tips := TacticsTip.new()
## add_child(tips)
## tips.offer(&"select")
## [/codeblock]

## Tip id -> its Locale key, in the order a first battle meets them.
const TIPS: Dictionary = {
	&"select": "TACTICS_TIP_SELECT",
	&"move": "TACTICS_TIP_MOVE",
	&"undo": "TACTICS_TIP_UNDO",
	&"order": "TACTICS_TIP_ORDER",
	&"waver": "TACTICS_TIP_WAVER",
	&"waver_unseen": "TACTICS_TIP_WAVER_UNSEEN",
	&"fog": "TACTICS_TIP_FOG",
}
const SETTINGS_PREFIX: String = "tactics."
const IN_SEC: float = 0.25
const SHOW_SEC: float = 4.5
const OUT_SEC: float = 0.3
const RISE_PX: float = 36.0

## Space kept free under the tip (the bottom panel).
var bottom_px: float = 430.0

var _box: PanelContainer
var _label: Label
var _seen: Array[String] = []
var _queue: Array[StringName] = []
var _shown: StringName = &""
var _tween: Tween


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _ready() -> void:
	_seen = RunSettings.load_seen_tips()
	_box = TacticsViews.panel(Color(Palette.PANEL, 0.95))
	(_box.get_theme_stylebox(&"panel") as StyleBoxFlat).border_color = Palette.GOLD
	_box.anchor_top = 1.0
	_box.anchor_right = 1.0
	_box.anchor_bottom = 1.0
	_box.offset_left = 24
	_box.offset_right = -24
	_box.offset_bottom = -bottom_px - 16
	_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_box)
	_label = TacticsViews.wrapped("", 26, Palette.CREAM)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(_label)


## Shows the tip once ever: now, or after the one on screen.
func offer(id: StringName) -> void:
	if not TIPS.has(id) or _seen.has(SETTINGS_PREFIX + id) or _queue.has(id) or _shown == id:
		return
	_queue.append(id)
	if _shown == &"":
		_show_next()


## The tip on screen, or an empty StringName.
func get_shown() -> StringName:
	return _shown


## Tips waiting for the one on screen.
func get_pending() -> Array[StringName]:
	return _queue.duplicate()


func get_text() -> String:
	return _label.text if _label != null else ""


func _show_next() -> void:
	if _queue.is_empty():
		_shown = &""
		visible = false
		return
	_shown = _queue.pop_front()
	_seen.append(SETTINGS_PREFIX + _shown)
	RunSettings.save_seen_tip(SETTINGS_PREFIX + _shown)
	_label.text = tr(TIPS[_shown])
	visible = true
	_box.modulate.a = 0.0
	position.y = RISE_PX
	Sound.play(&"text_blip")
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel()
	_tween.tween_property(_box, ^"modulate:a", 1.0, IN_SEC)
	_tween.tween_property(self, ^"position:y", 0.0, IN_SEC).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_tween.chain().tween_interval(SHOW_SEC)
	_tween.chain().tween_property(_box, ^"modulate:a", 0.0, OUT_SEC)
	_tween.chain().tween_callback(_show_next)
