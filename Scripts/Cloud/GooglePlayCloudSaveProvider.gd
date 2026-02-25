extends CloudSaveProvider
class_name GooglePlayCloudSaveProvider

var _signed_in: bool = false


func is_available() -> bool:
	if OS.get_name() != "Android":
		return false
	# TODO(PR2): Replace singleton name check with the concrete Google Play plugin bridge.
	return Engine.has_singleton("GodotPlayGames")


func is_signed_in() -> bool:
	return _signed_in


func sign_in() -> bool:
	if not is_available():
		_last_error = "Google Play Games plugin unavailable."
		return false
	# TODO(PR2): Call plugin silent sign-in and set _signed_in from callback result.
	_signed_in = false
	_last_error = "Google Play sign-in bridge is not wired yet."
	return false


func load_snapshot() -> Dictionary:
	if not is_available():
		return {
			"ok": false,
			"has_data": false,
			"data": PackedByteArray(),
			"error": "Google Play Games plugin unavailable.",
		}
	if not _signed_in:
		return {
			"ok": false,
			"has_data": false,
			"data": PackedByteArray(),
			"error": "Not signed in.",
		}
	# TODO(PR2): Load snapshot by name and return UTF-8 JSON bytes.
	return {
		"ok": false,
		"has_data": false,
		"data": PackedByteArray(),
		"error": "Google Play snapshot load bridge is not wired yet.",
	}


func save_snapshot(data: PackedByteArray) -> bool:
	if not is_available():
		_last_error = "Google Play Games plugin unavailable."
		return false
	if not _signed_in:
		_last_error = "Not signed in."
		return false
	# TODO(PR2): Save UTF-8 JSON bytes into snapshot by name.
	_last_error = "Google Play snapshot save bridge is not wired yet."
	return false
