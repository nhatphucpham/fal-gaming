class_name TacticsPieceView
extends Node2D
## One unit on the tactics map: a flat token with its troop glyph, an hp
## bar, for a leader with a skill the charge pips under it, the marks (Dấu)
## a roster soldier carries and the wavering mark (dao động) of an incident
## about to fire. Its origin
## is the centre of its cell. It has no per-frame work: it redraws only
## when a shown value changes, and moves through tweens made by
## TacticsPlayback. It never reads the battle; callers set what it shows.
## It draws as one triangle array (TacticsMeshCanvas): one draw call.
## [codeblock]
## var piece := TacticsPieceView.new()
## piece.setup(state, TacticsPainter.glyph_for(class_id, state["keywords"]))
## layer.add_child(piece)
## [/codeblock]

const TOKEN_OFFSET := Vector2(0, -5)
const BAR_Y: float = 19.0
const PIPS_Y: float = 26.0
const LEADER_BAR_PX: float = 44.0
const SOLDIER_BAR_PX: float = 34.0
const SHOWN_MARKS: int = 3

enum Wavering {NONE, GOOD, BAD}

var unit_index: int = -1
var side: int = 0
var is_leader: bool = false
var glyph: StringName = &"class.sword"
var hp: int = 1:
	set(value):
		if hp != value:
			hp = value
			queue_redraw()
var max_hp: int = 1
## Skill charge shown as pips; a threshold of 0 shows none.
var charge_value: int = 0:
	set(value):
		if charge_value != value:
			charge_value = value
			queue_redraw()
var charge_threshold: int = 0
## Greyed: this leader of ours has acted this phase.
var is_done: bool = false:
	set(value):
		if is_done != value:
			is_done = value
			queue_redraw()
## 0..1 white flash over the token while a hit lands.
var flash: float = 0.0:
	set(value):
		flash = value
		queue_redraw()
var is_dead: bool = false
## The wavering mark: NONE, GOOD (gold star) or BAD (red "!").
var wavering: Wavering = Wavering.NONE:
	set(value):
		if wavering != value:
			wavering = value
			queue_redraw()
## 0..1.4 size of the wavering mark, for its pop-in.
var wavering_scale: float = 1.0:
	set(value):
		if wavering_scale != value:
			wavering_scale = value
			queue_redraw()
## Marks this soldier carries (from the roster and this battle), up to 3 shown.
var mark_count: int = 0:
	set(value):
		if mark_count != value:
			mark_count = value
			queue_redraw()


## Takes what to show from a get_unit_state() dictionary.
func setup(state: Dictionary, glyph_id: StringName) -> void:
	unit_index = state["index"]
	side = state["side"]
	is_leader = state["role"] == &"leader"
	glyph = glyph_id
	max_hp = maxi(int(state["max_hp"]), 1)
	hp = state["hp"]
	queue_redraw()


## The side it fights for now (a soldier that defected changes colour).
func set_side(value: int) -> void:
	if side != value:
		side = value
		queue_redraw()


func set_charge(value: int, threshold: int) -> void:
	charge_threshold = threshold
	charge_value = value
	queue_redraw()


## The token's centre, in this node's coordinates (for effects).
func get_token_center() -> Vector2:
	return TOKEN_OFFSET


func _draw() -> void:
	# Recorded into one triangle array: one draw call for the whole token.
	var mesh := TacticsMeshCanvas.new()
	TacticsPainter.draw_token(mesh, TOKEN_OFFSET, side, is_leader, glyph, is_done)
	if flash > 0.01:
		var flash_r := 22.0 if is_leader else 16.0
		mesh.draw_circle(TOKEN_OFFSET, flash_r, Color(1, 1, 1, 0.75 * flash))
	TacticsPainter.draw_hp_bar(mesh, Vector2(0, BAR_Y), LEADER_BAR_PX if is_leader else SOLDIER_BAR_PX, float(hp) / max_hp, side)
	if is_leader and charge_threshold > 0:
		TacticsPainter.draw_pips(mesh, Vector2(0, PIPS_Y), charge_value, charge_threshold)
	var r := 21.0 if is_leader else 15.0
	for index: int in mini(mark_count, SHOWN_MARKS):
		var p := TOKEN_OFFSET + Vector2(-r - 1.0, -r + 3.0 + index * 7.0)
		mesh.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -3.5), p + Vector2(3.5, 0), p + Vector2(0, 3.5), p + Vector2(-3.5, 0)]), Palette.GOLD)
		mesh.draw_polyline(PackedVector2Array([p + Vector2(0, -3.5), p + Vector2(3.5, 0), p + Vector2(0, 3.5), p + Vector2(-3.5, 0), p + Vector2(0, -3.5)]), Palette.INK, 1.0)
	if wavering != Wavering.NONE and wavering_scale > 0.01:
		TacticsPainter.draw_wavering(mesh, TOKEN_OFFSET + Vector2(r * 0.85, -r * 1.05), 9.0 * wavering_scale, wavering == Wavering.GOOD)
	mesh.commit(get_canvas_item())
