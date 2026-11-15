class_name WeaponTrail
extends RefCounted
## The smear behind a swinging weapon, in figure space: one (tip, inner
## edge) sample of the weapon every frame while the pose's `trail` is up,
## at most SAMPLES of them, each with a weight that fades once the swing
## ends. PoseAnimator owns one; RigPainter draws it.

## Samples kept: the trail is this many frames long.
const SAMPLES: int = 14
const FADE_PER_SEC: float = 7.0
## A pose's `trail` above this takes samples.
const SAMPLE_TRAIL_MIN: float = 0.03

## (tip, inner edge) per sample, oldest first.
var points := PackedVector2Array()
## 0..1 per sample.
var weights := PackedFloat32Array()


## True when nothing is left to draw.
func is_empty() -> bool:
	return weights.is_empty()


func clear() -> void:
	points.clear()
	weights.clear()


## Takes a sample of `pose` (solved for `view` with `kit`) while its trail
## is up, else fades every sample by `dt` of battle time.
func update(pose: UnitPose, kit: RigKit, view: StringName, dt: float) -> void:
	if pose.values[UnitPose.TRAIL] > SAMPLE_TRAIL_MIN:
		var still := pose.merged({"dx": 0}) if pose.values[UnitPose.DX] != 0.0 else pose
		points.append_array(kit.get_trail_points(RigSolver.solve(still, view), still))
		weights.append(1.0)
	elif not weights.is_empty():
		for index: int in weights.size():
			weights[index] -= dt * FADE_PER_SEC
	var first := 0
	while first < weights.size() and weights[first] <= 0.0:
		first += 1
	first = maxi(first, weights.size() - SAMPLES)
	if first > 0:
		weights = weights.slice(first)
		points = points.slice(first * 2)
