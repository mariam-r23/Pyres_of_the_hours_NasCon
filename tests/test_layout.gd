extends "res://tests/test_suite.gd"
## Layout: the ring of rooms fills the screen, rooms never overlap each other
## or the hub, and from the overview camera no room is under the HUD (title
## column, sun dial, action bar) or Cinder's dialogue box, at 16:9 and at the
## canvas sizes other window shapes expand to. Uses a real Camera3D in a
## SubViewport, so the projection is Godot's own.

const RippleScript := preload("res://presentation/ripple_camera.gd")
const ClockLayoutScript := preload("res://presentation/clock_layout.gd")
const Hud := preload("res://ui/hud.gd")
const DialogueBox := preload("res://ui/dialogue_box.gd")

const HOURS := [12, 2, 4, 6, 8, 10]
## Half a 5x5 room plus the active-room rim, and the heights that matter
## (floor tiles to the top of a crate or the player).
const ROOM_HALF := 2.75
const LOW := -0.15
const HIGH := 1.0

## Canvas sizes (expand mode never goes below 1920x1080): 1920x1080, 1280x720
## and 1600x900 are all 16:9; 1366x768 is a hair wider; 1280x800 (16:10) expands
## to 1920x1200; a 21:9 window to about 2520x1080.
const CANVASES := [Vector2i(1920, 1080), Vector2i(1921, 1080), Vector2i(1920, 1200), Vector2i(2520, 1080)]


func _overview_camera(size: Vector2i) -> Array:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	Engine.get_main_loop().root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	var lens := RippleScript.lens_for_aspect(float(size.x) / size.y)
	camera.keep_aspect = lens["keep_aspect"]
	camera.fov = lens["fov"]
	camera.position = RippleScript.OVERVIEW_POSITION
	camera.look_at(RippleScript.OVERVIEW_LOOK)
	camera.current = true
	return [viewport, camera]


func _room_rect(camera: Camera3D, hour: int) -> Rect2:
	var center := ClockLayoutScript.hour_to_room_position(hour)
	var rect := Rect2()
	var first := true
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			for y in [LOW, HIGH]:
				var p := camera.unproject_position(center + Vector3(sx * ROOM_HALF, y, sz * ROOM_HALF))
				if first:
					rect = Rect2(p, Vector2.ZERO)
					first = false
				else:
					rect = rect.expand(p)
	return rect


func _dialogue_rect(size: Vector2) -> Rect2:
	return Rect2(0, size.y - 24.0 - DialogueBox.BOX_SIZE.y, 24.0 + DialogueBox.BOX_SIZE.x, 24.0 + DialogueBox.BOX_SIZE.y)


func test_rooms_stay_clear_of_the_hud_at_every_canvas() -> bool:
	for size in CANVASES:
		var pair := _overview_camera(size)
		var camera: Camera3D = pair[1]
		var zones := Hud.reserved_rects(Vector2(size))
		zones["dialogue"] = _dialogue_rect(Vector2(size))
		var screen := Rect2(Vector2.ZERO, Vector2(size))
		for hour in HOURS:
			var r := _room_rect(camera, hour)
			check(screen.encloses(r), "%s: room %d is fully on screen (%s)" % [str(size), hour, str(r)])
			for zone in zones:
				check(not r.intersects(zones[zone]), "%s: room %d is clear of the %s (%s vs %s)" % [str(size), hour, zone, str(r), str(zones[zone])])
		pair[0].queue_free()
		Engine.get_main_loop().root.remove_child(pair[0])
	return true


func test_the_ring_fills_most_of_a_16_9_screen() -> bool:
	var pair := _overview_camera(Vector2i(1920, 1080))
	var camera: Camera3D = pair[1]
	var top := INF
	var bottom := -INF
	for hour in HOURS:
		var r := _room_rect(camera, hour)
		top = minf(top, r.position.y)
		bottom = maxf(bottom, r.end.y)
	var share := (bottom - top) / 1080.0
	check(share >= 0.85 and share <= 0.92, "the ring uses %.0f%% of the height" % (share * 100.0))
	var room_width := _room_rect(camera, 12).size.x
	check(room_width > 240.0, "a room is big on screen (%.0f px wide)" % room_width)
	pair[0].queue_free()
	Engine.get_main_loop().root.remove_child(pair[0])
	return true


func test_rooms_do_not_overlap_each_other_or_the_hub() -> bool:
	var half := 2.5  # a 5x5 room without its rim
	for i in HOURS.size():
		var a := ClockLayoutScript.hour_to_room_position(HOURS[i])
		var b := ClockLayoutScript.hour_to_room_position(HOURS[(i + 1) % HOURS.size()])
		var gap := maxf(absf(a.x - b.x), absf(a.z - b.z)) - 2.0 * half
		check(gap >= 1.0, "rooms %d and %d are %.2f apart" % [HOURS[i], HOURS[(i + 1) % HOURS.size()], gap])
		# Along the hand's ray toward this room, the room edge is past the hand's tip.
		var to_edge := ClockLayoutScript.RADIUS - half / maxf(absf(sin(ClockLayoutScript.hour_angle(HOURS[i]))), absf(cos(ClockLayoutScript.hour_angle(HOURS[i]))))
		var tip := ClockLayoutScript.HAND_LENGTH + ClockLayoutScript.HAND_TIP_LENGTH
		check(to_edge > tip + 0.4, "the hand (tip %.1f) stays off room %d (edge %.2f)" % [tip, HOURS[i], to_edge])
	return true


func test_lens_keeps_the_design_framing() -> bool:
	var wide := RippleScript.lens_for_aspect(16.0 / 9.0)
	check_eq(wide["keep_aspect"], Camera3D.KEEP_HEIGHT, "16:9 keeps the height")
	check(is_equal_approx(wide["fov"], RippleScript.FOV), "with the design FOV")
	check_eq(RippleScript.lens_for_aspect(21.0 / 9.0)["keep_aspect"], Camera3D.KEEP_HEIGHT, "wider keeps the height too")
	var tall := RippleScript.lens_for_aspect(16.0 / 10.0)
	check_eq(tall["keep_aspect"], Camera3D.KEEP_WIDTH, "narrower keeps the width")
	var expected := 2.0 * rad_to_deg(atan(tan(deg_to_rad(RippleScript.FOV / 2.0)) * 16.0 / 9.0))
	check(is_equal_approx(tall["fov"], expected), "the same horizontal field as 16:9 (%.1f)" % tall["fov"])
	return true


func test_hud_zones_hug_the_edges() -> bool:
	for size in [Vector2(1920, 1080), Vector2(1920, 1200), Vector2(2520, 1080)]:
		var zones := Hud.reserved_rects(size)
		var screen := Rect2(Vector2.ZERO, size)
		for zone in zones:
			check(screen.encloses(zones[zone]), "%s: the %s zone is on screen" % [str(size), zone])
		check(is_equal_approx(zones["dial"].end.x, size.x), "%s: the dial is at the right edge" % str(size))
		check(is_equal_approx(zones["bar"].get_center().y, size.y / 2.0), "%s: the bar is centered vertically" % str(size))
	return true
