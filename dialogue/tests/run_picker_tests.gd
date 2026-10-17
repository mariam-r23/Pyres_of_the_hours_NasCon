extends SceneTree
## Run from the repo root:
##   godot --headless --path . --script res://dialogue/tests/run_picker_tests.gd
## Exit code 0 = all pass. Checks the GDScript picker against the cases recorded from the Python
## reference (reference/python/gen_dialogue_cases.py) plus properties of the real lines.json.

const Picker = preload("res://dialogue/dialogue_picker.gd")

var total := 0
var failed := 0


func _init() -> void:
	var cases: Dictionary = _read_json("res://dialogue/tests/picker_cases.json")
	var lines: Array = _read_json("res://dialogue/lines.json")["lines"]
	var config: Dictionary = _read_json("res://dialogue/picker_config.json")

	for c in cases["seed_cases"]:
		_check(Picker.seed_from_string(c["text"]) == int(c["seed"]), "seed_from_string(%s)" % c["text"])

	for c in cases["rng_cases"]:
		var rng = Picker.Rng.new(int(c["seed"]))
		var got: Array = []
		for i in 5:
			got.append(rng.next_u32())
		var want: Array = []
		for v in c["first5"]:
			want.append(int(v))
		_check(got == want, "rng seed %s: got %s want %s" % [c["seed"], got, want])

	for c in cases["picker_cases"]:
		var p = Picker.new(c["lines"], c["config"], c["level_id"])
		for i in c["calls"].size():
			var call: Dictionary = c["calls"][i]
			var r: Dictionary = p.say(call["trigger"], call["ctx"])
			var line_id: String = str(r["line"].get("id", "")) if not (r["line"] as Dictionary).is_empty() else ""
			var e: Dictionary = c["expect"][i]
			var ok: bool = r["mood"] == e["mood"] and line_id == e["line_id"] \
				and int(r["tier"]) == int(e["tier"]) and r["repeated"] == e["repeated"]
			_check(ok, "%s, call %d: got %s/%s/%s/%s want %s/%s/%s/%s" % [c["name"], i,
				r["mood"], line_id, r["tier"], r["repeated"], e["mood"], e["line_id"], e["tier"], e["repeated"]])

	# Properties of the real lines.json.
	var triggers := {}
	for l in lines:
		triggers[l["trigger"]] = true
	for act in [1, 2, 3]:
		var allowed: Array = config["allowed_moods"][str(act)]
		var weights := {}
		for m in allowed:
			weights[m] = 1.0
		for trig in triggers.keys():
			var available := 0
			for l in lines:
				if l["trigger"] == trig and int(l["act"]) <= act:
					available += 1
			for n in 8:
				var p = Picker.new(lines, config, "real%d%s%d" % [act, trig, n])
				for k in 5:
					var r: Dictionary = p.say(trig, {"act": act, "spirit_mood": allowed[0], "mood_weights": weights})
					_check(r["mood"] in allowed, "act %d %s: mood %s not allowed" % [act, trig, r["mood"]])
					if available > 0:
						_check(not (r["line"] as Dictionary).is_empty(), "act %d %s: no line although %d exist" % [act, trig, available])
						if not (r["line"] as Dictionary).is_empty():
							_check(int(r["line"]["act"]) <= act, "act %d %s: got a later-act line" % [act, trig])
					else:
						_check((r["line"] as Dictionary).is_empty(), "act %d %s: line returned from nothing" % [act, trig])

	# recent_texts and the AI path.
	var p2 = Picker.new(lines, config, "L01_first_crate")
	p2.remember(str(lines[0]["id"]))
	p2.remember("A freshly written line.")
	_check(p2.recent_texts() == [lines[0]["text"], "A freshly written line."], "recent_texts maps ids and keeps AI text")
	_check(p2.choose_mood({"act": 1, "spirit_mood": "annoyed"}) == "annoyed", "choose_mood single mood")

	print("%d checks, %d failed" % [total, failed])
	quit(1 if failed > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		failed += 1
		print("FAIL: ", msg)


func _read_json(path: String):
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(parsed != null)
	return parsed
