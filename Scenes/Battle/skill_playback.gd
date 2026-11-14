class_name SkillPlayback
extends RefCounted
## The skill half of BattlePlayback: turns Khí, cast, skill, passive and
## status events into animations. Each skill's look on resolve comes from a
## registry keyed by skill id (a glyph on every cell for a skill it does not
## know). Big effects and name popups are capped so a busy fight stays
## readable. See Docs/systems/battle_playback.md.

const WIND_UP_SEC: float = 0.2
const MAX_BIG_EFFECTS: int = 3
const MAX_NAME_POPUPS: int = 3
# How far apart two name popups must be to both be read.
const NAME_CLEAR_PX := Vector2(200.0, 30.0)
const NAME_MIN_Y: float = 20.0
const BIG_EFFECT_SEC: float = 0.5
const SHAKE_PX: float = 2.5
const SHAKE_SEC: float = 0.15
const ARROW_FALL_SEC: float = 0.25
const ARROW_STAGGER_SEC: float = 0.07

var _playback: BattlePlayback
var _catalog: Catalog
var _big_effects: int = 0
# Where the name popups on screen now are, so a new one can stack above.
var _name_spots: Array[Vector2] = []
var _shake_tween: Tween
# Skill damage events seen per cause, to stagger a volley's arrows.
var _volley_index: Dictionary[int, int] = {}
var _resolvers: Dictionary[StringName, Callable] = {}
var _damage_looks: Dictionary[StringName, Callable] = {}


func _init(playback: BattlePlayback) -> void:
	_playback = playback
	_resolvers = {
		&"skill.hold_ground": _resolve_hold_ground,
		&"skill.sweep": _resolve_sweep,
		&"skill.heart_pierce": _resolve_heart_pierce,
		&"skill.breakthrough": _resolve_breakthrough,
		&"skill.arrow_rain": _resolve_arrow_rain,
		&"skill.arcane_circle": _resolve_glyphs,
	}
	_damage_looks = {
		&"skill.arrow_rain": _arrow_rain_damage,
		# The arrow rain formation's volley falls like the skill's arrows.
		&"formation.arrow_rain": _arrow_rain_damage,
		&"skill.breakthrough": _breakthrough_damage,
	}


## Readies for a new battle; `catalog` (may be null) names the skills.
func begin(catalog: Catalog) -> void:
	_catalog = catalog
	_big_effects = 0
	_name_spots.clear()
	_volley_index.clear()


func get_handlers() -> Dictionary[StringName, Callable]:
	return {
		&"qi_changed": _on_qi_changed,
		&"skill_cast_started": _on_cast_started,
		&"skill_resolved": _on_skill_resolved,
		&"passive_triggered": _on_passive_triggered,
		&"status_applied": _on_status_applied,
		&"status_ended": _on_status_ended,
	}


## Seconds from a skill's damage event until it lands on screen, starting any
## effect that leads up to it (a falling arrow, an impact burst).
func damage_delay(event: Dictionary, base_delay: float) -> float:
	var look: Callable = _damage_looks.get(event["skill"], Callable())
	return look.call(event, base_delay) if look.is_valid() else base_delay


func _on_qi_changed(event: Dictionary) -> void:
	var view := _playback.get_view(event["unit"])
	if view != null:
		view.set_qi(event["qi"], event["qi_max"])


func _on_cast_started(event: Dictionary) -> void:
	var view := _playback.get_view(event["unit"])
	if view == null:
		return
	var color := _class_color(view)
	var seconds := float(int(event["end_tick"]) - int(event["tick"]) + 1) / _playback.get_ticks_per_second()
	view.wind_up(WIND_UP_SEC)
	view.skill_overlay.accent = color
	view.skill_overlay.set_casting(true)
	var centers: Array[Vector2] = []
	for cell: Vector2i in event["cells"]:
		centers.append(_playback.cell_center(cell))
	_playback.spawn_fx(SkillFx.area_glow(centers, color, seconds))
	_show_name(view, event["skill"], color)
	Sound.play(&"skill_cast")


func _on_skill_resolved(event: Dictionary) -> void:
	var view := _playback.get_view(event["unit"])
	if view == null:
		return
	view.skill_overlay.set_casting(false)
	view.recoil(Vector2(0, -1 if view.side == 0 else 1))
	_shake()
	Sound.play(&"spell")
	if _big_effects >= MAX_BIG_EFFECTS:
		return
	_big_effects += 1
	_playback.run_after(BIG_EFFECT_SEC, func() -> void: _big_effects = maxi(_big_effects - 1, 0))
	var resolver: Callable = _resolvers.get(event["skill"], _resolve_glyphs)
	var cells: Array[Vector2i] = []
	cells.assign(event["cells"])
	resolver.call(view, cells, _class_color(view))


func _on_passive_triggered(event: Dictionary) -> void:
	var view := _playback.get_view(event["unit"])
	if view != null:
		view.skill_overlay.accent = _class_color(view)
		view.skill_overlay.blink_passive()


func _on_status_applied(event: Dictionary) -> void:
	var view := _playback.get_view(event["unit"])
	if view == null:
		return
	var status: StringName = event["status"]
	view.skill_overlay.add_status(status)
	if status == &"status.stun":
		view.skill_overlay.set_casting(false)
	elif status == &"status.taunted":
		_playback.spawn_fx(SkillFx.taunt_mark(view.position + Vector2(0, -66)))
	elif status == &"status.petrified":
		view.skill_overlay.set_casting(false)
		view.set_petrified(true)
		_playback.spawn_fx(SkillFx.name_popup(view.position + Vector2(0, -96), view.tr("STATUS_PETRIFIED"), Palette.STEEL))
		Sound.play(&"petrify")
		_playback.unit_petrified.emit(event["unit"], true)


func _on_status_ended(event: Dictionary) -> void:
	var view := _playback.get_view(event["unit"])
	if view == null:
		return
	view.skill_overlay.remove_status(event["status"])
	if event["status"] == &"status.petrified":
		view.set_petrified(false)
		_playback.unit_petrified.emit(event["unit"], false)


func _show_name(view: UnitView, skill_id: StringName, color: Color) -> void:
	if _catalog == null or _name_spots.size() >= MAX_NAME_POPUPS:
		return
	var skill := _catalog.get_skill(skill_id)
	if skill == null:
		return
	var spot := view.position + Vector2(0, -62)
	# Side by side casters would print over each other: stack instead.
	var is_blocked := true
	while is_blocked:
		is_blocked = false
		for other: Vector2 in _name_spots:
			if absf(other.x - spot.x) < NAME_CLEAR_PX.x and absf(other.y - spot.y) < NAME_CLEAR_PX.y:
				spot.y = other.y - NAME_CLEAR_PX.y
				is_blocked = true
	# Keep it on the board above the top row.
	spot.y = maxf(spot.y, NAME_MIN_Y)
	_name_spots.append(spot)
	_playback.run_after(SkillFx.NAME_SEC, func() -> void: _name_spots.erase(spot))
	_playback.spawn_fx(SkillFx.name_popup(spot, view.tr(skill.name_key), color))


# Shakes the pieces and effects (not the board) by a few pixels.
func _shake() -> void:
	var layers: Array[Node2D] = _playback.get_shake_layers()
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = _playback.create_tween()
	_shake_tween.set_speed_scale(_playback.speed)
	var steps := 4
	for step: int in steps:
		var offset := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized() * SHAKE_PX
		if step == steps - 1:
			offset = Vector2.ZERO
		for layer: Node2D in layers:
			_shake_tween.parallel().tween_property(layer, ^"position", offset, SHAKE_SEC / steps)
		_shake_tween.chain()


func _resolve_hold_ground(view: UnitView, _cells: Array[Vector2i], color: Color) -> void:
	_playback.spawn_fx(SkillFx.ground_ring(view.position, BoardView.CELL_PX * 1.6, color))


func _resolve_sweep(view: UnitView, cells: Array[Vector2i], color: Color) -> void:
	var direction := _toward_cells(view, cells)
	_playback.spawn_fx(SkillFx.wide_slash(view.position + direction * BoardView.CELL_PX * 0.6, direction, color))


func _resolve_heart_pierce(view: UnitView, cells: Array[Vector2i], color: Color) -> void:
	var far := view.position
	for cell: Vector2i in cells:
		var point := _playback.cell_center(cell)
		if point.distance_to(view.position) > far.distance_to(view.position):
			far = point
	var direction := (far - view.position).normalized()
	_playback.spawn_fx(SkillFx.thrust(view.position + Vector2(0, -14), far + direction * 20.0 + Vector2(0, -14), color))


func _resolve_breakthrough(view: UnitView, _cells: Array[Vector2i], _color: Color) -> void:
	_playback.spawn_fx(BattleFx.dust(view.position + UnitView.FEET))


# The arrows themselves fall with their damage (_arrow_rain_damage).
func _resolve_arrow_rain(_view: UnitView, _cells: Array[Vector2i], _color: Color) -> void:
	pass


func _resolve_glyphs(_view: UnitView, cells: Array[Vector2i], color: Color) -> void:
	for cell: Vector2i in cells:
		_playback.spawn_fx(SkillFx.glyph(_playback.cell_center(cell), color))


# Each arrow of a volley falls a little after the one before.
func _arrow_rain_damage(event: Dictionary, base_delay: float) -> float:
	var cause: int = event["cause"]
	var index: int = _volley_index.get(cause, 0)
	_volley_index[cause] = index + 1
	var target := _playback.get_view(event["target"])
	var start := base_delay + index * ARROW_STAGGER_SEC
	if target != null:
		var at := target.position + Vector2(randf_range(-8.0, 8.0), -10.0)
		_playback.run_after(start, func() -> void: _playback.spawn_fx(SkillFx.falling_arrow(at, ARROW_FALL_SEC)))
	return start + ARROW_FALL_SEC


func _breakthrough_damage(event: Dictionary, base_delay: float) -> float:
	var target := _playback.get_view(event["target"])
	if target != null:
		var at := target.position + Vector2(0, -10)
		var color := Palette.class_color(&"class.cavalry")
		var source := _playback.get_view(event["source"])
		if source != null:
			color = _class_color(source)
		_playback.run_after(base_delay, func() -> void: _playback.spawn_fx(SkillFx.burst(at, color)))
	return base_delay


func _toward_cells(view: UnitView, cells: Array[Vector2i]) -> Vector2:
	var sum := Vector2.ZERO
	for cell: Vector2i in cells:
		sum += _playback.cell_center(cell) - view.position
	if sum.length() < 1.0:
		return Vector2(0, -1 if view.side == 0 else 1)
	return sum.normalized()


func _class_color(view: UnitView) -> Color:
	return Palette.class_color(view.unit.class_id) if view.unit != null else Palette.GOLD
