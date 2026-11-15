extends SceneTree

# Headless test of the rigged unit figures' drawing and rig (the animator
# has its own test, pose_animator_test.gd). The mesh cache: playing every
# clip of every class from both sides, in both races, several times over,
# keeps the cache under MESH_BUDGET and stops growing, and random poses
# never grow it past RigPainter.MAX_MESHES. The hit flash marks skip the
# trail and the glow, and the flash material is set up early. Drawing: every class (with the
# boss, the sage and an unknown one) x race (and an unknown one) draws
# posed, unposed and as a bust without a script error. The rig: every
# class, view and clip solves to finite bones at sampled times, and every
# standing pose keeps its lowest foot on the ground line.

const Kit := preload("res://Tests/pose_test_kit.gd")
const DRAWN_CLASS_IDS: Array[StringName] = [
	&"class.sword", &"class.shield", &"class.spear", &"class.archer", &"class.mage", &"class.cavalry",
	&"class.unknown_test", &"class.colossus", &"class.sage",
]
const CLIPS: Array[StringName] = [&"attackUp", &"attackDown", &"skillUp", &"skillDown", &"hit", &"die", &"fall", &"cheer"]
const SAMPLES: int = 5
const GROUND_TOLERANCE: float = 0.35
# Meshes the board's figures need in both races (about 1060 measured, see
# Docs/systems/board.md): the clips' poses cached at 30 redraws a second.
const MESH_BUDGET: int = 1300
const PLAYS: int = 3
# Painted poses that may still add meshes on the last play (a new idle
# clock, a rare blend), as a share of the cache.
const LATE_GROWTH: float = 0.05
const RANDOM_POSES: int = 3000


func _initialize() -> void:
	var ok := await _run()
	if ok:
		print("Unit pose test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	# The cache checks run first, before other checks fill the cache.
	var checks: Array[Callable] = [_check_mesh_cache, _check_mesh_cap, _check_flash_marks, _check_drawing, _check_clips_solve, _check_feet_on_ground]
	for check: Callable in checks:
		if not await check.call():
			push_error("Unit pose test failed in %s" % check.get_method())
			return false
	return true


# Plays each clip as the animator would at 30 redraws a second (from a
# random start, with a random idle clock) for every rigged class, view and
# real race, PLAYS times: the cache stays under the budget and the last
# play adds next to nothing.
func _check_mesh_cache() -> bool:
	seed(7)
	var counts: Array[int] = []
	for play: int in PLAYS:
		for class_id: StringName in Kit.RIG_CLASS_IDS:
			for race_id: StringName in [&"race.human", &"race.wolf"]:
				for view: StringName in Kit.VIEWS:
					_play_every_clip(RigKit.get_kit(class_id), view, _look(race_id))
		counts.append(RigPainter.get_cached_mesh_count())
	var last := counts[PLAYS - 1]
	print("Mesh cache after each play of every clip: %s" % [counts])
	if last > MESH_BUDGET:
		push_error("The mesh cache holds %d meshes after %d plays, over the budget of %d" % [last, PLAYS, MESH_BUDGET])
		return false
	if last - counts[PLAYS - 2] > counts[PLAYS - 2] * LATE_GROWTH:
		push_error("The mesh cache still grows on the last play: %s" % [counts])
		return false
	return true


# Random blends of every key with every other, far more varied than play,
# never grow the cache past its cap.
func _check_mesh_cap() -> bool:
	seed(11)
	var kits: Array[RigKit] = []
	for class_id: StringName in Kit.RIG_CLASS_IDS:
		kits.append(RigKit.get_kit(class_id))
	for index: int in RANDOM_POSES:
		var kit: RigKit = kits[randi() % kits.size()]
		var view: StringName = Kit.VIEWS[randi() % 2]
		var clip := kit.get_clip(CLIPS[randi() % CLIPS.size()], view)
		var other := kit.get_clip(CLIPS[randi() % CLIPS.size()], view)
		var pose := UnitPose.blend(clip[randi() % clip.size()].pose, other[randi() % other.size()].pose, randf())
		var look := _look(&"race.wolf" if randf() < 0.5 else &"race.human")
		look.clock = randf() * 100.0
		look.pixels_per_unit = randf_range(0.5, 5.0)
		_paint(kit, pose, view, look)
	var count := RigPainter.get_cached_mesh_count()
	if count > RigPainter.MAX_MESHES:
		push_error("The mesh cache holds %d meshes, over its cap of %d" % [count, RigPainter.MAX_MESHES])
		return false
	return true


# The hit flash leaves the weapon trail and the glow alone: paint() counts
# them (they come first) so UnitPainter marks only the pieces. A rigged
# figure gets its flash material as soon as it has a unit; the boss none.
func _check_flash_marks() -> bool:
	var kit := RigKit.get_kit(&"class.sword")
	var look := _look(&"race.human")
	var base := Transform2D(0.0, Vector2.ONE, 0.0, Vector2.ZERO)
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var plain := RigPainter.paint(points, colors, kit, kit.stance[RigSolver.VIEW_BACK], RigSolver.VIEW_BACK, look, base)
	points.clear()
	colors.clear()
	var glowing := RigPainter.paint(points, colors, kit, kit.stance[RigSolver.VIEW_BACK].merged({"glow": 1}), RigSolver.VIEW_BACK, look, base)
	var ok := true
	if plain != 0 or glowing <= 0 or glowing >= points.size():
		push_error("paint() should count the glow's points before the pieces: %d without a glow, %d of %d with one" % [plain, glowing, points.size()])
		ok = false
	var figure := UnitFigure.new()
	figure.unit = Kit.make_unit(&"class.archer")
	var material := figure.material as ShaderMaterial
	if material == null or material.shader != UnitFigure.FLASH_SHADER:
		push_error("A rigged figure should get its flash material with its unit")
		ok = false
	figure.unit = Kit.make_unit(&"class.colossus")
	if figure.material != null:
		push_error("A figure outside the rig should have no flash material")
		ok = false
	figure.free()
	return ok


func _check_drawing() -> bool:
	var poses: Array[UnitPose] = [
		RigClips.get_stance(), RigClips.walk_pose(0.3), RigClips.get_clip(&"die")[3].pose,
		RigClips.get_clip(&"skillUp")[1].pose.with_fields({"trail": 1, "flash": 0.6, "eyes": 2, "dx": 4}),
	]
	var expected := DRAWN_CLASS_IDS.size() * Kit.RACE_IDS.size() * (poses.size() + 2)
	var drawn: Array[int] = [0]
	var canvas := Node2D.new()
	canvas.draw.connect(func() -> void:
		for class_id: StringName in DRAWN_CLASS_IDS:
			for race_id: StringName in Kit.RACE_IDS:
				var unit := Kit.make_unit(class_id, race_id)
				for pose: UnitPose in poses:
					UnitPainter.draw_figure(canvas, unit, UnitPainter.FACING_UP, 0.5, Vector2(40, 80), 1.2, pose)
					drawn[0] += 1
				UnitPainter.draw_figure(canvas, unit, UnitPainter.FACING_DOWN, 0.0)
				drawn[0] += 1
				UnitPainter.draw_bust(canvas, unit, Vector2(60, 60), 1.6)
				drawn[0] += 1)
	var errors := Kit.ErrorCounter.new()
	OS.add_logger(errors)
	root.add_child(canvas)
	await process_frame
	await process_frame
	OS.remove_logger(errors)
	canvas.queue_free()
	if drawn[0] != expected or errors.count > 0:
		push_error("Drew %d of %d figures with %d errors (or _draw never ran)" % [drawn[0], expected, errors.count])
		return false
	return true


# Every pose a figure can show (clip keys, the blends between them, rests
# and the run) solves to finite bones.
func _check_clips_solve() -> bool:
	for class_id: StringName in Kit.RIG_CLASS_IDS:
		var kit := RigKit.get_kit(class_id)
		for view: StringName in Kit.VIEWS:
			var poses: Array[UnitPose] = [kit.idle[view], kit.stance[view]]
			for clip: StringName in CLIPS:
				var from := kit.stance[view]
				for key: RigClips.ClipKey in kit.get_clip(clip, view):
					for sample: int in SAMPLES:
						poses.append(UnitPose.blend(from, key.pose, RigClips.eased(key.easing, (sample + 1.0) / SAMPLES)))
					from = key.pose
			for step: int in 20:
				poses.append(kit.get_walk_pose(step / 20.0, view))
			for pose: UnitPose in poses:
				if not _is_finite(RigSolver.solve(pose, view)):
					push_error("%s seen from %s solves to a NaN bone in %s" % [class_id, view, pose.values])
					return false
	return true


# A pose standing on its legs (leg IK on, no jump, not riding) puts each
# foot that its leg can reach where the sketch plants it: the ankle above
# the ground line at x = f, raised by the lift `l` and shifted by half the
# step `st` (a foot farther from the viewer shows higher on screen).
func _check_feet_on_ground() -> bool:
	var ok := true
	for class_id: StringName in Kit.RIG_CLASS_IDS:
		var kit := RigKit.get_kit(class_id)
		for view: StringName in Kit.VIEWS:
			var poses: Array[UnitPose] = [kit.idle[view], kit.stance[view]]
			for clip: StringName in [&"attackUp", &"attackDown", &"skillUp", &"skillDown", &"hit", &"cheer"]:
				for key: RigClips.ClipKey in kit.get_clip(clip, view):
					poses.append(key.pose)
			for pose: UnitPose in poses:
				var v := pose.values
				if v[UnitPose.IK] < 1.0 or v[UnitPose.JUMP] != 0.0 or v[UnitPose.RIDE] != 0.0:
					continue
				var frame := RigSolver.solve(pose, view)
				var toward := -1.0 if view == RigSolver.VIEW_BACK else 1.0
				for foot: Array in [[RigSolver.TH_F, RigSolver.FT_F, UnitPose.F_F, UnitPose.L_F, UnitPose.ST_F], [RigSolver.TH_B, RigSolver.FT_B, UnitPose.F_B, UnitPose.L_B, UnitPose.ST_B]]:
					var planted := Vector2(v[foot[2]], -RigSolver.ANKLE - v[foot[3]] + toward * v[foot[4]] * 0.5)
					if frame.bones[foot[0]].origin.distance_to(planted) > 2.0 * RigSolver.LEG:
						continue
					var ankle := frame.bones[foot[1]].origin
					if ankle.distance_to(planted) > GROUND_TOLERANCE:
						push_error("%s seen from %s puts a foot at %s, not %s" % [class_id, view, ankle, planted])
						ok = false
	return ok


# One play of every clip at 30 frames a second, as the animator blends it.
func _play_every_clip(kit: RigKit, view: StringName, look: RigPainter.Look) -> void:
	for clip: StringName in CLIPS:
		var from := kit.stance[view]
		var time := randf() / PoseRedraws.ACTION_PER_SEC
		for key: RigClips.ClipKey in kit.get_clip(clip, view):
			while time < key.seconds:
				look.clock = randf() * 100.0
				_paint(kit, UnitPose.blend(from, key.pose, RigClips.eased(key.easing, time / key.seconds)), view, look)
				time += 1.0 / PoseRedraws.ACTION_PER_SEC
			time -= key.seconds
			from = key.pose
	for step: int in 30:
		_paint(kit, kit.get_walk_pose(step / 30.0, view), view, look)


func _paint(kit: RigKit, pose: UnitPose, view: StringName, look: RigPainter.Look) -> void:
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var base := Transform2D(0.0, Vector2.ONE * UnitView.FIGURE_SCALE, 0.0, Vector2.ZERO)
	RigPainter.paint(points, colors, kit, pose.merged({"dx": 0}), view, look, base)


# A board figure's look in `race_id`.
func _look(race_id: StringName) -> RigPainter.Look:
	var look := RigPainter.Look.new()
	look.race_id = race_id
	look.palette = RigPalette.get_palette(race_id, UnitPainter.RACE_LOOKS[race_id])
	look.has_fur = UnitPainter.RACE_LOOKS[race_id]["has_fur"]
	look.pixels_per_unit = UnitView.FIGURE_SCALE
	return look


func _is_finite(frame: RigSolver.Frame) -> bool:
	for bone: Transform2D in frame.bones:
		for axis: Vector2 in [bone.x, bone.y, bone.origin]:
			if not axis.is_finite():
				return false
	return true
