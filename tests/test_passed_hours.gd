extends "res://tests/test_suite.gd"
## Tests for passed-hour rendering (room_view.gd room_mood / grade / soot) and
## the shadow animation queue (fx_queue.gd).

const GS := preload("res://core/game_state.gd")
const Loader := preload("res://core/level_loader.gd")
const GameSession := preload("res://core/game_session.gd")
const RoomViewScript := preload("res://presentation/room_view.gd")
const RippleScript := preload("res://presentation/ripple_camera.gd")
const FxQueueScript := preload("res://presentation/fx_queue.gd")

const L01_PATH := "res://tests/fixtures/L01_first_crate.json"
const WAIT := {"type": "wait"}


## L01 with one hour per action, so each wait passes an hour.
func _one_hour_per_action() -> GS:
	var s: GS = Loader.load_file(L01_PATH)["state"]
	s.actions_per_hour = 1
	return s


func _mood(passed: bool, current: bool, depth: int) -> Dictionary:
	return {"passed": passed, "current": current, "depth": depth}


func test_room_mood_before_and_after_the_sun_passes() -> bool:
	var s := _one_hour_per_action()
	check_eq(RoomViewScript.room_mood(s, 12), _mood(false, true, 0), "start: the sun is on 12")
	check_eq(RoomViewScript.room_mood(s, 2), _mood(false, false, 0), "start: 2 is ahead")
	s.action_count = 1
	check_eq(RoomViewScript.room_mood(s, 12), _mood(true, false, 1), "12 just passed")
	check_eq(RoomViewScript.room_mood(s, 2), _mood(false, true, 0), "the sun is on 2")
	s.action_count = 3
	check_eq(RoomViewScript.room_mood(s, 12), _mood(true, false, 3), "12 passed 3 hours ago")
	check_eq(RoomViewScript.room_mood(s, 2), _mood(true, false, 2), "2 passed 2 hours ago")
	check_eq(RoomViewScript.room_mood(s, 4), _mood(true, false, 1), "4 just passed")
	check_eq(RoomViewScript.room_mood(s, 6), _mood(false, true, 0), "the sun is on 6")
	s.action_count = 6
	check_eq(RoomViewScript.room_mood(s, 10), _mood(true, false, 1), "dial complete: 10 passed")
	check(not RoomViewScript.room_mood(s, 12)["current"], "no current room once the dial is complete")
	return true


func test_depth_darkens_but_stays_playable() -> bool:
	var current := RoomViewScript.grade_for(_mood(false, true, 0))
	var ahead := RoomViewScript.grade_for(_mood(false, false, 0))
	check(current["brightness"] > ahead["brightness"], "the current room is brighter")
	var previous := ahead
	for depth in range(1, 7):
		var g := RoomViewScript.grade_for(_mood(true, false, depth))
		check(g["brightness"] <= previous["brightness"], "depth %d is not lighter" % depth)
		check(g["emission"] <= previous["emission"], "depth %d glows no more" % depth)
		check(g["soot"] >= previous["soot"], "depth %d has at least as much soot" % depth)
		check(g["brightness"] >= RoomViewScript.GRADE["passed_brightness_min"], "depth %d still readable" % depth)
		previous = g
	check(RoomViewScript.grade_for(_mood(true, false, 3))["brightness"] < RoomViewScript.grade_for(_mood(true, false, 1))["brightness"],
		"depth 3 is visibly darker than depth 1")
	return true


func test_undo_restores_the_earlier_mood() -> bool:
	var session := GameSession.new(_one_hour_per_action())
	for i in 3:
		session.perform(WAIT)
	check_eq(RoomViewScript.room_mood(session.current_state(), 12)["depth"], 3, "depth 3 after 3 hours")
	session.undo()
	check_eq(RoomViewScript.room_mood(session.current_state(), 12), _mood(true, false, 2), "undo: depth 2")
	session.undo()
	session.undo()
	check_eq(RoomViewScript.room_mood(session.current_state(), 12), _mood(false, true, 0), "back to the start")
	return true


func test_room_refresh_snaps_to_the_grade() -> bool:
	var s := _one_hour_per_action()
	var room: Node3D = RoomViewScript.new()
	room.refresh(s, 12)
	check_eq(room.grade_shown(), RoomViewScript.grade_for(_mood(false, true, 0)), "current grade at start")
	s.action_count = 2
	room.refresh(s, 12, [], true)  # not in a tree: snaps even when asked to animate
	check_eq(room.grade_shown(), RoomViewScript.grade_for(_mood(true, false, 2)), "passed grade (depth 2)")
	room.free()
	return true


func test_soot_is_deterministic() -> bool:
	var grid := Vector2i(5, 5)
	var a := RoomViewScript.soot_spots(4, 6, grid)
	var b := RoomViewScript.soot_spots(4, 6, grid)
	check_eq(a, b, "same hour, same soot")
	check_eq(a.size(), 6, "count")
	check(RoomViewScript.soot_spots(6, 6, grid) != a, "another hour gets other soot")
	check_eq(RoomViewScript.soot_spots(4, 3, grid), a.slice(0, 3), "more depth adds specks, keeps the old ones")
	for spot in a:
		check(spot["slot"].x >= 0 and spot["slot"].x < 5 and spot["slot"].y >= 0 and spot["slot"].y < 5, "inside the grid")
	return true


func test_animations_wait_for_the_ripple_and_drop_on_undo() -> bool:
	var ripple: Node3D = RippleScript.new()
	var queue := FxQueueScript.new()
	queue.blocker = ripple
	ripple.play(RippleScript.plan_shot(12, 2, Vector2i(2, 2)))
	queue.push({"kind": "rise", "hour": 2, "id": "sh_1"})
	queue.push({"kind": "dissipate", "hour": 12, "id": "sh_2", "ghost": null})
	check_eq(queue.take_ready(), [], "nothing plays during the shot")
	check_eq(queue.hidden_shadow_ids(), ["sh_1"], "the rising shadow is held back from drawing")
	ripple.advance(5.0)  # the shot finishes
	var ready := queue.take_ready()
	check_eq(ready.map(func(i): return i["kind"]), ["rise", "dissipate"], "both play after ripple_finished")
	check_eq(queue.size(), 0, "queue empty")
	ripple.play(RippleScript.plan_shot(12, 2, Vector2i(2, 2)))
	queue.push({"kind": "rise", "hour": 2, "id": "sh_3"})
	var dropped := queue.drop()  # undo / restart / level load
	ripple.cancel()
	check_eq(dropped.size(), 1, "undo drops the queued animation")
	check_eq(queue.take_ready(), [], "nothing left to play after the shot")
	check_eq(queue.hidden_shadow_ids(), [], "nothing held back")
	ripple.free()
	return true


func test_room_skips_shadows_waiting_to_rise_and_knows_their_slots() -> bool:
	var s: GS = Loader.load_file(L01_PATH)["state"]
	s.shadows["sh_1"] = {"id": "sh_1", "hour": 2, "slot": Vector2i(3, 1)}
	var room: Node3D = RoomViewScript.new()
	room.refresh(s, 2)
	check(room.shadow_node("sh_1") != null, "drawn normally")
	check_eq(room.last_shadow_slot("sh_1"), Vector2i(3, 1), "slot remembered for a dissipate ghost")
	room.refresh(s, 2, [], false, ["sh_1"])
	check(room.shadow_node("sh_1") == null, "not drawn while waiting to rise")
	check_eq(room.last_shadow_slot("nope"), Vector2i(-1, -1), "unknown shadow")
	check(room.add_shadow_ghost(Vector2i(-1, -1)) == null, "no ghost without a slot")
	room.free()
	return true
