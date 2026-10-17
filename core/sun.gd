extends RefCounted
## The sun marker and shadow activity (PROJECT_CONTEXT.md 3.5).
## No Nodes, graphics, audio or UI. Turn-based, never real time.
##
##   sun_index = start_index + floor(action_count / actions_per_hour)
##   an hour is passed when its order index (12, 2, 4, 6, 8, 10 = 0..5) < sun_index
##   a shadow is active when its hour is passed, otherwise dormant
##   the dial is complete when sun_index >= 6

const GameStateScript := preload("res://core/game_state.gd")

const DIAL_SIZE := 6  # GameStateScript.HOUR_ORDER.size()


static func sun_index(state: GameStateScript) -> int:
	return sun_index_at(state, state.action_count)


## The sun index `state` would have after `action_count` actions.
static func sun_index_at(state: GameStateScript, action_count: int) -> int:
	return state.sun_start_index + floori(action_count / float(state.actions_per_hour))


static func is_hour_passed(state: GameStateScript, hour: int) -> bool:
	var index := GameStateScript.order_index(hour)
	return index >= 0 and index < sun_index(state)


static func is_dial_complete(state: GameStateScript) -> bool:
	return sun_index(state) >= DIAL_SIZE


## Hours that become passed when the sun index goes from `from_index` to
## `to_index`, in sun order.
static func hours_passed_between(from_index: int, to_index: int) -> Array:
	var hours: Array = []
	for index in range(maxi(from_index, 0), mini(to_index, DIAL_SIZE)):
		hours.append(GameStateScript.HOUR_ORDER[index])
	return hours


## The ACTIVE shadow at a slot, or {} if none (a dormant shadow does not count).
static func active_shadow_at(state: GameStateScript, hour: int, slot: Vector2i) -> Dictionary:
	var sh := state.shadow_at(hour, slot)
	if not sh.is_empty() and is_hour_passed(state, hour):
		return sh
	return {}


## Shadows whose hour is in `hours`, sorted by id (deterministic event order).
static func shadows_in_hours(state: GameStateScript, hours: Array) -> Array:
	var ids := state.shadows.keys()
	ids.sort()
	var found: Array = []
	for id in ids:
		if hours.has(state.shadows[id]["hour"]):
			found.append(state.shadows[id])
	return found
