extends Node
class_name ProgressManager


func get_level() -> int:
	if Save == null:
		return 0
	return Save.get_player_level()


func get_day() -> int:
	if Save == null:
		return 0
	var days = Save.data.get("unique_days_played", [])
	if typeof(days) != TYPE_ARRAY:
		return 0
	return (days as Array).size()


func get_xp() -> int:
	if Save == null:
		return 0
	return int(Save.data.get("player_xp", 0))


func get_unique_days() -> Array:
	if Save == null:
		return []
	var days = Save.data.get("unique_days_played", [])
	if typeof(days) != TYPE_ARRAY:
		return []
	return days.duplicate()
