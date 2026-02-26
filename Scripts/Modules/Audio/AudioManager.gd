extends Node
class_name AudioManager

const MIN_DB = -80.0

var music_enabled: bool = true
var sfx_enabled: bool = true
var master_enabled: bool = true
var music_volume_linear: float = 1.0
var sfx_volume_linear: float = 1.0
var master_volume_linear: float = 1.0


func _ready() -> void:
	_apply_bus("Master", master_enabled, master_volume_linear)
	_apply_bus("Music", music_enabled, music_volume_linear)
	_apply_bus("SFX", sfx_enabled, sfx_volume_linear)


func apply_from_settings_dict(settings: Dictionary) -> void:
	if settings.has("music_enabled"):
		set_music_enabled(bool(settings["music_enabled"]))
	if settings.has("sfx_enabled"):
		set_sfx_enabled(bool(settings["sfx_enabled"]))
	if settings.has("music_volume"):
		set_music_volume_linear(float(settings["music_volume"]))
	if settings.has("sfx_volume"):
		set_sfx_volume_linear(float(settings["sfx_volume"]))
	if settings.has("master_enabled"):
		set_master_enabled(bool(settings["master_enabled"]))
	if settings.has("master_volume"):
		set_master_volume_linear(float(settings["master_volume"]))


func set_music_enabled(enabled: bool) -> void:
	music_enabled = enabled
	_apply_bus("Music", music_enabled, music_volume_linear)


func set_sfx_enabled(enabled: bool) -> void:
	sfx_enabled = enabled
	_apply_bus("SFX", sfx_enabled, sfx_volume_linear)


func set_master_enabled(enabled: bool) -> void:
	master_enabled = enabled
	_apply_bus("Master", master_enabled, master_volume_linear)


func set_music_volume_linear(volume_linear: float) -> void:
	music_volume_linear = clamp(volume_linear, 0.0, 1.0)
	_apply_bus("Music", music_enabled, music_volume_linear)


func set_sfx_volume_linear(volume_linear: float) -> void:
	sfx_volume_linear = clamp(volume_linear, 0.0, 1.0)
	_apply_bus("SFX", sfx_enabled, sfx_volume_linear)


func set_master_volume_linear(volume_linear: float) -> void:
	master_volume_linear = clamp(volume_linear, 0.0, 1.0)
	_apply_bus("Master", master_enabled, master_volume_linear)


func _apply_bus(bus_name: String, enabled: bool, volume_linear: float) -> void:
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx < 0:
		return
	AudioServer.set_bus_volume_db(bus_idx, _linear_to_db_safe(volume_linear))
	AudioServer.set_bus_mute(bus_idx, not enabled)


func _linear_to_db_safe(v: float) -> float:
	if v <= 0.0:
		return MIN_DB
	return linear_to_db(v)
