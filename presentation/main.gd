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
	controller.blocker = ripple
	for type in ["undo_done", "level_loaded"]:
		bus.connect(type, func(_arg): ripple.cancel())
	bus.level_restarted.connect(ripple.cancel)
	ripple.hidden_slots_changed.connect(_queue_refresh)
	ripple.slot_revealed.connect(_on_slot_revealed)

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
	controller.burn_mode_changed.connect(_on_burn_mode_changed)

	var first = LevelList.first()
	if first == null:
		_show_message(NO_LEVELS_TEXT)
	else:
		load_entry(first)


## Progression keys. The controller sees keys first (it is a child) and
## lets through the ones it does not use.
func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
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
	# can never show the arriving ash object early.
	clock.refresh_all(state, ripple.hidden_slots())
	for pop in _pending_pops:
		if not ripple.is_slot_hidden(pop[0], pop[1]):
			clock.pop_slot(pop[0], pop[1])
	_pending_pops = []
	ripple.grid_size = Vector2i(state.grid_w, state.grid_h)
	_show_message(end_message(state.status, LevelList.next_of(level_id) != null))
	_status.text = status_text(level_meta, level_id, state)
	_update_context_hint()


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
