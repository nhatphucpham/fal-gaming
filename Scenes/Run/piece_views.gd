class_name PieceViews
extends RefCounted
## Keeps one UnitView per RunPiece, on the board or on its bench slot, and
## animates what RunState reports: a bought unit flies from its shop card to
## its slot, moves hop between board and bench, merges pull the copies
## together and the result grows with confetti and stamps its stars (so
## does a free unit, through celebrate()), a sold unit shrinks into the gold
## counter. RunState stays the only owner of the
## pieces; this class only observes it. Positions are converted through
## canvas coordinates because board, bench and overlay are different nodes.

const HOP_SEC: float = 0.22
const FLY_SEC: float = 0.3
const PULL_SEC: float = 0.18
const SELL_SEC: float = 0.32

var _run: RunState
var _board: BoardView
var _bench: BenchBar
var _shop: ShopBar
var _overlay: Node2D
var _gold_target: Callable
var _views: Dictionary[int, UnitView] = {}
var _piece_scale: float = 1.0


## `overlay` is a Node2D above the board and bench for flights and
## confetti; `gold_target` returns the gold counter's global centre.
func _init(run: RunState, board: BoardView, bench: BenchBar, shop: ShopBar, overlay: Node2D, gold_target: Callable) -> void:
	_run = run
	_board = board
	_bench = bench
	_shop = shop
	_overlay = overlay
	_gold_target = gold_target
	_piece_scale = board.scale.x
	run.piece_bought.connect(_on_bought)
	run.piece_moved.connect(_on_moved)
	run.pieces_merged.connect(_on_merged)
	run.piece_sold.connect(_on_sold)


func get_view(piece_id: int) -> UnitView:
	var view: UnitView = _views.get(piece_id, null)
	return view if view != null and is_instance_valid(view) else null


## Frees every view and makes fresh ones where the pieces stand (a new
## preparation, a loaded run, after a battle).
func rebuild() -> void:
	for view: UnitView in _views.values():
		if is_instance_valid(view):
			view.queue_free()
	_views.clear()
	for piece: RunPiece in _run.get_pieces():
		var view := _make_view(piece)
		_attach(view, _home_parent(piece), _home_position(piece))
		view.drop_in()


## A piece that came for free (a road encounter) grows in where it stands
## with confetti and its stars.
func celebrate(piece_id: int) -> void:
	var piece := _run.get_piece(piece_id)
	var view := get_view(piece_id)
	if piece == null or view == null:
		return
	view.grow_in()
	view.stamp_stars(piece.star, 0.2)
	_burst_confetti(_to_global(view.get_parent() as Node2D, view.position))
	Sound.play(&"merge")


## Shows or hides the hp bars of every view (shown during battles).
func set_hp_bars_shown(shown: bool) -> void:
	for view: UnitView in _views.values():
		if is_instance_valid(view):
			view.is_hp_bar_shown = shown


func _make_view(piece: RunPiece) -> UnitView:
	var view := UnitView.new()
	view.setup(_run.catalog.get_unit(piece.unit_id), Battle.SIDE_A, piece.star)
	view.is_hp_bar_shown = false
	_views[piece.id] = view
	return view


func _on_bought(piece_id: int, shop_slot: int) -> void:
	var piece := _run.get_piece(piece_id)
	var view := _make_view(piece)
	var card := _shop.get_card(shop_slot)
	var start := card.get_portrait_center() if card != null else _overlay.get_global_transform_with_canvas().origin
	_attach(view, _home_parent(piece), Vector2.ZERO)
	view.position = _to_local(view.get_parent() as Node2D, start)
	view.squash = Vector2(0.6, 0.6)
	view.hop_to(_home_position(piece), FLY_SEC)
	view.create_tween().tween_property(view, ^"squash", Vector2.ONE, FLY_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_moved(piece_id: int) -> void:
	var piece := _run.get_piece(piece_id)
	var view := get_view(piece_id)
	if piece == null or view == null:
		return
	_settle(view, piece, HOP_SEC)


func _on_merged(result_id: int, consumed_ids: Array[int]) -> void:
	var piece := _run.get_piece(result_id)
	var result := get_view(result_id)
	if piece == null or result == null:
		return
	_settle(result, piece, PULL_SEC)
	var target := _to_global(result.get_parent() as Node2D, _home_position(piece))
	for consumed_id: int in consumed_ids:
		var view := get_view(consumed_id)
		_views.erase(consumed_id)
		if view == null:
			continue
		_reparent_keep(view, _overlay)
		view.is_dead = true
		view.hop_to(_to_local(_overlay, target), PULL_SEC)
		var tween := view.create_tween()
		tween.tween_property(view, ^"modulate:a", 0.0, PULL_SEC).set_ease(Tween.EASE_IN)
		tween.tween_callback(view.queue_free)
	var star := piece.star
	var tween := result.create_tween()
	tween.tween_interval(PULL_SEC)
	tween.tween_callback(func() -> void:
		result.grow_in()
		result.stamp_stars(star, 0.2)
		_burst_confetti(target))


func _on_sold(piece_id: int, _gold: int, _supply: int) -> void:
	var view := get_view(piece_id)
	_views.erase(piece_id)
	if view == null:
		return
	_reparent_keep(view, _overlay)
	view.shrink_to(_to_local(_overlay, _gold_target.call()), SELL_SEC)


# Puts a view under the parent of its piece's place and hops it there.
func _settle(view: UnitView, piece: RunPiece, seconds: float) -> void:
	var parent := _home_parent(piece)
	if view.get_parent() != parent:
		_reparent_keep(view, parent)
	view.hop_to(_home_position(piece), seconds)


func _home_parent(piece: RunPiece) -> Node2D:
	if piece.is_on_board():
		return _board.get_piece_layer()
	if piece.is_on_bench():
		return _bench.get_slot_anchor(piece.bench_slot)
	return _overlay


func _home_position(piece: RunPiece) -> Vector2:
	if piece.is_on_board():
		return _board.cell_to_local(Battle.local_to_global(Battle.SIDE_A, piece.cell.x, piece.cell.y))
	return Vector2.ZERO


func _attach(view: UnitView, parent: Node2D, local: Vector2) -> void:
	parent.add_child(view)
	view.position = local


# Moves a view to another parent without a visible jump.
func _reparent_keep(view: UnitView, parent: Node2D) -> void:
	var old_parent := view.get_parent() as Node2D
	var global := _to_global(old_parent, view.position) if old_parent != null else Vector2.ZERO
	if old_parent != null:
		old_parent.remove_child(view)
	parent.add_child(view)
	view.position = _to_local(parent, global)


func _burst_confetti(global_point: Vector2) -> void:
	var burst := ConfettiBurst.new()
	_overlay.add_child(burst)
	burst.position = _to_local(_overlay, global_point) + Vector2(0, -20)
	burst.play()


func _to_global(node: Node2D, local: Vector2) -> Vector2:
	return node.get_global_transform_with_canvas() * local


func _to_local(node: Node2D, global_point: Vector2) -> Vector2:
	return node.get_global_transform_with_canvas().affine_inverse() * global_point
