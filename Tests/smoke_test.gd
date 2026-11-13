extends SceneTree

# Checks return true only when every step succeeded. A GDScript runtime error
# makes a function return its type's default, false here, so an unbound or
# renamed C++ method fails the test instead of slipping through.


func _initialize() -> void:
	if _run():
		print("Falemag smoke test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	if not ClassDB.class_exists("SimClock"):
		push_error("SimClock is missing: build the GDExtension (scons) before importing")
		return false

	var scene := load("res://Scenes/main.tscn") as PackedScene
	if scene == null:
		push_error("Main scene failed to load")
		return false
	var main := scene.instantiate()
	var ok := _check_main(main)
	main.free()
	return ok


func _check_main(main: Node) -> bool:
	if not main is Node2D:
		push_error("Main scene root must be a Node2D")
		return false

	var clock := main.get_node_or_null("SimClock")
	if clock == null or clock.get_class() != "SimClock":
		push_error("Main scene must contain a SimClock node")
		return false

	# 20 ticks per second: a quarter second is exactly five ticks.
	var fired: Array[int] = []
	clock.ticked.connect(func(tick: int) -> void: fired.append(tick))
	if clock.advance(0.25) != 5 or clock.get_tick() != 5 or fired != [1, 2, 3, 4, 5]:
		push_error("SimClock did not fire five ticks for 0.25 s")
		return false

	# A long stall is capped at max_ticks_per_frame and the backlog dropped:
	# less than one 50 ms step afterwards must not tick.
	if clock.advance(10.0) != clock.max_ticks_per_frame or clock.advance(0.04) != 0:
		push_error("SimClock did not cap ticks after a stall")
		return false

	# Bad frame times are ignored and do not stall the clock.
	if clock.advance(NAN) != 0 or clock.advance(INF) != 0 or clock.advance(-1.0) != 0:
		push_error("SimClock accepted an invalid delta")
		return false
	if clock.advance(0.01) != 1:
		push_error("SimClock stopped ticking after an invalid delta")
		return false

	clock.reset()
	if clock.get_tick() != 0:
		push_error("SimClock did not reset")
		return false
	return true
