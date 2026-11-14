extends Node2D
## Root of the game: holds the SimClock and the current screen, and moves
## between screens with a slide: title, run, end, sandbox. The clock does
## not tick by itself here; BattlePlayback drives it at the chosen battle
## speed (see Docs/systems/battle_playback.md).

const LOCALE: String = "vi"
const CATALOG_PATH: String = "res://Data/catalog.tres"
const SANDBOX_SCENE: PackedScene = preload("res://Scenes/Sandbox/sandbox_screen.tscn")
const SLIDE_SEC: float = 0.32

## The screen shown now (TitleScreen, RunScreen, EndScreen or SandboxScreen).
var current_screen: Control

var _catalog: Catalog
@onready var _sim_clock: SimClock = $SimClock
@onready var _ui: CanvasLayer = $UI


func _enter_tree() -> void:
	# Vietnamese is the only player language for now, whatever the OS uses.
	# Set before the screens' _ready so their texts are translated in it.
	TranslationServer.set_locale(LOCALE)


func _ready() -> void:
	_sim_clock.set_process(false)
	_catalog = load(CATALOG_PATH) as Catalog
	for problem: String in _catalog.validate():
		push_error(problem)
	show_title()


func show_title() -> void:
	var title := TitleScreen.new()
	title.catalog = _catalog
	title.has_save = RunSave.has_save()
	title.prep_seconds = RunSettings.load_prep_seconds()
	title.new_run_requested.connect(start_new_run)
	title.continue_requested.connect(continue_run)
	title.sandbox_requested.connect(open_sandbox)
	_switch_to(title, -1.0)


## Starts a fresh run; a seed of -1 picks one from the clock.
func start_new_run(seed_value: int = -1) -> RunScreen:
	if seed_value < 0:
		seed_value = absi(int(Time.get_unix_time_from_system() * 1000.0) ^ randi())
	var run := RunState.new(_catalog, seed_value)
	run.start()
	RunSave.save(run)
	return _open_run(run)


## Loads the saved run into its preparation or reward choice. A save that
## cannot be used (already warned about) is deleted, so the title shown
## again offers no "Chơi tiếp".
func continue_run() -> RunScreen:
	var run := RunSave.load_run(_catalog)
	if run == null:
		RunSave.delete()
		show_title()
		return null
	return _open_run(run)


func open_sandbox() -> SandboxScreen:
	var sandbox := SANDBOX_SCENE.instantiate() as SandboxScreen
	sandbox.sim_clock = _sim_clock
	sandbox.back_requested.connect(show_title)
	_switch_to(sandbox, 1.0)
	return sandbox


func _open_run(run: RunState) -> RunScreen:
	var screen := RunScreen.new()
	screen.run = run
	screen.sim_clock = _sim_clock
	screen.prep_seconds = RunSettings.load_prep_seconds()
	screen.run_finished.connect(_show_end)
	_switch_to(screen, 1.0)
	return screen


func _show_end(run: RunState) -> void:
	var end := EndScreen.new()
	end.run = run
	end.home_requested.connect(show_title)
	_switch_to(end, 1.0)


# Slides the old screen out and the new one in; `direction` 1 comes from
# the right, -1 from the left.
func _switch_to(screen: Control, direction: float) -> void:
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	var old := current_screen
	current_screen = screen
	_ui.add_child(screen)
	if old == null:
		return
	var width := get_viewport().get_visible_rect().size.x
	old.mouse_filter = Control.MOUSE_FILTER_IGNORE
	old.process_mode = Node.PROCESS_MODE_DISABLED
	screen.position.x = width * direction
	var tween := create_tween().set_parallel()
	tween.tween_property(screen, ^"position:x", 0.0, SLIDE_SEC).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_property(old, ^"position:x", -width * direction, SLIDE_SEC).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(old.queue_free)
