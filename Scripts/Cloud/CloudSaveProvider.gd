extends RefCounted
class_name CloudSaveProvider

var snapshot_name: String = "player_save"
var _last_error: String = ""


func is_available() -> bool:
	return false


func is_signed_in() -> bool:
	return false


func sign_in() -> bool:
	_last_error = "Unavailable"
	return false


func load_snapshot() -> Dictionary:
	return {
		"ok": false,
		"has_data": false,
		"data": PackedByteArray(),
		"error": "Unavailable",
	}


func save_snapshot(data: PackedByteArray) -> bool:
	_last_error = "Unavailable"
	return false


func get_last_error() -> String:
	return _last_error
