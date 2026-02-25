extends Node
class_name SaveManager

const SAVE_PATH := "user://save.json"
const SAVE_VERSION = 1
const DATE_RX = "^\\d{4}-\\d{2}-\\d{2}$"

var data: Dictionary = {}

func _ready() -> void:
	load_save()


func defaults() -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"updated_at_ms": 0,
		"player_name": "Player",
		"unique_days_played": [],
		"player_level": 0,
		"unlocks": _default_unlocks(),
		"best_score_by_difficulty": _default_best_scores(),

		"best_score": 0,
		"best_level": 0,
		"music_volume": 1.0,
		"sfx_volume": 1.0,
		"difficulty": "Medium",
		"no_mercy": false,
	}


func _default_unlocks() -> Dictionary:
	return {
		"freeze_unlocked": false,
		"clear_board_unlocked": false,
		"safe_well_unlocked": false,
		"veteran_unlocked": false,
		"skin_sudoku_unlocked": false,
		"skin_rome_unlocked": false,
	}


func _default_best_scores() -> Dictionary:
	return {
		"easy": 0,
		"medium": 0,
		"hard": 0,
		"hard_plus_no_mercy": 0,
	}


func load_save() -> Dictionary:
	data = defaults()
	var needs_save = false

	var f = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		save()
		return data

	var txt = f.get_as_text()
	f.close()

	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		data = defaults()
		save()
		return data

	_merge_into(data, parsed)
	needs_save = _migrate_legacy_fields() or needs_save
	needs_save = _normalize_blob_shape() or needs_save
	needs_save = _sanitize_unique_days() or needs_save
	needs_save = recompute_player_level_and_unlocks() or needs_save

	if needs_save:
		save()
	return data


func save() -> void:
	var f = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Cannot open save file for writing: %s" % SAVE_PATH)
		return
	data["updated_at_ms"] = _now_unix_ms()
	var json_text = JSON.stringify(data)
	f.store_buffer(json_text.to_utf8_buffer())
	f.close()


func _merge_into(dst: Dictionary, src: Dictionary) -> void:
	for k in src.keys():
		var v = src[k]
		if dst.has(k) and typeof(dst[k]) == TYPE_DICTIONARY and typeof(v) == TYPE_DICTIONARY:
			_merge_into(dst[k], v)
		else:
			dst[k] = v


func _migrate_legacy_fields() -> bool:
	var changed = false
	var days = data.get("unique_days_played", [])
	if typeof(days) != TYPE_ARRAY:
		days = []
		changed = true

	if days.is_empty():
		var old_last = String(data.get("last_play_date", ""))
		if _is_valid_day_string(old_last):
			days.append(old_last)
			changed = true
		else:
			var old_total = int(data.get("days_played_total", 0))
			if old_total > 0:
				days = _build_synthetic_days(old_total)
				changed = true
	data["unique_days_played"] = days

	if int(data.get("save_version", 0)) != SAVE_VERSION:
		data["save_version"] = SAVE_VERSION
		changed = true

	return changed


func _normalize_blob_shape() -> bool:
	var changed = false
	if typeof(data.get("player_name", "")) != TYPE_STRING:
		data["player_name"] = "Player"
		changed = true
	if typeof(data.get("updated_at_ms", 0)) != TYPE_INT:
		data["updated_at_ms"] = 0
		changed = true
	if typeof(data.get("unique_days_played", [])) != TYPE_ARRAY:
		data["unique_days_played"] = []
		changed = true
	if typeof(data.get("unlocks", {})) != TYPE_DICTIONARY:
		data["unlocks"] = _default_unlocks()
		changed = true
	if typeof(data.get("best_score_by_difficulty", {})) != TYPE_DICTIONARY:
		data["best_score_by_difficulty"] = _default_best_scores()
		changed = true

	var unlocks = data["unlocks"]
	for k in _default_unlocks().keys():
		if typeof(unlocks.get(k, false)) != TYPE_BOOL:
			unlocks[k] = false
			changed = true
	data["unlocks"] = unlocks

	var best_map = data["best_score_by_difficulty"]
	for k in _default_best_scores().keys():
		if typeof(best_map.get(k, 0)) != TYPE_INT:
			best_map[k] = int(best_map.get(k, 0))
			changed = true
	data["best_score_by_difficulty"] = best_map
	return changed


func _sanitize_unique_days() -> bool:
	var source = data.get("unique_days_played", [])
	if typeof(source) != TYPE_ARRAY:
		data["unique_days_played"] = []
		return true

	var uniq := {}
	var cleaned: Array = []
	for entry in source:
		var s = String(entry)
		if not _is_valid_day_string(s):
			continue
		if uniq.has(s):
			continue
		uniq[s] = true
		cleaned.append(s)

	if cleaned.size() != source.size():
		data["unique_days_played"] = cleaned
		return true
	return false


func _is_valid_day_string(s: String) -> bool:
	var rx = RegEx.new()
	if rx.compile(DATE_RX) != OK:
		return false
	return rx.search(s) != null


func _build_synthetic_days(total: int) -> Array:
	var result: Array = []
	var seen := {}
	var now = int(Time.get_unix_time_from_system())
	for i in range(max(0, total)):
		var dt = Time.get_datetime_dict_from_unix_time(now - (i * 86400))
		var day = "%04d-%02d-%02d" % [int(dt.year), int(dt.month), int(dt.day)]
		if seen.has(day):
			continue
		seen[day] = true
		result.append(day)
	return result


func _now_unix_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


func get_today_date_string_local() -> String:
	var d = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [int(d.year), int(d.month), int(d.day)]


func recompute_player_level_and_unlocks() -> bool:
	var changed = false
	var unique_days = data.get("unique_days_played", [])
	if typeof(unique_days) != TYPE_ARRAY:
		unique_days = []
		data["unique_days_played"] = unique_days
		changed = true

	var level = unique_days.size()
	if int(data.get("player_level", -1)) != level:
		data["player_level"] = level
		changed = true

	var unlocks = data.get("unlocks", _default_unlocks())
	var expected = {
		"freeze_unlocked": level >= 5,
		"clear_board_unlocked": level >= 10,
		"safe_well_unlocked": level >= 20,
		"veteran_unlocked": level >= 50,
		"skin_sudoku_unlocked": level >= 10,
		"skin_rome_unlocked": level >= 50,
	}
	for key in expected.keys():
		if bool(unlocks.get(key, false)) != bool(expected[key]):
			unlocks[key] = expected[key]
			changed = true
	data["unlocks"] = unlocks

	if int(data.get("save_version", 0)) != SAVE_VERSION:
		data["save_version"] = SAVE_VERSION
		changed = true

	return changed


func add_unique_day_if_needed(on_round_completed: bool = true) -> bool:
	if not on_round_completed:
		return false
	var today = get_today_date_string_local()
	var unique_days = data.get("unique_days_played", [])
	if typeof(unique_days) != TYPE_ARRAY:
		unique_days = []

	if unique_days.has(today):
		return false

	unique_days.append(today)
	data["unique_days_played"] = unique_days
	recompute_player_level_and_unlocks()
	save()
	return true


func get_player_level() -> int:
	return int(data.get("player_level", 0))


func get_unlocks() -> Dictionary:
	if typeof(data.get("unlocks", {})) != TYPE_DICTIONARY:
		return _default_unlocks()
	return data["unlocks"]


func is_unlock_enabled(key: String) -> bool:
	var unlocks = get_unlocks()
	return bool(unlocks.get(key, false))


func get_best_score_by_difficulty() -> Dictionary:
	if typeof(data.get("best_score_by_difficulty", {})) != TYPE_DICTIONARY:
		data["best_score_by_difficulty"] = _default_best_scores()
	return data["best_score_by_difficulty"]


func _current_best_score_key() -> String:
	var difficulty = String(data.get("difficulty", "Medium")).to_lower()
	if difficulty == "easy":
		return "easy"
	if difficulty == "hard" and bool(data.get("no_mercy", false)):
		return "hard_plus_no_mercy"
	if difficulty == "hard":
		return "hard"
	return "medium"


func update_best(score: int, level: int) -> void:
	var best_score = int(data.get("best_score", 0))
	var best_level = int(data.get("best_level", 0))
	if score > best_score:
		data["best_score"] = score
	if level > best_level:
		data["best_level"] = level

	var map = get_best_score_by_difficulty()
	var key = _current_best_score_key()
	var prev = int(map.get(key, 0))
	if score > prev:
		map[key] = score
		data["best_score_by_difficulty"] = map


func get_music_volume() -> float:
	return float(data.get("music_volume", 1.0))


func get_sfx_volume() -> float:
	return float(data.get("sfx_volume", 1.0))


func set_music_volume(v: float) -> void:
	data["music_volume"] = clamp(v, 0.0, 1.0)


func set_sfx_volume(v: float) -> void:
	data["sfx_volume"] = clamp(v, 0.0, 1.0)


func get_current_difficulty() -> String:
	return String(data.get("difficulty", "Medium"))


func get_no_mercy() -> bool:
	return bool(data.get("no_mercy", false))


func set_difficulty(difficulty: String) -> void:
	var d = difficulty.capitalize()
	if d != "Easy" and d != "Medium" and d != "Hard":
		d = "Medium"
	data["difficulty"] = d


func set_no_mercy(v: bool) -> void:
	data["no_mercy"] = v
