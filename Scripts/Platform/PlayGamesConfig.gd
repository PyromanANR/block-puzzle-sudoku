extends RefCounted
class_name PlayGamesConfig

const PLACEHOLDER_IDS := {
	"easy": "LB_EASY_ID",
	"medium": "LB_MEDIUM_ID",
	"hard": "LB_HARD_ID",
	"hard_plus_no_mercy": "LB_HARD_NM_ID",
}

const SETTINGS_KEY := "play_games/leaderboards"


static func get_leaderboard_ids() -> Dictionary:
	var configured = ProjectSettings.get_setting(SETTINGS_KEY, {})
	if typeof(configured) != TYPE_DICTIONARY:
		configured = {}

	var ids: Dictionary = PLACEHOLDER_IDS.duplicate(true)
	for key in PLACEHOLDER_IDS.keys():
		var value = String(configured.get(key, PLACEHOLDER_IDS[key])).strip_edges()
		ids[key] = value
	return ids

