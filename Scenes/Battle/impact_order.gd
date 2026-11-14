class_name ImpactOrder
extends RefCounted
## Keeps delayed impacts in simulation order per unit. An arrow fired before a
## sword swing can land after it on screen; its older hp must not raise the
## bar again. Event ids grow with simulation order, so an impact applies only
## when its id is newer than the last one applied to that unit.
## [codeblock]
## if order.accept(target, event_id): view.set_hp_ratio(ratio)
## [/codeblock]

var _last_id: Dictionary[int, int] = {}


## True, and remembered, when `event_id` is newer than the last accepted
## impact on `unit`; false for an impact that arrives out of order.
func accept(unit: int, event_id: int) -> bool:
	if event_id <= _last_id.get(unit, 0):
		return false
	_last_id[unit] = event_id
	return true


func clear() -> void:
	_last_id.clear()
