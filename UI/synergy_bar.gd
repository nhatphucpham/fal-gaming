class_name SynergyBar
extends Control
## The prep info row's synergy half, drawn in one control so it stays one
## row at 720 px: the Hợp Lực ring (number, thin arc to the next tier), up to
## two active formation chips in their colours, and a "+N" pill counting what
## the chips leave out (more formations, milestones reached). A tap anywhere
## asks for the full SynergyPanel. While a move is previewed the ring shows
## "5 → 7" and the chips show the line-up the move would make.
## [codeblock]
## bar.setup(catalog)
## bar.show_result(catalog.get_synergy().evaluate(pieces))
## bar.opened.connect(panel.open)
## [/codeblock]

signal opened()

const MAX_CHIPS: int = 2
const RING_RADIUS_PX: float = 19.0
const CHIP_HEIGHT_PX: float = 34.0
const CHIP_MAX_WIDTH_PX: float = 176.0
const CHIP_FONT_SIZE: int = 18
const RING_FONT_SIZE: int = 22
const GAP_PX: float = 8.0
const PILL_WIDTH_PX: float = 50.0

var _catalog: Catalog
var _result: Dictionary = {}
var _preview: Dictionary = {}
var _is_previewing: bool = false
var _ring_scale: float = 1.0
var _bounce_tween: Tween
var _chip_box: StyleBoxFlat


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, 46)
	_chip_box = GameTheme.make_panel(Palette.PANEL, 17, 3)


func setup(catalog: Catalog) -> void:
	_catalog = catalog


## Shows an evaluate() result for the player's board.
func show_result(result: Dictionary) -> void:
	var before: int = _result.get("hop_luc", 0)
	_result = result
	queue_redraw()
	if result.get("hop_luc", 0) != before:
		bounce()


## Shows what a move would make, next to the current number.
func show_preview(result: Dictionary) -> void:
	_preview = result
	_is_previewing = true
	queue_redraw()


func end_preview() -> void:
	if not _is_previewing:
		return
	_is_previewing = false
	_preview = {}
	queue_redraw()


func is_previewing() -> bool:
	return _is_previewing


## The formation ids the chips show now, for tests.
func get_chip_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry: Dictionary in _shown().get("formations", []).slice(0, MAX_CHIPS):
		ids.append(entry["id"])
	return ids


## What the "+N" pill counts: formations past the chips and milestones reached.
func get_more_count() -> int:
	var shown := _shown()
	var more := maxi(0, shown.get("formations", []).size() - MAX_CHIPS)
	for entry: Dictionary in shown.get("class_milestones", []) + shown.get("race_milestones", []):
		if entry["reached"] > 0:
			more += 1
	return more


## The ring's pop when the number changes and at the battle's roll call.
func bounce() -> void:
	if _bounce_tween != null and _bounce_tween.is_valid():
		_bounce_tween.kill()
	_bounce_tween = create_tween()
	_bounce_tween.tween_method(_set_ring_scale, 1.35, 1.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		opened.emit()


func _draw() -> void:
	var font := get_theme_default_font()
	var middle := size.y / 2.0
	var x := _draw_ring(font, Vector2(RING_RADIUS_PX + 4.0, middle))
	var shown := _shown()
	var formations: Array = shown.get("formations", [])
	for entry: Dictionary in formations.slice(0, MAX_CHIPS):
		x = _draw_chip(font, entry["id"], x + GAP_PX, middle)
	_draw_pill(font, x + GAP_PX, middle, get_more_count())


# The ring, and in a preview the "5 → 7" beside it. Returns the right edge.
func _draw_ring(font: Font, center: Vector2) -> float:
	var points: int = _result.get("hop_luc", 0)
	var radius := RING_RADIUS_PX * _ring_scale
	draw_circle(center, radius + 3.0, Palette.INK)
	draw_circle(center, radius, Palette.PANEL)
	draw_arc(center, radius - 2.0, 0.0, TAU, 32, Color(Palette.GOLD, 0.25), 3.0, true)
	var share := _tier_share(points)
	if share > 0.0:
		draw_arc(center, radius - 2.0, -PI / 2.0, -PI / 2.0 + TAU * share, 32, Palette.GOLD, 3.5, true)
	var size_px := int(RING_FONT_SIZE * _ring_scale)
	_draw_centered(font, str(points), center, size_px, Palette.CREAM)
	var right := center.x + RING_RADIUS_PX + 3.0
	if not _is_previewing:
		return right
	var after: int = _preview.get("hop_luc", 0)
	var color := Palette.JADE_LIGHT if after > points else (Palette.VERMILION if after < points else Palette.TEXT_DIM)
	var text := "→ %d" % after
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, RING_FONT_SIZE).x
	var origin := Vector2(right + 6.0, center.y + RING_FONT_SIZE * 0.35)
	draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, RING_FONT_SIZE, 6, Palette.INK)
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, RING_FONT_SIZE, color)
	return right + 6.0 + width


# A rounded chip with the formation's colour dot and name.
func _draw_chip(font: Font, id: StringName, left: float, middle: float) -> float:
	var formation := _catalog.get_formation(id) if _catalog != null else null
	var label := tr(formation.name_key) if formation != null else String(id)
	var color := formation.color if formation != null else Palette.GOLD
	var text_width := minf(font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, CHIP_FONT_SIZE).x, CHIP_MAX_WIDTH_PX - 40.0)
	var rect := Rect2(left, middle - CHIP_HEIGHT_PX / 2.0, text_width + 40.0, CHIP_HEIGHT_PX)
	_chip_box.border_color = color
	_chip_box.draw(get_canvas_item(), rect)
	draw_circle(Vector2(left + 16.0, middle), 7.0, Palette.INK)
	draw_circle(Vector2(left + 16.0, middle), 5.0, color)
	draw_string(font, Vector2(left + 28.0, middle + CHIP_FONT_SIZE * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, text_width, CHIP_FONT_SIZE, Palette.TEXT)
	return rect.end.x


# "+N", or three dots when the chips already say everything.
func _draw_pill(font: Font, left: float, middle: float, more: int) -> void:
	var rect := Rect2(left, middle - CHIP_HEIGHT_PX / 2.0, PILL_WIDTH_PX, CHIP_HEIGHT_PX)
	_chip_box.border_color = Palette.INK
	_chip_box.draw(get_canvas_item(), rect)
	if more > 0:
		_draw_centered(font, "+%d" % more, rect.get_center(), CHIP_FONT_SIZE + 2, Palette.GOLD)
		return
	for dot: int in 3:
		draw_circle(rect.get_center() + Vector2((dot - 1) * 9.0, 0.0), 3.0, Palette.TEXT_DIM)


func _draw_centered(font: Font, text: String, center: Vector2, size_px: int, color: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var origin := center + Vector2(-width / 2.0, size_px * 0.35)
	draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 6, Palette.INK)
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)


# How far `points` is from the tier reached to the next one, 0..1.
func _tier_share(points: int) -> float:
	if _catalog == null or _catalog.hop_luc == null:
		return 0.0
	var below := 0
	for tier: SynergyTierData in _catalog.hop_luc.tiers:
		if points < tier.at:
			return float(points - below) / maxf(1.0, tier.at - below)
		below = tier.at
	return 1.0


func _shown() -> Dictionary:
	return _preview if _is_previewing else _result


func _set_ring_scale(value: float) -> void:
	_ring_scale = value
	queue_redraw()
