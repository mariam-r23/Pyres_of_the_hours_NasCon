extends "res://tests/test_suite.gd"
## Tests for the painted room floors (painted_floor.gd + room_view.gd): which
## painting each hour uses, the cover crop, the grade by depth, unused rooms,
## chasm cutouts, and that undo snaps the floor back.

const GS := preload("res://core/game_state.gd")
const Loader := preload("res://core/level_loader.gd")
const PaintedFloor := preload("res://presentation/painted_floor.gd")
const RoomViewScript := preload("res://presentation/room_view.gd")

const L01_PATH := "res://tests/fixtures/L01_first_crate.json"
const PAINTING_SIZE := Vector2(2752, 1536)


func _one_hour_per_action() -> GS:
	var s: GS = Loader.load_file(L01_PATH)["state"]
	s.actions_per_hour = 1
	return s


func _mood(passed: bool, current: bool, depth: int) -> Dictionary:
	return {"passed": passed, "current": current, "depth": depth}


func _look(passed: bool, current: bool, depth: int, used: bool = true) -> Dictionary:
	return PaintedFloor.floor_look(RoomViewScript.grade_for(_mood(passed, current, depth)), used)


func _vertex_count(node: MeshInstance3D) -> int:
	return (node.mesh as ArrayMesh).surface_get_array_len(0)


func test_each_hour_maps_to_its_painting() -> bool:
	for hour in [12, 2, 4, 6, 8, 10]:
		check_eq(PaintedFloor.image_path(hour), "res://art/hours/hour_%d.jpeg" % hour, "path for hour %d" % hour)
		var tex := PaintedFloor.texture_for(hour)
		check(tex != null, "hour %d loads" % hour)
	return true


func test_textures_are_loaded_once_shared_and_mipmapped() -> bool:
	var a := PaintedFloor.texture_for(2)
	check(a == PaintedFloor.texture_for(2), "the same texture object every time")
	check(a.get_width() <= PaintedFloor.TEXTURE_WIDTH, "downscaled for a floor (%d px)" % a.get_width())
	check(a.get_image().has_mipmaps(), "with mipmaps, so a far floor does not shimmer")
	var ratio := float(a.get_width()) / a.get_height()
	check(absf(ratio - PAINTING_SIZE.x / PAINTING_SIZE.y) < 0.01, "the painting's own aspect is kept (%.3f)" % ratio)
	check(PaintedFloor.new_material(2).shader == PaintedFloor.new_material(4).shader, "one shader for every room")
	return true


func test_cover_crop_keeps_the_room_aspect_and_the_center() -> bool:
	for grid in [Vector2i(5, 5), Vector2i(5, 3), Vector2i(3, 5), Vector2i(7, 2)]:
		var r := PaintedFloor.cover_uv_rect(PAINTING_SIZE, grid)
		var shown := Vector2(r.size.x * PAINTING_SIZE.x, r.size.y * PAINTING_SIZE.y)
		check(absf(shown.x / shown.y - float(grid.x) / grid.y) < 0.001, "%s: no stretch (%.3f)" % [str(grid), shown.x / shown.y])
		check(r.get_center().is_equal_approx(Vector2(0.5, 0.5)), "%s: centered" % str(grid))
		check(r.position.x >= 0.0 and r.position.y >= 0.0 and r.end.x <= 1.0001 and r.end.y <= 1.0001, "%s: inside the image" % str(grid))
		check(is_equal_approx(r.size.x, 1.0) or is_equal_approx(r.size.y, 1.0), "%s: as large as it can be" % str(grid))
	var square := PaintedFloor.cover_uv_rect(PAINTING_SIZE, Vector2i(5, 5))
	check(is_equal_approx(square.size.y, 1.0) and absf(square.size.x - 1536.0 / 2752.0) < 0.001, "5x5 keeps the full height")
	check(PaintedFloor.corner_uv(Vector2(5, 5), Vector2i(5, 5), square).is_equal_approx(square.end), "the far corner is the crop's corner")
	return true


func test_grade_follows_depth() -> bool:
	var ahead := _look(false, false, 0)
	var current := _look(false, true, 0)
	check(current["brightness"] > ahead["brightness"], "the current hour is a bit brighter")
	check(current["brightness"] < 0.8, "but still darker than the painting itself")
	var previous := ahead
	for depth in range(1, 5):
		var look := _look(true, false, depth)
		check(look["brightness"] < previous["brightness"], "depth %d is darker (%.3f)" % [depth, look["brightness"]])
		check(look["saturation"] < previous["saturation"], "depth %d is greyer (%.3f)" % [depth, look["saturation"]])
		previous = look
	check(_look(true, false, 9)["saturation"] >= PaintedFloor.MIN_SATURATION - 0.0001, "never fully grey")
	return true


func test_unused_rooms_are_dim_without_a_grid() -> bool:
	var s := _one_hour_per_action()
	check(PaintedFloor.room_used(s, 12), "the player's room is used")
	check(PaintedFloor.room_used(s, 2), "a room with a chasm is used")
	check(not PaintedFloor.room_used(s, 6), "an empty room is not")
	var unused := _look(false, false, 0, false)
	check(unused["brightness"] < _look(false, false, 0, true)["brightness"] * 0.6, "an unused room is clearly dimmer")
	var room: Node3D = RoomViewScript.new()
	room.refresh(s, 6)
	check(room.painted_floor() != null, "it still shows its painting")
	check(room.floor_grid() == null, "with no grid")
	check(is_equal_approx(room.floor_look_shown()["brightness"], unused["brightness"]), "at the unused brightness")
	room.refresh(s, 12)
	check(room.floor_grid() != null, "a used room has its grid")
	room.free()
	return true


func test_chasms_are_cut_out_and_walls_stay_blocks() -> bool:
	var s := _one_hour_per_action()  # hour 2 is "..~.." on every row
	check_eq(PaintedFloor.painted_cells(s, 2).size(), 20, "20 floor cells, the chasm column left out")
	var room: Node3D = RoomViewScript.new()
	room.refresh(s, 2)
	check_eq(_vertex_count(room.painted_floor()), 20 * 6, "one quad per painted cell")
	s.terrain[2] = ["..#..", ".....", ".....", ".....", "....."]
	check_eq(PaintedFloor.painted_cells(s, 2).size(), 24, "a wall cell is not painted")
	check_eq(PaintedFloor.grid_edges([Vector2i(0, 0), Vector2i(1, 0)]).size(), 7, "a shared edge is drawn once")
	room.free()
	return true


func test_hour_passed_darkens_and_undo_snaps_back() -> bool:
	var s := _one_hour_per_action()
	var room: Node3D = RoomViewScript.new()
	room.refresh(s, 12)
	var start: Dictionary = room.floor_look_shown()
	check(is_equal_approx(start["brightness"], _look(false, true, 0)["brightness"]), "the current hour's look at the start")
	s.action_count = 2
	room.refresh(s, 12, [], true)  # not in a tree: snaps even when asked to animate
	check(room.floor_look_shown()["brightness"] < start["brightness"], "darker two hours later")
	check(room.floor_look_shown()["saturation"] < start["saturation"], "and greyer")
	s.action_count = 0  # undo / restart
	room.refresh(s, 12)
	check_eq(room.floor_look_shown(), start, "undo snaps back exactly")
	room.free()
	return true


func test_the_floor_material_lives_with_the_room() -> bool:
	var s := _one_hour_per_action()
	var room: Node3D = RoomViewScript.new()
	room.refresh(s, 12)
	var mat: Material = room.painted_floor().material_override
	room.refresh(s, 12)
	check(room.painted_floor().material_override == mat, "the same material across redraws (no per-refresh reload)")
	room.free()
	return true
