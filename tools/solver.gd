extends RefCounted
## Breadth-first solver for Pyre of the Hours (owner: Mariam).
## GDScript twin of reference/python/pyre_ref/solver.py. Both must give the same answers.
##
## Uses only Anosha's core API: TurnManager.legal_actions(), TurnManager.apply_action(),
## GameState.hash_key(). It never changes the rules.
##
## Usage:
##   const Solver := preload("res://tools/solver.gd")
##   var result := Solver.solve(state)           # state: a GameState from core/level_loader.gd
##   result["status"]           # "solved" | "unsolvable" | "limit"
##   result["actions"]          # shortest winning list of action dictionaries ([] if not solved)
##   result["states_explored"]  # how many distinct states were seen
##
## "unsolvable" is a PROOF: the whole reachable state space was searched (it is finite, because
## the dial completes after (6 - start_index) * actions_per_hour actions) and no win was found.
## "limit" means a cap stopped the search first, so nothing is proven either way.

const GameStateScript := preload("res://core/game_state.gd")
const TurnManager := preload("res://core/turn_manager.gd")

const DEFAULT_MAX_STATES := 200000
const DEFAULT_MAX_DEPTH := 200


## Shortest list of actions that wins, found by breadth-first search.
static func solve(start: GameStateScript, max_states: int = DEFAULT_MAX_STATES, max_depth: int = DEFAULT_MAX_DEPTH) -> Dictionary:
	if start.status == GameStateScript.WON:
		return _result("solved", [], 1)
	if start.status == GameStateScript.FAILED:
		return _result("unsolvable", [], 1)

	var start_key: String = start.hash_key()
	# state key -> { "parent": parent key, "action": the action taken } (null for the start state)
	var parents: Dictionary = {start_key: null}
	var frontier: Array = [start]
	var frontier_keys: Array = [start_key]
	var frontier_depths: Array = [0]
	var head := 0
	var depth_cut := false

	while head < frontier.size():
		var state: GameStateScript = frontier[head]
		var key: String = frontier_keys[head]
		var depth: int = frontier_depths[head]
		frontier[head] = null  # free the state once it is expanded
		head += 1
		if depth >= max_depth:
			depth_cut = true
			continue
		for action in TurnManager.legal_actions(state):
			var applied: Dictionary = TurnManager.apply_action(state, action)
			var next_state: GameStateScript = applied["state"]
			if next_state.status == GameStateScript.FAILED:
				continue
			var next_key: String = next_state.hash_key()
			if parents.has(next_key):
				continue
			parents[next_key] = {"parent": key, "action": action}
			if next_state.status == GameStateScript.WON:
				return _result("solved", _path(parents, next_key), parents.size())
			if parents.size() >= max_states:
				return _result("limit", [], parents.size())
			frontier.append(next_state)
			frontier_keys.append(next_key)
			frontier_depths.append(depth + 1)

	if depth_cut:
		return _result("limit", [], parents.size())
	return _result("unsolvable", [], parents.size())


## {"type": "move", "dir": "right"} -> "move:right"; {"type": "wait"} -> "wait".
static func action_to_string(action: Dictionary) -> String:
	if action.has("dir"):
		return "%s:%s" % [action["type"], action["dir"]]
	return str(action["type"])


## Same, for a whole list: ["move:right", "burn:right", ...].
static func actions_to_strings(actions: Array) -> Array:
	var out: Array = []
	for action in actions:
		out.append(action_to_string(action))
	return out


static func _path(parents: Dictionary, key: String) -> Array:
	var actions: Array = []
	var link = parents[key]
	while link != null:
		actions.append(link["action"])
		link = parents[link["parent"]]
	actions.reverse()
	return actions


static func _result(status: String, actions: Array, explored: int) -> Dictionary:
	return {"status": status, "actions": actions, "states_explored": explored}
