extends RefCounted
## Validates and applies one action (PROJECT_CONTEXT.md 3.3, 6.2 and 11).
## No Nodes, graphics, audio or UI.
##
## apply_action(state, action) NEVER modifies `state`:
##   valid    -> { ok: true,  events: [..., action_applied], state: <new deep copy>, reason: "" }
##   rejected -> { ok: false, events: [action_rejected],     state: <the same input>, reason: "..." }
## Rejected actions are free: no counter change, no sun, no snapshot.
##
## Implemented so far: move, wait, interact (stairs).
## Still to come: burn + ash transfer, sun, shadows, win/fail (see TODOs).

const GameStateScript := preload("res://core/game_state.gd")
const Walkability := preload("res://core/walkability.gd")

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
const REASON_UNKNOWN_ACTION := "unknown_action"


static func apply_action(state: GameStateScript, action: Variant) -> Dictionary:
	# TODO(step 10): if state.won or state.failed, reject with "level_over".
	if typeof(action) != TYPE_DICTIONARY:
		return _reject(state, REASON_UNKNOWN_ACTION)

	# Validate against the untouched input first, so a rejection costs no copy.
	var reason := ""
	var target_hour := state.player_hour
	var target_slot := state.player_slot
	match action.get("type"):
		"move":
			var dir = action.get("dir")
			if not DIRECTIONS.has(dir):
				return _reject(state, REASON_UNKNOWN_ACTION)
			target_slot = state.player_slot + DIRECTIONS[dir]
			reason = Walkability.check_walkable(state, target_hour, target_slot)["reason"]
			# TODO(step 8): reject with "shadow_blocks" if an active shadow is on the target.
		"interact":
			var stair := state.object_at(state.player_hour, state.player_slot)
			if stair.get("type") != "stair":
				return _reject(state, REASON_NOT_ON_STAIR)
			if not stair.has("links_to"):
				return _reject(state, REASON_ARRIVAL_BLOCKED)
			target_hour = stair["links_to"]["hour"]
			target_slot = stair["links_to"]["slot"]
			if not Walkability.is_walkable(state, target_hour, target_slot):
				reason = REASON_ARRIVAL_BLOCKED
			# TODO(step 8): also "arrival_blocked" if an active shadow is on the arrival slot.
		"wait":
			pass
		# TODO(step 5b/6): "burn" by direction: nothing_to_burn, not_intact, not_flammable,
		# ash_target_occupied; then ash transfer and shadow destruction (core/ash_transfer.gd).
		_:
			return _reject(state, REASON_UNKNOWN_ACTION)
	if reason != "":
		return _reject(state, reason)

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
	new_state.action_count += 1

	# TODO(step 8): reject with "shadow_wakes_on_you" (returning the input state) if the
	# new sun index would wake a shadow on the player's tile. Applies to wait too.
	# TODO(step 7): sun_index from action_count; emit sun_advanced, hour_passed and
	# shadow_appeared when the index changes.
	# TODO(step 10): player on exit -> won + level_won; else sun_index >= 6 ->
	# failed + level_failed (reason "dial_complete").

	events.append({"type": "action_applied", "actions_used": new_state.action_count})
	return {"ok": true, "events": events, "state": new_state, "reason": ""}


## Every action that apply_action would accept right now, in a fixed order:
## move up/down/left/right, interact, wait. Never includes an invalid action.
static func legal_actions(state: GameStateScript) -> Array:
	var candidates: Array = []
	for dir in DIRECTION_ORDER:
		candidates.append({"type": "move", "dir": dir})
	# TODO(step 5b/6): burn in each direction.
	candidates.append({"type": "interact"})
	candidates.append({"type": "wait"})
	return candidates.filter(func(action): return apply_action(state, action)["ok"])


static func _reject(state: GameStateScript, reason: String) -> Dictionary:
	return {
		"ok": false,
		"events": [{"type": "action_rejected", "reason": reason}],
		"state": state,
		"reason": reason,
	}
