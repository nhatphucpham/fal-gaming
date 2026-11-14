class_name CoinBurst
extends Node2D
## A handful of coins that spring out of a point and fly in an arc into the
## gold chip, one after another; `landed` fires when the first one arrives
## (the chip ticks and bounces then) and the coin sound plays. Frees itself
## when the last coin is in. Positions are canvas coordinates.
## [codeblock]
## var burst := CoinBurst.new()
## layout.add_child(burst)
## burst.landed.connect(func() -> void: layout.gold_chip.set_value(run.gold))
## burst.launch(from, layout.gold_chip.get_icon_center(), 5)
## [/codeblock]

signal landed()

const FLY_SEC: float = 0.55
const STAGGER_SEC: float = 0.06
const COIN_PX: float = 30.0
const MAX_COINS: int = 10
const SPREAD_PX: float = 70.0

# Per coin: start, control point, end, delay; and the time since launch.
var _coins: Array[Dictionary] = []
var _time: float = 0.0
var _has_landed: bool = false


func _init() -> void:
	top_level = true
	z_index = 50


## Starts `count` coins (at most MAX_COINS) from `from` to `to`.
func launch(from: Vector2, to: Vector2, count: int) -> void:
	var total := clampi(count, 1, MAX_COINS)
	for index: int in total:
		# A fixed fan of start offsets, so every burst looks alike.
		var angle := TAU * index / total
		var start := from + Vector2(cos(angle), sin(angle)) * SPREAD_PX * 0.4
		var control := (start + to) / 2.0 + Vector2(cos(angle) * SPREAD_PX, -SPREAD_PX * 2.0)
		_coins.append({"start": start, "control": control, "end": to, "delay": index * STAGGER_SEC})
	Sound.play(&"coin")
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if not _has_landed and not _coins.is_empty() and _time >= FLY_SEC:
		_has_landed = true
		Sound.play(&"coin")
		landed.emit()
	if _coins.is_empty() or _time >= FLY_SEC + _coins.back()["delay"]:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	for coin: Dictionary in _coins:
		var t := clampf((_time - coin["delay"]) / FLY_SEC, 0.0, 1.0)
		if t >= 1.0:
			continue
		var eased := t * t * (3.0 - 2.0 * t)
		var a: Vector2 = (coin["start"] as Vector2).lerp(coin["control"], eased)
		var b: Vector2 = (coin["control"] as Vector2).lerp(coin["end"], eased)
		var spin := absf(cos(t * TAU * 1.5))
		draw_set_transform(a.lerp(b, eased), 0.0, Vector2(maxf(0.25, spin), 1.0))
		IconPainter.draw(self, &"coin", Vector2.ZERO, COIN_PX * (1.15 - 0.35 * t))
	draw_set_transform(Vector2.ZERO)
