extends "res://tests/test_suite.gd"
## Tests for the pure parts of presentation/room_view.gd and
## presentation/clock_layout.gd (no window, nodes never enter a tree).

const GS := preload("res://core/game_state.gd")
const Validator := preload("res://core/level_validator.gd")
const RoomViewScript := preload("res://presentation/room_view.gd")
const ClockLayoutScript := preload("res://presentation/clock_layout.gd")

## "Saturated orange": warm hue (red through yellow-orange), strongly
## saturated AND bright. Dim embers (low value) do not count.
const WARM_HUE_MAX := 0.15   # about 54 degrees
const WARM_HUE_WRAP := 0.95  # reds just below 360 degrees
const MAX_SATURATION := 0.6
const MAX_VALUE := 0.6


func _is_saturated_orange(c: Color) -> bool:
	var warm := c.h <= WARM_HUE_MAX or c.h >= WARM_HUE_WRAP
	return warm and c.s >= MAX_SATURATION and c.v >= MAX_VALUE


func test_slot_to_position_grid_math() -> bool:
	var room: Node3D = RoomViewScript.new()
	check_eq(room.slot_to_position(Vector2i(2, 2)), Vector3(0, 0, 0), "center slot at the origin")
	check_eq(room.slot_to_position(Vector2i(0, 0)), Vector3(-2, 0, -2), "top-left")
	check_eq(room.slot_to_position(Vector2i(4, 0)), Vector3(2, 0, -2), "top-right: x grows right")
	check_eq(room.slot_to_position(Vector2i(0, 4)), Vector3(-2, 0, 2), "bottom-left: grid y grows toward +Z")
	check_eq(room.slot_to_position(Vector2i(3, 1)) - room.slot_to_position(Vector2i(2, 1)), Vector3(1, 0, 0), "1 unit per cell")
	room.free()
	return true


func test_slot_to_position_uses_slot_markers() -> bool:
	var room: Node3D = RoomViewScript.new()
	var slots := Node3D.new()
	slots.name = "Slots"
	slots.position = Vector3(0, 0.5, 0)
	room.add_child(slots)
	var marker := Marker3D.new()
	marker.name = "slot_1_3"
	marker.position = Vector3(-1.2, 0, 1.1)
	slots.add_child(marker)
	check_eq(room.slot_to_position(Vector2i(1, 3)), Vector3(-1.2, 0.5, 1.1), "marker position used")
	check_eq(room.slot_to_position(Vector2i(2, 2)), Vector3(0, 0, 0), "missing marker falls back to grid math")
	room.free()
	return true


func test_hour_positions_on_a_circle() -> bool:
	var positions: Array = []
	for hour in GS.HOUR_ORDER:
		var p: Vector3 = ClockLayoutScript.hour_to_room_position(hour)
		check(is_equal_approx(p.length(), ClockLayoutScript.RADIUS), "hour %d on the circle" % hour)
		check(is_zero_approx(p.y), "hour %d on the floor plane" % hour)
		check(not positions.any(func(q): return q.is_equal_approx(p)), "hour %d is distinct" % hour)
		positions.append(p)
	check(ClockLayoutScript.hour_to_room_position(12).is_equal_approx(Vector3(0, 0, -ClockLayoutScript.RADIUS)), "12 at the top (-Z)")
	check(ClockLayoutScript.hour_to_room_position(6).is_equal_approx(Vector3(0, 0, ClockLayoutScript.RADIUS)), "6 at the bottom")
	check(ClockLayoutScript.hour_to_room_position(2).x > 0, "2 o'clock is on the right (clockwise)")
	return true


func test_rooms_never_overlap() -> bool:
	var room_size := float(GS.DEFAULT_GRID_SIZE)
	for a in GS.HOUR_ORDER:
		for b in GS.HOUR_ORDER:
			if a == b:
				continue
			var d: Vector3 = ClockLayoutScript.hour_to_room_position(a) - ClockLayoutScript.hour_to_room_position(b)
			check(absf(d.x) >= room_size or absf(d.z) >= room_size, "rooms %d and %d do not overlap" % [a, b])
	return true


func test_sun_hour() -> bool:
	var s: GS = GS.new()
	s.actions_per_hour = 1
	var expected := [12, 2, 4, 6, 8, 10, 12]
	for count in expected.size():
		s.action_count = count
		check_eq(ClockLayoutScript.sun_hour(s), expected[count], "after %d actions" % count)
	return true


func test_only_fire_is_saturated_orange() -> bool:
	var colors: Dictionary = RoomViewScript.COLORS
	check(colors.has("fire"), "fire color exists")
	check(_is_saturated_orange(colors["fire"]), "fire IS saturated orange")
	for key in colors:
		if key != "fire":
			check(not _is_saturated_orange(colors[key]), "%s must not be saturated orange (%s)" % [key, colors[key]])
	return true


func test_object_style_covers_every_type_and_state() -> bool:
	for type in Validator.KNOWN_TYPES:
		for state in [GS.INTACT, GS.ASH]:
			var style: Dictionary = RoomViewScript.object_style(type, state)
			check(style.has("color") and style["color"] is Color, "%s %s has a color" % [type, state])
			check(style.has("emission"), "%s %s says whether it glows" % [type, state])
			if style["emission"] != null:
				check(not _is_saturated_orange(style["emission"]), "%s %s glow is not saturated orange" % [type, state])
		check(RoomViewScript.object_style(type, GS.ASH)["emission"] != null, "ASH %s glows (ember)" % type)
	check(RoomViewScript.object_style("ash_path", GS.INTACT)["emission"] != null, "ash_path is gameplay ash and glows")
	check(RoomViewScript.object_style("crate", GS.INTACT)["emission"] == null, "an INTACT crate does not glow")
	return true


func test_main_script_parses() -> bool:
	var script: GDScript = load("res://presentation/main.gd")
	check(script != null and script.can_instantiate(), "main.gd loads")
	return true
