class_name FormationOutlines
extends Node2D
## Formation outlines on the board, drawn under the pieces in board-local
## pixels: a glowing line around each active formation in its colour, a
## dashed one with a ghost marker on the missing cell for a formation one
## unit short, dimmer red-tinted lines for the enemy's. A formation that
## first completes gets a light running along its outline and its name
## stamped once; roll_call() flashes them all at battle start; shatter()
## breaks one when the battle says it broke. Presentation only.
## [codeblock]
## outlines.setup(catalog)
## board.get_outline_layer().add_child(outlines)
## outlines.show_side(Battle.SIDE_A, result, true)
## [/codeblock]

const RUN_SEC: float = 0.9
const STAMP_SEC: float = 1.3
const SHATTER_SEC: float = 0.6
const ROLL_CALL_SEC: float = 0.8
const INSET_PX: float = 6.0
const LIGHT_PX: float = 70.0
const NAME_FONT_SIZE: int = 26
# Roll call: names stamp one after another, at most this far apart.
const STAMP_STEP_SEC: float = 0.2
const STAMP_LINE_PX: float = 34.0
const ENEMY_TINT := Color("ff6a50")
## How strong the outlines stay once units walk away from their cells.
const BATTLE_ALPHA: float = 0.35

## Hides near-misses and fades outlines during a battle.
var is_battle: bool = false:
	set(value):
		is_battle = value
		_alpha = BATTLE_ALPHA if value else 1.0
		queue_redraw()

var _catalog: Catalog
var _time: float = 0.0
var _alpha: float = 1.0
# Outlines by side: dictionaries with id, cells (global, sorted), color,
# loops, is_near, ghost, ghost_class, run_at, stamp_at, flash_at, broken_at,
# center, name.
var _by_side: Array[Array] = [[], []]
var _saved_own: Array = []
var _is_previewing: bool = false
var _known_own: Dictionary[StringName, bool] = {}
# Names are drawn above the pieces: a child with a higher z_index.
var _stamps: Node2D


func _init() -> void:
	_stamps = Node2D.new()
	_stamps.z_index = 5
	_stamps.draw.connect(_draw_stamps)
	add_child(_stamps)


func setup(catalog: Catalog) -> void:
	_catalog = catalog


## Shows a side's evaluate() result. With `animate`, a formation that was
## not active before runs its light and stamps its name.
func show_side(side: int, result: Dictionary, animate: bool) -> void:
	var outlines: Array = []
	var known: Dictionary[StringName, bool] = {}
	for entry: Dictionary in result.get("formations", []):
		var outline := _make_outline(side, entry["id"], entry["cells"], false)
		known[entry["id"]] = true
		if animate and side == Battle.SIDE_A and not _known_own.has(entry["id"]):
			outline["run_at"] = _time
			outline["stamp_at"] = _time
		outlines.append(outline)
	_place_stamps(outlines)
	if side == Battle.SIDE_A:
		var ghosts: Dictionary[Vector2i, bool] = {}
		for entry: Dictionary in result.get("near_formations", []):
			var missing: Vector2i = entry["missing_cell"]
			var cells: Array = entry["cells"].duplicate()
			cells.append(missing)
			var outline := _make_outline(side, entry["id"], cells, true)
			# Two near-misses sharing a missing cell need one ghost.
			if not ghosts.has(missing):
				ghosts[missing] = true
				outline["ghost"] = _cell_center(Battle.local_to_global(side, missing.x, missing.y))
				outline["ghost_class"] = entry["needed_class"]
			outlines.append(outline)
		_known_own = known
		_is_previewing = false
	_by_side[side] = outlines
	queue_redraw()


## Shows the player's outlines as a move would leave them; end_preview()
## puts the real ones back.
func show_preview(result: Dictionary) -> void:
	if not _is_previewing:
		_saved_own = _by_side[Battle.SIDE_A]
	var known := _known_own
	show_side(Battle.SIDE_A, result, false)
	_known_own = known
	_is_previewing = true


func end_preview() -> void:
	if not _is_previewing:
		return
	_by_side[Battle.SIDE_A] = _saved_own
	_saved_own = []
	_is_previewing = false
	queue_redraw()


func is_previewing() -> bool:
	return _is_previewing


## Ids of a side's active formations as drawn, for tests.
func get_formation_ids(side: int) -> Array[StringName]:
	var ids: Array[StringName] = []
	for outline: Dictionary in _by_side[side]:
		if not outline["is_near"]:
			ids.append(outline["id"])
	return ids


## Ids of the player's near-miss outlines, for tests.
func get_near_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for outline: Dictionary in _by_side[Battle.SIDE_A]:
		if outline["is_near"]:
			ids.append(outline["id"])
	return ids


## Battle start: every active outline flashes and the names stamp in one
## after another within ROLL_CALL_SEC.
func roll_call() -> void:
	var active: Array = []
	for side: int in 2:
		active.append_array(_by_side[side].filter(func(outline: Dictionary) -> bool: return not outline["is_near"]))
	var step := minf(STAMP_STEP_SEC, ROLL_CALL_SEC / maxf(1.0, active.size()))
	_place_stamps(active)
	for index: int in active.size():
		active[index]["flash_at"] = _time
		active[index]["stamp_at"] = _time + index * step
	queue_redraw()


## The battle broke a formation: the outline of that instance (matched by
## its members' global cells, as formation_broken reports them) shatters.
func shatter(side: int, id: StringName, cells: Array) -> void:
	var key := _sorted_cells(cells)
	for outline: Dictionary in _by_side[side]:
		if outline["id"] == id and not outline["is_near"] and outline["broken_at"] < 0.0 and outline["cells"] == key:
			outline["broken_at"] = _time
			return


## Ids of a side's shattered outlines still fading, with their cells, for tests.
func get_broken(side: int) -> Array:
	var broken: Array = []
	for outline: Dictionary in _by_side[side]:
		if outline["broken_at"] >= 0.0:
			broken.append([outline["id"], outline["cells"]])
	return broken


func clear() -> void:
	_by_side = [[], []]
	_saved_own = []
	_is_previewing = false
	_known_own.clear()
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	for side: int in 2:
		_by_side[side] = _by_side[side].filter(func(outline: Dictionary) -> bool:
			return outline["broken_at"] < 0.0 or _time - outline["broken_at"] < SHATTER_SEC)
	if not (_by_side[0].is_empty() and _by_side[1].is_empty()):
		queue_redraw()
		_stamps.queue_redraw()


func _draw() -> void:
	for side: int in 2:
		for outline: Dictionary in _by_side[side]:
			if outline["is_near"] and is_battle:
				continue
			if outline["broken_at"] >= 0.0:
				_draw_shards(outline)
			elif outline["is_near"]:
				_draw_near(outline)
			else:
				_draw_active(outline)


func _draw_stamps() -> void:
	for side: int in 2:
		for outline: Dictionary in _by_side[side]:
			_draw_stamp(outline)


func _draw_active(outline: Dictionary) -> void:
	var color: Color = outline["color"]
	var flash := _pulse(outline["flash_at"], ROLL_CALL_SEC)
	var alpha := clampf(_alpha + flash, 0.0, 1.0)
	for loop: PackedVector2Array in outline["loops"]:
		draw_colored_polygon(loop.slice(0, loop.size() - 1), Color(color, (0.12 + 0.2 * flash) * alpha))
		draw_polyline(loop, Color(color, 0.3 * alpha), 10.0 + 6.0 * flash, true)
		draw_polyline(loop, Color(Palette.INK, 0.7 * alpha), 5.0, true)
		draw_polyline(loop, Color(color.lightened(0.3 * flash), alpha), 3.0, true)
		var run_at: float = outline["run_at"]
		var run: float = (_time - run_at) / RUN_SEC
		if run_at >= 0.0 and run < 1.0:
			_draw_light(loop, run)


func _draw_near(outline: Dictionary) -> void:
	var color: Color = outline["color"]
	var breath := 0.6 + 0.25 * sin(_time * 3.0)
	for loop: PackedVector2Array in outline["loops"]:
		for index: int in loop.size() - 1:
			draw_dashed_line(loop[index], loop[index + 1], Color(color, breath), 3.0, 10.0, true, true)
	if outline["ghost"] == null:
		return
	var center: Vector2 = outline["ghost"]
	var ghost_class: StringName = outline["ghost_class"]
	var ghost_color := Palette.class_color(ghost_class) if ghost_class != &"" else Palette.CREAM
	draw_circle(center, 24.0, Color(ghost_color, 0.22 * breath))
	draw_arc(center, 24.0, 0.0, TAU, 24, Color(ghost_color, breath), 2.5, true)
	draw_line(center + Vector2(-9, 0), center + Vector2(9, 0), Color(Palette.INK, breath), 4.0, true)
	draw_line(center + Vector2(0, -9), center + Vector2(0, 9), Color(Palette.INK, breath), 4.0, true)


# The outline's edges fly apart from its centre and fade.
func _draw_shards(outline: Dictionary) -> void:
	var broken_at: float = outline["broken_at"]
	var progress: float = (_time - broken_at) / SHATTER_SEC
	var color: Color = outline["color"]
	var center: Vector2 = outline["center"]
	for loop: PackedVector2Array in outline["loops"]:
		for index: int in loop.size() - 1:
			var middle := (loop[index] + loop[index + 1]) / 2.0
			var push: Vector2 = (middle - center).normalized() * 40.0 * progress
			var turn: float = 0.6 * progress * (1.0 if index % 2 == 0 else -1.0)
			var half: Vector2 = (loop[index + 1] - loop[index]).rotated(turn) * 0.5 * (1.0 - 0.4 * progress)
			draw_line(middle + push - half, middle + push + half, Color(color, 1.0 - progress), 3.0, true)


# A bright stretch of line travelling once around the loop.
func _draw_light(loop: PackedVector2Array, progress: float) -> void:
	var length := OutlineGeometry.length_of(loop)
	var head := progress * length
	var points := PackedVector2Array()
	for step: int in 9:
		points.append(OutlineGeometry.point_at(loop, fposmod(head - LIGHT_PX * step / 8.0, length)))
	draw_polyline(points, Palette.CREAM, 5.0, true)


func _draw_stamp(outline: Dictionary) -> void:
	var stamp_at: float = outline["stamp_at"]
	var age := _time - stamp_at
	if stamp_at < 0.0 or age < 0.0 or age > STAMP_SEC or outline["is_near"]:
		return
	var font := ThemeDB.fallback_font
	var pop := 1.0 + 0.8 * maxf(0.0, 1.0 - age / 0.18)
	var alpha := 1.0 if age < STAMP_SEC - 0.3 else (STAMP_SEC - age) / 0.3
	var size_px := int(NAME_FONT_SIZE * pop)
	var center: Vector2 = outline["stamp"]
	var width := 360.0
	var origin := center + Vector2(-width / 2.0, size_px * 0.35)
	var color: Color = outline["color"]
	_stamps.draw_string_outline(font, origin, outline["name"], HORIZONTAL_ALIGNMENT_CENTER, width, size_px, 10, Color(Palette.INK, alpha))
	_stamps.draw_string(font, origin, outline["name"], HORIZONTAL_ALIGNMENT_CENTER, width, size_px, Color(color.lightened(0.4), alpha))


# Where each name stamps: over its formation, moved up a line while it would
# cover a name placed before it, and kept on the board.
func _place_stamps(outlines: Array) -> void:
	var font := ThemeDB.fallback_font
	var placed: Array[Rect2] = []
	var bottom := BoardView.ROWS * BoardView.CELL_PX - 20.0
	for outline: Dictionary in outlines:
		var width := font.get_string_size(outline["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FONT_SIZE).x + 16.0
		var center: Vector2 = outline["center"]
		var rect := Rect2(center.x - width / 2.0, center.y - STAMP_LINE_PX / 2.0, width, STAMP_LINE_PX)
		var is_blocked := true
		while is_blocked:
			is_blocked = false
			for other: Rect2 in placed:
				if other.intersects(rect):
					rect.position.y = other.position.y - STAMP_LINE_PX
					is_blocked = true
		rect.position.y = clampf(rect.position.y, 20.0, bottom - STAMP_LINE_PX)
		placed.append(rect)
		outline["stamp"] = rect.get_center()


func _make_outline(side: int, id: StringName, local_cells: Array, is_near: bool) -> Dictionary:
	var formation := _catalog.get_formation(id) if _catalog != null else null
	var color := formation.color if formation != null else Palette.GOLD
	if side == Battle.SIDE_B:
		color = color.lerp(ENEMY_TINT, 0.55)
		color.a = 0.75
	var cells: Array[Vector2i] = []
	var center := Vector2.ZERO
	for local: Vector2i in local_cells:
		var cell := Battle.local_to_global(side, local.x, local.y)
		cells.append(cell)
		center += _cell_center(cell)
	center /= maxf(1.0, cells.size())
	return {
		"id": id, "cells": _sorted_cells(cells), "color": color, "loops": OutlineGeometry.loops(cells, INSET_PX), "is_near": is_near, "ghost": null, "ghost_class": &"",
		"run_at": -1.0, "stamp_at": -1.0, "flash_at": -1.0, "broken_at": -1.0, "center": center, "stamp": center,
		"name": tr(formation.name_key) if formation != null else String(id),
	}


static func _sorted_cells(cells: Array) -> Array[Vector2i]:
	var sorted: Array[Vector2i] = []
	sorted.assign(cells)
	sorted.sort()
	return sorted


# 1 at `start`, easing to 0 over `seconds`; 0 when never started.
func _pulse(start: float, seconds: float) -> float:
	if start < 0.0 or _time - start > seconds:
		return 0.0
	var progress := (_time - start) / seconds
	return absf(sin(progress * PI * 3.0)) * (1.0 - progress)


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2((cell.x + 0.5) * BoardView.CELL_PX, (BoardView.ROWS - 1 - cell.y + 0.5) * BoardView.CELL_PX)
