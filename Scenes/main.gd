extends Node2D
## Root of the game: holds the SimClock and the screens and wires them. The
## clock does not tick by itself here; BattlePlayback drives it at the
## chosen battle speed (see Docs/systems/battle_playback.md).

const LOCALE: String = "vi"

@onready var _sim_clock: SimClock = $SimClock
@onready var _sandbox: SandboxScreen = $UI/SandboxScreen


func _enter_tree() -> void:
	# Vietnamese is the only player language for now, whatever the OS uses.
	# Set before the screens' _ready so their texts are translated in it.
	TranslationServer.set_locale(LOCALE)


func _ready() -> void:
	_sim_clock.set_process(false)
	_sandbox.sim_clock = _sim_clock
