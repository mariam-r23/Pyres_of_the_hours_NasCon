extends RefCounted
## Holds shadow animations (rise / dissipate) while the ripple shot plays and
## releases them once it is over. Undo, restart and level load drop them.
## No game rules: it only orders presentation effects.
##
## Items are Dictionaries: {"kind": "rise", "hour", "id"} or
## {"kind": "dissipate", "hour", "id", "ghost": Node3D}.

## Object with is_playing() (the ripple camera), or null (never blocked).
var blocker: Object = null
var _items: Array = []


func push(item: Dictionary) -> void:
	_items.append(item)


## All queued items if nothing blocks them (the queue is then empty);
## [] while the ripple shot plays.
func take_ready() -> Array:
	if blocker != null and blocker.is_playing():
		return []
	var ready := _items
	_items = []
	return ready


## Shadow ids waiting to rise: views do not draw them yet, so a shadow does
## not appear before its rise plays.
func hidden_shadow_ids() -> Array:
	var ids: Array = []
	for item in _items:
		if item["kind"] == "rise":
			ids.append(item["id"])
	return ids


## Drops everything (undo, restart, level load). Returns the dropped items so
## the caller can free any ghost nodes.
func drop() -> Array:
	var dropped := _items
	_items = []
	return dropped


func size() -> int:
	return _items.size()
