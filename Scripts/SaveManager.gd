extends Node
class_name SaveManager

# =========================
# Save schema (Stage 1)
# =========================
const SAVE_PATH := "user://save.json"

const MILESTONES := [5, 10, 20, 50, 100]

var data: Dictionary = {}

func _ready() -> void:
	load_save()

func defaults() -> Dictionary:
	return {
		"days_played_total": 0,
		"last_play_date": "",
		"rewards_claimed": { "d5": false, "d10": false, "d20": false, "d50": false, "d100": false },

		"best_score": 0,
		"best_level": 0,

		"music_volume": 1.0, # 0..1
		"sfx_volume": 1.0,   # 0..1
	}

func load_save() -> void:
	data = defaults()

	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		# First run: write defaults
		save()
		return

	var txt := f.get_as_text()
	f.close()

	var parsed = JSON.parse_string(txt)
	if typeof(parsed) == TYPE_DICTIONARY:
		# Merge parsed into defaults to stay forward-compatible
		_merge_into(data, parsed)
	else:
		# Corrupted save: overwrite with defaults
		save()

func save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Cannot open save file for writing: %s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()

func _merge_into(dst: Dictionary, src: Dictionary) -> void:
	for k in src.keys():
		var v = src[k]
		if dst.has(k) and typeof(dst[k]) == TYPE_DICTIONARY and typeof(v) == TYPE_DICTIONARY:
			_merge_into(dst[k], v)
		else:
			dst[k] = v

# -------------------------
# Date helpers
# -------------------------
func today_str() -> String:
	# YYYY-MM-DD (local system date)
	var d := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [int(d.year), int(d.month), int(d.day)]

# -------------------------
# Public API (Stage 1)
# -------------------------
func mark_played_today_if_needed() -> bool:
	# Returns true if it counted a new day
	var today := today_str()
	var last := String(data.get("last_play_date", ""))

	if last == today:
		return false

	data["last_play_date"] = today
	data["days_played_total"] = int(data.get("days_played_total", 0)) + 1
	return true

func update_best(score: int, level: int) -> void:
	var best_score := int(data.get("best_score", 0))
	var best_level := int(data.get("best_level", 0))

	if score > best_score:
		data["best_score"] = score
	if level > best_level:
		data["best_level"] = level

func get_days_played_total() -> int:
	return int(data.get("days_played_total", 0))

func is_reward_claimed(milestone: int) -> bool:
	var key := "d%d" % milestone
	var claimed: Dictionary = data.get("rewards_claimed", {})
	return bool(claimed.get(key, false))

func set_reward_claimed(milestone: int, value: bool) -> void:
	var key := "d%d" % milestone
	if not data.has("rewards_claimed") or typeof(data["rewards_claimed"]) != TYPE_DICTIONARY:
		data["rewards_claimed"] = {}
	data["rewards_claimed"][key] = value

func is_reward_ready(milestone: int) -> bool:
	# Ready = reached milestone and not claimed
	return get_days_played_total() >= milestone and not is_reward_claimed(milestone)

func get_music_volume() -> float:
	return float(data.get("music_volume", 1.0))

func get_sfx_volume() -> float:
	return float(data.get("sfx_volume", 1.0))

func set_music_volume(v: float) -> void:
	data["music_volume"] = clamp(v, 0.0, 1.0)

func set_sfx_volume(v: float) -> void:
	data["sfx_volume"] = clamp(v, 0.0, 1.0)
