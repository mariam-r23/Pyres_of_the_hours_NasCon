extends Control
## Cinder's dialogue box: a bottom panel with her portrait, name, a typewriter
## line and (for the priority lines) her voice. It listens to
## EventBus.spirit_said, which presentation/spirit_director.gd raises once per
## action after dialogue/dialogue_picker.gd chose the line (triggers on_burn,
## on_ash_moved, on_shadow_appeared, on_shadow_destroyed, on_undo, on_solve,
## on_fail, on_idle, and the act 3 ones). It never blocks input.
##
## Voice: audio/voice/cinder_<line id>.mp3, only for the 18 priority lines; every
## other line is text only. Her laugh (every ash_moved) is spirit_laugh.gd, and a
## line waits for it there, so it never starts on top of the laugh.
## Every file is optional: nothing here fails when one is missing.

const UiTheme := preload("res://ui/ui_theme.gd")
const Icons := preload("res://ui/icons.gd")

const SPIRIT_NAME := "Cinder"
const LINES_PATH := "res://dialogue/lines.json"
const VOICE_DIR := "res://audio/voice/"
const PORTRAIT_DIR := "res://art/portraits/"
const MOODS := ["amused", "annoyed", "menacing", "triumphant"]
const DEFAULT_MOOD := "amused"

## Seconds a text-only line stays, and how long the voice box outlasts the audio.
const TEXT_ONLY_BOX_TIME := 4.0
const VOICE_TAIL := 0.5
## The typewriter finishes at this fraction of the audio length (a bit before it ends).
const VOICE_TYPE_FRACTION := 0.8
const TEXT_ONLY_CHARS_PER_SECOND := 32.0
## At most one text-only line per this many seconds.
const TEXT_THROTTLE := 1.5
const FADE_OUT := 0.4
## Triggers that may cut a voice line short (a win or fail, and the story beats
## that replace on_solve or follow the ending choice).
const INTERRUPTING := ["on_solve", "on_fail", "on_choice", "on_reveal", "on_ending_wind", "on_ending_burn"]

## Bottom left, narrow enough to stay clear of the 6 o'clock room and the action bar.
const BOX_SIZE := Vector2(800, 276)
const PORTRAIT_SLOT := Vector2(260, 250)

static var _id_by_text: Dictionary = {}

var bus: Node = null
var act := 1
## Time bookkeeping for decide(): when the current voice ends, when the last text-only line began.
var gate := {"voice_until": -100.0, "last_text_at": -100.0}

var name_label: Label
var mood_label: Label
var text_label: Label
var portrait_rect: TextureRect
var silhouette: Control
var voice_player: AudioStreamPlayer
## What is on screen: the current line, how long it has been up and its timings.
var current_line_id := ""
var current_mood := DEFAULT_MOOD
var current_has_voice := false
var active := false

var _elapsed := 0.0
var _plan := {"box_time": 0.0, "type_time": 0.0}
var _fading := false
var _audio_cache: Dictionary = {}
var _texture_cache: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	visible = false


func setup(new_bus: Node) -> void:
	bus = new_bus
	bus.spirit_said.connect(show_line)
	bus.level_loaded.connect(func(meta): act = int(meta.get("act", 1)); stop())
	bus.level_restarted.connect(stop)


# --- Pure functions (tested without a window) ----------------------------------

static func voice_path(line_id: String) -> String:
	return "%scinder_%s.mp3" % [VOICE_DIR, line_id]


## art/portraits/spirit_portrait_<mood>.jpeg; an unknown mood uses the default.
static func portrait_path(mood: String) -> String:
	var m := mood if mood in MOODS else DEFAULT_MOOD
	return "%sspirit_portrait_%s.jpeg" % [PORTRAIT_DIR, m]


## How long the box stays and how long the typewriter takes. audio_length <= 0
## means a text-only line: about 4 s. With a voice, the box outlasts the audio
## by 0.5 s and the text is typed in 80% of the audio.
static func display_plan(audio_length: float, text: String) -> Dictionary:
	if audio_length > 0.0:
		return {"box_time": audio_length + VOICE_TAIL, "type_time": audio_length * VOICE_TYPE_FRACTION}
	var type_time := minf(text.length() / TEXT_ONLY_CHARS_PER_SECOND, TEXT_ONLY_BOX_TIME - 1.0)
	return {"box_time": TEXT_ONLY_BOX_TIME, "type_time": type_time}


## How many characters the typewriter shows after `elapsed` seconds.
static func visible_chars(total: int, elapsed: float, type_time: float) -> int:
	if type_time <= 0.0 or elapsed >= type_time:
		return total
	return clampi(int(floor(total * maxf(elapsed, 0.0) / type_time)), 0, total)


## Whether a line may start now. `state` holds voice_until (when the current
## voice ends) and last_text_at (when the last text-only line began), both in
## seconds on the same clock as `now`.
##  - while a voice line plays, only INTERRUPTING triggers may start;
##  - text-only lines are throttled to one per TEXT_THROTTLE seconds.
static func can_start(state: Dictionary, trigger: String, has_voice: bool, now: float) -> bool:
	if now < float(state.get("voice_until", -100.0)) and not (trigger in INTERRUPTING):
		return false
	if not has_voice and now - float(state.get("last_text_at", -100.0)) < TEXT_THROTTLE:
		return false
	return true


## The line id whose text is `text` ("" for an AI-written or unknown text).
static func line_id_for_text(text: String) -> String:
	if _id_by_text.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(LINES_PATH))
		if typeof(data) == TYPE_DICTIONARY:
			for l in data.get("lines", []):
				_id_by_text[str(l["text"])] = str(l["id"])
	return str(_id_by_text.get(text, ""))


# --- Showing a line -------------------------------------------------------------

## Handles one spirit_said. Returns true if the line was shown.
func show_line(trigger: String, mood: String, text: String) -> bool:
	var id := line_id_for_text(text)
	var stream: AudioStream = _audio(voice_path(id)) if id != "" else null
	var has_voice := stream != null
	var now := _now()
	if not can_start(gate, trigger, has_voice, now):
		return false
	_stop_audio()
	current_line_id = id
	current_has_voice = has_voice
	current_mood = mood if mood in MOODS else DEFAULT_MOOD
	var audio_length := stream.get_length() if has_voice else 0.0
	_plan = display_plan(audio_length, text)
	if has_voice:
		gate["voice_until"] = now + audio_length
		voice_player.stream = stream
		voice_player.play()
	else:
		gate["last_text_at"] = now
	_apply_portrait(current_mood)
	name_label.text = SPIRIT_NAME
	mood_label.text = current_mood
	text_label.text = text
	text_label.visible_characters = 0
	_elapsed = 0.0
	_fading = false
	modulate.a = 1.0
	active = true
	visible = true
	return true


## Hides the box and silences her (level change, restart).
func stop() -> void:
	_stop_audio()
	gate["voice_until"] = -100.0
	active = false
	_fading = false
	visible = false


func _process(delta: float) -> void:
	if not active:
		return
	advance(delta)


## Moves the box's clock forward (the typewriter, then the fade-out). _process calls it.
func advance(delta: float) -> void:
	_elapsed += delta
	text_label.visible_characters = visible_chars(text_label.text.length(), _elapsed, _plan["type_time"])
	var over: float = _elapsed - float(_plan["box_time"])
	if over >= 0.0:
		_fading = true
		modulate.a = clampf(1.0 - over / FADE_OUT, 0.0, 1.0)
		if over >= FADE_OUT:
			active = false
			visible = false


func _stop_audio() -> void:
	voice_player.stop()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Loads an AudioStream if the file is there, else null (never fails).
func _audio(path: String) -> AudioStream:
	if _audio_cache.has(path):
		return _audio_cache[path]
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is AudioStream:
			stream = res
	_audio_cache[path] = stream
	return stream


# --- Portrait ---------------------------------------------------------------------

## The one swap point: the real portrait for `mood`, or the silhouette if its file
## is missing.
func _apply_portrait(mood: String) -> void:
	var tex: Texture2D = _portrait_texture(mood)
	portrait_rect.texture = tex
	portrait_rect.visible = tex != null
	silhouette.visible = tex == null


func _portrait_texture(mood: String) -> Texture2D:
	var path := portrait_path(mood)
	if _texture_cache.has(path):
		return _texture_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			tex = res
	_texture_cache[path] = tex
	return tex


# --- Build ------------------------------------------------------------------------

func _build() -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.color("panel"), UiTheme.color("shadow_dark"), 12))
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 24
	panel.offset_right = 24 + BOX_SIZE.x
	panel.offset_bottom = -24
	panel.offset_top = -24 - BOX_SIZE.y
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(panel)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 20)
	panel.add_child(row)

	# Portrait slot: the picture is scaled to cover it, cropped, never stretched.
	var slot := PanelContainer.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.custom_minimum_size = PORTRAIT_SLOT
	slot.clip_contents = true
	slot.add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.color("background"), UiTheme.color("shadow_dark"), 0))
	row.add_child(slot)
	portrait_rect = TextureRect.new()
	portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	portrait_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slot.add_child(portrait_rect)
	silhouette = Icons.new()
	silhouette.kind = "burn"
	silhouette.color = UiTheme.color("shadow_light")
	silhouette.line_width = 5.0
	silhouette.custom_minimum_size = PORTRAIT_SLOT
	slot.add_child(silhouette)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	row.add_child(col)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 16)
	col.add_child(head)
	name_label = UiTheme.label(SPIRIT_NAME, "heading", 34)
	# Cinder's emphasis (her mood word) is the one warm thing in the box.
	mood_label = UiTheme.label("", "emphasis", 30, UiTheme.color("ember"))
	mood_label.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(name_label)
	head.add_child(mood_label)
	text_label = UiTheme.label("", "body", 38)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	col.add_child(text_label)

	voice_player = AudioStreamPlayer.new()
	voice_player.name = "VoicePlayer"
	add_child(voice_player)
