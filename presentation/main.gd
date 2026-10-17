extends Node3D
## Root of the game. Builds everything in code at runtime: camera, light,
## environment, the GameController, the clock of six rooms, and a minimal
## text overlay. Redraws from the session's state after every change.
## Holds no game rules.

const ControllerScript := preload("res://presentation/game_controller.gd")
const ClockLayoutScript := preload("res://presentation/clock_layout.gd")
const EventBusScript := preload("res://presentation/event_bus.gd")
const RoomViewScript := preload("res://presentation/room_view.gd")
const LevelList := preload("res://presentation/level_list.gd")
const RippleCameraScript := preload("res://presentation/ripple_camera.gd")
const SpiritDirectorScript := preload("res://presentation/spirit_director.gd")
const FxQueueScript := preload("res://presentation/fx_queue.gd")
const Progress := preload("res://presentation/menus/progress.gd")
const MainMenuScript := preload("res://presentation/menus/main_menu.gd")
const LevelSelectScript := preload("res://presentation/menus/level_select.gd")
const PauseMenuScript := preload("res://presentation/menus/pause_menu.gd")
const CreditsScript := preload("res://presentation/menus/credits.gd")
const MenuStyle := preload("res://presentation/menus/menu_style.gd")

## What the screen is doing. Game input reaches the controller only in PLAYING.
const MODE_MENU := "menu"                  # main menu over the clock
const MODE_PLAYING := "playing"
const MODE_PAUSED := "paused"
const MODE_LEVEL_SELECT := "level_select"
const MODE_CREDITS := "credits"

const RETURN_PROMPT := "\n\nPress Enter to return to the main menu."
const Sun := preload("res://core/sun.gd")

const WON_NEXT_TEXT := "You reached the exit.\nPress N for the next level, R to restart."
const WON_LAST_TEXT := "That was the last level for now.\nPress R to restart."
const FAILED_TEXT := "The dial completed.\nPress R to restart or Z to undo."
const NO_LEVELS_TEXT := "No levels found in levels/data/."
const CONTROLS_TEXT := "Arrows / WASD: move    B then a direction: burn    E: interact    Space: wait\nZ: undo    R: restart    N: next level (after a win)    [ ]: previous / next level"
const BURN_HINT := "Burn: choose a direction (Escape cancels)"
const STAIR_HINT := "Press E to use the stair."

## Friendly line for every rejection reason (clarification 11, plus undo's
## nothing_to_undo). An unmapped reason is shown as its raw string.
const REJECTION_MESSAGES := {
	"out_of_bounds": "That is the edge of the room.",
	"blocked_terrain": "A wall or a gap blocks the way.",
	"blocked_object": "Something is in the way.",
	"shadow_blocks": "A shadow blocks the way. Fire can destroy it.",
	"not_on_stair": "Stand on a stair to use it.",
	"arrival_blocked": "The way out of the stair is blocked.",
	"nothing_to_burn": "Nothing to burn there.",
	"not_flammable": "That will not burn.",
	"not_intact": "That is already burned.",
	"ash_target_occupied": "The ash has nowhere to land.",
	"shadow_wakes_on_you": "A shadow would wake on you. Do something else.",
	"level_over": "The level is over. Z undoes, R restarts.",
	"unknown_action": "That does nothing.",
	"nothing_to_undo": "Nothing to undo.",
}
## Seconds the rejection line stays fully visible, then fades.
const FEEDBACK_HOLD := 1.0
const FEEDBACK_FADE := 0.5
## The HUD (status, hint, controls) fades out during the ripple shot.
const HUD_FADE_TIME := 0.15

## Spirit speech placeholder (ui/ can replace it by listening to spirit_said):
## stays SPEECH_MIN_TIME s, longer for long lines, then fades.
const SPEECH_MIN_TIME := 3.5
const SPEECH_TIME_PER_CHAR := 0.05
const SPEECH_FADE := 0.6

## Placeholder ending prompt / lines until Mariam's ending screen (ui/) exists.
## Debug fallback: while the choice is pending, 1 = wind, 2 = burn.
const ENDING_DEBUG_TEXT := "Choose the ending:\n1 = wind the clock    2 = let it burn"
const ENDING_TEXTS := {
	"wind": "You wind the clock. The day goes on, and she goes out.",
	"burn": "You let it burn. She is free, and the hours are gone.",
}

## Cold, dark world (see room_view.gd COLORS for the color rule).
const BACKGROUND := Color(0.035, 0.045, 0.065)
const AMBIENT := Color(0.45, 0.52, 0.62)
const FOG := Color(0.10, 0.12, 0.16)
const LIGHT := Color(0.80, 0.86, 0.95)
const TEXT_COLOR := Color(0.65, 0.70, 0.78)
const HINT_COLOR := Color(0.80, 0.88, 0.96)

var controller: Node
var clock: Node3D
var bus: Node
var ripple: Node3D
var director: Node
## Id of the level being played ("" before the first load) and its meta.
var level_id := ""
var level_meta := {}
var _message: Label
var _hint: Label
var _status: Label
var _context: Label
var _feedback: Label
var _feedback_tween: Tween
var _hud_tween: Tween
var _refresh_queued := false
## [hour, slot] pairs the ripple camera revealed; popped after the next redraw.
var _pending_pops: Array = []
var _speech: Label
var _speech_mood: Label
var _speech_tween: Tween
var _loading_path := ""
## The placeholder ending line once a choice is made ("" before).
var _ending_text := ""
## Shadow rise / dissipate animations, held while the ripple shot plays.
var fx := FxQueueScript.new()
## Screen mode (MODE_*), and where Level Select / Credits go back to.
var mode := MODE_MENU
var _back_mode := MODE_MENU
## True once a level was started from a menu (the HUD shows only then).
var _in_game := false
## Saved progress (presentation/menus/progress.gd). Tests point the path elsewhere.
var progress_path := Progress.PATH
var progress := {}
var level_ids: Array = []
var _menu_layer: CanvasLayer
var _hud_layer: CanvasLayer
var _open_menu: Control = null
var _return_button: Button
## True once the ending choice was made: Enter returns to the main menu.
var _ending_done := false
## True when the next redraw should tween passed-hour grades (an hour passed).
var _animate_grades := false


func _ready() -> void:
	_build_world()
	clock = ClockLayoutScript.new()
	clock.name = "Clock"
	add_child(clock)

	controller = ControllerScript.new()
	controller.name = "GameController"
	add_child(controller)
	bus = get_node_or_null("/root/EventBus")
	if bus == null:
		push_warning("main: EventBus autoload is not registered; using a private bus")
		bus = EventBusScript.new()
		add_child(bus)
	controller.bus = bus

	# The ripple camera owns the game camera and plays the burn -> ash shot.
	ripple = RippleCameraScript.new()
	ripple.name = "RippleCamera"
	ripple.bus = bus
	add_child(ripple)
	# Keys reach the controller only while playing and no ripple shot runs.
	controller.blocker = InputGate.new([ripple.is_playing, func(): return mode != MODE_PLAYING])
	for type in ["undo_done", "level_loaded"]:
		bus.connect(type, func(_arg): ripple.cancel())
	bus.level_restarted.connect(ripple.cancel)
	ripple.hidden_slots_changed.connect(_queue_refresh)
	ripple.slot_revealed.connect(_on_slot_revealed)
	# ui/ listens to the bus, never to the camera.
	ripple.ripple_started.connect(func(): bus.ripple_started.emit())
	ripple.ripple_finished.connect(func(): bus.ripple_finished.emit())

	# The fire spirit: which trigger speaks when (lines come from dialogue/).
	director = SpiritDirectorScript.new()
	director.name = "SpiritDirector"
	director.connect_bus(bus)
	director.connect_ripple(ripple)
	add_child(director)

	# Passed hours tween to their new grade; shadows rise and dissipate.
	fx.blocker = ripple
	bus.hour_passed.connect(func(_event): _animate_grades = true)
	bus.shadow_appeared.connect(func(event): fx.push({"kind": "rise", "hour": event["hour"], "id": event["id"]}))
	bus.shadow_destroyed.connect(_on_shadow_destroyed)
	ripple.ripple_finished.connect(_queue_refresh)  # play what the shot held back
	bus.undo_done.connect(func(_event): _snap_and_drop_fx())
	bus.level_restarted.connect(_snap_and_drop_fx)
	bus.level_loaded.connect(func(_meta): _snap_and_drop_fx())

	_build_ui()
	ripple.ripple_started.connect(func(): fade_hud(0.0, HUD_FADE_TIME))
	ripple.ripple_finished.connect(_on_ripple_finished)
	# Every event of one action lands in the same frame; redraw once after them.
	for type in ["action_applied", "action_rejected", "undo_done", "shadow_appeared",
			"shadow_destroyed", "level_won", "level_failed"]:
		bus.connect(type, func(_event): _queue_refresh())
	bus.action_rejected.connect(func(event): show_feedback(rejection_message(event.get("reason", ""))))
	# A valid action makes an old rejection line stale; clear it at once.
	bus.action_applied.connect(func(_event): hide_feedback())
	bus.undo_done.connect(func(_event): hide_feedback())
	bus.level_loaded.connect(_on_level_loaded)
	bus.level_restarted.connect(_queue_refresh)
	bus.spirit_said.connect(show_speech)
	bus.ending_chosen.connect(_on_ending_chosen)
	bus.undo_done.connect(func(_event): _ending_text = "")
	bus.level_restarted.connect(func(): _ending_text = "")
	controller.burn_mode_changed.connect(_on_burn_mode_changed)

	level_ids = LevelList.all().map(func(e): return e["id"])
	progress = Progress.load_from(progress_path, level_ids)
	bus.level_won.connect(_on_level_won_progress)
	bus.undo_done.connect(func(_event): _ending_done = false)
	bus.level_restarted.connect(func(): _ending_done = false)

	# The first level stays loaded behind the main menu as a backdrop.
	var first = LevelList.first()
	if first == null:
		_show_message(NO_LEVELS_TEXT)
	else:
		load_entry(first)
	show_main_menu()


## Something with is_playing(): true while any check says input is blocked.
class InputGate:
	var checks: Array

	func _init(p_checks: Array) -> void:
		checks = p_checks

	func is_playing() -> bool:
		for check in checks:
			if check.call():
				return true
		return false


# --- Menus -----------------------------------------------------------------

func show_main_menu() -> void:
	ripple.cancel()
	_in_game = false
	_ending_done = false
	_set_mode(MODE_MENU)
	var menu: Control = MainMenuScript.new()
	menu.show_continue = Progress.has_progress(progress)
	menu.chosen.connect(_on_main_menu)
	_open(menu)


func _on_main_menu(action: String) -> void:
	match action:
		"continue":
			start_level(Progress.continue_level(progress, level_ids))
		"new_game":
			# Starts the first level; earlier progress stays (nothing is wiped).
			start_level(level_ids[0] if not level_ids.is_empty() else "")
		"level_select":
			open_level_select(MODE_MENU)
		"credits":
			open_credits(MODE_MENU)
		"quit":
			get_tree().quit()


## True if `id` is a known level that progress has unlocked.
func can_start(id: String) -> bool:
	return level_ids.has(id) and Progress.is_unlocked(progress, id)


## Starts an unlocked level from a menu. Returns false (and does nothing) for
## a locked or unknown level.
func start_level(id: String) -> bool:
	if not can_start(id):
		return false
	var entry := {"id": id, "path": LevelList.DEFAULT_DIR.path_join(id + ".json")}
	_close_menu()
	_in_game = true
	_set_mode(MODE_PLAYING)
	load_entry(entry)
	return true


func pause() -> void:
	if mode != MODE_PLAYING:
		return
	ripple.skip()  # a shot in progress ends cleanly (arrival revealed)
	controller.cancel_burn_mode()
	_set_mode(MODE_PAUSED)
	var menu: Control = PauseMenuScript.new()
	menu.chosen.connect(_on_pause_menu)
	_open(menu)


func resume() -> void:
	if mode != MODE_PAUSED:
		return
	_close_menu()
	_set_mode(MODE_PLAYING)
	director.note_activity()


func _on_pause_menu(action: String) -> void:
	match action:
		"resume":
			resume()
		"restart":
			resume()
			controller.restart()
		"level_select":
			open_level_select(MODE_PAUSED)
		"main_menu":
			show_main_menu()


func open_level_select(back_to: String) -> void:
	_back_mode = back_to
	_set_mode(MODE_LEVEL_SELECT)
	var menu: Control = LevelSelectScript.new()
	menu.rows = LevelSelectScript.build_rows(LevelList.all(), progress)
	menu.chosen.connect(_on_level_select)
	_open(menu)


func _on_level_select(action: String, id: String) -> void:
	if action == "start":
		start_level(id)
	else:
		go_back()


func open_credits(back_to: String) -> void:
	_back_mode = back_to
	_set_mode(MODE_CREDITS)
	var menu: Control = CreditsScript.new()
	menu.chosen.connect(func(_action): go_back())
	_open(menu)


## Level Select / Credits: back to where they were opened from.
func go_back() -> void:
	if _back_mode == MODE_PAUSED:
		_set_mode(MODE_PLAYING)  # pause() needs PLAYING
		pause()
	else:
		show_main_menu()


## What Escape does right now: "cancel_burn" (the controller handles it),
## "pause", "resume", "back" or "none".
func escape_action() -> String:
	match mode:
		MODE_PLAYING:
			return "cancel_burn" if controller.burn_mode else "pause"
		MODE_PAUSED:
			return "resume"
		MODE_LEVEL_SELECT, MODE_CREDITS:
			return "back"
	return "none"


## Runs before the controller (and the GUI) sees the key: Escape order is
## burn mode first, then pause. The ripple camera, a child, consumes keys
## during a shot before this runs.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		match escape_action():
			"pause":
				pause()
			"resume":
				resume()
			"back":
				go_back()
			_:
				return  # cancel_burn: let the controller have it
		get_viewport().set_input_as_handled()
	elif _ending_done and mode == MODE_PLAYING and key.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		show_main_menu()
		get_viewport().set_input_as_handled()


func _set_mode(new_mode: String) -> void:
	mode = new_mode
	director.suspended = mode != MODE_PLAYING
	if _hud_layer != null:
		_hud_layer.visible = _in_game
	if mode != MODE_PLAYING:
		controller.cancel_burn_mode()


func _open(menu: Control) -> void:
	_close_menu()
	_open_menu = menu
	_menu_layer.add_child(menu)


func _close_menu() -> void:
	if _open_menu != null and is_instance_valid(_open_menu):
		_open_menu.queue_free()
	_open_menu = null


## Progress is written only when a level is won.
func _on_level_won_progress(event: Dictionary) -> void:
	if level_id == "":
		return
	progress = Progress.record_win(progress, level_id, int(event["actions_used"]), level_ids)
	Progress.save_to(progress_path, progress)


## Progression keys. The controller sees keys first (it is a child) and
## lets through the ones it does not use.
func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or mode != MODE_PLAYING:
		return
	# Debug fallback for the ending choice until ui/ has its screen.
	if director.ending_pending and key.keycode in [KEY_1, KEY_2]:
		bus.ending_chosen.emit("wind" if key.keycode == KEY_1 else "burn")
		get_viewport().set_input_as_handled()
		return
	var target = null
	match key.keycode:
		KEY_N:
			var state = controller.current_state()
			if state != null and state.status == "won":
				target = LevelList.next_of(level_id)
		KEY_BRACKETRIGHT:
			target = LevelList.next_of(level_id)
		KEY_BRACKETLEFT:
			target = LevelList.previous_of(level_id)
	if target != null:
		load_entry(target)
		get_viewport().set_input_as_handled()


## Loads a {id, path} level. On failure the error is shown and the current
## level keeps playing. Returns the error list ([] on success).
func load_entry(entry: Dictionary) -> Array:
	ripple.cancel()
	var previous_id := level_id
	level_id = entry["id"]
	_loading_path = entry["path"]
	var errors: Array = controller.load_level(entry["path"])
	if not errors.is_empty():
		level_id = previous_id
		_show_message("Could not load %s:\n%s" % [entry["id"], "\n".join(PackedStringArray(errors))])
	return errors


## The centered message for a level status ("" while playing).
static func end_message(status: String, has_next_level: bool) -> String:
	match status:
		"won":
			return WON_NEXT_TEXT if has_next_level else WON_LAST_TEXT
		"failed":
			return FAILED_TEXT
	return ""


## What ui/ needs for the HUD, sent as hud_changed after every redraw.
static func hud_info(id: String, meta: Dictionary, state) -> Dictionary:
	return {
		"level_id": id,
		"title": meta.get("title", ""),
		"actions_used": state.action_count,
		"par": meta.get("par_actions", -1),
		"sun_index": Sun.sun_index(state),
		"sun_hour": ClockLayoutScript.sun_hour(state),
		"status": state.status,
	}


## Friendly text for a rejection reason; the raw reason if it is not mapped.
static func rejection_message(reason: String) -> String:
	return REJECTION_MESSAGES.get(reason, reason)


## The hint under the status label: burn mode first, then "stand on a stair",
## else "". Reads the state only (what is on the player's tile).
static func context_hint(state, burn_mode: bool) -> String:
	if state == null or state.status != "playing":
		return ""
	if burn_mode:
		return BURN_HINT
	if state.object_at(state.player_hour, state.player_slot).get("type") == "stair":
		return STAIR_HINT
	return ""


## Top-left status: level, actions / par, sun, spirit mood.
static func status_text(meta: Dictionary, id: String, state) -> String:
	var title: String = meta.get("title", "")
	var par: int = meta.get("par_actions", -1)
	return "\n".join(PackedStringArray([
		"%s (%s)" % [title, id] if title != "" else id,
		"Actions: %d / par %s" % [state.action_count, str(par) if par >= 0 else "-"],
		sun_text(state),
		"Spirit: %s" % meta.get("spirit_mood", "amused"),
	]))


## Which hour the sun is on, and how many actions until it moves on.
## Reads core/sun.gd only; makes up no rules.
static func sun_text(state) -> String:
	if Sun.is_dial_complete(state):
		return "Sun: dial complete"
	var now := Sun.sun_index(state)
	var steps := 1
	while Sun.sun_index_at(state, state.action_count + steps) == now:
		steps += 1
	return "Sun: %d o'clock, moves on in %d action%s" % [
		ClockLayoutScript.sun_hour(state), steps, "" if steps == 1 else "s"]


func _on_level_loaded(meta: Dictionary) -> void:
	level_meta = meta
	_ending_text = ""
	director.start_level(level_id, meta, _loading_path)
	hide_speech()
	_queue_refresh()


func _queue_refresh() -> void:
	if not _refresh_queued:
		_refresh_queued = true
		_refresh.call_deferred()


func _refresh() -> void:
	_refresh_queued = false
	var state = controller.current_state()
	if state == null:
		return
	# The hidden set is read here, at draw time, so a redraw during the shot
	# can never show the arriving ash object early. Shadow animations wait
	# for the shot too (take_ready() is empty while it plays).
	var animations := fx.take_ready()
	clock.refresh_all(state, ripple.hidden_slots(), _animate_grades, fx.hidden_shadow_ids())
	_animate_grades = false
	for item in animations:
		if item["kind"] == "rise":
			clock.room_for_hour(item["hour"]).rise_shadow(item["id"])
		else:
			RoomViewScript.dissipate_ghost(item["ghost"])
	for pop in _pending_pops:
		if not ripple.is_slot_hidden(pop[0], pop[1]):
			clock.pop_slot(pop[0], pop[1])
	_pending_pops = []
	ripple.grid_size = Vector2i(state.grid_w, state.grid_h)
	if state.status == "won" and level_id == SpiritDirectorScript.ENDING_LEVEL_ID:
		# The ending level: ui/ shows the choice (ending_choice_requested);
		# until it exists, a debug prompt, then the placeholder ending line.
		if _ending_text != "":
			_show_message(_ending_text)
		else:
			_show_message(ENDING_DEBUG_TEXT if director.ending_pending else "")
	else:
		_show_message(end_message(state.status, LevelList.next_of(level_id) != null))
	_status.text = status_text(level_meta, level_id, state)
	_update_context_hint()
	_return_button.visible = _ending_done
	bus.hud_changed.emit(hud_info(level_id, level_meta, state))


## Shows a short line near the bottom center, then fades it out.
func show_feedback(text: String) -> void:
	if _feedback_tween != null:
		_feedback_tween.kill()
	_feedback.text = text
	_feedback.modulate.a = 1.0
	_feedback.visible = true
	_feedback_tween = create_tween()
	_feedback_tween.tween_interval(FEEDBACK_HOLD)
	_feedback_tween.tween_property(_feedback, "modulate:a", 0.0, FEEDBACK_FADE)
	_feedback_tween.tween_callback(func(): _feedback.visible = false)


## Placeholder speech line at the top center with a small mood tag.
func show_speech(_trigger: String, mood: String, text: String) -> void:
	if _speech_tween != null:
		_speech_tween.kill()
	_speech.text = text
	_speech_mood.text = mood
	for label in [_speech, _speech_mood]:
		label.modulate.a = 1.0
		label.visible = true
	if not is_inside_tree():
		return
	var hold := maxf(SPEECH_MIN_TIME, text.length() * SPEECH_TIME_PER_CHAR)
	_speech_tween = create_tween()
	_speech_tween.tween_interval(hold)
	_speech_tween.set_parallel(true)
	_speech_tween.tween_property(_speech, "modulate:a", 0.0, SPEECH_FADE)
	_speech_tween.tween_property(_speech_mood, "modulate:a", 0.0, SPEECH_FADE)
	_speech_tween.chain().tween_callback(hide_speech)


func hide_speech() -> void:
	if _speech_tween != null:
		_speech_tween.kill()
		_speech_tween = null
	_speech.visible = false
	_speech_mood.visible = false


func _on_ending_chosen(choice: String) -> void:
	if ENDING_TEXTS.has(choice):
		_ending_text = ENDING_TEXTS[choice] + RETURN_PROMPT
		_ending_done = true
		_queue_refresh()


## The shadow is already gone from the state: keep a ghost where it stood
## (its slot from the last redraw) and let it dissipate.
func _on_shadow_destroyed(event: Dictionary) -> void:
	var room: Node3D = clock.room_for_hour(event["hour"])
	var ghost: Node3D = room.add_shadow_ghost(room.last_shadow_slot(event["id"]))
	if ghost != null:
		fx.push({"kind": "dissipate", "hour": event["hour"], "id": event["id"], "ghost": ghost})


## Undo, restart, level load: grades snap, queued shadow animations go.
func _snap_and_drop_fx() -> void:
	_animate_grades = false
	for item in fx.drop():
		if item.has("ghost") and is_instance_valid(item["ghost"]):
			item["ghost"].queue_free()


func _on_slot_revealed(hour: int, slot: Vector2i) -> void:
	_pending_pops.append([hour, slot])
	_queue_refresh()


## Fades back in after a finished shot; skip or cancel restore at once.
func _on_ripple_finished() -> void:
	if ripple.last_stop_reason == RippleCameraScript.STOP_FINISHED:
		fade_hud(1.0, HUD_FADE_TIME)
	else:
		fade_hud(1.0, 0.0)


## Fades the status label, context hint and controls text (not the
## rejection feedback) to `alpha` over `seconds` (0 = at once).
func fade_hud(alpha: float, seconds: float) -> void:
	if _hud_tween != null:
		_hud_tween.kill()
		_hud_tween = null
	var labels := [_status, _context, _hint]
	if seconds <= 0.0 or not is_inside_tree():
		for label in labels:
			label.modulate.a = alpha
		return
	_hud_tween = create_tween().set_parallel(true)
	for label in labels:
		_hud_tween.tween_property(label, "modulate:a", alpha, seconds)


func hide_feedback() -> void:
	if _feedback_tween != null:
		_feedback_tween.kill()
	_feedback.visible = false


func _update_context_hint() -> void:
	_context.text = context_hint(controller.current_state(), controller.burn_mode)
	_context.visible = _context.text != ""


func _show_message(text: String) -> void:
	_message.text = text
	_message.visible = text != ""


func _on_burn_mode_changed(_active: bool) -> void:
	_update_context_hint()


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACKGROUND
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = FOG
	env.fog_density = 0.012
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.1
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)

	var sun_light := DirectionalLight3D.new()
	sun_light.light_color = LIGHT
	sun_light.light_energy = 1.1
	sun_light.shadow_enabled = true
	sun_light.rotation_degrees = Vector3(-55, 30, 0)
	add_child(sun_light)
	# The camera lives in ripple_camera.gd (overview pose and the ripple shot).


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud_layer = layer
	_menu_layer = CanvasLayer.new()
	_menu_layer.layer = 10  # menus above the HUD
	add_child(_menu_layer)

	# After the ending: a clickable way back too (Enter also works).
	_return_button = MenuStyle.button("Return to main menu", 1.0)
	_return_button.theme = MenuStyle.theme(1.0)
	_return_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_return_button.offset_top = -150
	_return_button.offset_bottom = -110
	_return_button.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_return_button.visible = false
	_return_button.pressed.connect(show_main_menu)
	layer.add_child(_return_button)

	_message = Label.new()
	# Centered over the dial hub, the one empty spot between the rooms.
	_message.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_message.grow_vertical = Control.GROW_DIRECTION_BOTH
	_message.add_theme_constant_override("outline_size", 8)
	_message.add_theme_color_override("font_outline_color", BACKGROUND)
	_message.add_theme_font_size_override("font_size", 28)
	_message.add_theme_color_override("font_color", RoomViewScript.COLORS["sun_marker"])
	_message.visible = false
	layer.add_child(_message)

	_hint = Label.new()
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.offset_left = 16
	_hint.offset_bottom = -12
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", TEXT_COLOR)
	_hint.text = CONTROLS_TEXT
	layer.add_child(_hint)

	# Spirit speech (placeholder): a small mood tag over the line, top center.
	_speech_mood = Label.new()
	_speech_mood.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_speech_mood.offset_top = 14
	_speech_mood.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speech_mood.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_speech_mood.add_theme_font_size_override("font_size", 13)
	_speech_mood.add_theme_color_override("font_color", TEXT_COLOR)
	_speech_mood.visible = false
	layer.add_child(_speech_mood)
	_speech = Label.new()
	_speech.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_speech.offset_left = -540
	_speech.offset_right = 540
	_speech.offset_top = 32
	_speech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_speech.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speech.add_theme_font_size_override("font_size", 22)
	_speech.add_theme_color_override("font_color", HINT_COLOR)
	_speech.add_theme_constant_override("outline_size", 6)
	_speech.add_theme_color_override("font_outline_color", BACKGROUND)
	_speech.visible = false
	layer.add_child(_speech)

	_status = Label.new()
	_status.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_status.offset_left = 16
	_status.offset_top = 12
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", TEXT_COLOR)
	layer.add_child(_status)

	# Just under the four status lines.
	_context = Label.new()
	_context.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_context.offset_left = 16
	_context.offset_top = 112
	_context.add_theme_font_size_override("font_size", 17)
	_context.add_theme_color_override("font_color", HINT_COLOR)
	_context.visible = false
	layer.add_child(_context)

	# Bottom center, above the controls text.
	_feedback = Label.new()
	_feedback.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_feedback.offset_bottom = -64
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_feedback.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_feedback.add_theme_font_size_override("font_size", 20)
	_feedback.add_theme_color_override("font_color", HINT_COLOR)
	_feedback.add_theme_constant_override("outline_size", 6)
	_feedback.add_theme_color_override("font_outline_color", BACKGROUND)
	_feedback.visible = false
	layer.add_child(_feedback)
