class_name FigureParts
extends RefCounted
## The body parts every class figure is built from, all posed by the
## brush's UnitPose: legs, cape, torso, pauldrons, the race heads and eyes,
## the class headgear (registered by class id in UnitPainter), arms and the
## blend of a weapon's key poses. Figure space: feet at (0, 0), head centre
## near (0, -44). See Docs/systems/board.md and the visual reference
## Docs/concept-page/unit-figures.html.
## A grip (one key pose of a weapon) is a Vector4: the hand (x, y), the
## weapon's angle (z, 0 up) and how far the weapon slides through the hand
## along its length (w). A value, so drawing a figure allocates no objects.

const SHOULDER_RIGHT := Vector2(10, -32)
const SHOULDER_LEFT := Vector2(-10, -32)
const ARM_BONE: float = 9.5
const LEG_BONE: float = 7.3
const HAND_RADIUS: float = 2.7
const HEAD_RADIUS: float = 9.0
## Where the weapon hand sinks while the figure collapses.
const LIMP_HAND := Vector2(17, -6)


## Upper-body frame shared by every humanoid: x = how far the hips drop,
## y = how far the torso tilts (radians).
static func body_frame(brush: FigureBrush) -> Vector2:
	var pose := brush.pose
	var drop := pose.limp * 10.0 + pose.crouch * 4.0 + absf(sin(pose.step)) * pose.stride * 1.2
	var tilt := pose.sway * 0.025 - pose.flinch * 0.22 + pose.limp * 0.5 + pose.strike * 0.06
	return Vector2(drop, tilt)


## Pushes the upper-body frame: pivots at the hips by the body tilt.
static func push_upper_body(brush: FigureBrush, frame: Vector2) -> void:
	brush.push(Vector2(0, -15 + frame.x), frame.y)
	brush.push(Vector2(0, 15))


static func pop_upper_body(brush: FigureBrush) -> void:
	brush.pop()
	brush.pop()


## Starts a humanoid: cape and legs, then pushes the upper-body frame.
## Draw what goes behind the torso, then draw_trunk(), then the arms, head
## and weapon, then end_humanoid(). Returns the head centre.
static func begin_humanoid(brush: FigureBrush) -> Vector2:
	var frame := body_frame(brush)
	push_upper_body(brush, frame)
	draw_cape(brush)
	pop_upper_body(brush)
	draw_legs(brush, frame.x)
	push_upper_body(brush, frame)
	return head_center_of(brush.pose)


## The torso and the pauldrons of a humanoid.
static func draw_trunk(brush: FigureBrush) -> void:
	draw_torso(brush)
	draw_pauldrons(brush)


## Ends a humanoid: the crown, then pops the upper-body frame.
static func end_humanoid(brush: FigureBrush, head_center: Vector2) -> void:
	draw_crown(brush, head_center.x)
	pop_upper_body(brush)


static func head_center_of(pose: UnitPose) -> Vector2:
	return Vector2(pose.flinch * -2.0, -44.0 - pose.flinch * 1.5 + pose.limp * 4.0)


static func draw_legs(brush: FigureBrush, drop: float) -> void:
	var pose := brush.pose
	var swing := sin(pose.step) * pose.stride
	for side: float in [-1.0, 1.0]:
		var lift := maxf(0.0, swing * side) * 5.0
		var hip := Vector2(side * 5.0, -15.0 + drop)
		var foot := Vector2(side * 6.0 + pose.limp * side * 3.0, -1.0 - lift)
		brush.limb(hip, foot, LEG_BONE, LEG_BONE, side, 5.0, UnitPainter.TROUSERS)
		brush.fill_ellipse(foot + Vector2(side * 1.2, -0.5), 4.2, 2.6, UnitPainter.BOOT)


## Cost 4 and up wear a cape in a dark shade of the cost colour.
static func draw_cape(brush: FigureBrush) -> void:
	if brush.unit.cost < 4:
		return
	var pose := brush.pose
	var swing := pose.sway * 3.0 + pose.stride * sin(pose.step * 2.0) * 2.0 - pose.strike * 3.0
	brush.poly(PackedVector2Array([
		Vector2(-10, -34), Vector2(10, -34), Vector2(17 + swing, -7), Vector2(6 + swing * 1.3, -4),
		Vector2(-5 + swing * 1.3, -7), Vector2(-17 + swing, -4),
	]), brush.trim.darkened(0.25))


static func draw_torso(brush: FigureBrush) -> void:
	brush.poly(PackedVector2Array([Vector2(-11, -35), Vector2(11, -35), Vector2(9, -15), Vector2(-9, -15)]), brush.tunic)
	brush.stick(Vector2(-8, -17), Vector2(8, -17), 3.0, brush.trim)
	brush.dot(Vector2(0, -17), 1.8, Palette.GOLD)
	brush.stick_path(PackedVector2Array([Vector2(-4, -34), Vector2(0, -30), Vector2(4, -34)]), 2.0, brush.trim)
	if brush.has_fur:
		brush.stick(Vector2(-9, -35), Vector2(9, -35), 3.5, UnitPainter.FUR_LIGHT)


## Cost 3 wears steel shoulder guards, cost 4 and up gold ones.
static func draw_pauldrons(brush: FigureBrush) -> void:
	if brush.unit.cost < 3:
		return
	var color := Palette.GOLD if brush.unit.cost >= 4 else Palette.STEEL
	for side: float in [-1.0, 1.0]:
		brush.fill_ellipse(Vector2(side * 11, -34), 4.6, 3.6, color)


## The race head at `center` (drawer from UnitPainter.RACE_LOOKS), wearing
## the class headgear.
static func draw_head(brush: FigureBrush, center: Vector2) -> void:
	brush.crown_y = center.y - 16.0
	Callable(FigureParts, brush.look["head"]).call(brush, center)


static func draw_human_head(brush: FigureBrush, center: Vector2) -> void:
	var pose := brush.pose
	var look := _look_offset(brush)
	brush.circle(center, HEAD_RADIUS, brush.skin)
	var hair := PackedVector2Array()
	for index: int in 9:
		var angle := PI + PI * index / 8.0
		hair.append(center + Vector2(cos(angle), sin(angle)) * 9.5)
	hair.append_array([center + Vector2(6, -3.5), center + Vector2(1, -5), center + Vector2(-6, -3.5)])
	brush.poly(hair, UnitPainter.HAIR)
	_draw_headgear(brush, center)
	draw_eyes(brush, center + Vector2(0, 1), look)
	if pose.eyes == UnitPose.Eyes.HAPPY:
		brush.arc(center + Vector2(look.x, 3.5), 2.2, 0.15, PI - 0.15, Palette.INK, 1.2)
	elif pose.eyes == UnitPose.Eyes.HURT:
		brush.dot(center + Vector2(look.x, 5), 1.4, Palette.INK)


static func draw_wolf_head(brush: FigureBrush, center: Vector2) -> void:
	var pose := brush.pose
	var look := _look_offset(brush)
	var twitch := pose.flinch * 2.0 - pose.sway * 0.6
	for side: float in [-1.0, 1.0]:
		brush.poly(PackedVector2Array([
			center + Vector2(side * 9, -3),
			center + Vector2(side * (7 + twitch * side * 0.3), -16 + pose.flinch * 3),
			center + Vector2(side * 1.5, -7),
		]), brush.skin)
		brush.line(PackedVector2Array([center + Vector2(side * 7, -6), center + Vector2(side * 6.6, -12)]), UnitPainter.EAR_PINK, 1.6)
	brush.circle(center, HEAD_RADIUS, brush.skin)
	_draw_headgear(brush, center)
	var snout := center + Vector2(look.x * 0.6, 4 + look.y * 0.5)
	brush.fill_ellipse(snout, 5.5, 4.0, UnitPainter.FUR_LIGHT)
	brush.dot(snout + Vector2(0, -1.5), 1.8, Palette.INK)
	if pose.eyes == UnitPose.Eyes.HURT or pose.eyes == UnitPose.Eyes.HAPPY:
		brush.line(PackedVector2Array([snout + Vector2(-2.5, 1.6), snout + Vector2(0, 2.8), snout + Vector2(2.5, 1.6)]), Palette.INK, 1.1)
	draw_eyes(brush, center + Vector2(0, -2), Vector2(look.x, look.y * 0.6))


## Two eyes around `center`, shifted by `look`, in the pose's eye state.
static func draw_eyes(brush: FigureBrush, center: Vector2, look: Vector2) -> void:
	for side: float in [-1.0, 1.0]:
		var eye := center + Vector2(side * 3.6, 0) + look
		match brush.pose.eyes:
			UnitPose.Eyes.OPEN:
				brush.dot(eye, 1.5, Palette.INK)
			UnitPose.Eyes.BLINK:
				brush.line(PackedVector2Array([eye + Vector2(-1.6, 0), eye + Vector2(1.6, 0)]), Palette.INK, 1.3)
			UnitPose.Eyes.HURT:
				brush.line(PackedVector2Array([
					eye + Vector2(-side * 1.8, -1.6), eye + Vector2(side * 1.2, 0), eye + Vector2(-side * 1.8, 1.6),
				]), Palette.INK, 1.3)
			UnitPose.Eyes.HAPPY:
				brush.arc(eye + Vector2(0, 1), 1.9, PI, TAU, Palette.INK, 1.3)
			_:
				brush.line(PackedVector2Array([eye + Vector2(-1.5, -1.5), eye + Vector2(1.5, 1.5)]), Palette.INK, 1.2)
				brush.line(PackedVector2Array([eye + Vector2(-1.5, 1.5), eye + Vector2(1.5, -1.5)]), Palette.INK, 1.2)


## The gold crown of a cost 5 unit, once per figure.
static func draw_crown(brush: FigureBrush, x: float) -> void:
	if not brush.wears_crown:
		return
	brush.wears_crown = false
	var y := brush.crown_y
	brush.poly(PackedVector2Array([
		Vector2(x - 7, y), Vector2(x + 7, y), Vector2(x + 8, y - 7), Vector2(x + 3.5, y - 3),
		Vector2(x, y - 9), Vector2(x - 3.5, y - 3), Vector2(x - 8, y - 7),
	]), Palette.GOLD)


## An arm from the shoulder on `side` (+1 front, -1 back) to `hand`, with a
## hand at the end. Returns where the hand ends.
static func draw_arm(brush: FigureBrush, side: float, hand: Vector2, sleeve: Color) -> Vector2:
	var root := SHOULDER_RIGHT if side > 0.0 else SHOULDER_LEFT
	var tip := brush.limb(root, hand, ARM_BONE, ARM_BONE, 1.0 if side > 0.0 else -1.0, 4.0, sleeve)
	brush.circle(tip, HAND_RADIUS, brush.skin)
	return tip


## The free hand: hangs and swings with the walk, flies up when hit.
static func free_hand(brush: FigureBrush, side: float) -> Vector2:
	var pose := brush.pose
	return Vector2(
		side * (13.0 + pose.flinch * 5.0),
		-19.0 + sin(pose.step) * pose.stride * 3.0 * side - pose.flinch * 10.0 + pose.limp * 12.0 - pose.raise * 4.0)


## A grip from its hand, angle and slide.
static func grip_of(hand: Vector2, angle: float, slide: float = 0.0) -> Vector4:
	return Vector4(hand.x, hand.y, angle, slide)


## The hand of a grip.
static func hand_of(grip: Vector4) -> Vector2:
	return Vector2(grip.x, grip.y)


## The weapon grip blended from four key poses by strike and raise, plus the
## idle wobble, the flinch jerk and the death sink.
static func weapon_grip(brush: FigureBrush, ready: Vector4, wind: Vector4, strike: Vector4, raised: Vector4) -> Vector4:
	var pose := brush.pose
	var grip := ready.lerp(strike if pose.strike >= 0.0 else wind, absf(pose.strike)).lerp(raised, pose.raise)
	grip += Vector4(pose.flinch * 3.0, -pose.flinch * 4.0, pose.sway * 0.04 + pose.flinch * 0.5, 0.0)
	return grip.lerp(Vector4(LIMP_HAND.x, LIMP_HAND.y, 1.9, grip.w), pose.limp)


## The white smear of a swing, right after a strike.
static func draw_slash_trail(brush: FigureBrush, grip: Vector4, radius: float, sweep: float) -> void:
	var amount := brush.pose.trail
	if amount <= 0.0:
		return
	var end := grip.z - PI / 2.0
	brush.arc(hand_of(grip), radius, end - sweep, end, Color(Color.WHITE, amount * 0.75), 7.0)


## A straight white streak along a thrust, in the weapon's frame.
static func draw_thrust_trail(brush: FigureBrush, from_y: float, to_y: float) -> void:
	var amount := brush.pose.trail
	if amount > 0.0:
		brush.line(PackedVector2Array([Vector2(0, from_y), Vector2(0, to_y)]), Color(Color.WHITE, amount * 0.7), 6.0)


## A steel helmet with a brow band and a nose guard (shield).
static func draw_helmet(brush: FigureBrush, center: Vector2) -> void:
	brush.poly(_dome(center, 10.2, 10.5), Palette.STEEL)
	brush.stick(center + Vector2(-9.5, -3), center + Vector2(9.5, -3), 2.5, brush.trim)
	if not brush.has_fur:
		brush.stick(center + Vector2(0, -3), center + Vector2(0, 2), 2.0, Palette.STEEL)
	brush.dot(center + Vector2(0, -12), 1.8, Palette.GOLD)
	brush.crown_y = center.y - 14.0


## A red headband with two tails that fly with the swing (sword).
static func draw_headband(brush: FigureBrush, center: Vector2) -> void:
	var pose := brush.pose
	var swing := pose.sway * 2.5 - pose.strike * 4.0 + pose.stride * sin(pose.step * 2.0) * 2.0
	brush.stick_path(PackedVector2Array([
		center + Vector2(-8.5, -5), center + Vector2(-13 + swing, -1), center + Vector2(-15 + swing * 1.6, 5),
	]), 2.0, Palette.VERMILION)
	brush.stick(center + Vector2(-8.5, -5), center + Vector2(-11 + swing, 2), 2.0, Palette.VERMILION)
	brush.stick(center + Vector2(-8.8, -5), center + Vector2(8.8, -5), 2.6, Palette.VERMILION)
	if not brush.has_fur:
		brush.circle(center + Vector2(0, -10.5), 3.6, UnitPainter.HAIR)


## A wide conical war hat (spear).
static func draw_war_hat(brush: FigureBrush, center: Vector2) -> void:
	brush.poly(PackedVector2Array([
		center + Vector2(-15, -5), center + Vector2(15, -5), center + Vector2(2, -17), center + Vector2(-2, -17),
	]), UnitPainter.STRAW)
	brush.line(PackedVector2Array([center + Vector2(-9, -8), center + Vector2(9, -8)]), UnitPainter.STRAW.darkened(0.3), 1.2)
	brush.dot(center + Vector2(0, -17), 2.0, brush.trim)
	brush.crown_y = center.y - 18.0


## A helmet with a plume in the cost colour that streams back (cavalry).
static func draw_plumed_helmet(brush: FigureBrush, center: Vector2) -> void:
	var pose := brush.pose
	var swing := pose.sway * 2.0 - pose.stride * 5.0 - pose.strike * 3.0
	brush.poly(PackedVector2Array([
		center + Vector2(-1, -11), center + Vector2(2, -12), center + Vector2(-6 + swing, -21),
		center + Vector2(-13 + swing * 1.4, -15), center + Vector2(-9 + swing, -14),
	]), brush.trim)
	brush.poly(_dome(center, 9.8, 9.5), Palette.STEEL)
	brush.stick(center + Vector2(-9, -3), center + Vector2(9, -3), 2.2, Palette.OCHRE)
	brush.crown_y = center.y - 20.0


## A green band with a feather (archer).
static func draw_feather_band(brush: FigureBrush, center: Vector2) -> void:
	var swing := brush.pose.sway * 1.5
	brush.poly(PackedVector2Array([
		center + Vector2(5, -7), center + Vector2(8 + swing, -20), center + Vector2(12 + swing, -18), center + Vector2(9, -6),
	]), Palette.CREAM)
	brush.line(PackedVector2Array([center + Vector2(7, -7), center + Vector2(10 + swing, -18)]), Palette.VERMILION, 1.2)
	brush.stick(center + Vector2(-8.8, -5), center + Vector2(8.8, -5), 2.6, Palette.JADE)
	if not brush.has_fur:
		brush.circle(center + Vector2(0, -10.5), 3.4, UnitPainter.HAIR)


## A pointed hat whose tip bends with the sway (mage).
static func draw_pointed_hat(brush: FigureBrush, center: Vector2) -> void:
	var swing := brush.pose.sway * 2.5 - brush.pose.strike * 3.0
	brush.poly(PackedVector2Array([
		center + Vector2(-15, -6), center + Vector2(15, -6), center + Vector2(6, -12), center + Vector2(5 + swing, -26),
		center + Vector2(-2 + swing * 0.5, -19), center + Vector2(-6, -12),
	]), Palette.INDIGO)
	brush.stick(center + Vector2(-12, -7), center + Vector2(12, -7), 3.0, brush.trim)
	brush.dot(center + Vector2(5 + swing, -25), 1.6, Palette.GOLD)
	brush.crown_y = center.y - 27.0


static func _draw_headgear(brush: FigureBrush, center: Vector2) -> void:
	if brush.headgear.is_valid():
		brush.headgear.call(brush, center)


# Where the eyes and snout look: toward the aim, a little toward the facing.
static func _look_offset(brush: FigureBrush) -> Vector2:
	var direction := FigureBrush.dir_of(brush.pose.aim)
	return Vector2(direction.x * 1.2, direction.y * 1.4 + brush.facing * 0.6)


static func _dome(center: Vector2, radius_x: float, radius_y: float) -> PackedVector2Array:
	var dome := PackedVector2Array()
	for index: int in 9:
		var angle := PI + PI * index / 8.0
		dome.append(center + Vector2(cos(angle) * radius_x, -2.0 + sin(angle) * radius_y))
	return dome

