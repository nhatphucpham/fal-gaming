class_name RigKit
extends RefCounted
## How one class looks and moves (the sketch's `defClass`): its pieces, its
## rest poses per view, its own clips (the rest come from RigClips, passed
## through `fit`), its run cycle, where its weapon's tip and glow are, and
## which skill keys are the wind-up. Kits are built once per class id by
## the builders registered in BUILDERS; an unknown class gets the plain
## kit (the Kiếm body without a weapon).
## [codeblock]
## var kit := RigKit.get_kit(&"class.spear")
## var keys := kit.get_clip(&"attackUp", RigSolver.VIEW_BACK)
## [/codeblock]

## Builders by class id: each a script with `static func build() -> RigKit`.
const BUILDERS: Dictionary[StringName, String] = {
	&"class.sword": "res://Scenes/Board/kit_sword.gd",
	&"class.shield": "res://Scenes/Board/kit_shield.gd",
	&"class.spear": "res://Scenes/Board/kit_spear.gd",
	&"class.archer": "res://Scenes/Board/kit_archer.gd",
	&"class.mage": "res://Scenes/Board/kit_mage.gd",
	&"class.cavalry": "res://Scenes/Board/kit_cavalry.gd",
}
const PLAIN_ID: StringName = &"class.plain"

var pieces: Array[RigPiece] = []
## func(pose: UnitPose) -> Dictionary: class constants laid over the
## generic clips' poses (a two-handed grip, a seat on the horse). Optional.
var fit: Callable
## Rest poses by view: out of a fight (idle) and in one (stance).
var idle: Dictionary[StringName, UnitPose] = {}
var stance: Dictionary[StringName, UnitPose] = {}
## The class's own clips: name -> Array[RigClips.ClipKey], or name ->
## {view: Array[RigClips.ClipKey]} when the views differ.
var clips: Dictionary = {}
## func(phase: float, view: StringName) -> UnitPose. Optional: the generic
## run cycle, fitted.
var walk: Callable
## Where the weapon tip and the trail's inner edge sit along the sword
## hand (x), and whether they follow the weapon length and slide.
var tip := Vector2(27, 11)
var is_tip_on_weapon: bool = false
## Where the glow sits: a bone, x along it, following the weapon or not.
var glow_bone: int = RigSolver.H_F
var glow_x: float = 13.0
var is_glow_on_weapon: bool = false
## How many keys of a skill clip are its wind-up (held until release).
var skill_wind_keys: int = 2
var is_mounted: bool = false
## Archers face the target with the bow (off) hand.
var aims_off_hand: bool = false

static var _kits: Dictionary[StringName, RigKit] = {}

var _clip_cache: Dictionary[String, Array] = {}
var _z_sets: Dictionary[StringName, Array] = {}


## The kit of `class_id`, built once.
static func get_kit(class_id: StringName) -> RigKit:
	var id := class_id if BUILDERS.has(class_id) else PLAIN_ID
	if not _kits.has(id):
		var kit: RigKit
		if id == PLAIN_ID:
			kit = RigKit.new()
			kit.pieces = remix(RigBody.base_pieces(), {}, [&"sword"], [])
		else:
			kit = load(BUILDERS[id]).build()
		kit.fill_rests()
		_kits[id] = kit
	return _kits[id]


## The sketch's `kit()`: `base` with members replaced per id (`changes`),
## the ids in `drop` left out and `extra` added at the end.
static func remix(base: Array[RigPiece], changes: Dictionary, drop: Array[StringName], extra: Array[RigPiece]) -> Array[RigPiece]:
	var result: Array[RigPiece] = []
	for piece: RigPiece in base:
		if drop.has(piece.id):
			continue
		result.append(piece.with_members(changes[piece.id]) if changes.has(piece.id) else piece)
	result.append_array(extra)
	return result


## Fills the rest poses a builder left out from the generic ones, fitted.
func fill_rests() -> void:
	for view: StringName in [RigSolver.VIEW_BACK, RigSolver.VIEW_FRONT]:
		if not idle.has(view):
			idle[view] = fitted(RigClips.get_idle())
		if not stance.has(view):
			stance[view] = fitted(RigClips.get_stance())


## The same rest pose for both views.
static func both_views(pose: UnitPose) -> Dictionary[StringName, UnitPose]:
	return {RigSolver.VIEW_BACK: pose, RigSolver.VIEW_FRONT: pose}


func fitted(pose: UnitPose) -> UnitPose:
	return pose.merged(fit.call(pose)) if fit.is_valid() else pose


## The keys of clip `name` (attackUp, attackDown, skillUp, skillDown, hit,
## die, fall or cheer) seen from `view`, the generic rest keys filled in by
## this class's rest poses. The array is shared: do not change it.
func get_clip(name: StringName, view: StringName) -> Array[RigClips.ClipKey]:
	var cache_key := "%s|%s" % [name, view]
	if _clip_cache.has(cache_key):
		return _clip_cache[cache_key]
	var keys: Array[RigClips.ClipKey] = []
	var own: Variant = clips.get(name)
	if own is Dictionary:
		own = own[view]
	if own != null:
		keys.assign(own)
	else:
		for key: RigClips.ClipKey in RigClips.get_clip(name):
			var pose := key.pose
			match key.rest:
				RigClips.Rest.STANCE:
					pose = stance[view]
				RigClips.Rest.IDLE:
					pose = idle[view]
				_:
					pose = fitted(pose)
			keys.append(RigClips.ClipKey.new(key.seconds, key.easing, pose, key.rest))
	_clip_cache[cache_key] = keys
	return keys


## The skill clip seen from `view`: Up from behind, Down from the front.
func get_skill_clip(view: StringName) -> Array[RigClips.ClipKey]:
	return get_clip(&"skillUp" if view == RigSolver.VIEW_BACK else &"skillDown", view)


## The skill's first `skill_wind_keys` keys (the wind-up) stretched to last
## `seconds` (the cast) in all.
func get_wind_up(view: StringName, seconds: float) -> Array[RigClips.ClipKey]:
	var keys := get_skill_clip(view)
	var wind_seconds := 0.0
	for index: int in skill_wind_keys:
		wind_seconds += keys[index].seconds
	var stretch := seconds / wind_seconds if seconds > 0.0 else 1.0
	var wind: Array[RigClips.ClipKey] = []
	for index: int in skill_wind_keys:
		wind.append(RigClips.ClipKey.new(keys[index].seconds * stretch, keys[index].easing, keys[index].pose))
	return wind


## The run cycle at `phase` seen from `view`.
func get_walk_pose(phase: float, view: StringName) -> UnitPose:
	if walk.is_valid():
		return walk.call(phase, view)
	return fitted(RigClips.walk_pose(phase))


## The pieces seen from `view`, grouped by draw order, back to front.
func get_z_sets(view: StringName) -> Array:
	if _z_sets.has(view):
		return _z_sets[view]
	var orders: Array[float] = []
	for piece: RigPiece in pieces:
		var z := piece.z_of(view)
		if not is_nan(z) and not orders.has(z):
			orders.append(z)
	orders.sort()
	var sets: Array = []
	for z: float in orders:
		var group: Array[RigPiece] = []
		for piece: RigPiece in pieces:
			if piece.z_of(view) == z:
				group.append(piece)
		sets.append(group)
	_z_sets[view] = sets
	return sets


## The weapon's tip and the trail's inner edge, in figure space.
func get_trail_points(frame: RigSolver.Frame, pose: UnitPose) -> PackedVector2Array:
	var hand := frame.bones[RigSolver.H_F]
	var along := tip
	if is_tip_on_weapon:
		along = tip * pose.values[UnitPose.WL] + Vector2.ONE * pose.values[UnitPose.WO]
	return PackedVector2Array([hand * Vector2(along.x, 1.5), hand * Vector2(along.y, 1.5)])


## Where the glow sits, in figure space.
func get_glow_point(frame: RigSolver.Frame, pose: UnitPose) -> Vector2:
	var x := glow_x
	if is_glow_on_weapon:
		x = glow_x * pose.values[UnitPose.WL] + pose.values[UnitPose.WO]
	return frame.bones[glow_bone] * Vector2(x, 1.5)
