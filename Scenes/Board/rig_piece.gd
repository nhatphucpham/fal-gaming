class_name RigPiece
extends RefCounted
## One drawn piece of a figure (an arm, the torso, a helmet, a sword), in
## its bone's space with the joint at (0, 0), and its draw order per view
## (port of the sketch's `PIECES` entries). A piece with a `path` is
## stroked in ink (together with the other pieces of its draw order) and
## filled; `detail` adds to the fill. A piece with `paint` draws itself,
## outline included. Meshes are cached per race and per the inputs the
## piece depends on (`depends`), quantized, so only transforms change per
## frame. A piece with `live` paints every frame (the bow, the horse).

## Flags of the inputs a cached mesh depends on.
const USES_SCALE: int = 1
const USES_HEEL: int = 2
const USES_WEAPON: int = 4
const USES_EYES: int = 8
const USES_SWAY: int = 16
const USES_GLOW: int = 32
const USES_VIEW: int = 64
## Steps the inputs are rounded to before a mesh is built.
const SCALE_STEP: float = 0.02
const HEEL_STEP: float = 0.05
const WEAPON_LENGTH_STEP: float = 0.02
const SWAY_STEPS: float = 4.0
const GLOW_STEP: float = 0.1


## What a piece is drawn from. `sway` is -1..1 on the piece's own period.
class Args:
	extends RefCounted
	var view: StringName = RigSolver.VIEW_FRONT
	var scale: float = 1.0
	var heel: float = 0.0
	var weapon_length: float = 1.0
	var eyes: int = 0
	var sway: float = 0.0
	var glow: float = 0.0
	## A furred race (wolf folk): ears and a muzzle on the head.
	var has_fur: bool = false
	## The pose and solved frame, for live pieces only.
	var pose: UnitPose
	var frame: RigSolver.Frame


var id: StringName
## The mesh cache's name for the piece: its id, made unique when a class
## changes a shared piece (with_members), so unchanged pieces share meshes
## across classes.
var cache_id: String
var bone: int = RigSolver.ROOT
## Draw order seen from the front and from the back; NAN: not drawn.
var z_front: float = NAN
var z_back: float = NAN
var color := Color.WHITE
## func(path: RigPath, args: Args) -> void
var path: Callable
## func(mesh: RigMesh, args: Args) -> void
var detail: Callable
## func(mesh: RigMesh, args: Args) -> void, outline included.
var paint: Callable
## func(frame: RigSolver.Frame, pose: UnitPose, view: StringName) -> Transform2D,
## where a painted piece sits in its bone's space (identity when invalid).
var place: Callable
var depends: int = 0
## The period of the piece's idle sway (cloth, plume), in seconds.
var sway_period_sec: float = 0.0
var is_live: bool = false
## The step the weapon length is rounded to for this piece's meshes.
var weapon_length_step: float = WEAPON_LENGTH_STEP


static func make(piece_id: StringName, piece_bone: int, front: float, back: float) -> RigPiece:
	var piece := RigPiece.new()
	piece.id = piece_id
	piece.cache_id = piece_id
	piece.bone = piece_bone
	piece.z_front = front
	piece.z_back = back
	return piece


func z_of(view: StringName) -> float:
	return z_back if view == RigSolver.VIEW_BACK else z_front


## A copy with some members replaced, for a class's version of a piece.
func with_members(members: Dictionary) -> RigPiece:
	var piece := RigPiece.new()
	for member: String in ["id", "bone", "z_front", "z_back", "color", "path", "detail", "paint", "place", "depends", "sway_period_sec", "weapon_length_step", "is_live"]:
		piece.set(member, members.get(member, get(member)))
	piece.cache_id = "%s#%d" % [piece.id, piece.get_instance_id()]
	return piece


## The cache key of `args` for this piece (only the inputs it uses).
func key_of(args: Args, race_id: StringName) -> String:
	var key := "%s|%s" % [cache_id, race_id]
	if depends & USES_VIEW:
		key += "|" + args.view
	if depends & USES_SCALE:
		key += "|s%d" % roundi(args.scale / SCALE_STEP)
	if depends & USES_HEEL:
		key += "|h%d" % roundi(args.heel / HEEL_STEP)
	if depends & USES_WEAPON:
		key += "|w%d" % roundi(args.weapon_length / weapon_length_step)
	if depends & USES_EYES:
		key += "|e%d" % args.eyes
	if depends & USES_SWAY:
		key += "|y%d" % roundi(args.sway * SWAY_STEPS)
	if depends & USES_GLOW:
		key += "|g%d" % roundi(args.glow / GLOW_STEP)
	return key


## `args` with the inputs this piece uses rounded like its cache key, so
## the mesh built matches the key.
func quantize(args: Args) -> Args:
	var out := Args.new()
	out.view = args.view
	out.scale = roundi(args.scale / SCALE_STEP) * SCALE_STEP
	out.heel = roundi(args.heel / HEEL_STEP) * HEEL_STEP
	out.weapon_length = roundi(args.weapon_length / weapon_length_step) * weapon_length_step
	out.eyes = args.eyes
	out.sway = roundi(args.sway * SWAY_STEPS) / SWAY_STEPS
	out.glow = roundi(args.glow / GLOW_STEP) * GLOW_STEP
	out.has_fur = args.has_fur
	out.pose = args.pose
	out.frame = args.frame
	return out
