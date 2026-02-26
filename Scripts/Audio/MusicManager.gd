extends Node
class_name MusicManager

const SETTINGS_PATH = "user://settings.cfg"
const MENU_TRACK_PATH = "res://Assets/Audio/Music/Menu/ags_project-8-bit-219384.ogg"
const GAME_MUSIC_DIR = "res://Assets/Audio/Music/Game"
const MUSIC_ATTENUATION_LINEAR = 0.05

var music_player: AudioStreamPlayer = null
var music_enabled: bool = true
var music_volume: float = 0.5
var current_mode: String = "none"
var game_track_paths: Array = []
var game_queue: Array = []
var last_game_track_path: String = ""


func _ready() -> void:
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
	add_child(music_player)
	music_player.finished.connect(_on_music_finished)
	_load_audio_settings()
	_apply_music_runtime_volume()


func _load_audio_settings() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	music_enabled = bool(cfg.get_value("audio", "music_enabled", true))
	var loaded_music_volume = cfg.get_value("audio", "music_volume", 0.5)
	if typeof(loaded_music_volume) == TYPE_FLOAT or typeof(loaded_music_volume) == TYPE_INT:
		music_volume = clamp(float(loaded_music_volume), 0.0, 1.0)
	else:
		music_volume = 0.5

func set_audio_settings(enabled: bool, volume: float) -> void:
	music_enabled = enabled
	music_volume = clamp(volume, 0.0, 1.0)
	_apply_music_runtime_volume()
	if not _can_play_music():
		stop_music()
	else:
		ensure_playing_for_current_state()


func _effective_music_linear() -> float:
	return clamp(music_volume * MUSIC_ATTENUATION_LINEAR, 0.0, 1.0)


func _can_play_music() -> bool:
	return music_enabled and _effective_music_linear() > 0.0


func _apply_music_runtime_volume() -> void:
	var effective_volume = _effective_music_linear()
	var bus_idx = AudioServer.get_bus_index("Music")
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, _to_volume_db(effective_volume))
		AudioServer.set_bus_mute(bus_idx, not music_enabled)
	if music_player != null:
		music_player.volume_db = _to_volume_db(effective_volume)

func _to_volume_db(v: float) -> float:
	if v <= 0.0:
		return -80.0
	return linear_to_db(v)

func play_menu_music() -> void:
	current_mode = "menu"
	if not _can_play_music():
		stop_music()
		return
	if not ResourceLoader.exists(MENU_TRACK_PATH):
		stop_music()
		return
	var stream = load(MENU_TRACK_PATH)
	if stream == null:
		stop_music()
		return
	music_player.stream = stream
	music_player.play()


func _scan_game_track_paths() -> void:
	game_track_paths.clear()
	var dir = DirAccess.open(GAME_MUSIC_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var name = dir.get_next()
		if name == "":
			break
		if dir.current_is_dir():
			continue
		var lower = name.to_lower()
		if lower.ends_with(".ogg") or lower.ends_with(".wav") or lower.ends_with(".mp3"):
			game_track_paths.append("%s/%s" % [GAME_MUSIC_DIR, name])
	dir.list_dir_end()


func _refill_game_queue() -> void:
	if game_track_paths.is_empty():
		_scan_game_track_paths()
	if game_track_paths.is_empty():
		game_queue.clear()
		return
	game_queue = game_track_paths.duplicate()
	game_queue.shuffle()
	if game_queue.size() > 1 and String(game_queue[0]) == last_game_track_path:
		var swap_index = 1
		var tmp = game_queue[swap_index]
		game_queue[swap_index] = game_queue[0]
		game_queue[0] = tmp


func _play_next_game_track() -> void:
	if not _can_play_music():
		stop_music()
		return
	if game_queue.is_empty():
		_refill_game_queue()
	if game_queue.is_empty():
		stop_music()
		return
	var path = String(game_queue.pop_front())
	if not ResourceLoader.exists(path):
		_play_next_game_track()
		return
	var stream = load(path)
	if stream == null:
		_play_next_game_track()
		return
	last_game_track_path = path
	music_player.stream = stream
	music_player.play()


func play_game_music() -> void:
	current_mode = "game"
	_play_next_game_track()


func ensure_playing_for_current_state() -> void:
	if music_player == null:
		return
	if not _can_play_music():
		return
	if music_player.playing:
		return
	if music_player.stream != null:
		music_player.play()
		return
	if current_mode == "menu":
		play_menu_music()
	elif current_mode == "game":
		_play_next_game_track()


func stop_music() -> void:
	if music_player != null:
		music_player.stop()


func on_game_over_stop() -> void:
	stop_music()


func on_new_run_resume() -> void:
	if current_mode == "game":
		ensure_playing_for_current_state()


func _on_music_finished() -> void:
	if not _can_play_music():
		return
	if current_mode == "menu":
		play_menu_music()
	elif current_mode == "game":
		_play_next_game_track()
