class_name ClassFigures
extends RefCounted
## The six class figures (and the plain one for an unknown class), each a
## drawer registered by class id in UnitPainter. A drawer builds the body
## from FigureParts and places its weapon from key poses (ready, wind,
## strike, raise) that FigureParts.weapon_grip blends by the pose. Port of
## the prototype in Docs/concept-page/unit-figures.html.

const RIGHT: float = 1.0
const LEFT: float = -1.0
# Key poses that do not depend on the aim (see FigureParts: hand, angle, slide).
const SWORD_READY := Vector4(16, -26, 0.3, 0)
const SWORD_RAISED := Vector4(14, -47, 0.05, 0)
const SHIELD_READY := Vector4(16, -24, 0.6, 0)
const SHIELD_RAISED := Vector4(15, -46, 0.1, 0)
const SPEAR_READY := Vector4(16, -27, 0.0, 0)
const SPEAR_RAISED := Vector4(15, -44, 0.0, -6)
const MAGE_READY := Vector4(16, -30, 0.0, 0)
const MAGE_WIND := Vector4(13, -34, -0.45, 0)
const MAGE_RAISED := Vector4(14, -42, 0.0, -8)
const LANCE_READY := Vector4(11, -6, 0.55, 0)
const LANCE_WIND_HAND := Vector2(6, -8)
const LANCE_RAISED := Vector4(11, -24, 0.15, -4)


## No weapon: both hands hang free.
static func draw_plain(brush: FigureBrush) -> void:
	var head_center := FigureParts.begin_humanoid(brush)
	FigureParts.draw_trunk(brush)
	FigureParts.draw_arm(brush, LEFT, FigureParts.free_hand(brush, LEFT), brush.tunic)
	FigureParts.draw_head(brush, head_center)
	FigureParts.draw_arm(brush, RIGHT, FigureParts.free_hand(brush, RIGHT), brush.tunic)
	FigureParts.end_humanoid(brush, head_center)


## A sword swung in an arc, a scabbard on the back.
static func draw_sword(brush: FigureBrush) -> void:
	var pose := brush.pose
	var direction := FigureBrush.dir_of(pose.aim)
	var head_center := FigureParts.begin_humanoid(brush)
	brush.stick(Vector2(-7, -18), Vector2(-17, -5), 3.5, UnitPainter.LEATHER)
	FigureParts.draw_trunk(brush)
	FigureParts.draw_arm(brush, LEFT, FigureParts.free_hand(brush, LEFT), brush.tunic)
	FigureParts.draw_head(brush, head_center)
	var wind := FigureParts.grip_of(FigureParts.SHOULDER_RIGHT + Vector2(2 - direction.x * 3, -9), pose.aim - 1.9)
	var strike := FigureParts.grip_of(FigureParts.SHOULDER_RIGHT + direction * 11.0, pose.aim + 0.75)
	var grip := FigureParts.weapon_grip(brush, SWORD_READY, wind, strike, SWORD_RAISED)
	var hand := FigureParts.hand_of(grip)
	FigureParts.draw_slash_trail(brush, grip, 22.0, 1.9)
	FigureParts.draw_arm(brush, RIGHT, hand, brush.tunic)
	brush.push(hand, grip.z)
	brush.glow(Vector2(0, -18), 16.0, Palette.class_color(brush.unit.class_id), pose.glow)
	brush.poly(PackedVector2Array([Vector2(-2.4, -3), Vector2(2.4, -3), Vector2(2.4, -24), Vector2(0, -31), Vector2(-2.4, -24)]), Palette.STEEL)
	brush.line(PackedVector2Array([Vector2(0, -5), Vector2(0, -24)]), UnitPainter.STEEL_DARK, 1.0)
	brush.stick(Vector2(-5.5, -3), Vector2(5.5, -3), 2.5, Palette.OCHRE)
	brush.stick(Vector2(0, -2), Vector2(0, 4), 2.5, UnitPainter.LEATHER)
	brush.pop()
	brush.circle(hand, FigureParts.HAND_RADIUS, brush.skin)
	FigureParts.end_humanoid(brush, head_center)


## A short blade and a kite shield on the off arm: raised to guard, shoved
## toward the target to bash.
static func draw_shield(brush: FigureBrush) -> void:
	var pose := brush.pose
	var direction := FigureBrush.dir_of(pose.aim)
	var head_center := FigureParts.begin_humanoid(brush)
	FigureParts.draw_trunk(brush)
	var wind := FigureParts.grip_of(Vector2(15, -37), pose.aim - 1.7)
	var strike := FigureParts.grip_of(FigureParts.SHOULDER_RIGHT + direction * 10.0, pose.aim + 0.6)
	var grip := FigureParts.weapon_grip(brush, SHIELD_READY, wind, strike, SHIELD_RAISED)
	var hand := FigureParts.hand_of(grip)
	FigureParts.draw_slash_trail(brush, grip, 15.0, 1.6)
	FigureParts.draw_arm(brush, RIGHT, hand, brush.tunic)
	brush.push(hand, grip.z)
	brush.poly(PackedVector2Array([Vector2(-2.6, -2), Vector2(2.6, -2), Vector2(3, -15), Vector2(0, -19), Vector2(-3, -15)]), Palette.STEEL)
	brush.stick(Vector2(-4.5, -2), Vector2(4.5, -2), 2.5, Palette.OCHRE)
	brush.pop()
	brush.circle(hand, FigureParts.HAND_RADIUS, brush.skin)
	FigureParts.draw_head(brush, head_center)
	var bash := maxf(0.0, pose.strike)
	var center := Vector2(-13, -22)
	center += Vector2(pose.guard * 9.0 + bash * (6.0 + direction.x * 5.0), -pose.guard * 7.0 + bash * direction.y * 5.0 - pose.raise * 8.0)
	center += Vector2(pose.flinch * 2.0, pose.limp * 12.0)
	var size := 1.0 + pose.guard * 0.12 + bash * 0.08
	brush.limb(FigureParts.SHOULDER_LEFT, center + Vector2(2, -3), FigureParts.ARM_BONE, FigureParts.ARM_BONE, -1.0, 4.0, brush.tunic)
	brush.push(center, -0.06 + pose.guard * 0.1 + pose.limp * 0.9, Vector2(size, size))
	brush.glow(Vector2.ZERO, 26.0, Palette.class_color(brush.unit.class_id), maxf(pose.glow, pose.guard * 0.8))
	brush.poly(PackedVector2Array([Vector2(-14, -19), Vector2(14, -19), Vector2(15, -3), Vector2(0, 21), Vector2(-15, -3)]), Palette.VERMILION)
	brush.outline(PackedVector2Array([Vector2(-10, -15), Vector2(10, -15), Vector2(10.5, -3), Vector2(0, 14), Vector2(-10.5, -3)]), brush.trim, 2.0)
	brush.circle(Vector2(0, -5), 4.6, Palette.OCHRE)
	brush.dot(Vector2(0, -5), 1.6, Palette.INK)
	brush.pop()
	FigureParts.end_humanoid(brush, head_center)


## A long spear held upright, levelled and thrust at the target.
static func draw_spear(brush: FigureBrush) -> void:
	var pose := brush.pose
	var direction := FigureBrush.dir_of(pose.aim)
	var head_center := FigureParts.begin_humanoid(brush)
	FigureParts.draw_trunk(brush)
	FigureParts.draw_arm(brush, LEFT, FigureParts.free_hand(brush, LEFT), brush.tunic)
	FigureParts.draw_head(brush, head_center)
	var wind := FigureParts.grip_of(FigureParts.SHOULDER_RIGHT + Vector2(-direction.x * 4 + 3, -direction.y * 4 + 4), pose.aim, -9.0)
	var strike := FigureParts.grip_of(FigureParts.SHOULDER_RIGHT + direction * 14.0, pose.aim, 12.0)
	var grip := FigureParts.weapon_grip(brush, SPEAR_READY, wind, strike, SPEAR_RAISED)
	var hand := FigureParts.hand_of(grip)
	brush.push(hand, grip.z)
	var offset := -grip.w
	FigureParts.draw_thrust_trail(brush, offset - 20.0, offset - 62.0)
	brush.stick(Vector2(0, offset + 28), Vector2(0, offset - 36), 3.0, Palette.WOOD)
	brush.glow(Vector2(0, offset - 44), 14.0, Palette.class_color(brush.unit.class_id), pose.glow)
	brush.poly(PackedVector2Array([Vector2(0, offset - 52), Vector2(5, offset - 38), Vector2(0, offset - 34), Vector2(-5, offset - 38)]), Palette.STEEL)
	var swing := pose.sway * 2.0 - pose.strike * 3.0
	brush.stick_path(PackedVector2Array([Vector2(0, offset - 33), Vector2(-2 + swing, offset - 27), Vector2(-1 + swing * 1.5, offset - 22)]), 2.4, Palette.VERMILION)
	brush.pop()
	FigureParts.draw_arm(brush, RIGHT, hand, brush.tunic)
	FigureParts.end_humanoid(brush, head_center)


## A bow: lowered at rest, held out along the aim while drawn or loosed;
## the string hand pulls back with the draw. A quiver on the back.
static func draw_archer(brush: FigureBrush) -> void:
	var pose := brush.pose
	var direction := FigureBrush.dir_of(pose.aim)
	var drawn := clampf(-pose.strike, 0.0, 1.0)
	var loose := clampf(pose.strike, 0.0, 1.0)
	var engaged := maxf(maxf(drawn, loose), pose.raise)
	var bow_hand := Vector2(17, -22).lerp(FigureParts.SHOULDER_RIGHT + direction * 18.5, engaged)
	var bow_angle := lerpf(1.75, pose.aim, engaged)
	bow_hand = bow_hand.lerp(Vector2(12, -8), pose.limp)
	bow_angle = lerpf(bow_angle, 2.4, pose.limp) + pose.flinch * 0.4 + pose.sway * 0.03
	var bow_direction := FigureBrush.dir_of(bow_angle)
	var pull := drawn * 12.0
	var string_hand := bow_hand + bow_direction * -(7.0 + pull)
	var head_center := FigureParts.begin_humanoid(brush)
	brush.stick(Vector2(-13, -42), Vector2(-15.5, -49), 1.6, Palette.CREAM)
	brush.stick(Vector2(-16, -41), Vector2(-19.5, -47), 1.6, Palette.VERMILION)
	brush.poly(PackedVector2Array([Vector2(-18, -41), Vector2(-11, -44), Vector2(-5, -24), Vector2(-11, -21)]), UnitPainter.LEATHER)
	FigureParts.draw_trunk(brush)
	FigureParts.draw_head(brush, head_center)
	var off_hand := FigureParts.free_hand(brush, LEFT).lerp(string_hand, drawn)
	if loose > 0.0:
		off_hand = string_hand.lerp(string_hand - bow_direction * 6.0, loose)
	FigureParts.draw_arm(brush, LEFT, off_hand, brush.tunic)
	brush.push(bow_hand, bow_angle)
	brush.glow(Vector2(0, -4), 18.0, Palette.class_color(brush.unit.class_id), pose.glow)
	# In bow space the arrow flies along -y; the limbs spread along x.
	var tip := Vector2(18.0 - drawn * 3.0, 7.0 + drawn * 4.0)
	var string_y := 7.0 + pull - loose * 3.0
	brush.line(PackedVector2Array([Vector2(-tip.x, tip.y), Vector2(0, string_y), tip]), Palette.CREAM, 1.3)
	var limbs := _quadratic(Vector2(-tip.x, tip.y), Vector2(0, -15.0 - drawn * 2.0), tip)
	brush.line(limbs, Palette.INK, 6.5)
	brush.line(limbs, brush.tint(Palette.WOOD), 3.2)
	brush.stick(Vector2(0, -5.5), Vector2(0, -1.5), 4.0, UnitPainter.LEATHER)
	if pose.arrow > 0.0 and (drawn > 0.02 or pose.raise > 0.3):
		brush.stick(Vector2(0, string_y), Vector2(0, string_y - 27), 1.5, Palette.CREAM)
		brush.poly(PackedVector2Array([Vector2(0, string_y - 33), Vector2(3, string_y - 26), Vector2(-3, string_y - 26)]), Palette.STEEL)
	brush.pop()
	FigureParts.draw_arm(brush, RIGHT, bow_hand, brush.tunic)
	FigureParts.end_humanoid(brush, head_center)


## A robe instead of legs and a staff with a floating orb in the unit's
## element colour; the free hand lifts while casting.
static func draw_mage(brush: FigureBrush) -> void:
	var pose := brush.pose
	var direction := FigureBrush.dir_of(pose.aim)
	var orb_color: Color = UnitPainter.ELEMENT_COLORS.get(brush.unit.element_id, Palette.OCHRE)
	var strike := FigureParts.grip_of(FigureParts.SHOULDER_RIGHT + direction * 9.0, lerpf(0.2, pose.aim, 0.55))
	var frame := FigureParts.body_frame(brush)
	var hem := pose.sway * 1.5 + sin(pose.step) * pose.stride * 2.5
	var hem_lift := -frame.x * 0.6
	brush.push(Vector2(0, frame.x * 0.5))
	brush.fill_ellipse(Vector2(-5 - sin(pose.step) * pose.stride * 2.0, -1), 4.2, 2.6, UnitPainter.BOOT)
	brush.fill_ellipse(Vector2(5 + sin(pose.step) * pose.stride * 2.0, -1), 4.2, 2.6, UnitPainter.BOOT)
	brush.pop()
	FigureParts.push_upper_body(brush, frame)
	FigureParts.draw_cape(brush)
	brush.poly(PackedVector2Array([
		Vector2(-10, -35), Vector2(10, -35), Vector2(15 + hem, -3 + hem_lift), Vector2(5 + hem * 0.5, -1 + hem_lift),
		Vector2(-5 + hem * 0.5, -3 + hem_lift), Vector2(-15 + hem, -1 + hem_lift),
	]), brush.tunic)
	brush.stick(Vector2(0, -34), Vector2(hem * 0.4, -5 + hem_lift), 2.0, brush.trim)
	brush.stick(Vector2(-9, -17), Vector2(9, -17), 3.0, brush.trim)
	brush.stick_path(PackedVector2Array([Vector2(-4, -34), Vector2(0, -30), Vector2(4, -34)]), 2.0, brush.trim)
	FigureParts.draw_pauldrons(brush)
	var head_center := FigureParts.head_center_of(pose)
	var cast := maxf(pose.raise, maxf(0.0, pose.strike) * 0.6)
	FigureParts.draw_arm(brush, LEFT, FigureParts.free_hand(brush, LEFT).lerp(Vector2(-15, -38), cast), brush.tunic)
	FigureParts.draw_head(brush, head_center)
	var grip := FigureParts.weapon_grip(brush, MAGE_READY, MAGE_WIND, strike, MAGE_RAISED)
	var hand := FigureParts.hand_of(grip)
	brush.push(hand, grip.z)
	var offset := -grip.w
	brush.stick(Vector2(0, offset + 30), Vector2(0, offset - 24), 3.0, Palette.WOOD)
	brush.stick_path(PackedVector2Array([Vector2(-3.5, offset - 24), Vector2(0, offset - 21), Vector2(3.5, offset - 24)]), 2.2, Palette.OCHRE)
	# The orb bobs when idle and swells while casting.
	var grow := 1.0 + pose.raise * 0.5 + maxf(0.0, pose.strike) * 0.35 + pose.glow * 0.2
	var orb := Vector2(0, offset - 31 + pose.sway * 1.6 - pose.raise * 3.0)
	brush.glow(orb, 20.0 * grow, orb_color, 0.45 + maxf(maxf(pose.glow, pose.raise), absf(pose.strike)) * 0.55)
	brush.circle(orb, 5.2 * grow, orb_color)
	brush.dot(orb + Vector2(-1.6, -1.8) * grow, 1.4 * grow, Color.WHITE)
	brush.pop()
	FigureParts.draw_arm(brush, RIGHT, hand, brush.tunic)
	FigureParts.end_humanoid(brush, head_center)


## A rider on a galloping horse with a lance: couched at rest, levelled and
## driven forward to strike; the horse rears for a skill.
static func draw_cavalry(brush: FigureBrush) -> void:
	var pose := brush.pose
	var run := pose.stride
	var bounce := absf(sin(pose.gallop)) * run * 3.0
	# The hind hooves stay planted; the body pivots up around them when rearing.
	brush.push(Vector2(-14, -2), -pose.rear * 0.42 - pose.flinch * 0.06)
	brush.push(Vector2(14, 2 - bounce + pose.limp * 6.0), pose.limp * 0.12)
	_draw_horse(brush, bounce)
	_draw_rider(brush)
	brush.pop()
	brush.pop()


static func _draw_horse(brush: FigureBrush, bounce: float) -> void:
	var pose := brush.pose
	var run := pose.stride
	var horse := brush.mount
	var dark := horse.darkened(0.22)
	# Four two-bone legs driven by the gallop phase: [x, phase, knee side].
	for leg: Vector3 in [Vector3(-16, 0.0, 1), Vector3(-10, 0.9, 1), Vector3(10, PI, -1), Vector3(16, PI + 0.9, -1)]:
		var swing := sin(pose.gallop + leg.y)
		var foot := Vector2(leg.x + swing * 7.0 * run, -maxf(0.0, cos(pose.gallop + leg.y)) * 6.0 * run + bounce)
		if leg.x > 0.0:
			foot = foot.lerp(Vector2(leg.x + 9.0, -9.0 + swing * 2.0), pose.rear)
		foot.y = lerpf(foot.y, -3.0, pose.limp)
		var tip := brush.limb(Vector2(leg.x * 0.92, -13), foot, 7.5, 7.5, leg.z, 3.6, dark)
		brush.fill_ellipse(tip + Vector2(0.6, 0.2), 2.8, 2.2, UnitPainter.BOOT)
	var tail := pose.sway * 3.0 - run * 8.0
	brush.stick_path(PackedVector2Array([Vector2(-21, -19), Vector2(-28 + tail * 0.4, -14 - run * 3.0), Vector2(-30 + tail, -5 - run * 6.0)]), 4.0, UnitPainter.HAIR)
	brush.fill_ellipse(Vector2(0, -16), 23.0, 9.0, horse)
	# Neck and head nod with the gallop and toss up when rearing.
	brush.push(Vector2(15, -20), sin(pose.gallop * 2.0) * run * 0.12 - pose.rear * 0.25 + pose.sway * 0.02)
	brush.stick_path(PackedVector2Array([Vector2(1, -3), Vector2(6, -13), Vector2(9, -16)]), 3.2, UnitPainter.HAIR)
	brush.poly(PackedVector2Array([Vector2(-2, 3), Vector2(6, -14), Vector2(12, -15), Vector2(20, -9), Vector2(19.5, -4), Vector2(10, -4), Vector2(7, 8)]), horse)
	brush.poly(PackedVector2Array([Vector2(6.5, -13.5), Vector2(8, -20), Vector2(11, -14.5)]), horse)
	brush.dot(Vector2(12, -10.5), 1.4, Palette.INK)
	brush.dot(Vector2(18.6, -6.5), 0.9, Palette.INK)
	brush.line(PackedVector2Array([Vector2(15.5, -12.5), Vector2(14.5, -4.5)]), UnitPainter.LEATHER, 1.3)
	brush.pop()
	brush.poly(PackedVector2Array([Vector2(-9, -24), Vector2(9, -24), Vector2(8, -13), Vector2(-8, -13)]), brush.trim)
	brush.line(PackedVector2Array([Vector2(-6, -15.5), Vector2(6, -15.5)]), Palette.GOLD, 1.3)


static func _draw_rider(brush: FigureBrush) -> void:
	var pose := brush.pose
	var run := pose.stride
	var cost := brush.unit.cost
	brush.push(Vector2(0, -23), run * 0.14 - pose.flinch * 0.25 + pose.limp * 0.5 + pose.rear * 0.1)
	brush.stick_path(PackedVector2Array([Vector2(3, 1), Vector2(5, 9), Vector2(8, 12)]), 4.0, UnitPainter.TROUSERS)
	brush.fill_ellipse(Vector2(9, 12.5), 3.4, 2.2, UnitPainter.BOOT)
	if cost >= 4:
		var swing := pose.sway * 2.0 - run * 7.0
		brush.poly(PackedVector2Array([Vector2(-8, -16), Vector2(6, -16), Vector2(-6 + swing, 2), Vector2(-15 + swing, -1)]), brush.trim.darkened(0.25))
	brush.poly(PackedVector2Array([Vector2(-9, -17), Vector2(9, -17), Vector2(7.5, 0), Vector2(-7.5, 0)]), brush.tunic)
	brush.stick(Vector2(-6.5, -2), Vector2(6.5, -2), 2.6, brush.trim)
	if brush.has_fur:
		brush.stick(Vector2(-7, -17), Vector2(7, -17), 3.0, UnitPainter.FUR_LIGHT)
	if cost >= 3:
		for side: float in [-1.0, 1.0]:
			brush.fill_ellipse(Vector2(side * 9, -16), 4.0, 3.2, Palette.GOLD if cost >= 4 else Palette.STEEL)
	var head_center := Vector2(pose.flinch * -2.0, -25.0 + pose.limp * 3.0)
	brush.limb(Vector2(-8, -14), Vector2(-2 - pose.flinch * 4.0, -4 - pose.flinch * 6.0), 7.0, 7.0, -1.0, 3.6, brush.tunic)
	FigureParts.draw_head(brush, head_center)
	_draw_lance(brush)
	FigureParts.draw_crown(brush, head_center.x)
	brush.pop()


static func _draw_lance(brush: FigureBrush) -> void:
	var pose := brush.pose
	var run := pose.stride
	var aim := clampf(pose.aim, 0.9, 2.3)
	var direction := FigureBrush.dir_of(aim)
	var shoulder := Vector2(8, -14)
	var target := FigureParts.grip_of(shoulder + direction * 11.0, aim, 12.0) if pose.strike >= 0.0 else FigureParts.grip_of(LANCE_WIND_HAND, aim, -8.0)
	var amount := absf(pose.strike)
	var grip := LANCE_READY.lerp(target, amount).lerp(LANCE_RAISED, pose.raise)
	var hand := FigureParts.hand_of(grip)
	# Running lowers the lance toward level unless it is already in use.
	var angle := lerpf(grip.z, 1.2, run * (1.0 - amount) * (1.0 - pose.raise) * 0.6)
	var slide := grip.w
	angle += pose.flinch * 0.5
	hand = hand.lerp(Vector2(14, 6), pose.limp)
	angle = lerpf(angle, 1.8, pose.limp)
	brush.push(hand, angle)
	var offset := -slide
	FigureParts.draw_thrust_trail(brush, offset - 14.0, offset - 50.0)
	brush.stick(Vector2(0, offset + 14), Vector2(0, offset - 30), 3.0, Palette.WOOD)
	brush.glow(Vector2(0, offset - 36), 14.0, Palette.class_color(brush.unit.class_id), pose.glow)
	brush.poly(PackedVector2Array([Vector2(0, offset - 43), Vector2(4.5, offset - 30), Vector2(-4.5, offset - 30)]), Palette.STEEL)
	var pennant := pose.sway * 2.0 - run * 5.0 - pose.strike * 4.0
	brush.poly(PackedVector2Array([Vector2(0, offset - 29), Vector2(0, offset - 22), Vector2(-9 + pennant, offset - 23), Vector2(-7 + pennant, offset - 28)]), brush.trim)
	brush.pop()
	brush.limb(shoulder, hand, 7.0, 7.0, 1.0, 3.6, brush.tunic)
	brush.circle(hand, 2.5, brush.skin)


# Points along a quadratic curve from `from` to `to` bending toward `control`.
static func _quadratic(from: Vector2, control: Vector2, to: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index: int in 9:
		var t := index / 8.0
		points.append(from.lerp(control, t).lerp(control.lerp(to, t), t))
	return points
