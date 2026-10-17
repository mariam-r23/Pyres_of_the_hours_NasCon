extends "res://tests/test_suite.gd"
## Tests for core/game_state.gd: data, duplicate_deep() and hash_key().

const GS := preload("res://core/game_state.gd")


## A state shaped like L01 (PROJECT_CONTEXT.md 6.1), built by hand
## because the level loader does not exist yet.
func _make_state() -> GS:
	var s: GS = GS.new()
	s.level_id = "L01_first_crate"
	s.terrain[2] = ["..~..", "..~..", "..~..", "..~..", "..~.."]
	s.player_hour = 12
	s.player_slot = Vector2i(0, 2)
	s.objects["crate_a"] = {
		"id": "crate_a", "type": "crate", "hour": 12, "slot": Vector2i(2, 2),
		"state": GS.INTACT, "flammable": true,
		"ash_link": {"hour": 2, "slot": Vector2i(2, 2), "becomes": "ash_path"},
	}
	s.objects["stair_12"] = {
		"id": "stair_12", "type": "stair", "hour": 12, "slot": Vector2i(4, 2),
		"state": GS.INTACT, "flammable": false,
		"links_to": {"hour": 2, "slot": Vector2i(0, 2)},
	}
	s.objects["exit_1"] = {
		"id": "exit_1", "type": "exit", "hour": 2, "slot": Vector2i(4, 2),
		"state": GS.INTACT, "flammable": false,
	}
	s.shadows["sh_1"] = {"id": "sh_1", "hour": 2, "slot": Vector2i(3, 1)}
	return s


func test_defaults() -> bool:
	var s: GS = GS.new()
	check_eq(s.grid_w, 5, "grid_w")
	check_eq(s.grid_h, 5, "grid_h")
	check_eq(s.actions_per_hour, 3, "actions_per_hour")
	check_eq(s.action_count, 0, "action_count")
	check_eq(s.terrain.size(), 6, "terrain has every hour")
	for hour in GS.HOUR_ORDER:
		check_eq(s.terrain[hour], [".....", ".....", ".....", ".....", "....."], "hour %d is all floor" % hour)
	return true


func test_order_index() -> bool:
	check_eq(GS.order_index(12), 0, "12")
	check_eq(GS.order_index(2), 1, "2")
	check_eq(GS.order_index(10), 5, "10")
	check_eq(GS.order_index(3), -1, "not an hour")
	return true


func test_terrain_and_grid() -> bool:
	var s := _make_state()
	check(s.in_grid(Vector2i(0, 0)), "0,0 in grid")
	check(s.in_grid(Vector2i(4, 4)), "4,4 in grid")
	check(not s.in_grid(Vector2i(5, 0)), "5,0 outside")
	check(not s.in_grid(Vector2i(0, -1)), "0,-1 outside")
	check_eq(s.terrain_at(2, Vector2i(2, 3)), GS.CHASM, "chasm in hour 2")
	check_eq(s.terrain_at(2, Vector2i(1, 3)), GS.FLOOR, "floor in hour 2")
	check_eq(s.terrain_at(12, Vector2i(5, 5)), "", "outside grid")
	return true


func test_object_and_shadow_lookup() -> bool:
	var s := _make_state()
	check_eq(s.object_at(12, Vector2i(2, 2)).get("id"), "crate_a", "crate found")
	check(s.object_at(2, Vector2i(2, 2)).is_empty(), "empty slot")
	s.objects["crate_a"]["state"] = GS.GONE
	check(s.object_at(12, Vector2i(2, 2)).is_empty(), "GONE counts as empty")
	check_eq(s.shadow_at(2, Vector2i(3, 1)).get("id"), "sh_1", "shadow found")
	s.shadows.erase("sh_1")
	check(s.shadow_at(2, Vector2i(3, 1)).is_empty(), "destroyed (removed) shadow is gone")
	return true


func test_duplicate_deep_is_equal() -> bool:
	var s := _make_state()
	s.action_count = 4
	var c := s.duplicate_deep()
	check_eq(c.hash_key(), s.hash_key(), "copy has the same hash")
	check_eq(c.player_slot, s.player_slot, "player slot copied")
	check_eq(c.level_id, s.level_id, "level id copied")
	return true


func test_duplicate_deep_shares_nothing() -> bool:
	var s := _make_state()
	var before := s.hash_key()
	var c := s.duplicate_deep()
	c.objects["crate_a"]["state"] = GS.ASH
	c.objects["crate_a"]["ash_link"]["becomes"] = "bridge"
	c.objects["stair_12"]["links_to"]["hour"] = 4
	c.shadows.erase("sh_1")
	c.terrain[2][0] = "#####"
	c.objects["new"] = {"id": "new", "type": "ash_path", "hour": 2, "slot": Vector2i(2, 2), "state": GS.INTACT, "flammable": false}
	c.player_slot = Vector2i(1, 2)
	c.action_count = 9
	c.won = true
	check_eq(s.hash_key(), before, "original unchanged after editing the copy")
	check_eq(s.objects["crate_a"]["state"], GS.INTACT, "object state")
	check_eq(s.objects["crate_a"]["ash_link"]["becomes"], "ash_path", "nested ash_link")
	check_eq(s.terrain[2][0], "..~..", "terrain row")
	check_eq(s.objects.size(), 3, "object count")
	return true


func test_hash_key_detects_changes() -> bool:
	var base := _make_state().hash_key()
	var edits := {
		"player slot": func(s: GS): s.player_slot = Vector2i(1, 2),
		"player hour": func(s: GS): s.player_hour = 2,
		"action count": func(s: GS): s.action_count = 1,
		"object state": func(s: GS): s.objects["crate_a"]["state"] = GS.ASH,
		"shadow destroyed": func(s: GS): s.shadows.erase("sh_1"),
		"won": func(s: GS): s.won = true,
		"failed": func(s: GS): s.failed = true,
		"fail reason": func(s: GS): s.fail_reason = "dial_complete",
		"terrain": func(s: GS): s.terrain[12][0] = "#....",
		"new object": func(s: GS): s.objects["p"] = {"id": "p", "type": "ash_path", "hour": 2, "slot": Vector2i(2, 2), "state": GS.INTACT, "flammable": false},
	}
	for label in edits:
		var s := _make_state()
		edits[label].call(s)
		check(s.hash_key() != base, "hash changes on: " + label)
	return true


func test_hash_key_ignores_insertion_order() -> bool:
	var a := _make_state()
	var b := _make_state()
	b.objects = {}
	for id in ["exit_1", "stair_12", "crate_a"]:
		b.objects[id] = a.objects[id].duplicate(true)
	check_eq(b.hash_key(), a.hash_key(), "same objects in a different order")
	return true


func test_hash_key_is_stable() -> bool:
	var s := _make_state()
	check_eq(s.hash_key(), s.hash_key(), "same state, same key")
	check_eq(_make_state().hash_key(), s.hash_key(), "two identical builds, same key")
	return true
