class_name TacticsSkillFx
extends Control
## Draws a TacticsSkillLook in the close-up: (a) the caster's aura, (b) the
## skill's path to each target and (c) the impact, from one shared set of
## pieces (rings, streaks, arcs and five motif shapes) picked by the look's
## ids through registries. Everything is a pure function of `time`, so it
## costs a few dozen draw commands a frame and only while a skill plays.
## [codeblock]
## fx.present(look, caster_chest, caster_feet, targets_chest, targets_feet)
## fx.time = 1.2  # seconds since the cast began; redraws
## [/codeblock]

var look: TacticsSkillLook
## Seconds since the cast began; setting it redraws.
var time: float = 0.0:
	set(value):
		time = value
		queue_redraw()

var _caster := Vector2.ZERO
var _caster_feet := Vector2.ZERO
var _targets: Array[Vector2] = []
var _target_feet: Array[Vector2] = []
var _auras: Dictionary[StringName, Callable] = {}
var _paths: Dictionary[StringName, Callable] = {}
var _impacts: Dictionary[StringName, Callable] = {}
var _motifs: Dictionary[StringName, Callable] = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_auras = {&"aura.swirl": _aura_swirl, &"aura.sigil": _aura_sigil, &"aura.rise": _aura_rise}
	_paths = {&"path.arc": _path_arc, &"path.fall": _path_fall, &"path.beam": _path_beam, &"path.dash": _path_dash, &"path.wave": _path_wave}
	_impacts = {&"impact.burst": _impact_burst, &"impact.slash": _impact_slash, &"impact.marks": _impact_marks}
	_motifs = {
		&"motif.feather": _motif_feather, &"motif.crescent": _motif_crescent, &"motif.flame": _motif_flame,
		&"motif.fang": _motif_fang, &"motif.chevron": _motif_chevron,
	}


## Sets what to draw: the look and where the caster and targets stand
## (chest and feet points in this control's coordinates).
func present(skill_look: TacticsSkillLook, caster_chest: Vector2, caster_feet: Vector2, targets_chest: Array[Vector2], targets_feet: Array[Vector2]) -> void:
	look = skill_look
	_caster = caster_chest
	_caster_feet = caster_feet
	_targets = targets_chest
	_target_feet = targets_feet
	time = 0.0


## When the path reaches target `index`, in seconds from the start.
func get_impact_time(index: int) -> float:
	if look.path_order == &"chain":
		return look.cast_sec + look.path_sec * (index + 1) / maxf(_targets.size(), 1)
	return look.get_impact_start() + index * 0.07


## When the whole skill has played, in seconds.
func get_end_time() -> float:
	return get_impact_time(maxi(_targets.size() - 1, 0)) + look.impact_sec


## The screen shake now, in pixels (0 between impacts).
func get_shake() -> float:
	if look == null or look.shake_px <= 0.0:
		return 0.0
	for index: int in _targets.size():
		var since := time - get_impact_time(index)
		if since >= 0.0 and since < 0.22:
			return look.shake_px * sin(since * 90.0) * (1.0 - since / 0.22)
	return 0.0


## Draws the look's motif shape; `size` is its length in pixels.
func draw_motif(at: Vector2, size: float, angle: float, color: Color) -> void:
	var drawer: Callable = _motifs.get(look.motif, _motif_chevron)
	draw_set_transform(at, angle, Vector2.ONE)
	drawer.call(size, color)
	draw_set_transform(Vector2.ZERO)


func _draw() -> void:
	if look == null:
		return
	var aura: Callable = _auras.get(look.aura, _aura_rise)
	if time < look.cast_sec + 0.25:
		aura.call(clampf(time / look.cast_sec, 0.0, 1.0), 1.0 - _ramp(time, look.cast_sec, look.cast_sec + 0.25))
	var path: Callable = _paths.get(look.path, _path_arc)
	var impact: Callable = _impacts.get(look.impact, _impact_burst)
	for index: int in _targets.size():
		var hit_at := get_impact_time(index)
		var start := hit_at - (look.path_sec / maxf(_targets.size(), 1) if look.path_order == &"chain" else look.path_sec)
		var from := _caster if look.path_order != &"chain" or index == 0 else _targets[index - 1]
		var from_feet := _caster_feet if look.path_order != &"chain" or index == 0 else _target_feet[index - 1]
		if time >= start and time < hit_at:
			path.call(from, from_feet, index, (time - start) / maxf(hit_at - start, 0.01))
		if time >= hit_at and time < hit_at + look.impact_sec:
			impact.call(index, (time - hit_at) / look.impact_sec)


# Layer a.

func _aura_swirl(u: float, fade: float) -> void:
	draw_circle(_caster, 46.0 + 10.0 * sin(time * 9.0), Color(look.color_main, 0.18 * fade))
	for index: int in look.motif_count:
		var angle := TAU * index / look.motif_count + time * 6.0
		var radius := lerpf(92.0, 26.0, u)
		var at := _caster + Vector2(cos(angle) * radius, sin(angle) * radius * 0.7)
		var color := look.color_main if index % 2 == 0 else look.color_accent
		draw_motif(at, 16.0, angle + PI / 2.0, Color(color, fade))


func _aura_sigil(u: float, fade: float) -> void:
	var grow := _ease_out(u)
	for ring: float in [1.0, 0.72]:
		_ellipse(_caster_feet, Vector2(78.0, 17.0) * ring * grow, Color(look.color_main, 0.9 * fade), 4.0)
	for index: int in 10:
		var angle := TAU * index / 10.0 + time * 2.2
		var inner := _caster_feet + Vector2(cos(angle) * 78.0, sin(angle) * 17.0) * grow
		var outer := _caster_feet + Vector2(cos(angle) * 92.0, sin(angle) * 21.0) * grow
		draw_line(inner, outer, Color(look.color_accent, fade), 3.0)
	for index: int in look.motif_count:
		var rise := fposmod(time * 1.4 + float(index) / look.motif_count, 1.0)
		var at := _caster_feet + Vector2(-50.0 + 100.0 * _rnd(index), -150.0 * rise)
		draw_motif(at, 14.0 * (1.0 - rise * 0.5), 0.0, Color(look.color_accent, (1.0 - rise) * fade))


func _aura_rise(u: float, fade: float) -> void:
	draw_circle(_caster, 40.0 + 30.0 * u, Color(look.color_main, 0.16 * fade))
	for index: int in look.motif_count:
		var rise := fposmod(time * 1.1 + float(index) / look.motif_count, 1.0)
		var x := (_rnd(index + 7) - 0.5) * 110.0
		var at := _caster_feet + Vector2(x, -20.0 - 170.0 * rise)
		var color := look.color_main if index % 2 == 0 else look.color_accent
		draw_line(at, at + Vector2(0, 26.0), Color(color, 0.6 * (1.0 - rise) * fade), 3.0)
		draw_motif(at, 15.0, 0.0, Color(color, (1.0 - rise) * fade))


# Layer b: `u` runs 0..1 along one path from `from` to target `index`.

func _path_arc(from: Vector2, _from_feet: Vector2, index: int, u: float) -> void:
	var to := _targets[index]
	for shot: int in 3:
		var v := clampf(u * 1.25 - shot * 0.12, 0.0, 1.0)
		if v <= 0.0 or v >= 1.0:
			continue
		var aim := to + Vector2((shot - 1) * 14.0, (shot - 1) * 8.0)
		var head := _arc_point(from, aim, v)
		for trail: int in range(1, 5):
			var back := _arc_point(from, aim, maxf(v - trail * 0.04, 0.0))
			draw_circle(back, 3.0, Color(look.color_main, 0.6 - trail * 0.12))
		var ahead := _arc_point(from, aim, minf(v + 0.02, 1.0))
		draw_motif(head, 18.0, (ahead - head).angle() + PI / 2.0, look.color_accent)


func _path_fall(_from: Vector2, _from_feet: Vector2, index: int, u: float) -> void:
	var feet := _target_feet[index]
	for drop: int in 3:
		var v := clampf(u * 1.3 - drop * 0.15, 0.0, 1.0)
		if v <= 0.0 or v >= 1.0:
			continue
		var land := feet + Vector2((drop - 1) * 26.0, -10.0)
		var sky := land + Vector2(-140.0, -420.0)
		var head := sky.lerp(land, v * v)
		var direction := (land - sky).normalized()
		draw_line(head - direction * 70.0, head, Color(look.color_main, 0.55), 8.0)
		draw_line(head - direction * 40.0, head, Color(look.color_accent, 0.9), 3.0)
		draw_motif(head, 24.0, direction.angle() - PI / 2.0, look.color_main)


func _path_beam(from: Vector2, _from_feet: Vector2, index: int, u: float) -> void:
	var to := _targets[index]
	var tip := from.lerp(to, _ease_out(u))
	draw_line(from, tip, Color(look.color_main, 0.45), 16.0)
	draw_line(from, tip, look.color_accent, 4.0)
	for step: int in 3:
		var at := from.lerp(tip, 0.3 + step * 0.25)
		draw_motif(at, 16.0, (to - from).angle() + PI / 2.0, Color(look.color_main, 0.9))


func _path_dash(_from: Vector2, from_feet: Vector2, index: int, u: float) -> void:
	var to_feet := _target_feet[index]
	var reach := from_feet.lerp(to_feet, _ease_out(u))
	for line: int in 4:
		var y := -30.0 - line * 26.0
		draw_line(from_feet + Vector2(0, y), reach + Vector2(0, y), Color(look.color_accent if line % 2 == 0 else look.color_main, 0.5), 5.0 - line)
	for ghost: int in 3:
		var at := from_feet.lerp(reach, 0.25 + ghost * 0.25) + Vector2(0, -70.0)
		draw_motif(at, 26.0, PI / 2.0 * signf(to_feet.x - from_feet.x), Color(look.color_main, 0.25 + ghost * 0.2))


func _path_wave(_from: Vector2, from_feet: Vector2, index: int, u: float) -> void:
	if index > 0:
		return
	var far := 0.0
	for feet: Vector2 in _target_feet:
		far = maxf(far, absf(feet.x - from_feet.x))
	for ring: int in 3:
		var v := clampf(u * 1.4 - ring * 0.2, 0.0, 1.0)
		if v <= 0.0:
			continue
		_ellipse(from_feet, Vector2(far + 40.0, 26.0) * v, Color(look.color_main, 0.85 * (1.0 - v)), 5.0)
	for index_motif: int in look.motif_count:
		var v := clampf(u * 1.2 - index_motif * 0.06, 0.0, 1.0)
		var at := from_feet + Vector2((far + 40.0) * v * (1.0 if index_motif % 2 == 0 else 0.7), -14.0 - 10.0 * (index_motif % 3))
		draw_motif(at, 14.0, 0.0, Color(look.color_accent, 1.0 - v * 0.6))


# Layer c: `v` runs 0..1 over the impact at target `index`.

func _impact_burst(index: int, v: float) -> void:
	var at := _targets[index]
	_ellipse(at, Vector2(20.0, 20.0) + Vector2(70.0, 70.0) * _ease_out(v), Color(look.color_accent, 1.0 - v), 5.0)
	draw_circle(at, 34.0 * (1.0 - v), Color(look.color_main, 0.5 * (1.0 - v)))
	for piece: int in look.motif_count:
		var angle := TAU * piece / look.motif_count + index
		var at_piece := at + Vector2.from_angle(angle) * (18.0 + 90.0 * _ease_out(v))
		draw_motif(at_piece, 16.0, angle + PI / 2.0, Color(look.color_main if piece % 2 == 0 else look.color_accent, 1.0 - v))


func _impact_slash(index: int, v: float) -> void:
	var at := _targets[index]
	for cut: int in 3:
		var w := clampf(v * 4.0 - cut * 0.5, 0.0, 1.0)
		if w <= 0.0:
			continue
		var tilt := -0.9 + cut * 0.55
		var half := Vector2.from_angle(tilt) * 70.0
		var fade := 1.0 - _ramp(v, 0.5, 1.0)
		draw_line(at - half, at - half + half * 2.0 * w, Color(look.color_main, 0.6 * fade), 12.0)
		draw_line(at - half, at - half + half * 2.0 * w, Color(look.color_accent, fade), 4.0)
	draw_motif(at + Vector2(0, -60.0 - 30.0 * v), 30.0, 0.0, Color(look.color_main, 1.0 - v))


func _impact_marks(index: int, v: float) -> void:
	var feet := _target_feet[index]
	var head := _targets[index] + Vector2(0, -95.0)
	var shown := _ramp(v, 0.0, 0.15) * (1.0 - _ramp(v, 0.8, 1.0))
	_ellipse(feet, Vector2(44.0, 11.0), Color(look.color_main, 0.9 * shown), 4.0)
	draw_circle(_targets[index], 46.0, Color(look.color_accent, 0.14 * shown))
	for mark: int in 2:
		var bob := sin(time * 6.0 + index) * 4.0
		draw_motif(head + Vector2(0, mark * 12.0 + bob), 26.0, 0.0, Color(look.color_accent, shown))


# Motifs, drawn around the origin set by draw_motif; size is the length.

func _motif_feather(size: float, color: Color) -> void:
	var points := PackedVector2Array()
	for step: int in 9:
		var t := float(step) / 8.0
		points.append(Vector2(sin(t * PI) * size * 0.22, (t - 0.5) * size))
	for step: int in range(8, -1, -1):
		var t := float(step) / 8.0
		points.append(Vector2(-sin(t * PI) * size * 0.22, (t - 0.5) * size))
	draw_colored_polygon(points, color)
	draw_line(Vector2(0, -size * 0.5), Vector2(0, size * 0.6), Color(Palette.INK, color.a * 0.6), 1.5)


func _motif_crescent(size: float, color: Color) -> void:
	var points := PackedVector2Array()
	for step: int in 13:
		points.append(Vector2.from_angle(PI * 0.5 + PI * step / 12.0) * size * 0.5)
	for step: int in range(12, -1, -1):
		points.append(Vector2(size * 0.16, 0) + Vector2.from_angle(PI * 0.5 + PI * step / 12.0) * size * 0.4)
	draw_colored_polygon(points, color)


func _motif_flame(size: float, color: Color) -> void:
	var points := PackedVector2Array()
	for step: int in 16:
		var angle := TAU * step / 16.0
		var radius := size * 0.3 * (1.0 + 0.9 * maxf(-sin(angle), 0.0))
		points.append(Vector2(cos(angle) * size * 0.3, sin(angle) * radius))
	draw_colored_polygon(points, color)


func _motif_fang(size: float, color: Color) -> void:
	var points := PackedVector2Array([Vector2(-size * 0.22, -size * 0.5), Vector2(size * 0.22, -size * 0.45)])
	for step: int in 7:
		var t := float(step) / 6.0
		points.append(Vector2(size * 0.22 * (1.0 - t) + size * 0.12 * sin(t * PI), -size * 0.45 + size * t))
	draw_colored_polygon(points, color)


func _motif_chevron(size: float, color: Color) -> void:
	var half := size * 0.5
	draw_polyline(PackedVector2Array([Vector2(-half, half * 0.4), Vector2(0, -half * 0.4), Vector2(half, half * 0.4)]), color, maxf(size * 0.18, 2.0))


func _arc_point(from: Vector2, to: Vector2, u: float) -> Vector2:
	var apex := (from + to) / 2.0 + Vector2(0, -180.0)
	return from.lerp(apex, u).lerp(apex.lerp(to, u), u)


func _ellipse(c: Vector2, radius: Vector2, color: Color, width: float) -> void:
	if radius.x <= 0.5 or radius.y <= 0.5:
		return
	draw_set_transform(c, 0.0, Vector2(1.0, radius.y / radius.x))
	draw_arc(Vector2.ZERO, radius.x, 0.0, TAU, 32, color, width)
	draw_set_transform(Vector2.ZERO)


static func _ramp(value: float, from: float, to: float) -> float:
	return clampf((value - from) / maxf(to - from, 0.0001), 0.0, 1.0)


static func _ease_out(u: float) -> float:
	return 1.0 - (1.0 - u) * (1.0 - u)


# A fixed pseudo-random value in 0..1 per index; presentation only.
static func _rnd(n: int) -> float:
	var value := sin(n * 127.1) * 43758.5453
	return value - floorf(value)
