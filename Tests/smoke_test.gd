extends SceneTree


func _initialize() -> void:
	var scene := load("res://Scenes/main.tscn") as PackedScene
	if scene == null:
		push_error("Main scene failed to load")
		quit(1)
		return
	var main := scene.instantiate()
	if not main is Node2D:
		push_error("Main scene root must be a Node2D")
		main.free()
		quit(1)
		return
	main.free()
	print("Falemag smoke test passed")
	quit(0)
