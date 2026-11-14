class_name BattleStatus
extends Control
## Shown under the board during a battle: for each side, how many units are
## alive and a bar of its remaining health share (the sum of each unit's
## hp / max_hp, the measure that decides a battle at the time limit).
## [codeblock]
## status.show_sides(0.8, 6, 0.4, 3)
## [/codeblock]

const ROW_HEIGHT_PX: float = 56.0
const BAR_HEIGHT_PX: float = 22.0
const LABEL_WIDTH_PX: float = 176.0
const SIDE_MARGIN_PX: float = 52.0

var _shares: Array[float] = [1.0, 1.0]
var _alive: Array[int] = [0, 0]
var _labels: Array[Label] = []
var _tween: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for row: int in 2:
		var label := Label.new()
		label.add_theme_font_size_override(&"font_size", 26)
		label.position = Vector2(SIDE_MARGIN_PX, row * ROW_HEIGHT_PX)
		label.size = Vector2(LABEL_WIDTH_PX, ROW_HEIGHT_PX)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(label)
		_labels.append(label)


## Updates both sides: `*_share` 0..1 of total health, `*_alive` units left.
func show_sides(player_share: float, player_alive: int, enemy_share: float, enemy_alive: int) -> void:
	var changed := _alive[0] != player_alive or _alive[1] != enemy_alive
	_alive = [player_alive, enemy_alive]
	_labels[0].text = tr("SIDE_PLAYER") % player_alive
	_labels[1].text = tr("SIDE_ENEMY") % enemy_alive
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_parallel()
	_tween.tween_method(_set_share.bind(0), _shares[0], player_share, 0.2)
	_tween.tween_method(_set_share.bind(1), _shares[1], enemy_share, 0.2)
	if changed:
		queue_redraw()


func _set_share(value: float, side: int) -> void:
	_shares[side] = value
	queue_redraw()


func _draw() -> void:
	var colors: Array[Color] = [Palette.PLAYER_HP, Palette.ENEMY_HP]
	var bar_x := SIDE_MARGIN_PX + LABEL_WIDTH_PX
	var bar_width := size.x - bar_x - SIDE_MARGIN_PX
	for row: int in 2:
		var top := row * ROW_HEIGHT_PX + (ROW_HEIGHT_PX - BAR_HEIGHT_PX) / 2.0
		var frame := Rect2(bar_x, top, bar_width, BAR_HEIGHT_PX)
		draw_rect(frame.grow(3.0), Palette.INK)
		draw_rect(frame, Palette.PANEL)
		draw_rect(Rect2(frame.position, Vector2(bar_width * clampf(_shares[row], 0.0, 1.0), BAR_HEIGHT_PX)), colors[row])
