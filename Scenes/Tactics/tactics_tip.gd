class_name TacticsTip
extends Control
## First-time tips on the tactics map: one short line in a gold-edged box
## just above the bottom panel, or under the top bar when that strip holds
## units of ours (the screen tells which rects to keep clear), the first
## time the player selects a leader, moves one, spends a leader's last
## move point, changes an order, sees a soldier waver, meets an objective,
## a site within reach, a capture ring, the convoy, exits and an enemy
## wave. Each tip slides in with a sound, stays a few seconds or until the
## next tap anywhere, and fades; one shown is remembered in the settings
## (RunSettings) and never shown again. A tip that comes while another
## shows waits for it. It never catches taps.
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
	&"objective": "TACTICS_TIP_OBJECTIVE",
	&"site": "TACTICS_TIP_SITE",
	&"capture": "TACTICS_TIP_CAPTURE",
	&"convoy": "TACTICS_TIP_CONVOY",
	&"exit": "TACTICS_TIP_EXIT",
	&"wave": "TACTICS_TIP_WAVE",
}
const SETTINGS_PREFIX: String = "tactics."
const IN_SEC: float = 0.25
const SHOW_SEC: float = 4.5
const OUT_SEC: float = 0.3
const RISE_PX: float = 36.0
## A tap's fade, the beat before the next tip and a move between places.
const DISMISS_SEC: float = 0.15
const NEXT_GAP_SEC: float = 0.35
const MOVE_SEC: float = 0.2
const MARGIN_PX: float = 16.0
## The heights tried between the top and the bottom place, this far apart.
const SCAN_STEP_PX: float = 24.0

## Space kept free under the tip (the bottom panel).
var bottom_px: float = 430.0
## Space kept free over the tip when it sits at the top (the top bar and
## the map's corner buttons).
var top_px: float = 0.0
## Returns what the tip should not cover, [{rect, weight}] in this
## control's coordinates (our units weigh more than the enemy's); unset,
## the tip sits above the panel.
var avoid_rects: Callable

var _box: PanelContainer
var _label: Label
var _seen: Array[String] = []
var _queue: Array[StringName] = []
var _shown: StringName = &""
var _tween: Tween
var _move_tween: Tween
## The box's top now (layout px) and whether it sits at the top.
var _box_top: float = 0.0
var _is_at_top: bool = false
var _is_dismissing: bool = false
var _is_sliding_in: bool = false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _ready() -> void:
	_seen = RunSettings.load_seen_tips()
	_box = TacticsViews.panel(Color(Palette.PANEL, 0.95))
	(_box.get_theme_stylebox(&"panel") as StyleBoxFlat).border_color = Palette.GOLD
	_box.anchor_right = 1.0
	_box.offset_left = 24
	_box.offset_right = -24
	add_child(_box)
	_label = TacticsViews.wrapped("", 26, Palette.CREAM)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(_label)
	set_process_input(false)


## Shows the tip once ever: now, or after the one on screen.
func offer(id: StringName) -> void:
	if not TIPS.has(id) or _seen.has(SETTINGS_PREFIX + id) or _queue.has(id) or _shown == id:
		return
	_queue.append(id)
	if _shown == &"" and not _is_dismissing:
		_show_next()


## The tip on screen, or an empty StringName.
func get_shown() -> StringName:
	return _shown


## Tips waiting for the one on screen.
func get_pending() -> Array[StringName]:
	return _queue.duplicate()


func get_text() -> String:
	return _label.text if _label != null else ""


## The box's rect in this control's coordinates (for tests).
func get_box_rect() -> Rect2:
	return Rect2(_box.position + position, _box.size) if _box != null else Rect2()


## Whether the tip sits higher than its place above the panel.
func is_at_top() -> bool:
	return _is_at_top


## Moves the tip off what it would cover now (the camera or the units
## moved); nothing moves when its place stays the same.
func refresh_place() -> void:
	if _shown == &"" or _box == null:
		return
	var was_top := _box_top
	_choose_place()
	if is_equal_approx(was_top, _box_top) or _is_sliding_in:
		return
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = create_tween()
	_move_tween.tween_property(_box, ^"position:y", _box_top, MOVE_SEC).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)


# Above the panel unless that covers something to keep clear; else under
# the top bar, else the height between them that covers least (ties keep
# the earlier place).
func _choose_place() -> void:
	# The wrapped line's height at the box's width (before the box has
	# laid it out at that width).
	var frame := _box.get_theme_stylebox(&"panel").get_minimum_size()
	var width := size.x - _box.offset_left + _box.offset_right
	_label.size.x = width - frame.x
	var height := _label.get_minimum_size().y + frame.y
	var bottom_top := size.y - bottom_px - MARGIN_PX - height
	var top_top := top_px + MARGIN_PX
	var tops: Array[float] = [bottom_top, top_top]
	var step := top_top + SCAN_STEP_PX
	while step < bottom_top:
		tops.append(step)
		step += SCAN_STEP_PX
	var items: Array = avoid_rects.call() if avoid_rects.is_valid() else []
	var best_top := bottom_top
	var best_cost := -1
	for top: float in tops:
		var cost := _covered(items, top, height)
		if best_cost < 0 or cost < best_cost:
			best_cost = cost
			best_top = top
		if cost == 0:
			break
	_box_top = best_top
	_is_at_top = best_top < bottom_top
	# Its height by the offsets: the box is anchored across, and a size set
	# before it is ready would warn.
	_box.offset_bottom = _box.offset_top + height


func _covered(items: Array, top: float, height: float) -> int:
	var box := Rect2(Vector2(_box.offset_left, top), Vector2(size.x - _box.offset_left + _box.offset_right, height))
	var cost := 0
	for item: Dictionary in items:
		cost += int(item["weight"]) if box.intersects(item["rect"]) else 0
	return cost


# A tap anywhere (it is not caught) lets the tip go at once.
func _input(event: InputEvent) -> void:
	var is_press := (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	if is_press and _shown != &"":
		dismiss()


## Fades the tip on screen now; the next waiting one follows after a beat.
func dismiss() -> void:
	if _shown == &"":
		return
	set_process_input(false)
	_is_dismissing = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_box, ^"modulate:a", 0.0, DISMISS_SEC)
	_tween.tween_callback(func() -> void:
		_shown = &""
		visible = false)
	_tween.tween_interval(NEXT_GAP_SEC)
	_tween.tween_callback(_show_next)


func _show_next() -> void:
	_is_dismissing = false
	if _queue.is_empty():
		_shown = &""
		visible = false
		set_process_input(false)
		return
	_shown = _queue.pop_front()
	_seen.append(SETTINGS_PREFIX + _shown)
	RunSettings.save_seen_tip(SETTINGS_PREFIX + _shown)
	_label.text = tr(TIPS[_shown])
	visible = true
	set_process_input(true)
	_choose_place()
	_box.modulate.a = 0.0
	# It slides in from the panel's side, or down from the top bar, to
	# wherever its place is when the slide ends.
	var rise := -RISE_PX if _is_at_top else RISE_PX
	_slide(0.0, rise)
	Sound.play(&"text_blip")
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	_tween = create_tween()
	_tween.set_parallel()
	_tween.tween_property(_box, ^"modulate:a", 1.0, IN_SEC)
	_tween.tween_method(_slide.bind(rise), 0.0, 1.0, IN_SEC).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_tween.chain().tween_interval(SHOW_SEC)
	_tween.chain().tween_property(_box, ^"modulate:a", 0.0, OUT_SEC)
	_tween.chain().tween_callback(_show_next)


func _slide(weight: float, rise: float) -> void:
	_is_sliding_in = weight < 1.0
	var y := _box_top + rise * (1.0 - weight)
	if _box.position.y != y:
		_box.position.y = y
