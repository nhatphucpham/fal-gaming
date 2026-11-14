class_name RewardScreen
extends Control
## After a battle: two or three large reward cards slide in; tapping one
## pops it while the others fall away, then `reward_chosen` fires. The
## cards come from a registry by reward, so a new reward is one entry here
## plus its rule in RunState.
## [codeblock]
## reward_screen.reward_chosen.connect(run.choose_reward)
## reward_screen.present(run.get_reward_options(), run.rules)
## [/codeblock]

signal reward_chosen(reward: RunState.Reward)

const SLIDE_PX: float = 420.0

var _shade: ColorRect
var _title: Label
var _row: HBoxContainer
var _cards: Array[RewardCard] = []
var _is_choosing: bool = false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_shade = ColorRect.new()
	_shade.color = Color(Palette.BACKDROP, 0.82)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)
	_title = Label.new()
	_title.theme_type_variation = &"TitleLabel"
	_title.add_theme_font_size_override(&"font_size", 48)
	_title.text = "REWARD_TITLE"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	add_child(_title)
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override(&"separation", 18)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_row)


## Shows one card per reward in `options`, numbers taken from `rules`.
func present(options: Array[RunState.Reward], rules: RunRules) -> void:
	for card: RewardCard in _cards:
		card.queue_free()
	_cards.clear()
	_is_choosing = false
	var looks := _looks(rules)
	for index: int in options.size():
		var reward := options[index]
		var look: Array = looks[reward]
		var card := RewardCard.new()
		card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		card.setup(look[0], tr(look[1]), look[2])
		card.chosen.connect(_on_chosen.bind(reward, card))
		_row.add_child(card)
		_cards.append(card)
	visible = true
	_title.position.y = size.y * 0.24
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, ^"modulate:a", 1.0, 0.2)
	for index: int in _cards.size():
		var card := _cards[index]
		card.modulate.a = 0.0
		card.scale = Vector2(0.7, 0.7)
		tween.parallel().tween_property(card, ^"modulate:a", 1.0, 0.2).set_delay(0.1 + index * 0.08)
		tween.parallel().tween_property(card, ^"scale", Vector2.ONE, 0.3).set_delay(0.1 + index * 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Picks a reward as if its card was tapped (tests and keyboard).
func choose(reward: RunState.Reward) -> void:
	_is_choosing = false
	visible = false
	reward_chosen.emit(reward)


# Icon, title key and effect line per reward.
func _looks(rules: RunRules) -> Dictionary:
	return {
		RunState.Reward.REST: [&"tent", "REWARD_REST", tr("REWARD_REST_EFFECT") % rules.rest_morale],
		RunState.Reward.HUNT: [&"bow", "REWARD_HUNT", tr("REWARD_HUNT_EFFECT") % rules.hunt_supply],
		RunState.Reward.BLACK_MARKET: [&"lantern", "REWARD_BLACK_MARKET", tr("REWARD_BLACK_MARKET_EFFECT")],
	}


func _on_chosen(reward: RunState.Reward, card: RewardCard) -> void:
	if _is_choosing:
		return
	_is_choosing = true
	var tween := create_tween()
	for other: RewardCard in _cards:
		if other == card:
			tween.parallel().tween_property(card, ^"scale", Vector2(1.15, 1.15), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			tween.parallel().tween_property(other, ^"position:y", other.position.y + SLIDE_PX, 0.3).set_ease(Tween.EASE_IN)
			tween.parallel().tween_property(other, ^"modulate:a", 0.0, 0.25)
	tween.tween_interval(0.15)
	tween.tween_property(self, ^"modulate:a", 0.0, 0.2)
	tween.tween_callback(choose.bind(reward))
