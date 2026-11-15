extends SceneTree

# Performance probe: drives the real screens through fixed scenes (title,
# a full late preparation, a full battle at x1 and x4) at 60 frames a second
# and prints, per scene, the CPU time per frame, the frame times, how many
# canvas items redraw each second (by class), draw calls, the share of
# frames really drawn (rendered) or changed (headless, idle scenes) and
# memory. Not shipped (Tools/ is excluded from every
# export preset) and not part of Tools/build_and_test.sh. Usage:
#   godot --headless --path . --script res://Tools/perf_probe.gd -- [--json=<file>] [--budget=<file>] [--summary=<file>]
# Headless gives CPU and redraw numbers; under a display (xvfb-run with
# --rendering-driver opengl3) it also gives draw calls, primitives and
# frames_drawn_share. With --budget it fails (exit 1) when a scene goes over
# its budget (PerfBudget, Docs/perf_budget.json); --summary appends a
# Markdown table (CI's job summary). Any error logged on the way also fails
# it. See Docs/systems/performance.md.


# Counts errors (not warnings) logged while the probe runs.
class ErrorCounter extends Logger:
	var count: int = 0

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			count += 1


const SEED: int = 4242
const FPS: int = 60
const SETTLE_SEC: float = 2.0
const IDLE_FRAMES: int = 300
const CHANGED_FRAMES: int = 180
const MAX_BATTLE_FRAMES: int = 3600
const LATE_STAGE: int = 11
const MAX_SHOP_REFRESHES: int = 200
const SAVE_PATH: String = "user://run_save_perf_probe.json"
const SETTINGS_PATH: String = "user://settings_perf_probe.json"

var _main: Node
var _redraws: Dictionary[String, int] = {}
var _results: Dictionary = {}
var _is_rendering: bool = false
var _errors := ErrorCounter.new()


func _initialize() -> void:
	OS.add_logger(_errors)
	RunSave.path = SAVE_PATH
	RunSettings.path = SETTINGS_PATH
	# The figures' breathing phases and the title's hops use the global RNG.
	seed(SEED)
	Engine.max_fps = FPS
	_is_rendering = DisplayServer.get_name() != "headless"
	node_added.connect(_watch)
	var ok := await _run()
	RunSave.delete()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--json="):
			var file := FileAccess.open(arg.trim_prefix("--json="), FileAccess.WRITE)
			file.store_string(JSON.stringify(_results, "\t"))
		if arg.begins_with("--summary="):
			_append_summary(arg.trim_prefix("--summary="))
		if arg.begins_with("--budget="):
			for problem: String in PerfBudget.check(PerfBudget.load_file(arg.trim_prefix("--budget=")), _results, _is_rendering):
				push_error(problem)
				ok = false
	print(JSON.stringify(_results, "\t"))
	if _errors.count > 0:
		printerr("perf_probe: %d errors were logged" % _errors.count)
		ok = false
	OS.remove_logger(_errors)
	quit(0 if ok else 1)


func _run() -> bool:
	if not ClassDB.class_exists("Battle"):
		push_error("Battle is missing: build the GDExtension (scons) before importing")
		return false
	_main = (load("res://Scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await _wait(SETTLE_SEC)
	await _sample("title", IDLE_FRAMES, Callable())
	await _sample_changed_frames("title")

	var screen := await _open_late_run()
	await _wait(SETTLE_SEC)
	await _sample("prep_full", IDLE_FRAMES, Callable())
	await _sample_changed_frames("prep_full")
	screen.start_battle()
	await _sample("battle_x1", MAX_BATTLE_FRAMES, func() -> bool: return screen.run.phase != RunState.Phase.BATTLE)

	screen = await _open_late_run()
	for press: int in 2:
		screen.cycle_speed()
	await _wait(SETTLE_SEC)
	screen.start_battle()
	await _sample("battle_x4", MAX_BATTLE_FRAMES, func() -> bool: return screen.run.phase != RunState.Phase.BATTLE)
	_main.queue_free()
	await process_frame
	return true


# A stage-11 preparation with a full board (8 units), a full bench and the
# stage's 8 enemies shown: the most figures a screen holds.
func _open_late_run() -> RunScreen:
	var run := RunState.new(_main._catalog, SEED)
	run.start()
	run.stage = LATE_STAGE
	run.level = run.rules.max_level
	run.gold = 100000
	var screen: RunScreen = _main._open_run(run)
	screen.is_saving = false
	await _wait(0.6)
	var cells: Array[Vector2i] = []
	for row: int in [2, 1]:
		for col: int in [1, 2, 3, 4, 5]:
			cells.append(Vector2i(col, row))
	var refreshes := 0
	while refreshes < MAX_SHOP_REFRESHES and (run.get_board_count() < run.get_capacity() or run.has_free_bench_slot()):
		for slot: int in run.rules.shop_slots:
			if run.get_shop_offers()[slot] == &"":
				continue
			if run.get_board_count() < run.get_capacity():
				var cell: Vector2i = cells[run.get_board_count()]
				if run.get_board_piece(cell) == null:
					run.buy_to(slot, RunPiece.NO_BENCH, cell)
					continue
			if run.has_free_bench_slot():
				run.buy(slot)
		run.gold = 100000
		run.refresh_shop()
		refreshes += 1
	return screen


func _sample(scene: String, max_frames: int, is_done: Callable) -> void:
	_redraws.clear()
	var frame_ms := PackedFloat32Array()
	var draw_calls := 0
	var primitives := 0
	var objects := 0
	var cpu_start := _cpu_usec()
	var drawn_start := Engine.get_frames_drawn()
	var wall_start := Time.get_ticks_usec()
	var last := wall_start
	var frames := 0
	while frames < max_frames and not (is_done.is_valid() and is_done.call()):
		await process_frame
		var now := Time.get_ticks_usec()
		frame_ms.append((now - last) / 1000.0)
		last = now
		draw_calls = maxi(draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		primitives = maxi(primitives, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
		objects = maxi(objects, int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
		frames += 1
	var wall_sec := (Time.get_ticks_usec() - wall_start) / 1000000.0
	var cpu_sec := (_cpu_usec() - cpu_start) / 1000000.0
	var per_sec: Dictionary[String, float] = {}
	var total := 0.0
	for key: String in _redraws:
		per_sec[key] = snappedf(_redraws[key] / wall_sec, 0.1)
		total += _redraws[key] / wall_sec
	var sorted_frames := Array(frame_ms)
	sorted_frames.sort()
	var long_frames := 0
	for value: float in frame_ms:
		if value > 1000.0 / FPS * 1.5:
			long_frames += 1
	var result := {
		"frames": frames,
		"seconds": snappedf(wall_sec, 0.01),
		"cpu_ms_per_frame": snappedf(cpu_sec * 1000.0 / maxi(1, frames), 0.001),
		"cpu_percent_of_one_core": snappedf(cpu_sec / wall_sec * 100.0, 0.1),
		"frame_ms_p95": snappedf(sorted_frames[int(sorted_frames.size() * 0.95)], 0.01),
		"frame_ms_max": snappedf(sorted_frames[-1], 0.01),
		"long_frames": long_frames,
		"redraws_per_sec": snappedf(total, 0.1),
		"redraws_per_sec_by_class": per_sec,
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"static_memory_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.01),
		"rig_meshes": RigPainter.get_cached_mesh_count(),
		"is_rendering": _is_rendering,
	}
	if _is_rendering:
		result["draw_calls_max"] = draw_calls
		result["primitives_max"] = primitives
		result["render_objects_max"] = objects
		result["video_memory_mb"] = snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.01)
		# Frames the renderer really drew: below 1 when low processor mode
		# skips frames where nothing changed.
		result["frames_drawn_share"] = snappedf(float(Engine.get_frames_drawn() - drawn_start) / maxi(1, frames), 0.01)
	_results[scene] = result


# Headless only, on an idle scene, after its sample (so the CPU numbers
# leave it out): the share of frames after which something on screen
# changed (RenderingServer.has_changed()), drawing by hand in between.
# The renderer's own frames_drawn_share would show it only on a machine
# fast enough to draw every frame; this does not depend on one.
func _sample_changed_frames(scene: String) -> void:
	if _is_rendering:
		return
	var changed := 0
	RenderingServer.force_draw(false)
	for frame: int in CHANGED_FRAMES:
		await process_frame
		if RenderingServer.has_changed():
			changed += 1
			RenderingServer.force_draw(false)
	_results[scene]["frames_changed_share"] = snappedf(float(changed) / CHANGED_FRAMES, 0.01)


func _append_summary(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file == null:
		push_error("perf_probe: cannot write the summary %s" % path)
		return
	file.seek_end()
	file.store_string(PerfBudget.summary_table(_results, _is_rendering))


func _watch(node: Node) -> void:
	var item := node as CanvasItem
	if item == null:
		return
	var script := item.get_script() as Script
	var label: String = item.get_class()
	if script != null:
		label = script.get_global_name() if script.get_global_name() != &"" else script.resource_path.get_file()
	else:
		# A plain node is named after the nearest scripted node above it.
		var owner_node := item.get_parent()
		while owner_node != null and owner_node.get_script() == null:
			owner_node = owner_node.get_parent()
		if owner_node != null:
			var owner_script := owner_node.get_script() as Script
			label = "%s in %s" % [label, owner_script.get_global_name() if owner_script.get_global_name() != &"" else owner_script.resource_path.get_file()]
	if not item.has_meta(&"perf_probe"):
		item.set_meta(&"perf_probe", true)
		item.draw.connect(_count.bind(label))


func _count(label: String) -> void:
	_redraws[label] = _redraws.get(label, 0) + 1


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


# CPU time this process has used (user and system), from /proc; 0 where
# there is no /proc (Windows, the web).
func _cpu_usec() -> int:
	var output: Array = []
	if OS.get_name() != "Linux" or OS.execute("cat", ["/proc/%d/stat" % OS.get_process_id()], output) != 0:
		return 0
	var stat: String = output[0]
	var fields := stat.substr(stat.rfind(")") + 2).split(" ")
	# utime and stime are fields 14 and 15, in clock ticks of 1/100 s.
	return (int(fields[11]) + int(fields[12])) * 10000
