extends "res://tests/test_suite.gd"
## Tests for the shadow creatures (shadow_figure.gd and its use in room_view.gd):
## deterministic variants, dormant vs active glow, dissolve frees the ghost, and
## undo restores the right state.

const GS := preload("res://core/game_state.gd")
const Loader := preload("res://core/level_loader.gd")
const ShadowFigure := preload("res://presentation/shadow_figure.gd")
const RoomViewScript := preload("res://presentation/room_view.gd")

const L01_PATH := "res://tests/fixtures/L01_first_crate.json"


func _state_with_shadow(hour: int) -> GS:
	var s: GS = Loader.load_file(L01_PATH)["state"]
	s.actions_per_hour = 1
	s.shadows["sh_a"] = {"id": "sh_a", "hour": hour, "slot": Vector2i(3, 3)}
	return s


func test_variant_is_deterministic_and_varied() -> bool:
	for id in ["sh_1", "sh_2", "shadow_long_name", ""]:
		check_eq(ShadowFigure.variant_for(id), ShadowFigure.variant_for(id), "same id, same look: '%s'" % id)
	var indexes := {}
	var flips := {}
	for i in 12:
		var v := ShadowFigure.variant_for("sh_%d" % i)
		indexes[v["index"]] = true
		flips[v["flip"]] = true
		check(v["scale"] >= 0.85 and v["scale"] <= 1.1, "a modest size change (%.2f)" % v["scale"])
	check(indexes.size() >= 2, "a group of shadows uses more than one variant (%d)" % indexes.size())
	check_eq(flips.size(), 2, "some face left, some right")
	check_eq(ShadowFigure.id_hash("sh_1"), ShadowFigure.id_hash("sh_1"), "the hash is stable")
	return true


func test_dormant_and_active_glow() -> bool:
	var dormant := ShadowFigure.state_look(false)
	var active := ShadowFigure.state_look(true)
	check(dormant["glow"] <= 0.2, "dormant eyes almost off (%.2f)" % dormant["glow"])
	check(is_equal_approx(active["glow"], 1.0), "active eyes lit")
	check(dormant["opacity"] < 0.5, "dormant is mostly see-through")
	check(is_equal_approx(active["opacity"], 1.0), "active is solid")
	check(dormant["speed"] < active["speed"], "dormant smoke barely moves")
	check_eq(dormant["breathing"], 0.0, "no breathing pulse while asleep")
	var figure: Node3D = ShadowFigure.new()
	figure.setup("sh_1", false, RoomViewScript.COLORS)
	check(is_equal_approx(figure.glow_level, dormant["glow"]), "a dormant figure's glow_level")
	figure.set_active(true)
	check(is_equal_approx(figure.glow_level, 1.0), "waking lights the eyes")
	figure.glow_level = 5.0
	check(is_equal_approx(figure.glow_level, 1.0), "glow_level stays in 0..1")
	figure.free()
	return true


func test_shadow_ember_is_dimmer_than_fire() -> bool:
	var ember: Color = RoomViewScript.COLORS["shadow_tip"]
	var fire: Color = RoomViewScript.COLORS["fire"]
	check(ember.s < fire.s and ember.v < fire.v, "shadow embers are duller than Cinder's fire")
	return true


func test_room_draws_figures_dormant_until_their_hour_passes() -> bool:
	var s := _state_with_shadow(12)
	var room: Node3D = RoomViewScript.new()
	room.refresh(s, 12)
	var figure: Node3D = room.shadow_node("sh_a")
	check(figure != null and figure.has_method("set_active"), "a shadow figure, not a capsule")
	check(not figure.active, "dormant before its hour passes")
	s.action_count = 1  # 12 passes
	room.refresh(s, 12)
	check(room.shadow_node("sh_a").active, "active once its hour has passed")
	s.action_count = 0  # undo
	room.refresh(s, 12)
	check(not room.shadow_node("sh_a").active, "undo puts it back to sleep")
	check(is_equal_approx(room.shadow_node("sh_a").glow_level, ShadowFigure.DORMANT["glow"]), "with its eyes dimmed again")
	room.free()
	return true


func test_destroyed_shadow_leaves_no_nodes() -> bool:
	var s := _state_with_shadow(12)
	var room: Node3D = RoomViewScript.new()
	Engine.get_main_loop().root.add_child(room)
	room.refresh(s, 12)
	var ghost: Node3D = room.add_shadow_ghost(room.last_shadow_slot("sh_a"), "sh_a")
	check(ghost != null and ghost.active, "the ghost is the awake creature")
	RoomViewScript.dissipate_ghost(ghost)
	check(ghost.dissolving, "it starts breaking apart")
	ghost.advance_dissolve(ShadowFigure.DISSOLVE_TIME * 0.5)
	check(is_instance_valid(ghost) and not ghost.is_queued_for_deletion(), "still there half way")
	ghost.advance_dissolve(ShadowFigure.DISSOLVE_TIME)
	check(ghost.is_queued_for_deletion(), "freed when the dissolve ends")
	check(is_equal_approx(ShadowFigure.dissolve_at(ShadowFigure.DISSOLVE_TIME), 1.0), "fully dissolved at the end")
	Engine.get_main_loop().root.remove_child(room)
	room.free()
	return true


func test_a_ghost_outside_the_tree_is_freed_at_once() -> bool:
	var figure: Node3D = ShadowFigure.new()
	figure.setup("x", true, RoomViewScript.COLORS)
	RoomViewScript.dissipate_ghost(figure)
	check(not is_instance_valid(figure), "no tree, no animation: freed immediately")
	return true
