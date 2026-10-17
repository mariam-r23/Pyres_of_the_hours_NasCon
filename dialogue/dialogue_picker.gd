class_name DialoguePicker
extends RefCounted
## Seeded dialogue picker for the fire spirit (Cinder).
## DIALOGUE ONLY: never call this from core/. It decides which MOOD and which cached LINE to use.
## GDScript twin of reference/python/pyre_ref/dialogue.py. Both must agree on every case in
## dialogue/tests/picker_cases.json (run: dialogue/tests/run_picker_tests.gd).
##
## Usage:
##   var lines: Array = JSON.parse_string(FileAccess.get_file_as_string("res://dialogue/lines.json"))["lines"]
##   var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://dialogue/picker_config.json"))
##   var picker := DialoguePicker.new(lines, config, level_id)
##   var ctx := {"act": level.act, "spirit_mood": level.spirit_mood, "mood_weights": level.mood_weights}
##   var result := picker.say("on_burn", ctx)   # {mood, line, tier, repeated}; line is {} if none
##
## AI path: mood = picker.choose_mood(ctx); ask the model for a line in that mood, passing
## picker.recent_texts() as the "do not repeat" list, then call picker.remember(text).
##
## One call = one trigger-count step. The seed is FNV-1a of "<level_id>#<calls>", so demos are
## reproducible and no global random state is used.
##
## Line choice tiers (first tier with a fresh line wins; never a line from a LATER act):
##   0 same act, same trigger, same mood     1 same act, same trigger, any mood
##   2 same trigger, same mood, earlier act  3 same trigger, any mood, earlier act
## If everything was said recently, repeat the line said longest ago (never the one just spoken
## unless it is the only one).

var lines: Array = []
var allowed_moods: Dictionary = {}  # "1" -> ["amused", ...]
var recent_window: int = 3
var level_id: String = ""
var calls: int = 0
var recent: Array = []  # ids (or AI-written text), oldest first


## xorshift32: shifts and xors only, so it matches Python exactly.
class Rng:
	var s: int = 0

	func _init(seed_value: int) -> void:
		s = seed_value & 0xFFFFFFFF
		if s == 0:
			s = 2463534242
		for i in 3:
			next_u32()

	func next_u32() -> int:
		var x: int = s
		x ^= (x << 13) & 0xFFFFFFFF
		x ^= x >> 17
		x ^= (x << 5) & 0xFFFFFFFF
		s = x & 0xFFFFFFFF
		return s


static func seed_from_string(text: String) -> int:
	var h: int = 2166136261
	for b in text.to_utf8_buffer():
		h = ((h ^ b) * 16777619) & 0xFFFFFFFF
	return h


func _init(p_lines: Array, p_config: Dictionary, p_level_id: String) -> void:
	lines = p_lines
	allowed_moods = p_config.get("allowed_moods", {})
	recent_window = int(p_config.get("recent_window", 3))
	level_id = p_level_id


## Pick a mood and a cached line. Returns {mood, line, tier, repeated}; line is {} when none fits.
func say(trigger: String, ctx: Dictionary) -> Dictionary:
	var rng := _new_rng()
	var mood := _choose_mood(ctx, rng)
	var picked := _pick_line(trigger, ctx, mood, rng)
	calls += 1
	if not (picked["line"] as Dictionary).is_empty():
		remember(str(picked["line"]["id"]))
	return {"mood": mood, "line": picked["line"], "tier": picked["tier"], "repeated": picked["repeated"]}


## Mood only, for the live-AI path.
func choose_mood(ctx: Dictionary) -> String:
	var rng := _new_rng()
	var mood := _choose_mood(ctx, rng)
	calls += 1
	return mood


func remember(entry: String) -> void:
	recent.append(entry)
	if recent_window <= 0:
		recent.clear()
	while recent.size() > recent_window:
		recent.pop_front()


## Last lines as text, for the "Do not repeat" part of the AI prompt.
func recent_texts() -> Array:
	var by_id := {}
	for l in lines:
		by_id[l["id"]] = l["text"]
	var out: Array = []
	for e in recent:
		out.append(by_id.get(e, e))
	return out


func _new_rng() -> Rng:
	return Rng.new(seed_from_string("%s#%d" % [level_id, calls]))


func _choose_mood(ctx: Dictionary, rng: Rng) -> String:
	var act := int(ctx.get("act", 1))
	var spirit_mood := str(ctx.get("spirit_mood", "amused"))
	var weights: Dictionary = ctx.get("mood_weights", {})
	if weights.is_empty():
		weights = {spirit_mood: 1.0}
	var allowed: Array = allowed_moods.get(str(act), [])
	var moods: Array = weights.keys()
	moods.sort()
	var picks: Array = []  # [mood, per-mille weight]
	var total := 0
	for m in moods:
		if not allowed.is_empty() and not (m in allowed):
			continue
		var w := int(float(weights[m]) * 1000.0 + 0.5)
		if w <= 0:
			continue
		picks.append([m, w])
		total += w
	var r := rng.next_u32()  # always one draw, so the line draw is stable
	if picks.is_empty():
		return str(allowed[0]) if not allowed.is_empty() else spirit_mood
	var t := r % total
	for p in picks:
		if t < int(p[1]):
			return str(p[0])
		t -= int(p[1])
	return str(picks[picks.size() - 1][0])


func _by_id(a: Dictionary, b: Dictionary) -> bool:
	return str(a["id"]) < str(b["id"])


func _pick_line(trigger: String, ctx: Dictionary, mood: String, rng: Rng) -> Dictionary:
	var act := int(ctx.get("act", 1))
	var tiers: Array = [[], [], [], []]
	for l in lines:
		if l.get("trigger") != trigger:
			continue
		var la := int(l.get("act", 1))
		if la > act:
			continue
		var same_act := la == act
		var same_mood: bool = l.get("mood") == mood
		if same_act and same_mood:
			tiers[0].append(l)
		if same_act:
			tiers[1].append(l)
		if same_mood:
			tiers[2].append(l)
		tiers[3].append(l)
	for t in 4:
		tiers[t].sort_custom(_by_id)

	var first_nonempty := -1
	for t in 4:
		var cands: Array = tiers[t]
		if cands.is_empty():
			continue
		if first_nonempty == -1:
			first_nonempty = t
		var fresh: Array = []
		for c in cands:
			if not (c["id"] in recent):
				fresh.append(c)
		if not fresh.is_empty():
			return {"line": fresh[rng.next_u32() % fresh.size()], "tier": t, "repeated": false}
	rng.next_u32()  # keep the draw count identical on every path
	if first_nonempty == -1:
		return {"line": {}, "tier": -1, "repeated": false}

	# Everything was said recently: repeat the line said longest ago, from the best tier that
	# offers anything other than the line just spoken.
	var last = recent[recent.size() - 1] if not recent.is_empty() else null
	for t in 4:
		var oldest: Dictionary = {}
		var oldest_pos := 1 << 30
		for c in tiers[t]:
			if c["id"] == last:
				continue
			var pos: int = recent.find(c["id"])  # -1 if not in recent (cannot happen here)
			if oldest.is_empty() or pos < oldest_pos:
				oldest = c
				oldest_pos = pos
		if not oldest.is_empty():
			return {"line": oldest, "tier": t, "repeated": true}
	return {"line": tiers[first_nonempty][0], "tier": first_nonempty, "repeated": true}
