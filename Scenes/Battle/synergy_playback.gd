class_name SynergyPlayback
extends RefCounted
## The synergy half of BattlePlayback: small readable effects for the procs
## the battle reports with modifier_triggered (a "Chặn" over a block, lines
## from a split hit to the members sharing it, a flash on a double hit, the
## volley's name), and formation_broken, which BattlePlayback passes on as a
## signal for the outlines. Proc looks come from a registry keyed by the
## modifier's handler id. See Docs/systems/battle_playback.md.

const WORD_FONT_SIZE: int = 22
const SPLIT_LINE_SEC: float = 0.25

var _playback: BattlePlayback
var _looks: Dictionary[StringName, Callable] = {}


func _init(playback: BattlePlayback) -> void:
	_playback = playback
	_looks = {
		&"mod.block_first_hit": _show_word.bind("SYNERGY_BLOCKED", Palette.STEEL),
		&"mod.reflect_melee_pct": _show_word.bind("SYNERGY_REFLECT", Palette.class_color(&"class.sword")),
		&"mod.charge_immunity": _show_word.bind("SYNERGY_STOPPED", Palette.class_color(&"class.spear")),
		&"mod.nth_attack_bonus_pct": _show_double,
		&"mod.split_first_hit": _show_split,
		&"mod.volley": _show_volley,
	}


func get_handlers() -> Dictionary[StringName, Callable]:
	return {
		&"modifier_triggered": _on_modifier_triggered,
		&"formation_broken": _on_formation_broken,
	}


func _on_modifier_triggered(event: Dictionary) -> void:
	var look: Callable = _looks.get(event["modifier"], Callable())
	var view := _playback.get_view(event["unit"])
	if look.is_valid() and view != null:
		_playback.run_after(_playback.get_impact_delay(event["cause"]), look.bind(view, event))


func _on_formation_broken(event: Dictionary) -> void:
	_playback.formation_broken.emit(event["side"], event["source_id"])


func _show_word(view: UnitView, _event: Dictionary, key: String, color: Color) -> void:
	if view.is_dead:
		return
	var fx := SkillFx.name_popup(view.position + Vector2(0, -58), view.tr(key), color)
	fx.font_size = WORD_FONT_SIZE
	_playback.spawn_fx(fx)


func _show_double(view: UnitView, event: Dictionary) -> void:
	_playback.spawn_fx(BattleFx.cell_flash(view.position, Palette.GOLD))
	_show_word(view, event, "SYNERGY_DOUBLE", Palette.GOLD)


# Thin lines from the unit hit to each formation cell sharing the blow.
func _show_split(view: UnitView, event: Dictionary) -> void:
	var color := Palette.class_color(&"class.shield")
	for cell: Vector2i in event["cells"]:
		var to := _playback.cell_center(cell)
		if to.distance_to(view.position) > BoardView.CELL_PX * 0.5:
			_playback.spawn_fx(BattleFx.bolt(view.position + Vector2(0, -14), to + Vector2(0, -14), SPLIT_LINE_SEC, color))
	_show_word(view, event, "SYNERGY_SPLIT", color)


func _show_volley(view: UnitView, event: Dictionary) -> void:
	view.recoil(Vector2(0, -1 if view.side == 0 else 1))
	_playback.show_source_name(view, event["source_id"], Palette.class_color(&"class.archer"))
