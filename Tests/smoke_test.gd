extends SceneTree


func _initialize() -> void:
	quit(_run())


func _run() -> int:
	if not ClassDB.class_exists("SimClock"):
		push_error("SimClock is missing: build the GDExtension (scons) before importing")
		return 1

	var scene := load("res://Scenes/main.tscn") as PackedScene
	if scene == null:
		push_error("Main scene failed to load")
		return 1
	var main := scene.instantiate()
	var result := _check_main(main)
	main.free()
	if result == 0:
		print("Falemag smoke test passed")
	return result


func _check_main(main: Node) -> int:
	if not main is Node2D:
		push_error("Main scene root must be a Node2D")
		return 1

	var clock := main.get_node_or_null("SimClock")
	if clock == null or clock.get_class() != "SimClock":
		push_error("Main scene must contain a SimClock node")
		return 1

	# 20 ticks per second: a quarter second is exactly five ticks.
	var fired: Array[int] = []
	clock.ticked.connect(func(tick: int) -> void: fired.append(tick))
	if clock.advance(0.25) != 5 or clock.get_tick() != 5 or fired != [1, 2, 3, 4, 5]:
		push_error("SimClock did not fire five ticks for 0.25 s")
		return 1

	# A long stall is capped at max_ticks_per_frame and the backlog dropped.
	if clock.advance(10.0) != clock.max_ticks_per_frame or clock.advance(0.0) != 0:
		push_error("SimClock did not cap ticks after a stall")
		return 1

	# Bad frame times are ignored and do not stall the clock.
	if clock.advance(NAN) != 0 or clock.advance(INF) != 0 or clock.advance(-1.0) != 0:
		push_error("SimClock accepted an invalid delta")
		return 1
	if clock.advance(0.05) != 1:
		push_error("SimClock stopped ticking after an invalid delta")
		return 1

	clock.reset()
	if clock.get_tick() != 0:
		push_error("SimClock did not reset")
		return 1
	return 0
