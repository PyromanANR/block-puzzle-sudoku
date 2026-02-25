extends CloudSaveProvider
class_name NullCloudSaveProvider


func is_available() -> bool:
	return false


func is_signed_in() -> bool:
	return false


func sign_in() -> bool:
	_last_error = "Cloud save is not available on this platform."
	return false


func load_snapshot() -> Dictionary:
	return {
		"ok": false,
		"has_data": false,
		"data": PackedByteArray(),
		"error": "Cloud save is not available on this platform.",
	}


func save_snapshot(data: PackedByteArray) -> bool:
	_last_error = "Cloud save is not available on this platform."
	return false
