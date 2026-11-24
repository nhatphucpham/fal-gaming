class_name TacticsWorldMap
extends Control
## The Chiến Dịch world map: every region a round node on its spot, the
## roads between neighbours, and the region's control by colour (ours
## jade, the enemy's red, out of reach grey, the home gold). The region the
## enemy declared it will press next has a red ring and a war flag; red
## diamonds under a node count its pressure; a gold stall marks a market.
## All shapes go into one triangle array (MeshCanvas), names after.
## It redraws only when the state changes, the selection moves or a pulse
## plays (a changed region rings out once); an idle map draws nothing.
## [codeblock]
## var map := TacticsWorldMap.new()
## map.world = roster.world
## map.region_tapped.connect(func(id: StringName) -> void: ...)
## [/codeblock]

signal region_tapped(id: StringName)

const NODE_RADIUS_PX: float = 50.0
const NAME_FONT_PX: int = 25
const ROAD_WIDTH_PX: float = 9.0
const PULSE_SEC: float = 0.7
## How far a press may slide and still be a tap.
const TAP_SLOP_PX: float = 24.0
## Room kept around the nodes: a name under each, the flag above.
const MARGIN_PX := Vector2(80.0, 70.0)
const STATE_FILLS: Dictionary[StringName, Color] = {
	TacticsWorld.STATE_HOME: Palette.GOLD,
	TacticsWorld.STATE_OURS: Palette.JADE,
	TacticsWorld.STATE_OPEN: Palette.VERMILION_DARK,
	TacticsWorld.STATE_LOCKED: Color("4a4f63"),
}

var world: TacticsWorld:
	set(value):
		world = value
		queue_redraw()
var selected: StringName = &"":
	set(value):
		if selected != value:
			selected = value
			queue_redraw()
## Redraws taken (for tests: an idle map takes none).
var draw_count: int = 0

var _pulse_region: StringName = &""
var _pulse: float = 0.0:
	set(value):
		_pulse = value
		queue_redraw()
var _press_at := Vector2.ZERO
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)


## Where a region's node is drawn, in this control's pixels.
func get_node_center(id: StringName) -> Vector2:
	var region := world.data.get_region(id)
	if region == null:
		return Vector2(-1, -1)
	var area := Rect2(MARGIN_PX, size - MARGIN_PX * 2.0)
	return area.position + area.size * region.map_position


## The region whose node is under `point`, or empty.
func region_at(point: Vector2) -> StringName:
	for region: TacticsRegionData in world.data.regions:
		if point.distance_to(get_node_center(region.id)) <= NODE_RADIUS_PX * 1.25:
			return region.id
	return &""


## A ring that grows and fades on one region, once (a change landed there).
func pulse(id: StringName) -> void:
	_pulse_region = id
	if _tween != null:
		_tween.kill()
	_pulse = 0.0
	_tween = create_tween()
	_tween.tween_property(self, ^"_pulse", 1.0, PULSE_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(func() -> void:
		_pulse_region = &""
		queue_redraw())


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.pressed:
		_press_at = button.position
		return
	if button.position.distance_to(_press_at) > TAP_SLOP_PX:
		return
	var id := region_at(button.position)
	if id != &"":
		accept_event()
		region_tapped.emit(id)


func _draw() -> void:
	draw_count += 1
	if world == null:
		return
	var canvas := MeshCanvas.new()
	_draw_roads(canvas)
	var threat := world.get_threat()
	for region: TacticsRegionData in world.data.regions:
		_draw_node(canvas, region, region.id == threat)
	if _pulse_region != &"":
		var c := get_node_center(_pulse_region)
		canvas.draw_arc(c, NODE_RADIUS_PX * (1.0 + 0.7 * _pulse), 0.0, TAU, 40, Color(Palette.GOLD, 1.0 - _pulse), 6.0)
	canvas.commit(get_canvas_item())
	var font := get_theme_default_font()
	for region: TacticsRegionData in world.data.regions:
		var label := tr(region.name_key)
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FONT_PX).x
		var at := get_node_center(region.id) + Vector2(-width / 2.0, NODE_RADIUS_PX + 8.0 + font.get_ascent(NAME_FONT_PX))
		draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FONT_PX, 6, Palette.INK)
		draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FONT_PX, Palette.CREAM if world.get_state(region.id) != TacticsWorld.STATE_LOCKED else Palette.TEXT_DIM)


func _draw_roads(canvas: MeshCanvas) -> void:
	var drawn := {}
	for region: TacticsRegionData in world.data.regions:
		for other: StringName in world.get_neighbours(region.id):
			var key := [region.id, other] if String(region.id) < String(other) else [other, region.id]
			if drawn.has(key):
				continue
			drawn[key] = true
			var is_ours := _is_held(region.id) and _is_held(other)
			var color := Color(Palette.JADE_LIGHT, 0.8) if is_ours else Color(Palette.PAPER_DARK, 0.35)
			canvas.draw_line(get_node_center(region.id), get_node_center(other), Palette.INK, ROAD_WIDTH_PX + 4.0)
			canvas.draw_line(get_node_center(region.id), get_node_center(other), color, ROAD_WIDTH_PX)


func _is_held(id: StringName) -> bool:
	var state := world.get_state(id)
	return state == TacticsWorld.STATE_OURS or state == TacticsWorld.STATE_HOME


func _draw_node(canvas: MeshCanvas, region: TacticsRegionData, is_threat: bool) -> void:
	var c := get_node_center(region.id)
	var state := world.get_state(region.id)
	var r := NODE_RADIUS_PX
	if is_threat:
		canvas.draw_circle(c, r + 14.0, Color(Palette.VERMILION, 0.35))
		canvas.draw_arc(c, r + 10.0, 0.0, TAU, 40, Palette.VERMILION, 5.0)
		_draw_flag(canvas, c + Vector2(r * 0.55, -r - 4.0))
	canvas.draw_circle(c, r + 4.0, Palette.INK)
	canvas.draw_circle(c, r, STATE_FILLS[state])
	canvas.draw_circle(c, r * 0.72, Color(Palette.CREAM, 0.14))
	_draw_symbol(canvas, c, state)
	if region.id == selected:
		canvas.draw_arc(c, r + 4.0, 0.0, TAU, 40, Palette.GOLD, 6.0)
	if region.has_market():
		_draw_stall(canvas, c + Vector2(r * 0.78, r * 0.55))
	var pressure := world.get_pressure(region.id)
	for index: int in pressure:
		var p := c + Vector2((index - (pressure - 1) / 2.0) * 16.0, -r + 2.0)
		var diamond := PackedVector2Array([p + Vector2(0, -7), p + Vector2(7, 0), p + Vector2(0, 7), p + Vector2(-7, 0)])
		canvas.draw_colored_polygon(diamond, Palette.VERMILION)
		diamond.append(diamond[0])
		canvas.draw_polyline(diamond, Palette.INK, 2.0)


# The home's banner, a crossed pair of blades on the enemy's, a jade check
# on ours, a lock out of reach.
func _draw_symbol(canvas: MeshCanvas, c: Vector2, state: StringName) -> void:
	var r := NODE_RADIUS_PX * 0.42
	match state:
		TacticsWorld.STATE_HOME:
			canvas.draw_line(c + Vector2(-r * 0.4, r), c + Vector2(-r * 0.4, -r), Palette.INK, 5.0)
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.4, -r), c + Vector2(r, -r * 0.55), c + Vector2(-r * 0.4, -r * 0.1)]), Palette.VERMILION)
		TacticsWorld.STATE_OURS:
			canvas.draw_polyline(PackedVector2Array([c + Vector2(-r, 0), c + Vector2(-r * 0.25, r * 0.7), c + Vector2(r, -r * 0.7)]), Palette.CREAM, 8.0)
		TacticsWorld.STATE_OPEN:
			canvas.draw_line(c + Vector2(-r, -r), c + Vector2(r, r), Palette.STEEL, 6.0)
			canvas.draw_line(c + Vector2(r, -r), c + Vector2(-r, r), Palette.STEEL, 6.0)
		_:
			canvas.draw_rect(Rect2(c + Vector2(-r * 0.6, -r * 0.1), Vector2(r * 1.2, r * 0.9)), Palette.TEXT_DIM)
			canvas.draw_arc(c + Vector2(0, -r * 0.1), r * 0.42, PI, TAU, 12, Palette.TEXT_DIM, 4.0)


func _draw_flag(canvas: MeshCanvas, at: Vector2) -> void:
	canvas.draw_line(at, at + Vector2(0, -34), Palette.INK, 5.0)
	canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -34), at + Vector2(26, -26), at + Vector2(0, -16)]), Palette.VERMILION)


func _draw_stall(canvas: MeshCanvas, at: Vector2) -> void:
	canvas.draw_circle(at, 17.0, Palette.INK)
	canvas.draw_circle(at, 14.0, Palette.GOLD)
	canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(-9, -2), at + Vector2(0, -9), at + Vector2(9, -2)]), Palette.VERMILION)
	canvas.draw_rect(Rect2(at + Vector2(-7, -1), Vector2(14, 8)), Palette.WOOD)
