extends "res://tests/test_suite.gd"
## Tests for player feedback in presentation/main.gd: rejection messages and
## the context hint (stair / burn mode). Pure functions only, no window.

const GS := preload("res://core/game_state.gd")
const Loader := preload("res://core/level_loader.gd")
const MainScript := preload("res://presentation/main.gd")
const RoomViewScript := preload("res://presentation/room_view.gd")

## Every reason core/ can send (clarification 11) plus undo's nothing_to_undo.
const ALL_REASONS := [
	"out_of_bounds", "blocked_terrain", "blocked_object", "shadow_blocks",
	"not_on_stair", "arrival_blocked",
	"nothing_to_burn", "not_flammable", "not_intact", "ash_target_occupied",
	"shadow_wakes_on_you", "level_over", "unknown_action", "nothing_to_undo",
]


func _l01() -> GS:
	return Loader.load_file("res://tests/fixtures/L01_first_crate.json")["state"]


func test_every_reason_has_a_message() -> bool:
	for reason in ALL_REASONS:
		var text: String = MainScript.rejection_message(reason)
		check(text != reason and text != "", "%s has a friendly message (got \"%s\")" % [reason, text])
		check(text.ends_with("."), "%s message is a sentence" % reason)
	check_eq(MainScript.rejection_message("not_on_stair"), "Stand on a stair to use it.", "the playtest case")
	return true


func test_core_reasons_are_all_listed() -> bool:
	# Every rejection constant core/ defines must be in the test list above.
	var found := {}
	for path in ["res://core/turn_manager.gd", "res://core/ash_transfer.gd", "res://core/walkability.gd", "res://core/snapshot_stack.gd"]:
		var constants: Dictionary = load(path).get_script_constant_map()
		for name in constants:
			if name.begins_with("REASON_"):
				found[constants[name]] = true
				check(ALL_REASONS.has(constants[name]), "%s.%s (%s) is covered" % [path.get_file(), name, constants[name]])
	check(found.size() >= 12, "found the core reason constants (%d: %s)" % [found.size(), str(found.keys())])
	return true


func test_unknown_reason_falls_back_to_raw_string() -> bool:
	check_eq(MainScript.rejection_message("some_new_reason"), "some_new_reason", "raw reason")
	check_eq(MainScript.rejection_message(""), "", "empty reason")
	return true


func test_context_hint() -> bool:
	var s := _l01()  # player at [0,2] in hour 12; the stair is at [4,2]
	check_eq(MainScript.context_hint(s, false), "", "nothing to say off the stair")
	check_eq(MainScript.context_hint(s, true), "Burn: choose a direction (Escape cancels)", "burn mode")
	s.player_slot = Vector2i(4, 2)
	check_eq(MainScript.context_hint(s, false), "Press E to use the stair.", "on the stair")
	check_eq(MainScript.context_hint(s, true), "Burn: choose a direction (Escape cancels)", "burn mode wins over the stair hint")
	s.status = GS.WON
	check_eq(MainScript.context_hint(s, false), "", "no hint once the level is over")
	check_eq(MainScript.context_hint(null, true), "", "no hint without a level")
	return true


func test_new_colors_exist() -> bool:
	for key in ["stair_marker", "exit_halo", "burnable_edge"]:
		check(RoomViewScript.COLORS.has(key), "%s color is in the one color table" % key)
	return true
