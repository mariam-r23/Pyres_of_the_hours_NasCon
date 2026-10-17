extends RefCounted
## Validates and applies one action (PROJECT_CONTEXT.md 3.3 to 3.5, 6.2 and 11).
## No Nodes, graphics, audio or UI.
##
## apply_action(state, action) NEVER modifies `state`:
##   valid    -> { ok: true,  events: [...], state: <new deep copy>, reason: "" }
##   rejected -> { ok: false, events: [action_rejected], state: <the same input>, reason: "..." }
## Rejected actions are free: no counter change, no sun, no snapshot.
##
## Event order for a valid action:
##   the action's own events (moved | burned, ash_moved, shadow_destroyed),
##   sun_advanced, hour_passed (each newly passed hour),
##   shadow_appeared (each surviving shadow in a newly passed hour),
##   action_applied (last of the action's events),
##   then level_won or level_failed if the action ended the level.
## Once the level is won or failed, every action is rejected with level_over.

const GameStateScript := preload("res://core/game_state.gd")
const Walkability := preload("res://core/walkability.gd")
const AshTransfer := preload("res://core/ash_transfer.gd")
const Sun := preload("res://core/sun.gd")

## y grows downward (section 3.1).
const DIRECTIONS := {
	"up": Vector2i(0, -1),
	"down": Vector2i(0, 1),
	"left": Vector2i(-1, 0),
	"right": Vector2i(1, 0),
}
## Fixed order so legal_actions() is deterministic.
const DIRECTION_ORDER := ["up", "down", "left", "right"]

const REASON_NOT_ON_STAIR := "not_on_stair"
const REASON_ARRIVAL_BLOCKED := "arrival_blocked"
const REASON_SHADOW_BLOCKS := "shadow_blocks"
const REASON_SHADOW_WAKES_ON_YOU := "shadow_wakes_on_you"
const REASON_UNKNOWN_ACTION := "unknown_action"
const REASON_LEVEL_OVER := "level_over"
const FAIL_DIAL_COMPLETE := "dial_complete"


static func apply_action(state: GameStateScript, action: Variant) -> Dictionary:
	if state.status != GameStateScript.PLAYING:
		return _reject(state, REASON_LEVEL_OVER)
	if typeof(action) != TYPE_DICTIONARY:
		return _reject(state, REASON_UNKNOWN_ACTION)

	# Validate against the untouched input first, so a rejection costs no copy.
	# Shadow checks here use the sun BEFORE the action.
	var reason := ""
	var target_hour := state.player_hour
	var target_slot := state.player_slot
	var burn_slot = null  # Vector2i of the object to burn, for a burn action
	match action.get("type"):
		"move":
			var dir = action.get("dir")
			if not DIRECTIONS.has(dir):
				return _reject(state, REASON_UNKNOWN_ACTION)
			target_slot = state.player_slot + DIRECTIONS[dir]
			reason = Walkability.check_walkable(state, target_hour, target_slot)["reason"]
			if reason == "" and not Sun.active_shadow_at(state, target_hour, target_slot).is_empty():
				reason = REASON_SHADOW_BLOCKS
		"interact":
			var stair := state.object_at(state.player_hour, state.player_slot)
			if stair.get("type") != "stair":
				return _reject(state, REASON_NOT_ON_STAIR)
			if not stair.has("links_to"):
				return _reject(state, REASON_ARRIVAL_BLOCKED)
			target_hour = stair["links_to"]["hour"]
			target_slot = stair["links_to"]["slot"]
			if not Walkability.is_walkable(state, target_hour, target_slot) \
					or not Sun.active_shadow_at(state, target_hour, target_slot).is_empty():
				reason = REASON_ARRIVAL_BLOCKED
		"burn":
			var dir = action.get("dir")
			if not DIRECTIONS.has(dir):
				return _reject(state, REASON_UNKNOWN_ACTION)
			burn_slot = state.player_slot + DIRECTIONS[dir]
			reason = AshTransfer.check_burn(state, state.player_hour, burn_slot)
		"wait":
			pass
		_:
			return _reject(state, REASON_UNKNOWN_ACTION)
	if reason != "":
		return _reject(state, reason)

	# Would a shadow wake on the player's tile after this action? Only shadows
	# in newly passed hours wake; a burn only destroys already-active shadows,
	# so it cannot remove one of these.
	var from_index := Sun.sun_index(state)
	var to_index := Sun.sun_index_at(state, state.action_count + 1)
	var newly_passed := Sun.hours_passed_between(from_index, to_index)
	if newly_passed.has(target_hour) and not state.shadow_at(target_hour, target_slot).is_empty():
		return _reject(state, REASON_SHADOW_WAKES_ON_YOU)

	var new_state: GameStateScript = state.duplicate_deep()
	var events: Array = []
	if target_hour != state.player_hour or target_slot != state.player_slot:
		new_state.player_hour = target_hour
		new_state.player_slot = target_slot
		events.append({
			"type": "moved",
			"from_hour": state.player_hour, "from_slot": state.player_slot,
			"to_hour": target_hour, "to_slot": target_slot,
		})
	if burn_slot != null:
		AshTransfer.apply_burn(new_state, state.player_hour, burn_slot, events)
	new_state.action_count += 1

	if to_index != from_index:
		events.append({"type": "sun_advanced", "from_index": from_index, "to_index": to_index})
	for hour in newly_passed:
		events.append({"type": "hour_passed", "hour": hour})
	for sh in Sun.shadows_in_hours(new_state, newly_passed):
		events.append({"type": "shadow_appeared", "id": sh["id"], "hour": sh["hour"], "slot": sh["slot"]})

	events.append({"type": "action_applied", "actions_used": new_state.action_count})

	# Win beats fail (3.5): reaching the exit on the action that completes
	# the dial still wins. Terminal events come after action_applied.
	var on_tile := new_state.object_at(new_state.player_hour, new_state.player_slot)
	if on_tile.get("type") == "exit" and on_tile["state"] == GameStateScript.INTACT:
		new_state.status = GameStateScript.WON
		events.append({"type": "level_won", "actions_used": new_state.action_count})
	elif Sun.is_dial_complete(new_state):
		new_state.status = GameStateScript.FAILED
		events.append({"type": "level_failed", "reason": FAIL_DIAL_COMPLETE})
	return {"ok": true, "events": events, "state": new_state, "reason": ""}


## Every action that apply_action would accept right now, in a fixed order:
## move up/down/left/right, burn up/down/left/right, interact, wait.
## Never includes an invalid action; empty once the level is won or failed.
static func legal_actions(state: GameStateScript) -> Array:
	if state.status != GameStateScript.PLAYING:
		return []
	var candidates: Array = []
	for dir in DIRECTION_ORDER:
		candidates.append({"type": "move", "dir": dir})
	for dir in DIRECTION_ORDER:
		candidates.append({"type": "burn", "dir": dir})
	candidates.append({"type": "interact"})
	candidates.append({"type": "wait"})
	return candidates.filter(func(action): return apply_action(state, action)["ok"])


## True if the sun has passed `hour` (section 3.5). See core/sun.gd.
static func is_hour_passed(state: GameStateScript, hour: int) -> bool:
	return Sun.is_hour_passed(state, hour)


static func _reject(state: GameStateScript, reason: String) -> Dictionary:
	return {
		"ok": false,
		"events": [{"type": "action_rejected", "reason": reason}],
		"state": state,
		"reason": reason,
	}
