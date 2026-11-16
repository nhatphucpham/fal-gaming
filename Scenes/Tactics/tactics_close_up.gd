class_name TacticsCloseUp
extends Control
## The side-view close-up over the tactics map: a painted band (the
## cutscene backdrop) with the bone-rig figures of the units involved,
## for a leader's attack (each hit and the counter with its number) and
## for a leader's skill (TacticsSkillFx draws its three layers). It lasts
## about 2-3 s and a tap skips it. It shows what it is given; the map is
## brought in line with the battle afterwards by the caller.
## [codeblock]
## await close_up.play_engagement(attacker, defender, hits, false, &"backdrop.road")
## await close_up.play_skill(look, caster, targets, results, "Hiệu triệu", &"backdrop.camp")
## [/codeblock]

signal finished()

const BAND_TOP: float = 0.25
const BAND_BOTTOM: float = 0.64
const FIGURE_SCALE: float = 3.1
const HIT_SEC: float = 0.22
const INTRO_SEC: float = 0.3
const OUTRO_SEC: float = 0.55
## Where the two figures of an engagement stand across the band
## (fractions): our side on the left.
const DUEL_SPOTS: Array[float] = [0.28, 0.7]
## A skill's caster stands alone at CASTER_SPOT from its edge; its one to
## three targets (or the allies it reaches) spread over the rest.
const CASTER_SPOT: float = 0.15
const SKILL_SPOTS: Array[Array] = [[0.66], [0.52, 0.8], [0.4, 0.63, 0.86]]
## How far up from the feet the chest and the name plate are, in pixels.
const CHEST_PX: float = 95.0
const PLATE_PX: float = 215.0

var is_playing: bool = false
## Seconds since the scene began, for tests and screenshots.
var elapsed: float = 0.0

var _band: Control
var _backdrop: CutsceneBackdrop
var _stage: Node2D
var _fx: TacticsSkillFx
var _plates: Control
var _numbers: Control
var _title: Label
var _subtitle: Label
var _hint: Label
var _tween: Tween
## Each: {unit, view, name, side, hp, max_hp, feet}.
var _actors: Array[Dictionary] = []
var _is_skill: bool = false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_process(false)
	var shade := ColorRect.new()
	shade.color = Color(Palette.BACKDROP, 0.9)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_title = _label(46, Palette.GOLD)
	_place(_title, 0.0, 0.1, 1.0, 0.18)
	_subtitle = _label(26, Palette.CREAM)
	_place(_subtitle, 0.0, 0.18, 1.0, BAND_TOP - 0.01)
	_band = Control.new()
	_band.clip_contents = true
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_band, 0.0, BAND_TOP, 1.0, BAND_BOTTOM)
	_backdrop = CutsceneBackdrop.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_band.add_child(_backdrop)
	_stage = Node2D.new()
	_band.add_child(_stage)
	_fx = TacticsSkillFx.new()
	_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_band.add_child(_fx)
	_plates = _Plates.new()
	(_plates as _Plates).owner_scene = self
	_plates.set_anchors_preset(Control.PRESET_FULL_RECT)
	_plates.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.add_child(_plates)
	_numbers = Control.new()
	_numbers.set_anchors_preset(Control.PRESET_FULL_RECT)
	_numbers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.add_child(_numbers)
	_hint = _label(24, Palette.TEXT_DIM)
	_hint.text = "CLOSEUP_SKIP"
	_place(_hint, 0.0, BAND_BOTTOM + 0.02, 1.0, BAND_BOTTOM + 0.07)


func _ready() -> void:
	# Godot turns processing on at ready for a script with _process; the
	# close-up only ticks while it plays.
	set_process(false)
	_backdrop.set_process(false)


func _process(delta: float) -> void:
	elapsed += delta
	if _is_skill:
		_fx.time = elapsed - INTRO_SEC
		_stage.position.x = _fx.get_shake()
	_plates.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
		accept_event()
		skip()


## Plays a leader's engagement. `attacker` and `defender` are actor
## dictionaries ({unit, data: UnitData, name, side, hp, max_hp,
## is_ranged}, hp before the fight); `hits` the damage_dealt events in
## order. Returns when it ends or is skipped.
func play_engagement(attacker: Dictionary, defender: Dictionary, hits: Array, is_first_strike: bool, backdrop_kind: StringName) -> void:
	_begin(backdrop_kind, "%s  ⚔  %s" % [attacker["name"], defender["name"]], "")
	var attacker_actor := _add_actor(attacker, _side_spot(attacker["side"]), 0)
	var defender_actor := _add_actor(defender, _side_spot(defender["side"]), 0)
	_tween = create_tween()
	_tween.tween_interval(INTRO_SEC)
	if not attacker["is_ranged"]:
		var view: UnitView = attacker_actor["view"]
		var toward: float = view.position.x + (defender_actor["view"].position.x - view.position.x) * 0.35
		_tween.tween_property(view, ^"position:x", toward, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if is_first_strike:
		_tween.tween_callback(_float_over.bind(defender_actor, tr("CLOSEUP_FIRST_STRIKE"), Palette.GOLD, 30))
		_tween.tween_interval(0.25)
	var countered := false
	for hit: Dictionary in hits:
		var is_counter: bool = hit["is_counter"]
		if is_counter and not countered:
			countered = true
			_tween.tween_callback(_float_over.bind(defender_actor, tr("CLOSEUP_COUNTER"), Palette.CREAM, 26))
		var source := attacker_actor if hit["source"] == attacker["unit"] else defender_actor
		var target := defender_actor if source == attacker_actor else attacker_actor
		var is_ranged: bool = attacker["is_ranged"] if source == attacker_actor else defender["is_ranged"]
		_tween.tween_callback(_land_hit.bind(source, target, hit, is_ranged))
		_tween.tween_interval(HIT_SEC)
	_tween.tween_interval(OUTRO_SEC)
	_tween.tween_callback(_end)
	await finished


## Plays a leader's skill: the look's three layers from `caster` to each
## of `targets` (actor dictionaries; allies for a support skill), with
## `results` ({unit: {amount, hp_after}}) as numbers and `mark_text` over
## each target that has no number (a support mark).
func play_skill(look: TacticsSkillLook, caster: Dictionary, targets: Array, results: Dictionary, mark_text: String, title: String, subtitle: String, backdrop_kind: StringName) -> void:
	_begin(backdrop_kind, title, subtitle)
	_is_skill = true
	var is_left: bool = caster["side"] == 0
	var caster_actor := _add_actor(caster, CASTER_SPOT if is_left else 1.0 - CASTER_SPOT, 0)
	var target_actors: Array[Dictionary] = []
	var chests: Array[Vector2] = []
	var feet: Array[Vector2] = []
	var spots: Array = SKILL_SPOTS[clampi(targets.size(), 1, SKILL_SPOTS.size()) - 1]
	for index: int in mini(targets.size(), spots.size()):
		var spot: float = spots[index] if is_left else 1.0 - spots[index]
		var actor := _add_actor(targets[index], spot, 1 if index % 2 == 1 else 0)
		target_actors.append(actor)
		feet.append(actor["feet"])
		chests.append(actor["feet"] + Vector2(0, -CHEST_PX))
	_fx.present(look, caster_actor["feet"] + Vector2(0, -CHEST_PX), caster_actor["feet"], chests, feet)
	var caster_view: UnitView = caster_actor["view"]
	caster_view.wind_up(look.cast_sec)
	Sound.play(&"skill_cast")
	_tween = create_tween()
	_tween.tween_interval(INTRO_SEC + look.cast_sec)
	_tween.tween_callback(_release.bind(caster_actor, target_actors, look))
	for index: int in target_actors.size():
		var at := INTRO_SEC + _fx.get_impact_time(index)
		_tween.parallel().tween_callback(_land_skill.bind(target_actors[index], results, mark_text, look)).set_delay(at - INTRO_SEC - look.cast_sec)
	_tween.tween_interval(maxf(_fx.get_end_time() - _fx.get_impact_time(target_actors.size() - 1), 0.3) + 0.25)
	_tween.tween_callback(_end)
	await finished


## Ends the scene at once (a tap).
func skip() -> void:
	if not is_playing:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_end()


## The actors on stage now (for tests): [{unit, name, hp, max_hp, side}].
func get_actors() -> Array[Dictionary]:
	return _actors


## The scene's title and subtitle as shown now, for tests.
func get_title() -> String:
	return _title.text


func get_subtitle() -> String:
	return _subtitle.text


func _begin(backdrop_kind: StringName, title: String, subtitle: String) -> void:
	_clear_stage()
	is_playing = true
	elapsed = 0.0
	_is_skill = false
	_fx.look = null
	_fx.queue_redraw()
	_stage.position = Vector2.ZERO
	_backdrop.kind = backdrop_kind
	_title.text = title
	_subtitle.text = subtitle
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, ^"modulate:a", 1.0, 0.18)
	set_process(true)
	_backdrop.set_process(true)


func _end() -> void:
	is_playing = false
	_is_skill = false
	set_process(false)
	_backdrop.set_process(false)
	visible = false
	_clear_stage()
	finished.emit()


func _clear_stage() -> void:
	for actor: Dictionary in _actors:
		(actor["view"] as UnitView).queue_free()
	_actors.clear()
	for child: Node in _numbers.get_children():
		child.queue_free()


func _side_spot(side: int) -> float:
	return DUEL_SPOTS[0] if side == 0 else DUEL_SPOTS[1]


# Puts a figure with its feet at `spot` across the band, facing the other
# side (our side faces right). `depth` 1 stands a little behind and smaller.
func _add_actor(info: Dictionary, spot: float, depth: int) -> Dictionary:
	var view := UnitView.new()
	view.setup(info["data"], info["side"], 0)
	view.is_hp_bar_shown = false
	view.face_front(info["side"] == 0)
	view.scale = Vector2.ONE * FIGURE_SCALE * (1.0 if depth == 0 else 0.88)
	_stage.add_child(view)
	var ground := _band.size.y * CutsceneBackdrop.GROUND_RATIO + 6.0 - depth * 6.0
	var feet := Vector2(_band.size.x * spot, ground)
	view.position = feet - UnitView.FEET * view.scale
	var actor := {
		"unit": info["unit"], "view": view, "name": info["name"], "side": info["side"],
		"hp": int(info["hp"]), "max_hp": maxi(int(info["max_hp"]), 1), "feet": feet, "floats": 0,
	}
	_actors.append(actor)
	# Figures further back are drawn first.
	if depth > 0:
		_stage.move_child(view, 0)
	return actor


func _land_hit(source: Dictionary, target: Dictionary, hit: Dictionary, is_ranged: bool) -> void:
	var source_view: UnitView = source["view"]
	var target_view: UnitView = target["view"]
	var direction := target_view.position - source_view.position
	if is_ranged:
		source_view.recoil(direction)
		Sound.play(&"arrow")
	else:
		source_view.lunge(direction)
		Sound.play(&"hit_heavy")
	target_view.hit_flash()
	target["hp"] = int(hit["hp_after"])
	_float_number(target, "-%d" % int(hit["amount"]), Palette.CREAM if hit["is_counter"] else Color("ffd27a"))
	if int(hit["hp_after"]) <= 0 and not target_view.is_dead:
		target_view.die()
		Sound.play(&"death")
		_float_over(target, tr("CLOSEUP_FALLEN"), Palette.VERMILION, 34)


func _release(caster: Dictionary, targets: Array[Dictionary], look: TacticsSkillLook) -> void:
	var view: UnitView = caster["view"]
	var aim := Vector2.RIGHT * (1.0 if caster["feet"].x < _band.size.x / 2.0 else -1.0)
	if not targets.is_empty() and targets[0]["side"] != caster["side"]:
		aim = targets[0]["view"].position - view.position
	if look.path == &"path.dash" or look.path == &"path.beam":
		view.lunge(aim)
	else:
		view.recoil(aim)
	Sound.play(look.path_sound)


func _land_skill(target: Dictionary, results: Dictionary, mark_text: String, look: TacticsSkillLook) -> void:
	var view: UnitView = target["view"]
	Sound.play(look.impact_sound)
	if not results.has(target["unit"]):
		view.cheer()
		_float_over(target, mark_text, Palette.JADE_LIGHT, 28)
		return
	var result: Dictionary = results[target["unit"]]
	view.hit_flash()
	target["hp"] = int(result["hp_after"])
	_float_number(target, "-%d" % int(result["amount"]), look.color_accent.lightened(0.2))
	if int(result["hp_after"]) <= 0 and not view.is_dead:
		view.die()
		Sound.play(&"death")


func _float_number(actor: Dictionary, text: String, color: Color) -> void:
	_float_over(actor, text, color, 40)


func _float_over(actor: Dictionary, text: String, color: Color, font_px: int) -> void:
	var label := _label(font_px, color)
	label.text = text
	label.add_theme_constant_override(&"outline_size", 9)
	_numbers.add_child(label)
	label.reset_size()
	var feet: Vector2 = actor["feet"]
	# Numbers that follow each other step aside so they do not cover each other.
	var stack: int = actor["floats"]
	actor["floats"] = stack + 1
	var shift := Vector2(-22.0 if stack % 2 == 0 else 22.0, -30.0 * (stack % 3)) if stack > 0 else Vector2.ZERO
	var x := clampf(feet.x - label.size.x / 2.0 + shift.x, 4.0, _band.size.x - label.size.x - 4.0)
	label.position = Vector2(x, feet.y - PLATE_PX - 10.0 - label.size.y + shift.y)
	var tween := label.create_tween()
	tween.tween_property(label, ^"position:y", label.position.y - 46.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, ^"modulate:a", 0.0, 0.3).set_delay(0.6)
	tween.tween_callback(label.queue_free)


func _label(font_px: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override(&"font_size", font_px)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Palette.INK)
	label.add_theme_constant_override(&"outline_size", 8)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _place(control: Control, left: float, top: float, right: float, bottom: float) -> void:
	control.anchor_left = left
	control.anchor_top = top
	control.anchor_right = right
	control.anchor_bottom = bottom
	if control.get_parent() == null:
		add_child(control)


## Name plates and hp bars over the figures.
class _Plates extends Control:
	var owner_scene: TacticsCloseUp

	func _draw() -> void:
		var font := get_theme_default_font()
		for actor: Dictionary in owner_scene.get_actors():
			var feet: Vector2 = actor["feet"]
			var top := feet + Vector2(0, -TacticsCloseUp.PLATE_PX)
			# Narrower plates when the stage is crowded.
			var width := 150.0 if owner_scene.get_actors().size() <= 2 else 124.0
			var font_px := 22 if owner_scene.get_actors().size() <= 2 else 19
			var rect := Rect2(top - Vector2(width / 2.0, 0), Vector2(width, 12))
			draw_rect(rect.grow(2.0), Palette.INK)
			draw_rect(rect, Color("3a302b"))
			var ratio := clampf(float(actor["hp"]) / actor["max_hp"], 0.0, 1.0)
			draw_rect(Rect2(rect.position, Vector2(width * ratio, 12)), Palette.PLAYER_HP if actor["side"] == 0 else Palette.ENEMY_HP)
			var text := "%s  %d" % [actor["name"], actor["hp"]]
			var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px)
			var at := Vector2(clampf(top.x - text_size.x / 2.0, 4.0, size.x - text_size.x - 4.0), top.y - 8.0)
			draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, 6, Palette.INK)
			draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, Palette.CREAM)
