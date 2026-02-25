extends Node
class_name SaveManager

const SAVE_PATH := "user://save.json"
const SAVE_VERSION = 1
const DATE_RX = "^\\d{4}-\\d{2}-\\d{2}$"

const NullCloudSaveProviderScript = preload("res://Scripts/Cloud/NullCloudSaveProvider.gd")
const GooglePlayCloudSaveProviderScript = preload("res://Scripts/Cloud/GooglePlayCloudSaveProvider.gd")

var data: Dictionary = {}
var cloud_provider: CloudSaveProvider = null
var cloud_sync_in_progress = false
var cloud_pending_upload = false


func _ready() -> void:
	load_save()
	cloud_provider = _create_cloud_provider()
	call_deferred("startup_cloud_sync")



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


func _create_cloud_provider() -> CloudSaveProvider:
	if OS.get_name() == "Android":
		return GooglePlayCloudSaveProviderScript.new()
	return NullCloudSaveProviderScript.new()


func load_save() -> Dictionary:
	data = defaults()
	var needs_save = false

	var f = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		save(false)
		return data

	var txt = f.get_as_text()
	f.close()

	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		data = defaults()
		save(false)
		return data

	_merge_into(data, parsed)
	needs_save = _migrate_legacy_fields() or needs_save
	needs_save = _normalize_blob_shape() or needs_save
	needs_save = _sanitize_unique_days() or needs_save
	needs_save = recompute_player_level_and_unlocks() or needs_save

	if needs_save:
		save(false)
	return data


func save(push_cloud: bool = true) -> void:
	var f = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Cannot open save file for writing: %s" % SAVE_PATH)
		return
	data["updated_at_ms"] = _now_unix_ms()
	var json_text = JSON.stringify(data)
	f.store_buffer(json_text.to_utf8_buffer())
	f.close()
	if push_cloud:
		cloud_push_best_effort()



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

	var uniq = {}
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
	var seen = {}
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


func _date_string_from_unix_local(unix_sec: int) -> String:
	var d = Time.get_datetime_dict_from_unix_time(unix_sec)
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
	var today = get_today_date_string_local()
	var unique_days = data.get("unique_days_played", [])
	if typeof(unique_days) != TYPE_ARRAY:
		unique_days = []

	unique_days.append(today)
	data["unique_days_played"] = unique_days
	recompute_player_level_and_unlocks()
	save(true)
	return true


func startup_cloud_sync() -> void:
	if cloud_sync_in_progress:
		return
	if cloud_provider == null:
		return
	if not cloud_provider.is_available():
		return

	cloud_sync_in_progress = true
	if not cloud_provider.is_signed_in():
		cloud_provider.sign_in()
	if not cloud_provider.is_signed_in():
		cloud_sync_in_progress = false
		return

	var pull_result = cloud_provider.load_snapshot()
	if not _is_snapshot_payload_ok(pull_result):
		cloud_sync_in_progress = false
		return

	var remote_blob = _parse_blob_from_snapshot(pull_result.get("data", PackedByteArray()))
	if remote_blob.is_empty():
		cloud_sync_in_progress = false
		return

	var decision = _compare_blobs(remote_blob, data)
	if decision > 0:
		_apply_remote_blob(remote_blob)
	elif decision < 0:
		cloud_push_best_effort()

	cloud_sync_in_progress = false


func cloud_sign_in() -> bool:
	if cloud_provider == null:
		return false
	if not cloud_provider.is_available():
		return false
	var ok = cloud_provider.sign_in()
	if ok and cloud_pending_upload:
		cloud_push_best_effort()
	return ok


func cloud_pull_now() -> bool:
	if cloud_provider == null:
		return false
	if not cloud_provider.is_available():
		return false
	if not cloud_provider.is_signed_in():
		return false

	var pull_result = cloud_provider.load_snapshot()
	if not _is_snapshot_payload_ok(pull_result):
		return false

	var remote_blob = _parse_blob_from_snapshot(pull_result.get("data", PackedByteArray()))
	if remote_blob.is_empty():
		return false

	var decision = _compare_blobs(remote_blob, data)
	if decision > 0:
		_apply_remote_blob(remote_blob)
		return true
	if decision < 0:
		cloud_push_best_effort()
	return true


func cloud_push_best_effort() -> bool:
	if cloud_provider == null:
		cloud_pending_upload = true
		return false
	if not cloud_provider.is_available():
		cloud_pending_upload = true
		return false
	if not cloud_provider.is_signed_in():
		cloud_pending_upload = true
		return false

	var ok = cloud_provider.save_snapshot(get_blob_bytes())
	cloud_pending_upload = not ok
	return ok


func cloud_push_now() -> bool:
	return cloud_push_best_effort()


func get_blob_bytes() -> PackedByteArray:
	return JSON.stringify(data).to_utf8_buffer()


func _is_snapshot_payload_ok(payload: Dictionary) -> bool:
	if typeof(payload) != TYPE_DICTIONARY:
		return false
	if not bool(payload.get("ok", false)):
		return false
	if not bool(payload.get("has_data", false)):
		return false
	return true


func _parse_blob_from_snapshot(raw_data) -> Dictionary:
	var json_text = ""
	if raw_data is PackedByteArray:
		json_text = (raw_data as PackedByteArray).get_string_from_utf8()
	else:
		json_text = String(raw_data)
	if json_text == "":
		return {}
	var parsed = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _compare_blobs(remote_blob: Dictionary, local_blob: Dictionary) -> int:
	var remote_updated = int(remote_blob.get("updated_at_ms", 0))
	var local_updated = int(local_blob.get("updated_at_ms", 0))
	if remote_updated > local_updated:
		return 1
	if remote_updated < local_updated:
		return -1

	var remote_level = _blob_level_value(remote_blob)
	var local_level = _blob_level_value(local_blob)
	if remote_level > local_level:
		return 1
	if remote_level < local_level:
		return -1
	return -1


func _blob_level_value(blob: Dictionary) -> int:
	if typeof(blob.get("player_level", null)) == TYPE_INT:
		return int(blob.get("player_level", 0))
	var days = blob.get("unique_days_played", [])
	if typeof(days) == TYPE_ARRAY:
		return (days as Array).size()
	return 0


func _apply_remote_blob(remote_blob: Dictionary) -> void:
	var normalized = defaults()
	_merge_into(normalized, remote_blob)
	data = normalized
	_migrate_legacy_fields()
	_normalize_blob_shape()
	_sanitize_unique_days()
	recompute_player_level_and_unlocks()
	save(false)


func get_cloud_last_error() -> String:
	if cloud_provider == null:
		return "Cloud provider unavailable."
	return cloud_provider.get_last_error()


func is_cloud_available() -> bool:
	if cloud_provider == null:
		return false
	return cloud_provider.is_available()


func is_cloud_signed_in() -> bool:
	if cloud_provider == null:
		return false
	return cloud_provider.is_signed_in()


func debug_add_one_level() -> bool:
	var unique_days = data.get("unique_days_played", [])
	if typeof(unique_days) != TYPE_ARRAY:
		unique_days = []

	var existing = {}
	for day in unique_days:
		existing[String(day)] = true

	var base_unix = int(Time.get_unix_time_from_system())
	for i in range(0, 5000):
		var candidate = _date_string_from_unix_local(base_unix + (i * 86400))
		if not existing.has(candidate):
			unique_days.append(candidate)
			data["unique_days_played"] = unique_days
			recompute_player_level_and_unlocks()
			save(true)
			return true
	return false


func debug_remove_one_level() -> bool:
	var unique_days = data.get("unique_days_played", [])
	if typeof(unique_days) != TYPE_ARRAY:
		return false
	if unique_days.is_empty():
		return false
	unique_days.pop_back()
	data["unique_days_played"] = unique_days
	recompute_player_level_and_unlocks()
	save(true)
	return true


func debug_print_save() -> void:
	print("SAVE_BLOB: %s" % JSON.stringify(data))


func debug_corrupt_local_save() -> void:
	var f = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Cannot open save file for corrupt-write test: %s" % SAVE_PATH)
		return
	f.store_string("{ invalid json")
	f.close()


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
