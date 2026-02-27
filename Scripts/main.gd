extends Control

const BoardGridOverlay = preload("res://Scripts/BoardGridOverlay.gd")
const SkillVFXControllerScript = preload("res://Scripts/VFX/SkillVFXController.gd")
const MusicManagerScript = preload("res://Scripts/Audio/MusicManager.gd")
const AudioManagerScript = preload("res://Scripts/Modules/Audio/AudioManager.gd")
const SettingsPanel = preload("res://Scripts/Modules/UI/Common/SettingsPanel.gd")
const MAIN_MENU_SCENE = "res://Scenes/MainMenu.tscn"
const MAIN_SCENE = "res://Scenes/Main.tscn"

# ============================================================
# TETRIS SUDOKU (UI v2)
# - Top row: Board (left) + HUD (right)
# - Bottom row: Wide well (lane + pile) across full width
# - Pile works correctly (no "only 1 piece", no overflow drawing)
# - Settings + Exit buttons
# - Ghost always visible while dragging
# Requires CoreBridge.cs:
#   - CreateBoard()
#   - PopNextPieceForBoard(board)
#   - PeekNextPieceForBoard(board)
# ============================================================

# ----------------------------
# C# core / model
# ----------------------------
var core = null
var board = null

# ----------------------------
# Board
# ----------------------------
const BOARD_SIZE := 9
var cell_size: int = 54
var board_start := Vector2.ZERO
var board_cells := []
var board_hl := []
var color_grid := []
var board_grid_overlay: Control

# ----------------------------
# Gameplay
# ----------------------------
var score: int = 0
var level: int = 1
var speed_ui: float = 1.0
var start_ms: int = 0

# Selected piece
var selected_piece = null
var selected_from_pile_index: int = -1
var dragging: bool = false
var drag_anchor: Vector2i = Vector2i(-999, -999)
var drag_start_ms: int = 0

# ----------------------------
# Ghost (always visible)
# ----------------------------
var ghost_layer: Control
var ghost_root: Control
var ghost_bbox_size := Vector2.ZERO

# ----------------------------
# UI nodes
# ----------------------------
var root_frame: Panel
var title_label: Label
var title_texture_rect: TextureRect

var board_panel: Panel
var hud_panel: Panel
var well_panel: Panel
var well_draw: Control
var drop_zone_panel: Panel
var well_slots_panel: Panel
var drop_zone_draw: Control
var well_slots_draw: Control

var lbl_score: Label
var lbl_speed: Label
var lbl_level: Label
var lbl_time: Label
var lbl_rescue: Label
var lbl_skill_hint: Label
var btn_time_slow: TextureButton
var bar_time_slow: ProgressBar
var next_box: Panel

var btn_settings: TextureButton
var btn_exit: TextureButton
var btn_skill_freeze: TextureButton
var btn_skill_clear: TextureButton
var btn_skill_invuln: TextureButton
var board_overlay_right: Control
var exit_dialog: AcceptDialog
var settings_popup: Control

# Game Over overlay
var overlay_dim: ColorRect
var overlay_text: Label
var is_game_over: bool = false
var fx_layer: CanvasLayer
var time_slow_overlay: ColorRect
var pending_invalid_piece = null
var pending_invalid_from_pile_index: int = -1
var pending_invalid_root: Control
var pending_invalid_until_ms = 0
var pending_invalid_timer: Timer
var next_piece_state_id: int = 1
var grace_piece_by_id: Dictionary = {}
var invalid_drop_slow_until_ms = 0
var toast_layer: CanvasLayer
var toast_panel: Panel
var toast_label: Label

# ----------------------------
# Colors
# ----------------------------
const COLOR_EMPTY := Color(0.15, 0.15, 0.15, 1.0)
const COLOR_FILLED := Color(0.82, 0.82, 0.90, 1.0)
const HL_OK := Color(0.10, 0.85, 0.20, 0.60)
const HL_BAD := Color(0.95, 0.20, 0.20, 0.60)
const RETRO_GRID_BASE := Color(0.21, 0.10, 0.04, 1.0)
const RETRO_GRID_DARK := Color(0.16, 0.07, 0.03, 1.0)
const RETRO_GRID_BORDER := Color(0.60, 0.36, 0.18, 1.0)

# ----------------------------
# Well / pile
# ----------------------------
var pile: Array = []
var pile_max: int = 8
var pile_selectable: int = 3
var pile_visible: int = 8
var danger_start_ratio: float = 0.68
var danger_end_ratio: float = 0.88

# Zones inside well
const FALL_PAD := 12
const PILE_PAD := 12
const SLOT_H := 54
const SLOT_GAP := 6
const HEADER_BUTTON_SIZE := 76.0
const EXIT_BUTTON_SIZE := 84.0
const HEADER_BUTTON_MARGIN := 20.0

var toast_hide_at_ms = 0

var fall_piece = null
var fall_y: float = 10.0
var fall_piece_2 = null
var fall_y_2: float = 10.0
var frozen_left: float = 0.0
var spawn_wait_until_ms = 0
var pending_spawn_piece = false
var pending_dual_spawn_ms = 0
var pending_dual_fallback_ms = 0
var dual_drop_cycle_pending = false
var dual_drop_waiting_for_gap = false
var dual_drop_anchor_y = 10.0
var dual_drop_trigger_count = 0
var rescue_trigger_count = 0
var auto_slow_until_ms = 0
var auto_slow_trigger_count = 0
var micro_freeze_until_ms = 0
var clear_flash_left = 0.0
var clear_flash_cells = []
var rescue_eligible_until_ms = 0
var rescue_from_well_pending = false
var panic_sfx_cooldown_ms = 0
var well_header_pulse_left = 0.0
var time_scale_reason = "Normal"
var time_slow_cooldown_until_ms = 0
var time_slow_overlay_until_ms = 0
var time_slow_overlay_input_release_ms = 0
var time_slow_effect_until_ms = 0
var well_first_entry_slow_until_ms = 0
var well_first_entry_slow_used = false
var freeze_effect_until_ms = 0
var freeze_effect_multiplier = 1.0
var safe_well_effect_until_ms = 0
var used_freeze_this_round = false
var used_clear_board_this_round = false
var used_safe_well_this_round = false
var sfx_players = {}
var missing_sfx_warned = {}
var sfx_base_volume_db = {}
var music_manager: MusicManager = null
var music_enabled: bool = true
var sfx_enabled: bool = true
var music_volume: float = 0.5
var sfx_volume: float = 1.0
var sfx_blocked_by_game_over: bool = false
var game_over_sfx_played: bool = false
var last_dual_drop_min = -1.0
var speed_curve_warning_shown = false
var time_slow_ui_ready = false
var skill_vfx_controller: SkillVFXController = null
var skill_vfx_debug_rects_logged: bool = false

const UI_ICON_MAP = {
	"score": {"tres": "res://Assets/UI/icons/icon_score.tres", "png": "res://Assets/UI/icons/icon_score.png", "placeholder": "S"},
	"speed": {"tres": "res://Assets/UI/icons/icon_speed.tres", "png": "res://Assets/UI/icons/icon_speed.png", "placeholder": "SPD"},
	"time": {"tres": "res://Assets/UI/icons/icon_time.tres", "png": "res://Assets/UI/icons/icon_time.png", "placeholder": "T"},
	"timeslow": {"tres": "res://Assets/UI/icons/icon_timeslow.tres", "png": "res://Assets/UI/icons/icon_timeslow.png", "placeholder": "TS"},
	"freeze": {"tres": "res://Assets/UI/icons/skill/skill_freeze.tres", "png": "res://Assets/UI/icons/skill_freeze.png", "placeholder": "F"},
	"clear": {"tres": "res://Assets/UI/icons/skill/skill_clear_board.tres", "png": "res://Assets/UI/icons/skill_clear_board.png", "placeholder": "C"},
	"safe_well": {"tres": "res://Assets/UI/icons/skill/skill_safe_well.tres", "png": "res://Assets/UI/icons/skill_safe_well.png", "placeholder": "W"}
}

const NORMAL_RESPAWN_DELAY_MS = 260
const PANIC_HIGH_THRESHOLD = 0.85
const PANIC_MID_THRESHOLD = 0.60
const PANIC_PULSE_SPEED = 2.0
const PANIC_BLINK_SPEED = 7.0
const FREEZE_DURATION_MS = 5000
const FREEZE_MULTIPLIER = 0.10
const SAFE_WELL_DURATION_MS = 7000
const CLEAR_BOARD_POINTS_PER_CELL = 1
const TIME_SLOW_ATLAS_PATH = "res://Assets/UI/time_slow/atlas_time_slow.tres"
const TIME_SLOW_GLASS_OVERLAY_PATH = "res://Assets/UI/time_slow/tex_glass_overlay.tres"
const TIME_SLOW_SAND_FILL_PATH = "res://Assets/UI/time_slow/tex_sand_fill.tres"
const TIME_SLOW_FRAME_PATH = "res://Assets/UI/time_slow/tex_frame.tres"
const TIME_SLOW_SAND_SHADER_PATH = "res://Assets/UI/time_slow/shaders/sand_fill.gdshader"
const TIME_SLOW_GLASS_SHADER_PATH = "res://Assets/UI/time_slow/shaders/glass_overlay.gdshader"
const TIME_SLOW_ATLAS_PNG_PATH = "res://Assets/UI/time_slow/time_slow_atlas.png"
const SETTINGS_PATH = "user://settings.cfg"
const MUSIC_ATTENUATION_LINEAR = 0.05
const GAME_OVER_SFX_PATH = "res://Assets/Audio/SFX/game_over.ogg"

# Per-round perks (optional: keep buttons later if you want)
var reroll_uses_left: int = 1
var freeze_uses_left: int = 1
var time_slow_atlas: Resource = null
var time_slow_glass_overlay: Resource = null
var time_slow_sand_fill: Resource = null
var time_slow_frame_tex: Resource = null
var time_slow_sand_shader: Shader = null
var time_slow_glass_shader: Shader = null
var time_slow_sand_rect: TextureRect = null
var time_slow_glass_rect: TextureRect = null
var time_slow_frame_rect: TextureRect = null
var time_slow_mid: PanelContainer = null
var time_slow_sand_mat: ShaderMaterial = null
var time_slow_glass_mat: ShaderMaterial = null


func _skin_manager():
	return get_node_or_null("/root/SkinManager")


func _skin_theme():
	var sm = _skin_manager()
	if sm != null:
		return sm.get_theme()
	return null


func _skin_color(key: String, fallback: Color) -> Color:
	var sm = _skin_manager()
	if sm != null:
		return sm.get_color(key, fallback)
	return fallback


func _skin_font_size(key: String, fallback: int) -> int:
	var sm = _skin_manager()
	if sm != null:
		return sm.get_font_size(key, fallback)
	return fallback


func _skin_piece_color(kind: String) -> Color:
	var sm = _skin_manager()
	if sm != null:
		return sm.get_piece_color(kind)
	return COLOR_FILLED


# ============================================================
# Entry
# ============================================================
func _ready() -> void:
	core = get_node_or_null("/root/Core")
	if core == null:
		push_error("Core autoload not found.")
		return

	_apply_balance_well_settings()

	board = core.call("CreateBoard")
	board.call("Reset")

	start_ms = Time.get_ticks_msec()
	_load_audio_settings()
	if music_manager == null:
		music_manager = MusicManagerScript.new()
		add_child(music_manager)
	_audio_setup()
	_apply_audio_settings()
	if music_manager != null:
		music_manager.play_game_music()

	_build_ui()
	# HUD is built from this single path during startup; no secondary HUD builder runs after this.
	await get_tree().process_frame
	_build_board_grid()
	_setup_skill_vfx_controller()

	_start_round()
	set_process(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		call_deferred("_sync_time_slow_column_width")


func _sync_time_slow_column_width() -> void:
	if time_slow_mid == null:
		return
	const TIME_SLOW_GAP_W = 55.0
	time_slow_mid.custom_minimum_size.x = TIME_SLOW_GAP_W
	var p = time_slow_mid.get_parent()
	if p is Container:
		(p as Container).queue_sort()


func _apply_balance_well_settings() -> void:
	var s: Dictionary = core.call("GetWellSettings")
	pile_max = int(s.get("pile_max", pile_max))
	pile_selectable = int(s.get("top_selectable", pile_selectable))
	pile_visible = pile_max
	danger_start_ratio = float(s.get("danger_start_ratio", danger_start_ratio))
	danger_end_ratio = float(s.get("danger_end_ratio", danger_end_ratio))


func _start_round() -> void:
	is_game_over = false
	score = 0
	level = 1
	speed_ui = 1.0
	frozen_left = 0.0
	spawn_wait_until_ms = 0
	pending_spawn_piece = false
	pending_dual_spawn_ms = 0
	pending_dual_fallback_ms = 0
	dual_drop_cycle_pending = false
	dual_drop_waiting_for_gap = false
	dual_drop_anchor_y = 10.0
	dual_drop_trigger_count = 0
	last_dual_drop_min = -1.0
	speed_curve_warning_shown = false
	rescue_trigger_count = 0
	auto_slow_until_ms = 0
	auto_slow_trigger_count = 0
	micro_freeze_until_ms = 0
	clear_flash_left = 0.0
	clear_flash_cells.clear()
	rescue_eligible_until_ms = 0
	rescue_from_well_pending = false
	fall_piece_2 = null
	fall_y_2 = 10.0
	panic_sfx_cooldown_ms = 0
	well_header_pulse_left = 0.0
	time_scale_reason = "Normal"
	time_slow_cooldown_until_ms = 0
	time_slow_overlay_until_ms = 0
	time_slow_overlay_input_release_ms = 0
	time_slow_effect_until_ms = 0
	well_first_entry_slow_until_ms = 0
	well_first_entry_slow_used = false
	freeze_effect_until_ms = 0
	freeze_effect_multiplier = 1.0
	safe_well_effect_until_ms = 0
	used_freeze_this_round = false
	used_clear_board_this_round = false
	used_safe_well_this_round = false
	Engine.time_scale = 1.0
	core.call("ResetRuntimeClock")
	sfx_blocked_by_game_over = false
	game_over_sfx_played = false
	_apply_audio_settings()
	if music_manager != null:
		music_manager.on_new_run_resume()

	pile.clear()
	board.call("Reset")
	_clear_color_grid()
	_refresh_board_visual()

	selected_piece = null
	selected_from_pile_index = -1
	dragging = false
	ghost_root.visible = false
	_clear_highlight()

	_spawn_falling_piece()
	_redraw_well()
	_update_hud()
	_hide_game_over_overlay()
	if toast_panel != null:
		toast_panel.visible = false
	_clear_pending_invalid_piece()
	time_slow_ui_ready = false
	call_deferred("_sync_time_slow_column_width")


func _trigger_game_over() -> void:
	if is_game_over:
		return
	is_game_over = true
	pending_spawn_piece = false
	spawn_wait_until_ms = 0
	pending_dual_spawn_ms = 0
	pending_dual_fallback_ms = 0
	dual_drop_cycle_pending = false
	dual_drop_waiting_for_gap = false
	rescue_from_well_pending = false
	rescue_eligible_until_ms = 0
	auto_slow_until_ms = 0
	micro_freeze_until_ms = 0
	panic_sfx_cooldown_ms = 0
	time_slow_cooldown_until_ms = 0
	time_slow_overlay_until_ms = 0
	time_slow_overlay_input_release_ms = 0
	time_slow_effect_until_ms = 0
	well_first_entry_slow_until_ms = 0
	well_first_entry_slow_used = false
	if time_slow_overlay != null:
		time_slow_overlay.visible = false
	Engine.time_scale = 1.0
	sfx_blocked_by_game_over = true
	if music_manager != null:
		music_manager.on_game_over_stop()
	_stop_music_if_any()
	_stop_all_sfx()
	if not game_over_sfx_played:
		_play_sfx("game_over")
		game_over_sfx_played = true
	set_process(false)

	# Save global progress (player profile)
	Save.add_unique_day_if_needed(true)
	var difficulty_key = Save.get_current_difficulty_key()
	var best_by_difficulty = Save.get_best_score_by_difficulty()
	var previous_best = int(best_by_difficulty.get(difficulty_key, 0))
	Save.update_best(score, level)
	Save.save()
	if score > previous_best:
		Save.play_games_submit_best_if_needed(difficulty_key, score)

	_show_game_over_overlay()
	if toast_panel != null:
		toast_panel.visible = false
	_clear_pending_invalid_piece()




func _wire_button_sfx(btn) -> void:
	btn.mouse_entered.connect(func(): _play_sfx("ui_hover"))
	btn.pressed.connect(func(): _play_sfx("ui_click"))


func _load_audio_settings() -> void:
	var cfg = ConfigFile.new()
	var err = cfg.load(SETTINGS_PATH)
	var save_defaults = false
	if err != OK:
		save_defaults = true
	else:
		if cfg.has_section_key("audio", "music_enabled"):
			music_enabled = bool(cfg.get_value("audio", "music_enabled", true))
		else:
			music_enabled = true
			save_defaults = true
		if cfg.has_section_key("audio", "sfx_enabled"):
			sfx_enabled = bool(cfg.get_value("audio", "sfx_enabled", true))
		else:
			sfx_enabled = true
			save_defaults = true
		if cfg.has_section_key("audio", "music_volume"):
			var loaded_music_volume = cfg.get_value("audio", "music_volume", 0.5)
			if typeof(loaded_music_volume) == TYPE_FLOAT or typeof(loaded_music_volume) == TYPE_INT:
				music_volume = clamp(float(loaded_music_volume), 0.0, 1.0)
			else:
				music_volume = 0.5
				save_defaults = true
		else:
			music_volume = 0.5
			save_defaults = true
		if cfg.has_section_key("audio", "sfx_volume"):
			var loaded_sfx_volume = cfg.get_value("audio", "sfx_volume", 1.0)
			if typeof(loaded_sfx_volume) == TYPE_FLOAT or typeof(loaded_sfx_volume) == TYPE_INT:
				sfx_volume = clamp(float(loaded_sfx_volume), 0.0, 1.0)
			else:
				sfx_volume = 1.0
				save_defaults = true
		else:
			sfx_volume = 1.0
			save_defaults = true
	if save_defaults:
		_save_audio_settings()


func _save_audio_settings() -> void:
	var cfg = ConfigFile.new()
	cfg.set_value("audio", "music_enabled", music_enabled)
	cfg.set_value("audio", "sfx_enabled", sfx_enabled)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.save(SETTINGS_PATH)


func _get_audio_manager() -> AudioManager:
	var manager = get_node_or_null("/root/AudioManager")
	if manager == null:
		manager = AudioManagerScript.new()
		manager.name = "AudioManager"
		get_tree().root.add_child(manager)
	return manager


func _apply_audio_settings() -> void:
	var effective_music_volume = clamp(music_volume * MUSIC_ATTENUATION_LINEAR, 0.0, 1.0)
	var audio_manager = _get_audio_manager()
	audio_manager.apply_from_settings_dict({
		"music_enabled": music_enabled,
		"sfx_enabled": sfx_enabled,
		"music_volume": effective_music_volume,
		"sfx_volume": sfx_volume,
		"master_enabled": true,
		"master_volume": 1.0,
	})
	if music_manager != null:
		music_manager.set_audio_settings(music_enabled, music_volume)
	for key in sfx_players.keys():
		var p = sfx_players[key]
		var base_db = float(sfx_base_volume_db.get(key, 0.0))
		if p != null:
			if sfx_volume <= 0.0:
				p.volume_db = -80.0
			else:
				p.volume_db = clamp(base_db + linear_to_db(sfx_volume), -80.0, 24.0)
	if not sfx_enabled:
		_stop_all_sfx()


func _audio_setup() -> void:
	_ensure_sfx("ui_hover", "res://Assets/Audio/ui_hover.wav", -12.0)
	_ensure_sfx("ui_click", "res://Assets/Audio/ui_click.wav", -10.0)
	_ensure_sfx("pick", "res://Assets/Audio/pick_piece.wav", -11.0)
	_ensure_sfx("place", "res://Assets/Audio/place_piece.wav", -9.0)
	_ensure_sfx("invalid", "res://Assets/Audio/invalid_drop.wav", -9.0)
	_ensure_sfx("well_enter", "res://Assets/Audio/well_enter.wav", -6.0)
	_ensure_sfx("clear", "res://Assets/Audio/clear.wav", -7.0)
	_ensure_sfx("panic", "res://Assets/Audio/panic_tick.wav", -14.0)
	_ensure_sfx("game_over", GAME_OVER_SFX_PATH, -7.0)
	var ts_path = String(core.call("GetTimeSlowReadySfxPath"))
	if ts_path != "":
		_ensure_sfx("time_slow", ts_path, -8.0)


func _setup_skill_vfx_controller() -> void:
	if skill_vfx_controller != null and is_instance_valid(skill_vfx_controller):
		return
	skill_vfx_controller = SkillVFXControllerScript.new()
	add_child(skill_vfx_controller)
	skill_vfx_controller.setup(self, board_panel, drop_zone_panel, well_slots_panel, root_frame)
	skill_vfx_controller.setup_sfx_callback(Callable(self, "_play_sfx"))
	if OS.is_debug_build() and not skill_vfx_debug_rects_logged and drop_zone_panel != null and well_slots_panel != null:
		skill_vfx_debug_rects_logged = true
		print("DROP:", drop_zone_panel.get_global_rect())
		print("WELL:", well_slots_panel.get_global_rect())


func _ensure_sfx(key, path, volume_db) -> void:
	if sfx_players.has(key):
		return
	if not ResourceLoader.exists(path):
		_warn_missing_sfx_once(key, path)
		return
	var p = AudioStreamPlayer.new()
	p.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	p.volume_db = volume_db
	p.stream = load(path)
	if p.stream == null:
		_warn_missing_sfx_once(key, path)
		return
	add_child(p)
	sfx_players[key] = p
	sfx_base_volume_db[key] = volume_db


func _warn_missing_sfx_once(key, path) -> void:
	if missing_sfx_warned.has(key):
		return
	missing_sfx_warned[key] = true
	if OS.is_debug_build():
		push_warning("Missing SFX '%s' at %s (audio skipped)." % [key, path])


func _stop_all_sfx() -> void:
	for key in sfx_players.keys():
		var p = sfx_players[key]
		if p != null:
			p.stop()


func _stop_music_if_any() -> void:
	if music_manager != null:
		music_manager.stop_music()


func _play_sfx(key) -> void:
	if not sfx_enabled:
		return
	if sfx_blocked_by_game_over and key != "game_over":
		return
	if not sfx_players.has(key):
		return
	var p = sfx_players[key]
	if p != null and p.stream != null:
		p.play()


func _set_time_scale(reason, scale) -> void:
	if reason == "Normal":
		Engine.time_scale = 1.0
		time_scale_reason = "Normal"
		return
	Engine.time_scale = clamp(scale, 0.05, 1.0)
	time_scale_reason = reason


func _update_time_scale_runtime() -> void:
	var now = Time.get_ticks_msec()
	var final_scale = 1.0
	var reason = "Normal"
	if _is_no_mercy_active():
		var nm_scale = float(core.call("GetNoMercyExtraTimeScale", _well_fill_ratio()))
		if nm_scale < final_scale:
			final_scale = nm_scale
			reason = "NoMercyExtra"
	if dragging and selected_from_pile_index >= 0 and selected_piece != null:
		var well_drag_scale = float(core.call("GetWellDragTimeScale", _well_fill_ratio()))
		if well_drag_scale < final_scale:
			final_scale = well_drag_scale
			reason = "WellDrag"
	if auto_slow_until_ms > now:
		var auto_scale = float(core.call("GetAutoSlowScale"))
		if auto_scale < final_scale:
			final_scale = auto_scale
			reason = "AutoSlow"
	if micro_freeze_until_ms > now:
		var micro_scale = 0.15
		if micro_scale < final_scale:
			final_scale = micro_scale
			reason = "MicroFreeze"
	if well_first_entry_slow_until_ms > now:
		var first_well_scale = float(core.call("GetWellFirstEntrySlowTimeScale"))
		if first_well_scale < final_scale:
			final_scale = first_well_scale
			reason = "WellFirstEntry"
	if time_slow_effect_until_ms > now:
		var ts_scale = float(core.call("GetTimeSlowEffectTimeScale"))
		if ts_scale < final_scale:
			final_scale = ts_scale
			reason = "TimeSlow"
	if is_freeze_active():
		var freeze_scale = freeze_effect_multiplier
		if freeze_scale < final_scale:
			final_scale = freeze_scale
			reason = "FreezeSkill"
	if invalid_drop_slow_until_ms > now:
		var invalid_slow_scale = float(core.call("GetInvalidDropFailTimeScale"))
		if invalid_slow_scale < final_scale:
			final_scale = invalid_slow_scale
			reason = "InvalidDropFail"
	_set_time_scale(reason, final_scale)



func _active_falling_count() -> int:
	var c = 0
	if fall_piece != null:
		c += 1
	if fall_piece_2 != null:
		c += 1
	return c


func _is_no_mercy_active() -> bool:
	return Save.get_current_difficulty() == "Hard" and Save.get_no_mercy()


func _well_fill_ratio() -> float:
	if pile_max <= 0:
		return 0.0
	return clamp(float(pile.size()) / float(pile_max), 0.0, 1.0)


func _schedule_next_falling_piece() -> void:
	pending_spawn_piece = true
	spawn_wait_until_ms = Time.get_ticks_msec() + NORMAL_RESPAWN_DELAY_MS
	dual_drop_cycle_pending = bool(core.call("ConsumeDualDropTrigger"))
	if dual_drop_cycle_pending:
		dual_drop_trigger_count += 1
		last_dual_drop_min = float(core.call("GetElapsedMinutesForDebug"))


func _trigger_micro_freeze() -> void:
	var sec = float(core.call("GetMicroFreezeSec"))
	micro_freeze_until_ms = Time.get_ticks_msec() + int(sec * 1000.0)


func _trigger_auto_slow_if_needed() -> void:
	if core.call("ShouldTriggerAutoSlow", _board_fill_ratio(), _well_fill_ratio()):
		auto_slow_trigger_count += 1
		var dur = float(core.call("GetAutoSlowDurationSec"))
		auto_slow_until_ms = Time.get_ticks_msec() + int(dur * 1000.0)


func _update_status_hud() -> void:
	if bar_time_slow == null:
		return
	var now = Time.get_ticks_msec()
	var cooldown_sec = float(core.call("GetTimeSlowCooldownSec"))
	var remaining_ms = max(0, time_slow_cooldown_until_ms - now)
	var cooldown_remaining = float(remaining_ms) / 1000.0
	if not time_slow_ui_ready and cooldown_sec > 0.0:
		time_slow_ui_ready = true
	var progress01 = clamp(1.0 - (cooldown_remaining / max(0.001, cooldown_sec)), 0.0, 1.0)
	bar_time_slow.value = progress01 * 100.0
	if time_slow_sand_mat != null:
		time_slow_sand_mat.set_shader_parameter("u_fill", progress01)
	if btn_time_slow != null:
		if time_slow_ui_ready and remaining_ms <= 0:
			var t = float(Time.get_ticks_msec()) / 1000.0
			var wave = 0.5 + 0.5 * sin(TAU * 1.35 * t)
			var icon_scale = 1.00 + 0.08 * wave
			btn_time_slow.scale = Vector2(icon_scale, icon_scale)
			btn_time_slow.modulate = Color(1.0, 1.0, 1.0, 1.00 - 0.20 * wave)
		else:
			btn_time_slow.scale = Vector2.ONE
			btn_time_slow.modulate = Color(1.0, 1.0, 1.0, 1.0)
	bar_time_slow.modulate = Color(1, 1, 1, 1)
	_update_skill_icon_states()


# Trigger condition: successful placement of a piece taken from WELL.
# Cooldown: 60 sec real time using ticks, so it ignores Engine.time_scale.
func _try_trigger_time_slow_from_well_placement() -> void:
	var now = Time.get_ticks_msec()
	if now < time_slow_cooldown_until_ms:
		return
	time_slow_cooldown_until_ms = now + int(float(core.call("GetTimeSlowCooldownSec")) * 1000.0)
	var overlay_sec = float(core.call("GetTimeSlowReadyOverlayDurationSec"))
	time_slow_overlay_until_ms = now + int(overlay_sec * 1000.0)
	time_slow_overlay_input_release_ms = now + 300
	time_slow_effect_until_ms = now + int(float(core.call("GetTimeSlowEffectDurationSec")) * 1000.0)
	if time_slow_overlay != null:
		time_slow_overlay.visible = true
		time_slow_overlay.modulate = Color(0.45, 0.78, 1.0, 0.55)
		time_slow_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	if skill_vfx_controller != null:
		skill_vfx_controller.on_time_slow_cast()


func _try_trigger_first_well_entry_slow() -> void:
	if well_first_entry_slow_used:
		return
	well_first_entry_slow_used = true
	well_first_entry_slow_until_ms = Time.get_ticks_msec() + int(float(core.call("GetWellFirstEntrySlowDurationSec")) * 1000.0)


func _update_time_slow_overlay() -> void:
	if time_slow_overlay == null:
		return
	if not time_slow_overlay.visible:
		return
	var now = Time.get_ticks_msec()
	if now >= time_slow_overlay_until_ms:
		time_slow_overlay.visible = false
		time_slow_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return
	if now >= time_slow_overlay_input_release_ms:
		time_slow_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left = max(1, time_slow_overlay_until_ms - now)
	var total = max(0.001, float(core.call("GetTimeSlowReadyOverlayDurationSec")) * 1000.0)
	var p = clamp(float(left) / total, 0.0, 1.0)
	var wave = 0.5 + 0.5 * sin(float(now) / 70.0)
	time_slow_overlay.modulate = Color(0.35 + 0.25 * wave, 0.70 + 0.20 * wave, 1.0, 0.45 * p)


# ============================================================
# UI build (new layout)
# ============================================================
func _build_ui() -> void:
	for ch in get_children():
		if ch is AudioStreamPlayer or ch == music_manager:
			continue
		ch.queue_free()

	root_frame = Panel.new()
	root_frame.clip_contents = true
	var skin_theme = _skin_theme()
	if skin_theme != null:
		root_frame.theme = skin_theme
	root_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_frame.add_theme_stylebox_override("panel", _style_cartridge_frame())
	add_child(root_frame)

	var header_row = HBoxContainer.new()
	header_row.name = "header_row"
	header_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header_row.offset_left = 20
	header_row.offset_right = -20
	header_row.offset_top = 14
	header_row.offset_bottom = 108
	header_row.add_theme_constant_override("separation", 16)
	header_row.alignment = BoxContainer.ALIGNMENT_CENTER
	header_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_frame.add_child(header_row)

	var left_button_section = HBoxContainer.new()
	left_button_section.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left_button_section.alignment = BoxContainer.ALIGNMENT_BEGIN
	left_button_section.add_theme_constant_override("separation", 10)
	header_row.add_child(left_button_section)

	btn_exit = TextureButton.new()
	btn_exit.custom_minimum_size = Vector2(EXIT_BUTTON_SIZE, EXIT_BUTTON_SIZE)
	btn_exit.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn_exit.ignore_texture_size = true
	btn_exit.mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_header_button_icon(btn_exit, "res://Assets/UI/icons/icon_close.png", "X", 34)
	btn_exit.pressed.connect(_on_exit)
	_wire_button_sfx(btn_exit)
	left_button_section.add_child(btn_exit)

	var gapL = Control.new()
	gapL.custom_minimum_size = Vector2(10, 0)
	gapL.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(gapL)

	var left_stats = VBoxContainer.new()
	left_stats.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	left_stats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_stats.alignment = BoxContainer.ALIGNMENT_CENTER
	left_stats.add_theme_constant_override("separation", 4)
	header_row.add_child(left_stats)

	var center_section = Control.new()
	center_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_section.custom_minimum_size = Vector2(260, 0)
	center_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_section.clip_contents = false
	header_row.add_child(center_section)

	title_label = Label.new()
	title_label.text = "TETRIS SUDOKU"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.visible = true
	title_label.z_index = 50
	title_label.self_modulate = Color(1, 1, 1, 1)
	title_label.custom_minimum_size = Vector2(0, 0)
	title_label.clip_text = true
	var fs = int(_skin_font_size("title", 44))
	if fs <= 0:
		fs = 44
	title_label.add_theme_font_size_override("font_size", fs)
	title_label.add_theme_color_override("font_color", _skin_color("text_primary", Color(0.10, 0.10, 0.10)))
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_label.clip_text = false
	center_section.add_child(title_label)

	title_texture_rect = TextureRect.new()
	title_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_texture_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title_texture_rect.visible = false
	center_section.add_child(title_texture_rect)
	var title_image_path = "res://Assets/UI/Title/Title_Tetris.png"
	if ResourceLoader.exists(title_image_path):
		var title_texture = load(title_image_path)
		if title_texture != null:
			title_texture_rect.texture = title_texture
			title_texture_rect.visible = true
			title_label.visible = false

	var right_stats = VBoxContainer.new()
	right_stats.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	right_stats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_stats.alignment = BoxContainer.ALIGNMENT_CENTER
	right_stats.add_theme_constant_override("separation", 4)
	header_row.add_child(right_stats)

	var gapR = Control.new()
	gapR.custom_minimum_size = Vector2(10, 0)
	gapR.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(gapR)

	var right_button_section = HBoxContainer.new()
	right_button_section.size_flags_horizontal = Control.SIZE_SHRINK_END
	right_button_section.alignment = BoxContainer.ALIGNMENT_END
	right_button_section.add_theme_constant_override("separation", 10)
	header_row.add_child(right_button_section)

	btn_settings = TextureButton.new()
	btn_settings.custom_minimum_size = Vector2(HEADER_BUTTON_SIZE, HEADER_BUTTON_SIZE)
	btn_settings.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn_settings.ignore_texture_size = true
	btn_settings.mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_header_button_icon(btn_settings, "res://Assets/UI/icons/icon_settings.png", "⚙", 40)
	btn_settings.pressed.connect(_on_settings)
	_wire_button_sfx(btn_settings)
	right_button_section.add_child(btn_settings)

	lbl_score = _hud_metric_row(left_stats, "score", "Score", "0")
	lbl_speed = _hud_metric_row(left_stats, "speed", "Speed", "1.00")
	lbl_level = _hud_metric_row(right_stats, "level", "Level", "1")
	lbl_time = _hud_metric_row(right_stats, "time", "Time", "00:00")

	var root_margin = MarginContainer.new()
	root_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_margin.add_theme_constant_override("margin_left", 24)
	root_margin.add_theme_constant_override("margin_right", 24)
	root_margin.add_theme_constant_override("margin_top", 118)
	root_margin.add_theme_constant_override("margin_bottom", 24)
	root_frame.add_child(root_margin)

	var main_v = VBoxContainer.new()
	main_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_v.add_theme_constant_override("separation", 14)
	root_margin.add_child(main_v)

	var top_row = HBoxContainer.new()
	top_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.size_flags_stretch_ratio = 1.22
	main_v.add_child(top_row)

	board_panel = Panel.new()
	board_panel.custom_minimum_size = Vector2(700, 740)
	board_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_panel.add_theme_stylebox_override("panel", _style_board_panel())
	top_row.add_child(board_panel)

	next_box = null

	well_panel = Panel.new()
	well_panel.custom_minimum_size = Vector2(0, 420)
	well_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	well_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	well_panel.size_flags_stretch_ratio = 1.03
	well_panel.add_theme_stylebox_override("panel", _style_bottom_panel())
	well_panel.clip_contents = false
	main_v.add_child(well_panel)

	well_draw = HBoxContainer.new()
	well_draw.name = "bottom_row"
	well_draw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	well_draw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	well_draw.size_flags_vertical = Control.SIZE_EXPAND_FILL
	well_draw.offset_left = 14
	well_draw.offset_right = -14
	well_draw.offset_top = 14
	well_draw.offset_bottom = -14
	well_draw.add_theme_constant_override("separation", 12)
	well_panel.add_child(well_draw)

	drop_zone_panel = Panel.new()
	drop_zone_panel.name = "drop_zone_panel"
	drop_zone_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drop_zone_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	drop_zone_panel.size_flags_stretch_ratio = 1.0
	drop_zone_panel.add_theme_stylebox_override("panel", _style_preview_box())
	well_draw.add_child(drop_zone_panel)

	const TIME_SLOW_GAP_W = 24.0
	time_slow_mid = PanelContainer.new()
	time_slow_mid.name = "time_slow_mid"
	time_slow_mid.custom_minimum_size = Vector2(TIME_SLOW_GAP_W, 0)
	time_slow_mid.size_flags_horizontal = Control.SIZE_FILL
	time_slow_mid.size_flags_stretch_ratio = 0.0
	time_slow_mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	time_slow_mid.z_index = 0
	time_slow_mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var time_slow_frame = StyleBoxFlat.new()
	time_slow_frame.set_border_width_all(2)
	time_slow_frame.border_color = Color(0.12, 0.12, 0.12, 0.7)
	time_slow_frame.bg_color = Color(0, 0, 0, 0)
	time_slow_mid.add_theme_stylebox_override("panel", time_slow_frame)
	time_slow_mid.clip_contents = true
	well_draw.add_child(time_slow_mid)

	var time_slow_frame_panel = PanelContainer.new()
	time_slow_frame_panel.name = "time_slow_frame_panel"
	time_slow_frame_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	time_slow_frame_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_slow_frame_panel.clip_contents = true
	time_slow_mid.add_child(time_slow_frame_panel)


	var time_slow_stack = Control.new()
	time_slow_stack.name = "time_slow_stack"
	time_slow_stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	time_slow_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_slow_frame_panel.add_child(time_slow_stack)

	time_slow_sand_rect = TextureRect.new()
	time_slow_sand_rect.name = "sand_rect"
	time_slow_sand_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	time_slow_sand_rect.offset_left = 0
	time_slow_sand_rect.offset_top = 0
	time_slow_sand_rect.offset_right = 0
	time_slow_sand_rect.offset_bottom = 0
	time_slow_sand_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_slow_sand_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	time_slow_sand_rect.stretch_mode = TextureRect.STRETCH_SCALE
	time_slow_sand_rect.visible = false
	time_slow_stack.add_child(time_slow_sand_rect)

	time_slow_glass_rect = TextureRect.new()
	time_slow_glass_rect.name = "glass_rect"
	time_slow_glass_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	time_slow_glass_rect.offset_left = 0
	time_slow_glass_rect.offset_top = 0
	time_slow_glass_rect.offset_right = 0
	time_slow_glass_rect.offset_bottom = 0
	time_slow_glass_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_slow_glass_rect.z_index = 1
	time_slow_glass_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	time_slow_glass_rect.stretch_mode = TextureRect.STRETCH_SCALE
	time_slow_glass_rect.visible = false
	time_slow_stack.add_child(time_slow_glass_rect)

	time_slow_frame_rect = TextureRect.new()
	time_slow_frame_rect.name = "frame_rect"
	time_slow_frame_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	time_slow_frame_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_slow_frame_rect.z_index = 2
	time_slow_frame_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	time_slow_frame_rect.stretch_mode = TextureRect.STRETCH_SCALE
	time_slow_frame_rect.visible = false
	time_slow_stack.add_child(time_slow_frame_rect)

	bar_time_slow = ProgressBar.new()
	bar_time_slow.custom_minimum_size = Vector2(14, 0)
	bar_time_slow.max_value = 100
	bar_time_slow.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	bar_time_slow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bar_time_slow.show_percentage = false
	bar_time_slow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_time_slow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar_time_slow.offset_left = 10
	bar_time_slow.offset_top = 12
	bar_time_slow.offset_right = -10
	bar_time_slow.offset_bottom = -12
	var time_slow_bg = StyleBoxFlat.new()
	time_slow_bg.bg_color = Color(0.10, 0.12, 0.14, 0.25)
	bar_time_slow.add_theme_stylebox_override("background", time_slow_bg)
	time_slow_stack.add_child(bar_time_slow)
	_setup_time_slow_future_assets()
	call_deferred("_sync_time_slow_column_width")


	well_slots_panel = Panel.new()
	well_slots_panel.name = "well_panel"
	well_slots_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	well_slots_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	well_slots_panel.size_flags_stretch_ratio = 1.0
	well_slots_panel.add_theme_stylebox_override("panel", _style_preview_box())
	well_draw.add_child(well_slots_panel)

	drop_zone_draw = Control.new()
	drop_zone_draw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	drop_zone_draw.offset_left = 10
	drop_zone_draw.offset_right = -10
	drop_zone_draw.offset_top = 10
	drop_zone_draw.offset_bottom = -10
	drop_zone_draw.mouse_filter = Control.MOUSE_FILTER_STOP
	drop_zone_panel.add_child(drop_zone_draw)

	well_slots_draw = Control.new()
	well_slots_draw.clip_contents = false
	well_slots_draw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	well_slots_draw.offset_left = 10
	well_slots_draw.offset_right = -10
	well_slots_draw.offset_top = 10
	well_slots_draw.offset_bottom = -10
	well_slots_draw.mouse_filter = Control.MOUSE_FILTER_STOP
	well_slots_panel.add_child(well_slots_draw)

	ghost_layer = Control.new()
	ghost_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ghost_layer.z_index = 1000
	root_frame.add_child(ghost_layer)

	ghost_root = Control.new()
	ghost_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost_root.visible = false
	ghost_layer.add_child(ghost_root)

	fx_layer = CanvasLayer.new()
	fx_layer.layer = 50
	add_child(fx_layer)
	time_slow_overlay = ColorRect.new()
	time_slow_overlay.color = Color(0.35, 0.70, 1.0, 0.0)
	time_slow_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	time_slow_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_slow_overlay.visible = false
	fx_layer.add_child(time_slow_overlay)

	toast_layer = CanvasLayer.new()
	toast_layer.layer = 60
	add_child(toast_layer)
	toast_panel = Panel.new()
	toast_panel.visible = false
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.add_theme_stylebox_override("panel", _style_preview_box())
	toast_panel.set_anchors_preset(Control.PRESET_CENTER)
	toast_panel.offset_left = -220
	toast_panel.offset_right = 220
	toast_panel.offset_top = -36
	toast_panel.offset_bottom = 36
	toast_layer.add_child(toast_panel)
	var toast_margin = MarginContainer.new()
	toast_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	toast_margin.add_theme_constant_override("margin_left", 12)
	toast_margin.add_theme_constant_override("margin_right", 12)
	toast_margin.add_theme_constant_override("margin_top", 8)
	toast_margin.add_theme_constant_override("margin_bottom", 8)
	toast_panel.add_child(toast_margin)
	toast_label = Label.new()
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.add_theme_font_size_override("font_size", _skin_font_size("small", 16))
	toast_margin.add_child(toast_label)

	overlay_dim = ColorRect.new()
	overlay_dim.color = Color(0, 0, 0, 0.55)
	overlay_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_dim.visible = false
	overlay_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_frame.add_child(overlay_dim)

	overlay_text = Label.new()
	overlay_text.text = "GAME OVER"
	overlay_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	overlay_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_text.add_theme_font_size_override("font_size", 72)
	overlay_text.add_theme_color_override("font_color", Color(1, 1, 1))
	overlay_text.visible = false
	overlay_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_frame.add_child(overlay_text)

	exit_dialog = AcceptDialog.new()
	exit_dialog.title = "Exit"
	exit_dialog.dialog_text = "What would you like to do?"
	exit_dialog.add_button("Main Menu", false, "main_menu")
	exit_dialog.add_button("Restart", false, "restart")
	exit_dialog.add_button("Cancel", true, "cancel")
	exit_dialog.custom_action.connect(_on_exit_dialog_action)
	root_frame.add_child(exit_dialog)

	settings_popup = SettingsPanel.build(root_frame, Callable(), {
		"state_getter": Callable(self, "_get_audio_settings_state"),
		"on_music_enabled": Callable(self, "_on_music_enabled_toggled"),
		"on_sfx_enabled": Callable(self, "_on_sfx_enabled_toggled"),
		"on_music_volume": Callable(self, "_on_music_volume_changed"),
		"on_sfx_volume": Callable(self, "_on_sfx_volume_changed")
	})


func _hud_line(k: String, v: String) -> Label:
	var l = Label.new()
	l.text = "%s: %s" % [k, v]
	l.add_theme_font_size_override("font_size", _skin_font_size("normal", 24))
	l.add_theme_color_override("font_color", _skin_color("text_primary", Color(0.10, 0.10, 0.10)))
	return l


func _hud_metric_row(parent: Control, metric_key: String, prefix: String, value: String) -> Label:
	var wrap = HBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wrap.add_theme_constant_override("separation", 6)
	parent.add_child(wrap)
	if metric_key == "score" or metric_key == "speed" or metric_key == "time":
		_add_icon_or_fallback(wrap, metric_key, 16, 28)
	var value_label = Label.new()
	value_label.text = "%s: %s" % [prefix, value]
	value_label.add_theme_font_size_override("font_size", _skin_font_size("small", 16))
	value_label.add_theme_color_override("font_color", _skin_color("text_primary", Color(0.10, 0.10, 0.10)))
	wrap.add_child(value_label)
	return value_label


func _load_ui_icon(key: String) -> Texture2D:
	if not UI_ICON_MAP.has(key):
		return null
	var cfg = UI_ICON_MAP[key]
	var tres_path = String(cfg.get("tres", ""))
	if tres_path != "" and ResourceLoader.exists(tres_path):
		var tres_tex = load(tres_path)
		if tres_tex is Texture2D:
			return tres_tex as Texture2D
	var png_path = String(cfg.get("png", ""))
	if png_path != "" and ResourceLoader.exists(png_path):
		var png_tex = load(png_path)
		if png_tex is Texture2D:
			return png_tex as Texture2D
	return null


func _ui_icon_placeholder(key: String, fallback_text: String) -> String:
	if UI_ICON_MAP.has(key):
		return String(UI_ICON_MAP[key].get("placeholder", fallback_text))
	return fallback_text


func _add_icon_or_fallback(parent: Control, icon_key: String, fallback_size: int, icon_size: int = 18) -> void:
	var tex = _load_ui_icon(icon_key)
	if tex != null:
		var icon = TextureRect.new()
		icon.custom_minimum_size = Vector2(icon_size, icon_size)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = tex
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(icon)
		return
	var fallback = Label.new()
	fallback.custom_minimum_size = Vector2(icon_size, icon_size)
	fallback.text = _ui_icon_placeholder(icon_key, "")
	fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fallback.add_theme_font_size_override("font_size", fallback_size)
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(fallback)


func _apply_header_button_icon(btn: TextureButton, icon_path: String, fallback_text: String, fallback_size: int) -> void:
	for ch in btn.get_children():
		ch.queue_free()
	if ResourceLoader.exists(icon_path):
		var tex = load(icon_path) as Texture2D
		if tex != null:
			btn.texture_normal = tex
			btn.texture_pressed = tex
			btn.texture_hover = tex
			btn.texture_disabled = tex
			return
	btn.texture_normal = null
	btn.texture_pressed = null
	btn.texture_hover = null
	btn.texture_disabled = null
	var fallback = Label.new()
	fallback.text = fallback_text
	fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fallback.add_theme_font_size_override("font_size", fallback_size)
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(fallback)


func _build_skill_card(label_text: String, req_level: int, progress_level: int) -> Control:
	var panel = Panel.new()
	panel.custom_minimum_size = Vector2(0, 84)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.clip_contents = true
	panel.add_theme_stylebox_override("panel", _style_preview_box())
	var row = HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_right = -10
	row.offset_top = 10
	row.offset_bottom = -10
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	var icon = Label.new()
	icon.text = "◼"
	icon.custom_minimum_size = Vector2(24, 24)
	icon.add_theme_font_size_override("font_size", 26)
	row.add_child(icon)

	var col = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(col)

	var t = Label.new()
	t.text = "%s (Lv.%d)" % [label_text, req_level]
	t.add_theme_font_size_override("font_size", _skin_font_size("small", 16))
	col.add_child(t)

	if progress_level >= req_level:
		var ready = Label.new()
		ready.text = "Ready"
		ready.add_theme_font_size_override("font_size", _skin_font_size("small", 16))
		col.add_child(ready)
	else:
		var pb = ProgressBar.new()
		pb.max_value = req_level
		pb.value = progress_level
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(0, 14)
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(pb)
		var lock = Label.new()
		lock.text = "Locked until Lv.%d" % req_level
		lock.add_theme_font_size_override("font_size", _skin_font_size("tiny", 12))
		col.add_child(lock)

	return panel


func _load_texture_or_null(path: String) -> Texture2D:
	if path == "":
		return null
	if not ResourceLoader.exists(path):
		return null
	var tex = load(path)
	if tex is Texture2D:
		return tex as Texture2D
	return null




func _safe_load_resource(path: String) -> Resource:
	if path == "":
		return null
	if not ResourceLoader.exists(path):
		return null
	return load(path)


func _setup_time_slow_future_assets() -> void:
	time_slow_atlas = _safe_load_resource(TIME_SLOW_ATLAS_PATH)
	time_slow_glass_overlay = _safe_load_resource(TIME_SLOW_GLASS_OVERLAY_PATH)
	time_slow_sand_fill = _safe_load_resource(TIME_SLOW_SAND_FILL_PATH)
	time_slow_frame_tex = _safe_load_resource(TIME_SLOW_FRAME_PATH)
	var sand_shader_res = _safe_load_resource(TIME_SLOW_SAND_SHADER_PATH)
	if sand_shader_res is Shader:
		time_slow_sand_shader = sand_shader_res as Shader
	else:
		time_slow_sand_shader = null
	var glass_shader_res = _safe_load_resource(TIME_SLOW_GLASS_SHADER_PATH)
	if glass_shader_res is Shader:
		time_slow_glass_shader = glass_shader_res as Shader
	else:
		time_slow_glass_shader = null
	time_slow_sand_mat = null
	time_slow_glass_mat = null
	if time_slow_sand_rect == null or time_slow_glass_rect == null or time_slow_frame_rect == null or bar_time_slow == null:
		return
	time_slow_sand_rect.visible = false
	time_slow_glass_rect.visible = false
	time_slow_frame_rect.visible = false
	bar_time_slow.visible = true
	if time_slow_sand_shader == null or time_slow_glass_shader == null:
		return
	var atlas_png_res = _safe_load_resource(TIME_SLOW_ATLAS_PNG_PATH)
	if not (atlas_png_res is Texture2D):
		return
	if not (time_slow_sand_fill is AtlasTexture):
		return
	if not (time_slow_glass_overlay is AtlasTexture):
		return
	if not (time_slow_frame_tex is AtlasTexture):
		return
	var atlas_png = atlas_png_res as Texture2D
	var sand_atlas = time_slow_sand_fill as AtlasTexture
	var glass_atlas = time_slow_glass_overlay as AtlasTexture
	var frame_atlas = time_slow_frame_tex as AtlasTexture
	var atlas_size = atlas_png.get_size()
	if atlas_size.x <= 0.0 or atlas_size.y <= 0.0:
		return
	var r = sand_atlas.region
	var uv_off = Vector2(r.position.x / atlas_size.x, r.position.y / atlas_size.y)
	var uv_sz = Vector2(r.size.x / atlas_size.x, r.size.y / atlas_size.y)
	var g = glass_atlas.region
	var glass_off = Vector2(g.position.x / atlas_size.x, g.position.y / atlas_size.y)
	var glass_sz = Vector2(g.size.x / atlas_size.x, g.size.y / atlas_size.y)
	time_slow_sand_mat = ShaderMaterial.new()
	time_slow_sand_mat.shader = time_slow_sand_shader
	time_slow_sand_mat.set_shader_parameter("u_atlas_tex", atlas_png)
	time_slow_sand_mat.set_shader_parameter("u_region_uv", Vector4(uv_off.x, uv_off.y, uv_sz.x, uv_sz.y))
	time_slow_sand_mat.set_shader_parameter("u_fill", 0.0)
	time_slow_sand_rect.material = time_slow_sand_mat
	time_slow_sand_rect.texture = atlas_png
	time_slow_sand_rect.visible = true
	time_slow_glass_mat = ShaderMaterial.new()
	time_slow_glass_mat.shader = time_slow_glass_shader
	time_slow_glass_mat.set_shader_parameter("u_atlas_tex", atlas_png)
	time_slow_glass_mat.set_shader_parameter("u_region_uv", Vector4(glass_off.x, glass_off.y, glass_sz.x, glass_sz.y))
	time_slow_glass_rect.material = time_slow_glass_mat
	time_slow_glass_rect.texture = atlas_png
	time_slow_glass_rect.visible = true
	time_slow_frame_rect.texture = frame_atlas
	time_slow_frame_rect.visible = true
	bar_time_slow.visible = false


func _build_skill_icon_button(icon_key: String) -> TextureButton:
	var b = TextureButton.new()
	b.custom_minimum_size = Vector2(64, 64)
	b.size = Vector2(64, 64)
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.ignore_texture_size = true
	b.texture_focused = null
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	var tex = _load_ui_icon(icon_key)
	if tex != null:
		b.texture_normal = tex
		b.texture_hover = tex
		b.texture_pressed = tex
		b.texture_disabled = tex
	else:
		var fallback = Label.new()
		fallback.text = _ui_icon_placeholder(icon_key, "?")
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fallback.add_theme_font_size_override("font_size", 20)
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(fallback)
	return b
func _on_skill_icon_pressed(btn: TextureButton, unlock_key: String, _locked_msg: String) -> void:
	if not Save.is_unlock_enabled(unlock_key):
		return
	if btn == btn_skill_freeze:
		try_use_freeze()
	elif btn == btn_skill_clear:
		try_use_clear_board()
	elif btn == btn_skill_invuln:
		try_use_safe_well()


func is_freeze_active() -> bool:
	return Time.get_ticks_msec() < freeze_effect_until_ms


func is_safe_well_active() -> bool:
	return Time.get_ticks_msec() < safe_well_effect_until_ms


func apply_freeze(duration_ms: int, multiplier: float) -> void:
	freeze_effect_multiplier = clamp(multiplier, 0.05, 1.0)
	freeze_effect_until_ms = Time.get_ticks_msec() + max(0, duration_ms)


func apply_safe_well(duration_ms: int) -> void:
	safe_well_effect_until_ms = Time.get_ticks_msec() + max(0, duration_ms)


func try_use_freeze() -> bool:
	if not Save.is_unlock_enabled("freeze_unlocked"):
		show_toast("Reach player level 5", 1.9)
		return false
	if used_freeze_this_round:
		show_toast("Freeze already used this round", 1.9)
		return false
	apply_freeze(FREEZE_DURATION_MS, FREEZE_MULTIPLIER)
	if skill_vfx_controller != null:
		skill_vfx_controller.on_freeze_cast(FREEZE_DURATION_MS)
	used_freeze_this_round = true
	_update_skill_icon_states()
	show_toast("Freeze active for 5s", 1.6)
	_play_sfx("ui_click")
	return true


func count_filled_cells_on_board() -> int:
	var count = 0
	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			if int(board.call("GetCell", x, y)) != 0:
				count += 1
	return count


func _clear_board_bulk() -> int:
	var filled_cells = count_filled_cells_on_board()
	if filled_cells <= 0:
		return 0
	board.call("Reset")
	_clear_color_grid()
	clear_flash_left = 0.0
	clear_flash_cells.clear()
	return filled_cells


func try_use_clear_board() -> bool:
	if not Save.is_unlock_enabled("clear_board_unlocked"):
		show_toast("Reach player level 10", 1.9)
		return false
	if used_clear_board_this_round:
		show_toast("Clear Board already used this round", 1.9)
		return false
	var filled_cells = _clear_board_bulk()
	if skill_vfx_controller != null:
		skill_vfx_controller.on_clear_board_cast()
	used_clear_board_this_round = true
	if filled_cells > 0:
		score += filled_cells * CLEAR_BOARD_POINTS_PER_CELL
		show_toast("Board cleared: +%d" % (filled_cells * CLEAR_BOARD_POINTS_PER_CELL), 1.7)
		_play_sfx("clear")
	else:
		show_toast("Board already empty", 1.5)
	_play_sfx("ui_click")
	_refresh_board_visual()
	_update_hud()
	_update_skill_icon_states()
	return true


func try_use_safe_well() -> bool:
	if not Save.is_unlock_enabled("safe_well_unlocked"):
		show_toast("Reach player level 20", 1.9)
		return false
	if used_safe_well_this_round:
		show_toast("Safe Well already used this round", 1.9)
		return false
	pile.clear()
	apply_safe_well(SAFE_WELL_DURATION_MS)
	if skill_vfx_controller != null:
		skill_vfx_controller.on_safe_well_cast(SAFE_WELL_DURATION_MS)
	used_safe_well_this_round = true
	show_toast("Safe Well active for 7s", 1.6)
	_play_sfx("ui_click")
	_redraw_well()
	_update_skill_icon_states()
	return true



func _required_level_for_unlock(unlock_key: String) -> int:
	if unlock_key == "freeze_unlocked":
		return 5
	if unlock_key == "clear_board_unlocked":
		return 10
	if unlock_key == "safe_well_unlocked":
		return 20
	return 0


func _skill_locked_tooltip(required_level: int) -> String:
	var current_level = Save.get_player_level()
	return "Reach Level %d (current %d)" % [required_level, current_level]


func _set_skill_button_state(button: TextureButton, unlock_key: String, used_this_round: bool, default_tooltip: String) -> void:
	if button == null:
		return
	var unlock_ready = Save.is_unlock_enabled(unlock_key)
	var locked = (not unlock_ready) or used_this_round
	button.disabled = locked
	if not unlock_ready:
		button.tooltip_text = _skill_locked_tooltip(_required_level_for_unlock(unlock_key))
	else:
		button.tooltip_text = default_tooltip

func _update_skill_icon_states() -> void:
	if btn_skill_freeze == null or btn_skill_clear == null or btn_skill_invuln == null:
		return
	var freeze_locked = not Save.is_unlock_enabled("freeze_unlocked") or used_freeze_this_round
	var clear_locked = not Save.is_unlock_enabled("clear_board_unlocked") or used_clear_board_this_round
	var well_locked = not Save.is_unlock_enabled("safe_well_unlocked") or used_safe_well_this_round
	var a_freeze = 0.45 if freeze_locked else 1.0
	var a_clear = 0.45 if clear_locked else 1.0
	var a_well = 0.45 if well_locked else 1.0
	btn_skill_freeze.modulate = Color(1, 1, 1, a_freeze)
	btn_skill_clear.modulate = Color(1, 1, 1, a_clear)
	btn_skill_invuln.modulate = Color(1, 1, 1, a_well)
	_set_skill_button_state(btn_skill_freeze, "freeze_unlocked", used_freeze_this_round, "Freeze time flow for 5 seconds")
	_set_skill_button_state(btn_skill_clear, "clear_board_unlocked", used_clear_board_this_round, "Clear all filled board cells")
	_set_skill_button_state(btn_skill_invuln, "safe_well_unlocked", used_safe_well_this_round, "Safe Well for 7 seconds")
	if btn_skill_freeze.get_child_count() > 0 and btn_skill_freeze.get_child(0) is Label:
		btn_skill_freeze.get_child(0).modulate = Color(1, 1, 1, a_freeze)
	if btn_skill_clear.get_child_count() > 0 and btn_skill_clear.get_child(0) is Label:
		btn_skill_clear.get_child(0).modulate = Color(1, 1, 1, a_clear)
	if btn_skill_invuln.get_child_count() > 0 and btn_skill_invuln.get_child(0) is Label:
		btn_skill_invuln.get_child(0).modulate = Color(1, 1, 1, a_well)


func show_toast(text: String, duration_sec: float = 1.9) -> void:
	if toast_panel == null or toast_label == null:
		return
	toast_label.text = text
	toast_panel.visible = true
	toast_hide_at_ms = Time.get_ticks_msec() + int(max(0.1, duration_sec) * 1000.0)


func _update_toast() -> void:
	if toast_panel == null:
		return
	if not toast_panel.visible:
		return
	if Time.get_ticks_msec() >= toast_hide_at_ms:
		toast_panel.visible = false


func _show_game_over_overlay() -> void:
	overlay_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay_dim.visible = true
	overlay_text.visible = true
	overlay_dim.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_start_round()
			set_process(true)
	)


func _hide_game_over_overlay() -> void:
	overlay_dim.visible = false
	overlay_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_text.visible = false


func _on_settings() -> void:
	if settings_popup == null:
		return
	if settings_popup.has_meta("sync_settings"):
		var sync_settings = settings_popup.get_meta("sync_settings")
		if sync_settings is Callable:
			(sync_settings as Callable).call()
	settings_popup.visible = true



func _get_audio_settings_state() -> Dictionary:
	return {
		"music_enabled": music_enabled,
		"sfx_enabled": sfx_enabled,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume
	}

func _on_music_enabled_toggled(enabled: bool) -> void:
	music_enabled = enabled
	_apply_audio_settings()
	_save_audio_settings()


func _on_sfx_enabled_toggled(enabled: bool) -> void:
	sfx_enabled = enabled
	_apply_audio_settings()
	_save_audio_settings()


func _on_music_volume_changed(value: float) -> void:
	music_volume = clamp(value / 100.0, 0.0, 1.0)
	_apply_audio_settings()
	_save_audio_settings()


func _on_sfx_volume_changed(value: float) -> void:
	sfx_volume = clamp(value / 100.0, 0.0, 1.0)
	_apply_audio_settings()
	_save_audio_settings()


func _on_exit() -> void:
	exit_dialog.popup_centered(Vector2i(380, 180))


func _on_exit_dialog_action(action: StringName) -> void:
	if action == "main_menu":
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)
	elif action == "restart":
		if get_tree().current_scene != null and get_tree().current_scene.scene_file_path == MAIN_SCENE:
			get_tree().reload_current_scene()
		else:
			_start_round()
			set_process(true)
	exit_dialog.hide()


# ============================================================
# Board build + colors
# ============================================================
func _clear_color_grid() -> void:
	color_grid.clear()
	for y in range(BOARD_SIZE):
		var row := []
		for x in range(BOARD_SIZE):
			row.append(null)
		color_grid.append(row)


func _build_board_side_overlays() -> void:
	var skills_holder = Control.new()
	skills_holder.name = "skills_holder"
	skills_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skills_holder.modulate = Color(1, 1, 1, 1)
	skills_holder.custom_minimum_size = Vector2(84, 0)
	skills_holder.size_flags_vertical = Control.SIZE_FILL
	board_panel.add_child(skills_holder)
	board_overlay_right = skills_holder

	var skills_bg = Panel.new()
	skills_bg.name = "skills_bg"
	skills_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	skills_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var skills_bg_style = StyleBoxFlat.new()
	skills_bg_style.bg_color = _skin_color("board_bg", Color(0.20, 0.22, 0.20, 1.0))
	skills_bg.add_theme_stylebox_override("panel", skills_bg_style)
	skills_holder.add_child(skills_bg)
	skills_holder.move_child(skills_bg, 0)

	var skills_margin = MarginContainer.new()
	skills_margin.name = "skills_margin"
	skills_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	skills_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skills_margin.add_theme_constant_override("margin_left", 8)
	skills_margin.add_theme_constant_override("margin_right", 8)
	skills_margin.add_theme_constant_override("margin_top", 10)
	skills_margin.add_theme_constant_override("margin_bottom", 10)
	skills_holder.add_child(skills_margin)

	var skills_v = VBoxContainer.new()
	skills_v.name = "skills_v"
	skills_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	skills_v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	skills_v.size_flags_horizontal = Control.SIZE_FILL
	skills_v.alignment = BoxContainer.ALIGNMENT_CENTER
	skills_v.add_theme_constant_override("separation", 10)
	skills_margin.add_child(skills_v)

	var top_sp = skills_v.add_spacer(true)
	top_sp.size_flags_vertical = Control.SIZE_EXPAND_FILL

	btn_skill_freeze = _build_skill_icon_button("freeze")
	btn_skill_freeze.tooltip_text = "Freeze time flow for 5 seconds"
	btn_skill_freeze.pressed.connect(func(): _on_skill_icon_pressed(btn_skill_freeze, "freeze_unlocked", "Reach player level 5"))
	skills_v.add_child(btn_skill_freeze)
	var mid1 = skills_v.add_spacer(false)
	mid1.size_flags_vertical = Control.SIZE_EXPAND_FILL

	btn_skill_clear = _build_skill_icon_button("clear")
	btn_skill_clear.tooltip_text = "Clear all filled board cells"
	btn_skill_clear.pressed.connect(func(): _on_skill_icon_pressed(btn_skill_clear, "clear_board_unlocked", "Reach player level 10"))
	skills_v.add_child(btn_skill_clear)
	var mid2 = skills_v.add_spacer(false)
	mid2.size_flags_vertical = Control.SIZE_EXPAND_FILL

	btn_skill_invuln = _build_skill_icon_button("safe_well")
	btn_skill_invuln.tooltip_text = "Safe Well for 7 seconds"
	btn_skill_invuln.pressed.connect(func(): _on_skill_icon_pressed(btn_skill_invuln, "safe_well_unlocked", "Reach player level 20"))
	skills_v.add_child(btn_skill_invuln)
	var bot_sp = skills_v.add_spacer(false)
	bot_sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_reposition_board_side_overlays()


func _reposition_board_side_overlays() -> void:
	if board_panel == null or board_overlay_right == null:
		return
	var grid_control = board_grid_overlay
	var grid_rect = Rect2(board_start, Vector2(BOARD_SIZE * cell_size, BOARD_SIZE * cell_size))
	if grid_control != null:
		grid_rect = Rect2(grid_control.position, grid_control.size)
	const BEZEL_PAD = 14.0
	var bezel_top = grid_rect.position.y - BEZEL_PAD
	var bezel_h = grid_rect.size.y + (BEZEL_PAD * 2.0)
	var extra_top := 11.0
	var extra_bottom := 8.0
	bezel_top -= extra_top
	bezel_h += extra_top + extra_bottom
	bezel_top = clamp(bezel_top, 0.0, max(0.0, board_panel.size.y - bezel_h))
	const GAP_FROM_GRID = 12.0
	var left_x = (grid_rect.position.x + grid_rect.size.x) + GAP_FROM_GRID
	const RIGHT_MARGIN = 10.0
	var right_x = board_panel.size.x - RIGHT_MARGIN
	var w = max(0.0, right_x - left_x)
	board_overlay_right.scale = Vector2.ONE
	board_overlay_right.position = Vector2(left_x, bezel_top)
	board_overlay_right.size = Vector2(w, bezel_h)
	var skill_even_area = board_overlay_right.get_node_or_null("skill_even_area") as Control
	if skill_even_area != null:
		skill_even_area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _build_board_grid() -> void:
	for ch in board_panel.get_children():
		ch.queue_free()

	board_cells.clear()
	board_hl.clear()
	_clear_color_grid()

	var board_px = min(board_panel.size.x, board_panel.size.y) - 40.0
	cell_size = int(floor(board_px / float(BOARD_SIZE)))
	board_px = float(cell_size * BOARD_SIZE)

	# Center grid in board panel
	board_start = Vector2(
		int((board_panel.size.x - board_px) * 0.5),
		int((board_panel.size.y - board_px) * 0.55) # push slightly down (less empty top)
	)

	var screen_bezel = Panel.new()
	screen_bezel.position = board_start - Vector2(14, 14)
	screen_bezel.size = Vector2(board_px + 28, board_px + 28)
	screen_bezel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var screen_bezel_style = StyleBoxFlat.new()
	screen_bezel_style.bg_color = Color(0.06, 0.08, 0.07, 0.95)
	screen_bezel_style.border_width_left = 4
	screen_bezel_style.border_width_right = 4
	screen_bezel_style.border_width_top = 4
	screen_bezel_style.border_width_bottom = 4
	screen_bezel_style.border_color = Color(0.28, 0.30, 0.28)
	screen_bezel_style.corner_radius_top_left = 12
	screen_bezel_style.corner_radius_top_right = 12
	screen_bezel_style.corner_radius_bottom_left = 12
	screen_bezel_style.corner_radius_bottom_right = 12
	screen_bezel.add_theme_stylebox_override("panel", screen_bezel_style)
	board_panel.add_child(screen_bezel)

	for y in range(BOARD_SIZE):
		var row := []
		var row2 := []
		for x in range(BOARD_SIZE):
			var cell := Panel.new()
			cell.position = board_start + Vector2(x * cell_size, y * cell_size)
			cell.size = Vector2(cell_size - 2, cell_size - 2)
			cell.mouse_filter = Control.MOUSE_FILTER_STOP
			cell.gui_input.connect(func(ev): _on_board_cell_input(ev, x, y))
			cell.add_theme_stylebox_override("panel", _style_cell_empty(x, y))
			board_panel.add_child(cell)
			row.append(cell)

			var hl := ColorRect.new()
			hl.position = cell.position
			hl.size = cell.size
			hl.color = Color(0, 0, 0, 0)
			hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			board_panel.add_child(hl)
			row2.append(hl)

		board_cells.append(row)
		board_hl.append(row2)

	board_grid_overlay = BoardGridOverlay.new()
	board_grid_overlay.position = board_start
	board_grid_overlay.size = Vector2(BOARD_SIZE * cell_size, BOARD_SIZE * cell_size)
	board_grid_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_grid_overlay.call("configure", BOARD_SIZE, cell_size)
	var grid_col = _skin_color("grid_border", Color(0.90, 0.66, 0.34, 0.95))
	board_grid_overlay.thin_color = Color(grid_col.r, grid_col.g, grid_col.b, 0.40)
	board_grid_overlay.thick_color = Color(grid_col.r, grid_col.g, grid_col.b, 0.92)
	board_panel.add_child(board_grid_overlay)

	var glare = ColorRect.new()
	glare.position = board_start
	glare.size = Vector2(BOARD_SIZE * cell_size, BOARD_SIZE * cell_size)
	glare.color = Color(1, 1, 1, 0.04)
	glare.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_panel.add_child(glare)

	_build_board_side_overlays()
	_refresh_board_visual()


func _refresh_board_visual() -> void:
	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			var v := int(board.call("GetCell", x, y))
			if v == 1:
				var c = color_grid[y][x]
				if c == null:
					c = COLOR_FILLED
				board_cells[y][x].add_theme_stylebox_override("panel", _style_cell_filled_colored(c))
			else:
				board_cells[y][x].add_theme_stylebox_override("panel", _style_cell_empty(x, y))
				color_grid[y][x] = null

			board_hl[y][x].color = Color(0, 0, 0, 0)
	if clear_flash_left > 0.0:
		var a = clamp(clear_flash_left * 3.8, 0.0, 0.8)
		for pos in clear_flash_cells:
			var fx = int(pos.x)
			var fy = int(pos.y)
			if fx >= 0 and fx < BOARD_SIZE and fy >= 0 and fy < BOARD_SIZE:
				board_hl[fy][fx].color = Color(1.0, 1.0, 0.45, a)


# ============================================================
# Next preview
# ============================================================
func _update_previews() -> void:
	if next_box == null:
		return
	var next_piece = core.call("PeekNextPieceForBoard", board)
	_draw_preview(next_box, next_piece)


func _draw_preview(target: Panel, piece) -> void:
	for ch in target.get_children():
		ch.queue_free()

	target.queue_redraw()
	if piece == null:
		return

	var target_size = Vector2(max(target.size.x, target.custom_minimum_size.x), max(target.size.y, target.custom_minimum_size.y))
	var target_rect = Rect2(Vector2.ZERO, target_size)
	var preview_size = target_rect.size - Vector2(20, 20)
	if preview_size.x <= 0.0 or preview_size.y <= 0.0:
		return

	var desired_cell = int(clamp(float(cell_size) * 0.75, 14.0, 34.0))
	var preview_cell_size = _fitted_cell_size(piece, desired_cell, preview_size, 0.97)

	var min_x = 999
	var min_y = 999
	var max_x = -999
	var max_y = -999
	for c in piece.get("Cells"):
		min_x = min(min_x, int(c.x))
		min_y = min(min_y, int(c.y))
		max_x = max(max_x, int(c.x))
		max_y = max(max_y, int(c.y))

	var bbox_px_w = (max_x - min_x + 1) * preview_cell_size
	var bbox_px_h = (max_y - min_y + 1) * preview_cell_size
	var offset = (preview_size - Vector2(bbox_px_w, bbox_px_h)) * 0.5 - Vector2(min_x, min_y) * preview_cell_size

	var pv = Control.new()
	pv.size = preview_size
	pv.position = (target_rect.size - preview_size) * 0.5
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var col = _color_for_kind(String(piece.get("Kind")))
	for c in piece.get("Cells"):
		var b = _bevel_block(col, preview_cell_size - 2)
		b.position = offset + Vector2(int(c.x) * preview_cell_size, int(c.y) * preview_cell_size)
		pv.add_child(b)

	target.add_child(pv)


func _fitted_cell_size(piece, desired_cell: int, frame: Vector2, fit_ratio: float = 0.9) -> int:
	var min_x = 999
	var min_y = 999
	var max_x = -999
	var max_y = -999
	for c in piece.get("Cells"):
		min_x = min(min_x, int(c.x))
		min_y = min(min_y, int(c.y))
		max_x = max(max_x, int(c.x))
		max_y = max(max_y, int(c.y))

	var bbox_w_cells = max(1, max_x - min_x + 1)
	var bbox_h_cells = max(1, max_y - min_y + 1)
	var fit_w = frame.x / float(bbox_w_cells)
	var fit_h = frame.y / float(bbox_h_cells)
	var fit_cell = int(floor(min(fit_w, fit_h) * fit_ratio))
	fit_cell = max(8, fit_cell)
	return min(desired_cell, fit_cell)


func _spawn_falling_piece() -> void:
	fall_piece = core.call("PopNextPieceForBoard", board)
	fall_y = 10.0
	pending_spawn_piece = false
	if dual_drop_cycle_pending:
		var speed_mul = float(core.call("GetDisplayedFallSpeed")) / max(0.001, float(core.call("GetBaseFallSpeed")))
		var stagger_sec = float(core.call("GetDualDropStaggerSecForSpeedMul", speed_mul))
		pending_dual_spawn_ms = Time.get_ticks_msec() + int(stagger_sec * 1000.0)
		pending_dual_fallback_ms = Time.get_ticks_msec() + 2000
		dual_drop_waiting_for_gap = true
		dual_drop_anchor_y = fall_y
		dual_drop_cycle_pending = false
	if next_box != null:
		next_box.queue_redraw()
	_update_previews()

func _dual_drop_can_spawn(now_ms: int) -> bool:
	if is_game_over:
		return false
	if pending_dual_spawn_ms <= 0 or now_ms < pending_dual_spawn_ms:
		return false
	if not dual_drop_waiting_for_gap:
		return true
	var min_gap_cells = float(core.call("GetDualDropMinGapCells"))
	var min_gap_px = min_gap_cells * float(cell_size)
	if fall_piece == null:
		return true
	if fall_y >= dual_drop_anchor_y + min_gap_px:
		return true
	if pending_dual_fallback_ms > 0 and now_ms >= pending_dual_fallback_ms:
		return true
	return false

func _spawn_second_falling_piece() -> void:
	if is_game_over:
		pending_dual_spawn_ms = 0
		pending_dual_fallback_ms = 0
		dual_drop_waiting_for_gap = false
		return
	if fall_piece_2 != null:
		return
	var p2 = core.call("PopNextPieceForBoard", board)
	if fall_piece == null:
		fall_piece = p2
		fall_y = 10.0
	else:
		fall_piece_2 = p2
		fall_y_2 = 10.0
	pending_dual_spawn_ms = 0
	pending_dual_fallback_ms = 0
	dual_drop_waiting_for_gap = false
	if next_box != null:
		next_box.queue_redraw()
	_update_previews()


func _lock_falling_to_pile() -> void:
	_commit_piece_to_well(fall_piece)


func _selected_neon_pile_index() -> int:
	if selected_from_pile_index >= 0 and selected_from_pile_index < pile.size():
		return selected_from_pile_index
	if pile.size() <= 0:
		return -1
	var max_selectable = min(pile_selectable, pile.size())
	if max_selectable <= 0:
		return -1
	return pile.size() - 1


func _well_geometry() -> Dictionary:
	var drop_h = drop_zone_draw.size.y
	var drop_w = drop_zone_draw.size.x
	var slots_h = well_slots_draw.size.y
	var slots_w = well_slots_draw.size.x
	var full_h = well_panel.size.y - 28.0

	if drop_h <= 1.0 or drop_w <= 1.0 or slots_h <= 1.0 or slots_w <= 1.0 or full_h <= 1.0:
		return {
			"drop_w": 100.0,
			"drop_h": 100.0,
			"slots_w": 80.0,
			"slots_h": 100.0,
			"fall_top": 10.0,
			"fall_bottom": 50.0,
			"pile_top": 10.0,
			"pile_bottom": 90.0
		}

	var fall_top = FALL_PAD
	var fall_bottom = drop_h - 120.0
	if fall_bottom < fall_top + 40.0:
		fall_bottom = fall_top + 40.0

	return {
		"drop_w": drop_w,
		"drop_h": drop_h,
		"slots_w": slots_w,
		"slots_h": slots_h,
		"fall_top": fall_top,
		"fall_bottom": fall_bottom,
		"pile_top": 8.0,
		"pile_bottom": slots_h - 8.0
	}


func _redraw_well() -> void:
	for ch in drop_zone_draw.get_children():
		ch.queue_free()
	for ch in well_slots_draw.get_children():
		ch.queue_free()

	var g = _well_geometry()
	var drop_w = float(g["drop_w"])
	var slots_w = float(g["slots_w"])
	var slots_h = float(g["slots_h"])
	var pile_top = float(g["pile_top"])
	var pile_bottom = float(g["pile_bottom"])
	var fall_top = float(g["fall_top"])
	var fall_bottom = float(g["fall_bottom"])

	var fill_ratio = clamp(float(pile.size()) / float(pile_max), 0.0, 1.0)
	var now_ms = Time.get_ticks_msec()
	var neon_speed = float(core.call("GetWellNeonPulseSpeed"))
	var neon = 0.5 + 0.5 * sin(float(now_ms) / 1000.0 * TAU * neon_speed)
	
	var drop_header = Label.new()
	drop_header.text = "DROP ZONE"
	drop_header.position = Vector2(8, 4)
	drop_header.add_theme_font_size_override("font_size", _skin_font_size("small", 16))
	drop_header.add_theme_color_override("font_color", _skin_color("text_muted", Color(0.84, 0.84, 0.84)))
	drop_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drop_zone_draw.add_child(drop_header)

	var drop_marker = ColorRect.new()
	drop_marker.color = Color(1.0, 1.0, 1.0, 0.10)
	drop_marker.position = Vector2(0, fall_top - 10)
	drop_marker.size = Vector2(drop_w, 8)
	drop_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drop_zone_draw.add_child(drop_marker)


	var slots_header_row = HBoxContainer.new()
	slots_header_row.position = Vector2(8, 4)
	slots_header_row.size = Vector2(max(0.0, slots_w - 16.0), 28)
	slots_header_row.add_theme_constant_override("separation", 10)
	slots_header_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well_slots_draw.add_child(slots_header_row)

	var slots_progress = ProgressBar.new()
	slots_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots_progress.custom_minimum_size = Vector2(0, 18)
	slots_progress.max_value = 1.0
	slots_progress.value = fill_ratio
	slots_progress.show_percentage = false
	slots_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var slots_fill_style = StyleBoxFlat.new()
	if fill_ratio < 0.50:
		slots_fill_style.bg_color = Color(0.30, 0.78, 0.34, 1.0)
	elif fill_ratio < 0.70:
		slots_fill_style.bg_color = Color(0.90, 0.78, 0.25, 1.0)
	else:
		slots_fill_style.bg_color = Color(0.88, 0.30, 0.30, 1.0)
	slots_progress.add_theme_stylebox_override("fill", slots_fill_style)
	slots_header_row.add_child(slots_progress)

	var slots_top = max(pile_top, 58.0)
	var slot_w = max(0.0, slots_w - 16.0)
	var available_h = max(140.0, pile_bottom - slots_top)
	var per_slot = available_h / float(max(1, pile_max))
	var dynamic_h = max(64.0, min(120.0, per_slot - SLOT_GAP * 0.5))
	var slot_preview_cell = int(clamp(float(cell_size) * 0.95, 14.0, 52.0))
	var neon_min = float(core.call("GetWellNeonMinAlpha"))
	var neon_max = float(core.call("GetWellNeonMaxAlpha"))

	for slot_i in range(pile_max):
		var y = pile_bottom - dynamic_h - float(slot_i) * (dynamic_h + SLOT_GAP)

		var slot = Panel.new()
		slot.size = Vector2(slot_w, dynamic_h)
		slot.position = Vector2(8, y)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		well_slots_draw.add_child(slot)

		var pile_index = (pile.size() - 1) - slot_i
		var is_active = slot_i < pile_selectable

		if is_active:
			slot.add_theme_stylebox_override("panel", _style_stack_slot_selectable())
			slot.modulate = Color(1.0, 1.0, 0.85 + 0.15 * neon, 1.0)
		else:
			slot.add_theme_stylebox_override("panel", _style_stack_slot_locked())

		if pile_index >= 0:
			var p = pile[pile_index]
			if is_active:
				slot.gui_input.connect(func(ev): _on_pile_slot_input(ev, pile_index))

			var slot_frame = Vector2(slot.size.x - 6, slot.size.y - 6)
			var slot_cell = _fitted_cell_size(p, slot_preview_cell, slot_frame, 0.97)
			var preview = _make_piece_preview(p, slot_cell, slot_frame)
			var slot_rect = Rect2(Vector2.ZERO, slot.size)
			preview.position = slot_rect.position + (slot_rect.size - preview.size) * 0.5
			slot.add_child(preview)
			if is_active:
				var neon_phase = 0.5 + 0.5 * sin(float(now_ms) / 1000.0 * TAU * neon_speed)
				var neon_alpha = lerp(neon_min, neon_max, neon_phase)
				var neon_frame = Panel.new()
				neon_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				neon_frame.offset_left = 2
				neon_frame.offset_top = 2
				neon_frame.offset_right = -2
				neon_frame.offset_bottom = -2
				neon_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
				var neon_style = StyleBoxFlat.new()
				neon_style.bg_color = Color(0, 0, 0, 0)
				neon_style.border_width_left = 3
				neon_style.border_width_top = 3
				neon_style.border_width_right = 3
				neon_style.border_width_bottom = 3
				neon_style.border_color = Color(1.0, 0.92, 0.40, neon_alpha)
				neon_style.corner_radius_top_left = 8
				neon_style.corner_radius_top_right = 8
				neon_style.corner_radius_bottom_left = 8
				neon_style.corner_radius_bottom_right = 8
				neon_frame.add_theme_stylebox_override("panel", neon_style)
				slot.add_child(neon_frame)
		elif is_active:
			pass

	if fall_piece != null and not is_game_over:
		var drop_cell_size = int(clamp(float(cell_size) * 1.0, 18.0, 54.0))
		var fall_frame_w = min(drop_w - 20.0, 300.0)
		var fall_frame = Vector2(fall_frame_w, 170)
		var fitted_drop_cell = _fitted_cell_size(fall_piece, drop_cell_size, fall_frame, 0.97)
		var fall = _make_piece_preview(fall_piece, fitted_drop_cell, fall_frame)
		var fx = (drop_w - fall.size.x) * 0.5
		var fy = clamp(fall_y, fall_top, fall_bottom)
		fall.position = Vector2(fx, fy)
		fall.mouse_filter = Control.MOUSE_FILTER_STOP
		fall.gui_input.connect(func(ev): _on_falling_piece_input(ev, 1))
		drop_zone_draw.add_child(fall)

	if fall_piece_2 != null and not is_game_over:
		var drop_cell_size_2 = int(clamp(float(cell_size) * 1.0, 18.0, 54.0))
		var fall_frame_w_2 = min(drop_w - 20.0, 300.0)
		var fall_frame_2 = Vector2(fall_frame_w_2, 170)
		var fitted_drop_cell_2 = _fitted_cell_size(fall_piece_2, drop_cell_size_2, fall_frame_2, 0.97)
		var fall2 = _make_piece_preview(fall_piece_2, fitted_drop_cell_2, fall_frame_2)
		var fx2 = (drop_w - fall2.size.x) * 0.5
		var fy2 = clamp(fall_y_2, fall_top, fall_bottom)
		fall2.position = Vector2(fx2, fy2)
		fall2.mouse_filter = Control.MOUSE_FILTER_STOP
		fall2.gui_input.connect(func(ev): _on_falling_piece_input(ev, 2))
		drop_zone_draw.add_child(fall2)

func _on_pile_slot_input(event: InputEvent, pile_index: int) -> void:
	if is_game_over:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected_piece = pile[pile_index]
		selected_from_pile_index = pile_index
		_play_sfx("pick")
		_start_drag_selected()


func _on_falling_piece_input(event: InputEvent, slot: int) -> void:
	if is_game_over:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if slot == 1:
			selected_piece = fall_piece
		elif slot == 2:
			selected_piece = fall_piece_2
		selected_from_pile_index = -1
		_play_sfx("pick")
		_start_drag_selected()


# ============================================================
# Drag + place
# ============================================================
func _start_drag_selected() -> void:
	if selected_piece == null:
		return
	_ensure_piece_state(selected_piece)
	# Committed pieces in the well MUST remain pickable (yellow/top_selectable logic is elsewhere).
	# Only block re-grab if this piece is explicitly grace-blocked.
	if bool(selected_piece.get_meta("grace_blocked", false)):
		selected_piece = null
		selected_from_pile_index = -1
		return
	_set_piece_in_hand_state(selected_piece, true)
	if selected_from_pile_index >= 0:
		rescue_from_well_pending = true
		rescue_eligible_until_ms = Time.get_ticks_msec() + int(float(core.call("GetRescueWindowSec")) * 1000.0)
	dragging = true
	drag_anchor = Vector2i(-999, -999)
	drag_start_ms = Time.get_ticks_msec()
	_build_ghost_for_piece(selected_piece)
	ghost_root.visible = true


func _finish_drag() -> void:
	dragging = false
	ghost_root.visible = false

	var anchor = drag_anchor
	var release_mouse = get_viewport().get_mouse_position()
	var selected_snapshot = selected_piece
	var source_snapshot = selected_from_pile_index
	drag_anchor = Vector2i(-999, -999)
	_clear_highlight()

	var was_selected := selected_piece != null
	var placed := false
	if anchor.x != -999 and was_selected:
		placed = _try_place_piece(selected_piece, anchor.x, anchor.y)

	if was_selected and not placed:
		_play_sfx("invalid")
		core.call("RegisterCancelledDrag")
		_spawn_pending_invalid_piece(selected_snapshot, source_snapshot, release_mouse)
	if was_selected:
		_set_piece_in_hand_state(selected_snapshot, false)

	selected_piece = null
	selected_from_pile_index = -1

func _ensure_piece_state(piece) -> void:
	if piece == null:
		return
	if not piece.has_meta("piece_id"):
		piece.set_meta("piece_id", next_piece_state_id)
		next_piece_state_id += 1
	if not piece.has_meta("is_in_hand"):
		piece.set_meta("is_in_hand", false)
	if not piece.has_meta("is_in_grace"):
		piece.set_meta("is_in_grace", false)
	if not piece.has_meta("is_committed"):
		piece.set_meta("is_committed", false)
	if not piece.has_meta("grace_timer"):
		piece.set_meta("grace_timer", null)
	if not piece.has_meta("grace_blocked"):
		piece.set_meta("grace_blocked", false)
	_assert_piece_state_invariant(piece)


func _piece_is_committed(piece) -> bool:
	if piece == null:
		return false
	_ensure_piece_state(piece)
	return bool(piece.get_meta("is_committed", false))


func _piece_is_in_hand(piece) -> bool:
	if piece == null:
		return false
	_ensure_piece_state(piece)
	return bool(piece.get_meta("is_in_hand", false))


func _piece_is_in_grace(piece) -> bool:
	if piece == null:
		return false
	_ensure_piece_state(piece)
	return bool(piece.get_meta("is_in_grace", false))


func _assert_piece_state_invariant(piece) -> void:
	if piece == null:
		return
	var committed = bool(piece.get_meta("is_committed", false))
	var in_hand = bool(piece.get_meta("is_in_hand", false))
	if committed and in_hand:
		push_error("Piece state invariant failed: committed and in_hand for piece_id=%d" % int(piece.get_meta("piece_id", -1)))


func _set_piece_in_hand_state(piece, in_hand: bool) -> void:
	if piece == null:
		return
	_ensure_piece_state(piece)
	piece.set_meta("is_in_hand", in_hand)
	if in_hand:
		piece.set_meta("is_in_grace", false)
	_assert_piece_state_invariant(piece)


func _commit_piece_to_well(piece) -> void:
	if piece == null:
		return
	_ensure_piece_state(piece)
	if bool(piece.get_meta("is_committed", false)):
		return
	piece.set_meta("is_committed", true)
	# Block grace re-grab ONLY if this piece is currently part of the grace flow.
	var was_in_grace = bool(piece.get_meta("is_in_grace", false)) or (pending_invalid_piece == piece)
	piece.set_meta("grace_blocked", was_in_grace)
	piece.set_meta("is_in_grace", false)
	piece.set_meta("is_in_hand", false)
	var piece_id = int(piece.get_meta("piece_id", -1))
	grace_piece_by_id.erase(piece_id)
	var grace_timer = null
	if piece.has_meta("grace_timer"):
		grace_timer = piece.get_meta("grace_timer")
	else:
		piece.set_meta("grace_timer", null)
	if grace_timer != null and is_instance_valid(grace_timer):
		grace_timer.stop()
		grace_timer.call_deferred("queue_free")
	piece.set_meta("grace_timer", null)
	if pending_invalid_piece == piece:
		_clear_pending_invalid_piece()
	if selected_piece == piece:
		_force_cancel_drag("CommittedToWell", true)
	if piece == fall_piece:
		fall_piece = null
	elif piece == fall_piece_2:
		fall_piece_2 = null
	if is_safe_well_active():
		# Discard the falling piece safely (PieceData is a Resource, no queue_free()).
		if piece == fall_piece:
			fall_piece = null
		elif piece == fall_piece_2:
			fall_piece_2 = null

		# If this piece was involved in grace/drag, clear those references too.
		if pending_invalid_piece == piece:
			_clear_pending_invalid_piece()
		if selected_piece == piece:
			_force_cancel_drag("SafeWellDiscard", true)

		_assert_piece_state_invariant(piece)

		if _active_falling_count() == 0 and pending_dual_spawn_ms == 0:
			_schedule_next_falling_piece()
		return
	_assert_piece_state_invariant(piece)
	var stored = piece.duplicate(true)
	_ensure_piece_state(stored)
	stored.set_meta("is_committed", true)
	stored.set_meta("is_in_hand", false)
	stored.set_meta("is_in_grace", false)
	stored.set_meta("grace_blocked", false) # in the well it must be pickable
	pile.append(stored)
	_play_sfx("well_enter")
	_try_trigger_first_well_entry_slow()
	_trigger_micro_freeze()
	well_header_pulse_left = 0.35
	if pile.size() > pile_max:
		_trigger_game_over()
		return
	if _active_falling_count() == 0 and pending_dual_spawn_ms == 0:
		_schedule_next_falling_piece()



func _spawn_pending_invalid_piece(piece, source_index: int, screen_pos: Vector2) -> void:
	if piece == null:
		return
	_ensure_piece_state(piece)
	# Block only if explicitly blocked from grace re-grab after a commit race.
	if bool(piece.get_meta("grace_blocked", false)):
		return
	_clear_pending_invalid_piece()
	piece.set_meta("is_in_hand", false)
	piece.set_meta("is_in_grace", true)
	_assert_piece_state_invariant(piece)
	pending_invalid_piece = piece
	pending_invalid_from_pile_index = source_index
	pending_invalid_until_ms = Time.get_ticks_msec() + int(float(core.call("GetInvalidDropGraceSec")) * 1000.0)
	grace_piece_by_id[int(piece.get_meta("piece_id", -1))] = piece
	if pending_invalid_timer != null and is_instance_valid(pending_invalid_timer):
		pending_invalid_timer.stop()
		pending_invalid_timer.queue_free()
	pending_invalid_timer = Timer.new()
	pending_invalid_timer.one_shot = true
	pending_invalid_timer.wait_time = max(0.01, float(core.call("GetInvalidDropGraceSec")))
	pending_invalid_timer.timeout.connect(_on_pending_invalid_timeout.bind(int(piece.get_meta("piece_id", -1))))
	add_child(pending_invalid_timer)

	piece.set_meta("grace_timer", pending_invalid_timer)
	pending_invalid_timer.start()

	var frame = Vector2(max(48.0, float(cell_size) * 2.0), max(48.0, float(cell_size) * 2.0))
	pending_invalid_root = Control.new()
	pending_invalid_root.size = frame
	pending_invalid_root.mouse_filter = Control.MOUSE_FILTER_STOP
	pending_invalid_root.z_index = 1200
	pending_invalid_root.z_as_relative = false
	pending_invalid_root.position = screen_pos - frame * 0.5
	pending_invalid_root.gui_input.connect(_on_pending_invalid_input)

	var pv = _make_piece_preview(piece, max(16, int(float(cell_size) * 0.78)), frame)
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pending_invalid_root.add_child(pv)
	root_frame.add_child(pending_invalid_root)


func _clear_pending_invalid_piece() -> void:
	if pending_invalid_piece != null:
		_ensure_piece_state(pending_invalid_piece)
		pending_invalid_piece.set_meta("is_in_grace", false)
		pending_invalid_piece.set_meta("grace_timer", null)
		grace_piece_by_id.erase(int(pending_invalid_piece.get_meta("piece_id", -1)))
	if pending_invalid_timer != null and is_instance_valid(pending_invalid_timer):
		pending_invalid_timer.stop()
		pending_invalid_timer.call_deferred("queue_free")
	pending_invalid_timer = null
	if pending_invalid_root != null and is_instance_valid(pending_invalid_root):
		pending_invalid_root.call_deferred("queue_free")
	pending_invalid_root = null
	pending_invalid_piece = null
	pending_invalid_from_pile_index = -1
	pending_invalid_until_ms = 0


func _on_pending_invalid_input(event: InputEvent) -> void:
	if pending_invalid_piece == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_ensure_piece_state(pending_invalid_piece)
		if bool(pending_invalid_piece.get_meta("grace_blocked", false)):
			_clear_pending_invalid_piece()
			return
		_ensure_piece_state(pending_invalid_piece)
		pending_invalid_piece.set_meta("is_in_grace", false)
		pending_invalid_piece.set_meta("is_in_hand", true)
		pending_invalid_piece.set_meta("grace_timer", null)
		_assert_piece_state_invariant(pending_invalid_piece)
		selected_piece = pending_invalid_piece
		selected_from_pile_index = pending_invalid_from_pile_index
		_clear_pending_invalid_piece()
		_play_sfx("pick")
		call_deferred("_start_drag_selected")


func _update_pending_invalid_grace() -> void:
	if pending_invalid_piece == null:
		return
	_ensure_piece_state(pending_invalid_piece)
	if bool(pending_invalid_piece.get_meta("grace_blocked", false)) or _piece_is_in_hand(pending_invalid_piece):
		return
	if Time.get_ticks_msec() < pending_invalid_until_ms:
		return
	_on_pending_invalid_timeout(int(pending_invalid_piece.get_meta("piece_id", -1)))


func _on_pending_invalid_timeout(piece_id: int) -> void:
	var piece = grace_piece_by_id.get(piece_id, null)
	if piece == null:
		return
	_ensure_piece_state(piece)
	if bool(piece.get_meta("grace_blocked", false)) or _piece_is_in_hand(piece):
		return
	if not _piece_is_in_grace(piece):
		return
	_clear_pending_invalid_piece()
	invalid_drop_slow_until_ms = Time.get_ticks_msec() + int(float(core.call("GetInvalidDropFailSlowSec")) * 1000.0)


func _force_cancel_drag(reason: String = "", committed: bool = false) -> void:
	dragging = false
	ghost_root.visible = false
	drag_anchor = Vector2i(-999, -999)
	_clear_highlight()
	if committed:
		selected_piece = null
		selected_from_pile_index = -1



func _try_place_piece(piece, ax: int, ay: int) -> bool:
	if not bool(board.call("CanPlace", piece, ax, ay)):
		_play_sfx("invalid")
		return false

	var result: Dictionary = board.call("PlaceAndClear", piece, ax, ay)

	# Paint placed cells
	var kind = String(piece.get("Kind"))
	var col = _color_for_kind(kind)
	for c in piece.get("Cells"):
		var x = ax + int(c.x)
		var y = ay + int(c.y)
		if x >= 0 and x < BOARD_SIZE and y >= 0 and y < BOARD_SIZE:
			color_grid[y][x] = col

	# Clear colors for cleared cells
	var cleared = result.get("cleared", [])
	for pos in cleared:
		var px = int(pos.x)
		var py = int(pos.y)
		if px >= 0 and px < BOARD_SIZE and py >= 0 and py < BOARD_SIZE:
			color_grid[py][px] = null

	score += int(piece.get("Cells").size())
	var cleared_count = int(result.get("cleared_count", 0))
	score += cleared_count * 2

	# Remove from pile if it came from pile
	var placed_from_well = selected_from_pile_index >= 0 and selected_from_pile_index < pile.size()
	if placed_from_well:
		_ensure_piece_state(piece)
		piece.set_meta("is_committed", true)
		piece.set_meta("is_in_hand", false)
		piece.set_meta("is_in_grace", false)
		pile.remove_at(selected_from_pile_index)
		if pile.size() == 0:
			well_first_entry_slow_used = false
		_force_cancel_drag("CommittedToBoard", true)
	else:
		_ensure_piece_state(piece)
		piece.set_meta("is_committed", true)
		piece.set_meta("is_in_hand", false)
		piece.set_meta("is_in_grace", false)
		# Falling piece is consumed only after successful placement.
		if selected_piece == fall_piece:
			fall_piece = null
		elif selected_piece == fall_piece_2:
			fall_piece_2 = null
		_force_cancel_drag("CommittedToBoard", true)
		if _active_falling_count() == 0 and pending_dual_spawn_ms == 0:
			_schedule_next_falling_piece()

	var move_time_sec = max(0.05, float(Time.get_ticks_msec() - drag_start_ms) / 1000.0)
	core.call("RegisterSuccessfulPlacement", cleared_count, move_time_sec, _board_fill_ratio())
	_play_sfx("place")
	if cleared_count > 0:
		_play_sfx("clear")
		clear_flash_left = 0.20
		clear_flash_cells = cleared
	if rescue_from_well_pending and Time.get_ticks_msec() <= rescue_eligible_until_ms:
		score += int(core.call("GetRescueScoreBonus"))
		core.call("TriggerRescueStability")
		rescue_trigger_count += 1
	if placed_from_well:
		_try_trigger_time_slow_from_well_placement()
	rescue_from_well_pending = false
	_trigger_auto_slow_if_needed()

	_refresh_board_visual()
	_update_hud()
	_redraw_well()
	return true


func _on_board_cell_input(event: InputEvent, x: int, y: int) -> void:
	if is_game_over:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if selected_piece != null:
			_try_place_piece(selected_piece, x, y)


func _mouse_to_board_cell(mouse_pos: Vector2) -> Vector2i:
	var local := mouse_pos - board_panel.global_position - board_start
	var x := int(floor(local.x / float(cell_size)))
	var y := int(floor(local.y / float(cell_size)))
	if x < 0 or x >= BOARD_SIZE or y < 0 or y >= BOARD_SIZE:
		return Vector2i(-1, -1)
	return Vector2i(x, y)


# ============================================================
# Loop (classic-like slow start)
# ============================================================
func _process(delta: float) -> void:
	_update_toast()
	_update_pending_invalid_grace()
	if is_game_over:
		return

	if well_header_pulse_left > 0.0:
		well_header_pulse_left = max(0.0, well_header_pulse_left - delta)
	if clear_flash_left > 0.0:
		clear_flash_left = max(0.0, clear_flash_left - delta)
		_refresh_board_visual()

	if rescue_from_well_pending and Time.get_ticks_msec() > rescue_eligible_until_ms:
		rescue_from_well_pending = false
	if _well_fill_ratio() >= 0.82 and Time.get_ticks_msec() >= panic_sfx_cooldown_ms:
		panic_sfx_cooldown_ms = Time.get_ticks_msec() + 1800
		_play_sfx("panic")
		well_header_pulse_left = 0.25

	_update_time()
	_update_difficulty()
	_update_time_scale_runtime()

	# Falling speed is driven by DifficultyDirector + level curve from Core.
	var fall_speed = float(core.call("GetFallSpeed", float(level)))
	speed_ui = fall_speed / max(0.001, float(core.call("GetBaseFallSpeed")))
	lbl_speed.text = "Speed: %.2f" % speed_ui
	if not speed_curve_warning_shown:
		var elapsed_min = float(core.call("GetElapsedMinutesForDebug"))
		var peak1_min = float(core.call("GetSpeedPeak1Minutes"))
		if elapsed_min > peak1_min + 0.5:
			var speed_mul = fall_speed / max(0.001, float(core.call("GetBaseFallSpeed")))
			var expected_mul = float(core.call("GetPeak1TargetMultiplier"))
			if speed_mul < expected_mul * 0.98:
				push_warning("Speed curve sanity: elapsed=%.2f min, speedMul=%.2f, expected>=%.2f" % [elapsed_min, speed_mul, expected_mul])
				speed_curve_warning_shown = true

	var now_ms = Time.get_ticks_msec()
	if pending_spawn_piece and now_ms >= spawn_wait_until_ms:
		_spawn_falling_piece()
	if pending_dual_spawn_ms > 0 and _dual_drop_can_spawn(now_ms):
		_spawn_second_falling_piece()

	var geom = _well_geometry()
	var fall_bottom = float(geom["fall_bottom"])
	if fall_piece != null:
		fall_y += fall_speed * delta
		if fall_y > fall_bottom:
			_lock_falling_to_pile()
	if fall_piece_2 != null:
		fall_y_2 += fall_speed * delta
		if fall_y_2 > fall_bottom:
			_commit_piece_to_well(fall_piece_2)
			if is_game_over:
				return

	_redraw_well()
	_update_status_hud()
	_update_time_slow_overlay()

	# Drag: ghost always visible
	if dragging and selected_piece != null:
		var mouse = get_viewport().get_mouse_position()
		var cell = _mouse_to_board_cell(mouse)

		if cell.x == -1:
			drag_anchor = Vector2i(-999, -999)
			_clear_highlight()
			ghost_root.visible = true
			ghost_root.global_position = mouse - ghost_bbox_size * 0.5
		else:
			var top_left = board_panel.global_position + board_start + Vector2(cell.x * cell_size, cell.y * cell_size)
			ghost_root.visible = true
			ghost_root.global_position = top_left
			drag_anchor = cell
			_highlight_piece(selected_piece, cell.x, cell.y)

		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_finish_drag()


func _board_fill_ratio() -> float:
	var occ := 0
	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			if int(board.call("GetCell", x, y)) != 0:
				occ += 1
	return float(occ) / float(BOARD_SIZE * BOARD_SIZE)


# ============================================================
# HUD
# ============================================================
func _update_time() -> void:
	var t := Time.get_ticks_msec() - start_ms
	var sec := int(t / 1000)
	var mm := int(sec / 60)
	var ss := sec % 60
	lbl_time.text = "Time: %02d:%02d" % [mm, ss]


func _update_difficulty() -> void:
	level = int(core.call("GetLevelForScore", score))
	lbl_level.text = "Level: %d" % level


func _update_hud() -> void:
	lbl_score.text = "Score: %d" % score
	_update_previews()
	_update_status_hud()
	_update_time_slow_overlay()


# ============================================================
# Highlight + ghost build
# ============================================================
func _clear_highlight() -> void:
	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			board_hl[y][x].color = Color(0, 0, 0, 0)
	if clear_flash_left > 0.0:
		var a = clamp(clear_flash_left * 3.8, 0.0, 0.8)
		for pos in clear_flash_cells:
			var fx = int(pos.x)
			var fy = int(pos.y)
			if fx >= 0 and fx < BOARD_SIZE and fy >= 0 and fy < BOARD_SIZE:
				board_hl[fy][fx].color = Color(1.0, 1.0, 0.45, a)


func _highlight_piece(piece, ax: int, ay: int) -> void:
	_clear_highlight()
	var ok := bool(board.call("CanPlace", piece, ax, ay))
	var col := HL_OK if ok else HL_BAD

	for c in piece.get("Cells"):
		var x := ax + int(c.x)
		var y := ay + int(c.y)
		if x >= 0 and x < BOARD_SIZE and y >= 0 and y < BOARD_SIZE:
			if int(board.call("GetCell", x, y)) == 0:
				board_hl[y][x].color = col


func _build_ghost_for_piece(piece) -> void:
	for ch in ghost_root.get_children():
		ch.queue_free()

	var min_x := 999
	var min_y := 999
	var max_x := -999
	var max_y := -999
	for c in piece.get("Cells"):
		min_x = min(min_x, int(c.x))
		min_y = min(min_y, int(c.y))
		max_x = max(max_x, int(c.x))
		max_y = max(max_y, int(c.y))

	var w_cells := (max_x - min_x + 1)
	var h_cells := (max_y - min_y + 1)
	ghost_bbox_size = Vector2(float(w_cells * cell_size), float(h_cells * cell_size))

	var base_col := _color_for_kind(String(piece.get("Kind")))
	var ghost_col := Color(base_col.r, base_col.g, base_col.b, 0.35)

	for c in piece.get("Cells"):
		var px := int(c.x) - min_x
		var py := int(c.y) - min_y
		var b := _bevel_block(ghost_col, cell_size - 6)
		b.position = Vector2(px * cell_size, py * cell_size)
		ghost_root.add_child(b)


# ============================================================
# Preview blocks
# ============================================================
func _make_piece_preview(piece, mini: int, frame: Vector2 = Vector2(140, 90)) -> Control:
	var root := Control.new()
	root.size = frame
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var min_x := 999
	var min_y := 999
	var max_x := -999
	var max_y := -999
	for c in piece.get("Cells"):
		min_x = min(min_x, int(c.x))
		min_y = min(min_y, int(c.y))
		max_x = max(max_x, int(c.x))
		max_y = max(max_y, int(c.y))

	var w := (max_x - min_x + 1) * mini
	var h := (max_y - min_y + 1) * mini
	var start_x := int((root.size.x - w) * 0.5)
	var start_y := int((root.size.y - h) * 0.5)

	var col := _color_for_kind(String(piece.get("Kind")))
	for c in piece.get("Cells"):
		var px := int(c.x) - min_x
		var py := int(c.y) - min_y
		var b := _bevel_block(col, mini - 2)
		b.position = Vector2(start_x + px * mini, start_y + py * mini)
		root.add_child(b)

	return root


func _color_for_kind(kind: String) -> Color:
	return _skin_piece_color(kind)


# ============================================================
# Styles
# ============================================================


func _style_skills_panel() -> StyleBox:
	var base_style = root_frame.get_theme_stylebox("panel") if root_frame != null else null
	if base_style == null:
		base_style = board_panel.get_theme_stylebox("panel") if board_panel != null else null
	if base_style is StyleBoxFlat:
		var panel_style = (base_style as StyleBoxFlat).duplicate() as StyleBoxFlat
		panel_style.set_border_width_all(2)
		panel_style.bg_color = Color(panel_style.bg_color.r, panel_style.bg_color.g, panel_style.bg_color.b, 0.0)
		panel_style.border_color = Color(panel_style.border_color.r * 0.75, panel_style.border_color.g * 0.75, panel_style.border_color.b * 0.75, panel_style.border_color.a)
		return panel_style
	var fallback = StyleBoxFlat.new()
	var representative = well_slots_panel.get_theme_stylebox("panel") if well_slots_panel != null else null
	var panel_base_color = _skin_color("cartridge_bg", Color(0.93, 0.86, 0.42))
	if representative is StyleBoxFlat:
		panel_base_color = (representative as StyleBoxFlat).bg_color
	fallback.bg_color = Color(panel_base_color.r, panel_base_color.g, panel_base_color.b, 0.0)
	fallback.set_border_width_all(2)
	fallback.border_color = Color(panel_base_color.r * 0.75, panel_base_color.g * 0.75, panel_base_color.b * 0.75, 0.95)
	return fallback


func _style_skills_slot() -> StyleBox:
	return _style_skills_slot_outer(_skills_outer_bg_color())


func _skills_outer_bg_color() -> Color:
	if root_frame != null:
		var root_sb = root_frame.get_theme_stylebox("panel")
		if root_sb is StyleBoxFlat:
			var root_color = (root_sb as StyleBoxFlat).bg_color
			if root_color.a > 0.0:
				return root_color
	return _skin_color("hud_bg", _skin_color("cartridge_bg", Color(0.93, 0.86, 0.42)))


func _style_skills_slot_outer(outer_bg_color: Color) -> StyleBox:
	var sb_outer = StyleBoxFlat.new()
	sb_outer.set_border_width_all(2)
	sb_outer.bg_color = Color(outer_bg_color.r, outer_bg_color.g, outer_bg_color.b, 0.20)
	sb_outer.border_color = Color(outer_bg_color.r * 0.65, outer_bg_color.g * 0.65, outer_bg_color.b * 0.65, outer_bg_color.a)
	sb_outer.shadow_size = 0
	return sb_outer


func _build_skill_slot_cutout(slot: PanelContainer, outer_bg_color: Color) -> PanelContainer:
	var inner_cutout = PanelContainer.new()
	inner_cutout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner_cutout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner_cutout.offset_left = 6
	inner_cutout.offset_top = 6
	inner_cutout.offset_right = -6
	inner_cutout.offset_bottom = -6
	var sb_inset = StyleBoxFlat.new()
	sb_inset.set_border_width_all(2)
	sb_inset.bg_color = Color(outer_bg_color.r * 0.70, outer_bg_color.g * 0.70, outer_bg_color.b * 0.70, 0.35)
	sb_inset.border_color = Color(outer_bg_color.r * 0.50, outer_bg_color.g * 0.50, outer_bg_color.b * 0.50, outer_bg_color.a)
	sb_inset.shadow_size = 8
	sb_inset.shadow_offset = Vector2(0, 2)
	sb_inset.shadow_color = Color(0, 0, 0, 0.45)
	inner_cutout.add_theme_stylebox_override("panel", sb_inset)

	var top_highlight = ColorRect.new()
	top_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_highlight.anchor_left = 0
	top_highlight.anchor_right = 1
	top_highlight.anchor_top = 0
	top_highlight.anchor_bottom = 0
	top_highlight.offset_left = 2
	top_highlight.offset_right = -2
	top_highlight.offset_top = 2
	top_highlight.offset_bottom = 6
	var hi_r = outer_bg_color.r + (1.0 - outer_bg_color.r) * 0.18
	var hi_g = outer_bg_color.g + (1.0 - outer_bg_color.g) * 0.18
	var hi_b = outer_bg_color.b + (1.0 - outer_bg_color.b) * 0.18
	top_highlight.color = Color(hi_r, hi_g, hi_b, 0.28)
	top_highlight.z_index = 1
	inner_cutout.add_child(top_highlight)

	var bottom_shade = ColorRect.new()
	bottom_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_shade.anchor_left = 0
	bottom_shade.anchor_right = 1
	bottom_shade.anchor_top = 1
	bottom_shade.anchor_bottom = 1
	bottom_shade.offset_left = 2
	bottom_shade.offset_right = -2
	bottom_shade.offset_top = -6
	bottom_shade.offset_bottom = -2
	bottom_shade.color = Color(0, 0, 0, 0.26)
	bottom_shade.z_index = 1
	inner_cutout.add_child(bottom_shade)

	slot.add_child(inner_cutout)
	return inner_cutout


func _style_cartridge_frame() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = _skin_color("cartridge_bg", Color(0.93, 0.86, 0.42))
	s.border_width_left = 8
	s.border_width_right = 8
	s.border_width_top = 8
	s.border_width_bottom = 8
	s.border_color = Color(0.15, 0.12, 0.02)
	s.corner_radius_top_left = 16
	s.corner_radius_top_right = 16
	s.corner_radius_bottom_left = 16
	s.corner_radius_bottom_right = 16
	return s


func _style_board_panel() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = _skin_color("board_bg", Color(0.20, 0.22, 0.20))
	s.border_width_left = 6
	s.border_width_right = 6
	s.border_width_top = 6
	s.border_width_bottom = 6
	s.border_color = Color(0.14, 0.16, 0.14)
	s.corner_radius_top_left = 10
	s.corner_radius_top_right = 10
	s.corner_radius_bottom_left = 10
	s.corner_radius_bottom_right = 10
	return s


func _style_hud_panel() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = _skin_color("hud_bg", Color(0.92, 0.92, 0.92))
	s.border_width_left = 6
	s.border_width_right = 6
	s.border_width_top = 6
	s.border_width_bottom = 6
	s.border_color = Color(0.15, 0.15, 0.15)
	s.corner_radius_top_left = 10
	s.corner_radius_top_right = 10
	s.corner_radius_bottom_left = 10
	s.corner_radius_bottom_right = 10
	return s


func _style_bottom_panel() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = _skin_color("well_bg", Color(0.20, 0.20, 0.20))
	s.border_width_left = 4
	s.border_width_right = 4
	s.border_width_top = 4
	s.border_width_bottom = 4
	s.border_color = Color(0.10, 0.10, 0.10)
	s.corner_radius_top_left = 10
	s.corner_radius_top_right = 10
	s.corner_radius_bottom_left = 10
	s.corner_radius_bottom_right = 10
	return s


func _style_preview_box() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(1.0, 1.0, 1.0, 0.10)
	s.border_width_left = 2
	s.border_width_right = 2
	s.border_width_top = 2
	s.border_width_bottom = 2
	s.border_color = Color(0.20, 0.20, 0.20, 0.35)
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.corner_radius_bottom_left = 8
	s.corner_radius_bottom_right = 8
	s.shadow_color = Color(0, 0, 0, 0.20)
	s.shadow_size = 4
	return s


func _style_cell_empty(x: int, y: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	var in_block_dark := ((x / 3) + (y / 3)) % 2 == 1
	s.bg_color = _skin_color("cell_dark", RETRO_GRID_DARK) if in_block_dark else _skin_color("cell_base", RETRO_GRID_BASE)

	var thick_left := (x % 3 == 0)
	var thick_top := (y % 3 == 0)
	var thick_right := ((x + 1) % 3 == 0)
	var thick_bottom := ((y + 1) % 3 == 0)

	s.border_width_left = 4 if thick_left else 1
	s.border_width_top = 4 if thick_top else 1
	s.border_width_right = 4 if thick_right else 1
	s.border_width_bottom = 4 if thick_bottom else 1
	s.border_color = _skin_color("grid_border", RETRO_GRID_BORDER)
	return s


func _style_cell_filled_colored(base: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(min(1.0, base.r * 0.95), min(1.0, base.g * 0.95), min(1.0, base.b * 0.95), 1.0)
	s.border_width_left = 1
	s.border_width_right = 1
	s.border_width_top = 1
	s.border_width_bottom = 1
	s.border_color = Color(0.22, 0.22, 0.22)
	return s


func _style_stack_slot() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.08, 0.10)
	s.border_width_left = 2
	s.border_width_right = 2
	s.border_width_top = 2
	s.border_width_bottom = 2
	s.border_color = Color(0.26, 0.26, 0.30)
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.corner_radius_bottom_left = 8
	s.corner_radius_bottom_right = 8
	return s


func _style_stack_slot_selectable() -> StyleBoxFlat:
	var s = _style_stack_slot()
	s.border_color = Color(0.95, 0.88, 0.28)
	s.bg_color = Color(0.18, 0.18, 0.20, 1.0)
	return s


func _style_stack_slot_locked() -> StyleBoxFlat:
	var s = _style_stack_slot()
	s.border_color = Color(0.36, 0.36, 0.40)
	s.bg_color = Color(0.07, 0.07, 0.09, 1.0)
	return s


func _style_gamepad_button_normal() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.90, 0.90, 0.94)
	s.border_width_left = 2
	s.border_width_right = 2
	s.border_width_top = 2
	s.border_width_bottom = 4
	s.border_color = Color(0.20, 0.20, 0.24)
	s.corner_radius_top_left = 12
	s.corner_radius_top_right = 12
	s.corner_radius_bottom_left = 12
	s.corner_radius_bottom_right = 12
	return s


func _style_gamepad_button_hover() -> StyleBoxFlat:
	var s = _style_gamepad_button_normal()
	s.bg_color = Color(0.98, 0.97, 0.88)
	s.border_color = Color(0.28, 0.26, 0.18)
	return s


func _style_gamepad_button_pressed() -> StyleBoxFlat:
	var s = _style_gamepad_button_normal()
	s.bg_color = Color(0.82, 0.82, 0.86)
	s.border_width_top = 4
	s.border_width_bottom = 2
	return s


func _bevel_block(base: Color, size_px: int) -> Control:
	var p := Panel.new()
	p.size = Vector2(size_px, size_px)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", _style_bevel_outer(base))

	var inner := Panel.new()
	inner.position = Vector2(3, 3)
	inner.size = Vector2(size_px - 6, size_px - 6)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_stylebox_override("panel", _style_bevel_inner(base))
	p.add_child(inner)
	return p


func _style_bevel_outer(base: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = base
	s.border_width_left = 3
	s.border_width_top = 3
	s.border_width_right = 3
	s.border_width_bottom = 3
	s.border_color = Color(base.r * 0.55, base.g * 0.55, base.b * 0.55, base.a)
	s.corner_radius_top_left = 3
	s.corner_radius_top_right = 3
	s.corner_radius_bottom_left = 3
	s.corner_radius_bottom_right = 3
	return s


func _style_bevel_inner(base: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(min(1.0, base.r * 1.08), min(1.0, base.g * 1.08), min(1.0, base.b * 1.08), base.a)
	s.border_width_left = 2
	s.border_width_top = 2
	s.border_width_right = 2
	s.border_width_bottom = 2
	s.border_color = Color(min(1.0, base.r * 1.20), min(1.0, base.g * 1.20), min(1.0, base.b * 1.20), base.a)
	s.corner_radius_top_left = 2
	s.corner_radius_top_right = 2
	s.corner_radius_bottom_left = 2
	s.corner_radius_bottom_right = 2
	return s
