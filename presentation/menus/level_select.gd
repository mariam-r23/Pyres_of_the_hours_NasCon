extends Control
## Level select, built in code: every level from LevelList with its title,
## locked / unlocked, and best / par. Locked levels cannot be started.
## Emits chosen("start", level_id) or chosen("back", ""). Escape is handled by
## main.gd (it goes back).

const Style := preload("res://presentation/menus/menu_style.gd")
const Progress := preload("res://presentation/menus/progress.gd")
const LevelList := preload("res://presentation/level_list.gd")
const Loader := preload("res://core/level_loader.gd")

signal chosen(action: String, level_id: String)

## Set before adding (see build_rows).
var rows: Array = []


## One row per level: {id, path, title, unlocked, best, par, text}.
static func build_rows(entries: Array, progress: Dictionary) -> Array:
	var out: Array = []
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var meta: Dictionary = Loader.load_file(entry["path"])["meta"]
		var title: String = meta.get("title", entry["id"])
		var par: int = meta.get("par_actions", -1)
		var best := Progress.best_of(progress, entry["id"])
		var unlocked := Progress.is_unlocked(progress, entry["id"])
		out.append({
			"id": entry["id"], "path": entry["path"], "title": title,
			"unlocked": unlocked, "best": best, "par": par,
			"text": row_text(i + 1, title, unlocked, best, par),
		})
	return out


## "3   Wrong Ash        12 / par 10", "- / par 10" if never won, or locked.
static func row_text(number: int, title: String, unlocked: bool, best: int, par: int) -> String:
	if not unlocked:
		return "%d   %s        locked" % [number, title]
	return "%d   %s        %s" % [number, title, best_par_text(best, par)]


static func best_par_text(best: int, par: int) -> String:
	return "%s / par %s" % [str(best) if best >= 0 else "-", str(par) if par >= 0 else "-"]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scale := Style.scale_for(get_viewport_rect().size.y)
	theme = Style.theme(scale)
	add_child(Style.backdrop())
	var col := Style.column(scale)
	add_child(col)
	col.add_child(Style.label("Level Select", Style.HEADING_SIZE, scale))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 440) * scale
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", int(6 * scale))
	scroll.add_child(list)
	var first: Button = null
	for row in rows:
		var b := Style.button(row["text"], scale)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = not row["unlocked"]
		if row["unlocked"]:
			var id: String = row["id"]
			b.pressed.connect(func(): chosen.emit("start", id))
			if first == null:
				first = b
		list.add_child(b)
	var back := Style.button("Back", scale)
	back.pressed.connect(func(): chosen.emit("back", ""))
	col.add_child(back)
	col.add_child(Style.label("Escape: back", Style.BODY_SIZE, scale, Style.TEXT_DIM))
	(first if first != null else back).grab_focus.call_deferred()
