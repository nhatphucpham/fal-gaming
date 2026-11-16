class_name TacticsFace
extends RefCounted
## A roster soldier's face, drawn flat from its face seed (`look`): skin,
## head cover (topknot, headband, conical hat or bare), brows, a beard and
## a scar, each picked from a hash of the seed, so a person always looks
## the same. A few polygons and circles; callers redraw when it changes.
## [codeblock]
## TacticsFace.draw_face(self, Vector2(32, 32), 28.0, person["look"])
## [/codeblock]

const SKINS: Array[Color] = [Color("e8c39a"), Color("d6a878"), Color("c08a5c"), Color("a8744a")]
const HAIRS: Array[Color] = [Color("2b2320"), Color("3d2c22"), Color("54463c")]
const CLOTH: Array[Color] = [Color("2f3e6b"), Color("9e2f1e"), Color("3e9c7e"), Color("8a5a35")]


## A face of radius `r` centred on `c`; `ring` outlines it (side colour or
## gold for a named soldier).
static func draw_face(canvas: CanvasItem, c: Vector2, r: float, look: int, ring: Color = Palette.INK) -> void:
	var digits := absi(look)
	var skin := SKINS[_pick(look, 1, SKINS.size())]
	var hair := HAIRS[_pick(look, 2, HAIRS.size())]
	var cover := _pick(look, 3, 4)
	var cloth := CLOTH[_pick(look, 4, CLOTH.size())]
	var has_beard := _pick(look, 5, 3) == 0
	var has_scar := _pick(look, 6, 5) == 0
	canvas.draw_circle(c, r, ring)
	canvas.draw_circle(c, r - 2.5, Palette.PAPER_DARK)
	# Shoulders (the bottom of the disc below a chord), then the head.
	var shoulders := PackedVector2Array()
	for step: int in 9:
		shoulders.append(c + Vector2.from_angle(deg_to_rad(25.0 + 130.0 * step / 8.0)) * (r - 2.5))
	canvas.draw_colored_polygon(shoulders, cloth)
	var head := c + Vector2(0, -r * 0.05)
	var head_r := r * 0.5
	canvas.draw_circle(head, head_r, skin)
	match cover:
		0:
			canvas.draw_circle(head + Vector2(0, -head_r * 0.35), head_r * 0.92, hair)
			canvas.draw_circle(head + Vector2(0, -head_r * 1.15), head_r * 0.32, hair)
			canvas.draw_circle(head + Vector2(0, head_r * 0.12), head_r * 0.86, skin)
		1:
			canvas.draw_circle(head + Vector2(0, -head_r * 0.3), head_r * 0.95, hair)
			canvas.draw_circle(head + Vector2(0, head_r * 0.15), head_r * 0.86, skin)
			canvas.draw_rect(Rect2(head + Vector2(-head_r, -head_r * 0.62), Vector2(head_r * 2.0, head_r * 0.3)), Palette.VERMILION)
		2:
			canvas.draw_colored_polygon(PackedVector2Array([
				head + Vector2(-head_r * 1.6, -head_r * 0.35), head + Vector2(0, -head_r * 1.55), head + Vector2(head_r * 1.6, -head_r * 0.35),
			]), Palette.OCHRE)
			canvas.draw_line(head + Vector2(-head_r * 1.6, -head_r * 0.35), head + Vector2(head_r * 1.6, -head_r * 0.35), Palette.INK, 1.5)
		_:
			canvas.draw_arc(head, head_r * 0.98, PI * 1.1, PI * 1.9, 10, hair, head_r * 0.25)
	var eye_y := head.y + head_r * 0.05
	for side: float in [-1.0, 1.0]:
		canvas.draw_circle(Vector2(head.x + side * head_r * 0.38, eye_y), maxf(r * 0.05, 1.2), Palette.INK)
		var brow := Vector2(head.x + side * head_r * 0.38, eye_y - head_r * 0.28)
		canvas.draw_line(brow - Vector2(head_r * 0.2, -side * head_r * 0.04 * float(digits % 2)), brow + Vector2(head_r * 0.2, 0), hair, maxf(r * 0.05, 1.2))
	if has_beard:
		canvas.draw_colored_polygon(PackedVector2Array([
			head + Vector2(-head_r * 0.55, head_r * 0.4), head + Vector2(head_r * 0.55, head_r * 0.4), head + Vector2(0, head_r * 1.15),
		]), hair)
	else:
		canvas.draw_line(head + Vector2(-head_r * 0.22, head_r * 0.5), head + Vector2(head_r * 0.22, head_r * 0.5), Palette.INK_SOFT, maxf(r * 0.04, 1.0))
	if has_scar:
		canvas.draw_line(head + Vector2(head_r * 0.15, -head_r * 0.25), head + Vector2(head_r * 0.6, head_r * 0.35), Palette.VERMILION_DARK, maxf(r * 0.04, 1.0))


# One feature of a face, spread from the seed so features vary apart.
static func _pick(look: int, feature: int, count: int) -> int:
	return absi(hash(look * 31 + feature)) % count


## A Control that shows one face; set `look` (and `ring`) and it redraws.
class FaceView extends Control:
	var look: int = 0:
		set(value):
			look = value
			queue_redraw()
	var ring: Color = Palette.INK:
		set(value):
			ring = value
			queue_redraw()

	func _draw() -> void:
		var r := minf(size.x, size.y) / 2.0
		TacticsFace.draw_face(self, size / 2.0, r, look, ring)
