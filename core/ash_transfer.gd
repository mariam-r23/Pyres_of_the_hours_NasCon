extends RefCounted
## Burning and ash links (PROJECT_CONTEXT.md 3.3 and 3.4).
## No Nodes, graphics, audio or UI.
##
## turn_manager.gd calls check_burn() on the untouched input state, and only
## if it returns "" calls apply_burn() on its fresh copy.

const GameStateScript := preload("res://core/game_state.gd")
const Walkability := preload("res://core/walkability.gd")

const REASON_NOTHING_TO_BURN := "nothing_to_burn"
const REASON_NOT_INTACT := "not_intact"
const REASON_NOT_FLAMMABLE := "not_flammable"
const REASON_ASH_TARGET_OCCUPIED := "ash_target_occupied"

## Objects created by an ash link get the id "<source id>" + ASH_ID_SUFFIX.
const ASH_ID_SUFFIX := "_ash"


## "" if the object at (hour, slot) can be burned, otherwise the reason.
## Reads `state` only.
static func check_burn(state: GameStateScript, hour: int, slot: Vector2i) -> String:
	var obj := state.object_at(hour, slot)  # {} for an empty slot, off the grid, or GONE
	if obj.is_empty():
		return REASON_NOTHING_TO_BURN
	if obj["state"] != GameStateScript.INTACT:
		return REASON_NOT_INTACT
	if not obj["flammable"]:
		return REASON_NOT_FLAMMABLE
	if obj.has("ash_link"):
		var link: Dictionary = obj["ash_link"]
		if not state.object_at(link["hour"], link["slot"]).is_empty():
			return REASON_ASH_TARGET_OCCUPIED
		if state.player_hour == link["hour"] and state.player_slot == link["slot"]:
			return REASON_ASH_TARGET_OCCUPIED
		# TODO(step 8): also ash_target_occupied if an ACTIVE shadow is on the link target.
	return ""


## Burns the object at (hour, slot) in `state` (which the caller owns) and
## appends the events. Call only after check_burn() returned "".
static func apply_burn(state: GameStateScript, hour: int, slot: Vector2i, events: Array) -> void:
	var obj := state.object_at(hour, slot)
	# 1. The target becomes ASH and stays in place. ASH cannot burn again,
	#    so its ash link fires exactly once.
	obj["state"] = GameStateScript.ASH
	events.append({"type": "burned", "id": obj["id"], "hour": hour, "slot": slot})

	# 2. Its ash link spawns a new INTACT object (fixed data, never random).
	if obj.has("ash_link"):
		var link: Dictionary = obj["ash_link"]
		var id: String = obj["id"] + ASH_ID_SUFFIX
		state.objects[id] = {
			"id": id,
			"type": link["becomes"],
			"hour": link["hour"],
			"slot": link["slot"],
			"state": GameStateScript.INTACT,
			"flammable": Walkability.DEFAULT_FLAMMABLE.get(link["becomes"], false),
		}
		events.append({
			"type": "ash_moved",
			"from_hour": hour, "to_hour": link["hour"], "to_slot": link["slot"],
			"becomes": link["becomes"],
		})

	# 3. TODO(step 8): destroy every ACTIVE shadow in the same hour in the
	#    4-neighbourhood of `slot` (not `slot` itself, clarification 5): set
	#    "destroyed" = true and emit shadow_destroyed {id, hour}. Dormant
	#    shadows are not affected.
