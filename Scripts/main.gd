extends Control

class CooldownRadial extends Control:
	var progress_remaining_01 := 0.0:
		set(value):
			progress_remaining_01 = clamp(value, 0.0, 1.0)
			visible = progress_remaining_01 > 0.001
			queue_redraw()
	func _draw() -> void:
		if progress_remaining_01 <= 0.001:
			return
		var center = size * 0.5
		var radius = min(size.x, size.y) * 0.52
		var angle_span = TAU * progress_remaining_01
		var start_angle = -PI * 0.5
		var points: PackedVector2Array = PackedVector2Array()
		points.append(center)
		var steps = max(6, int(48.0 * progress_remaining_01))
		for i in range(steps + 1):
			var t = float(i) / float(max(1, steps))
			var a = start_angle + angle_span * t
			points.append(center + Vector2(cos(a), sin(a)) * radius)
		draw_colored_polygon(points, Color(0, 0, 0, 0.85))

const BoardGridOverlay = preload("res://Scripts/BoardGridOverlay.gd")
const SkillVFXControllerScript = preload("res://Scripts/VFX/SkillVFXController.gd")
const MusicManagerScript = preload("res://Scripts/Audio/MusicManager.gd")
const AudioManagerScript = preload("res://Scripts/Modules/Audio/AudioManager.gd")
const SettingsPanel = preload("res://Scripts/Modules/UI/Common/SettingsPanel.gd")
const UIStyle = preload("res://Scripts/Modules/UI/Common/UIStyle.gd")
const MAIN_MENU_SCENE = "res://Scenes/MainMenu.tscn"
const MAIN_SCENE = "res://Scenes/Main.tscn"
const STONE_OVERLAY_TEX_PATH = "res://Assets/Skins/Default/Blocks/stone_vine_overlay.png"

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
var board_block_faces := []
var board_stone_overlay := []
var board_stone_overlay_revealed := []
var color_grid := []
var sticky_grid := []
var board_grid_overlay: Control
var board_content_root: Control
var _stone_overlay_tex_cache: Texture2D
var _sticky_piece_access_warned := false

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
var auto_snap_cooldown_until_ms: int = 0
var drag_trail: PackedVector2Array = PackedVector2Array()

# ----------------------------
# Ghost (always visible)
# ----------------------------
var ghost_layer: Control
var ghost_root: Control
var ghost_bbox_size := Vector2.ZERO
var ghost_valid_state: int = 0

# ----------------------------
# UI nodes
# ----------------------------
var root_frame: Panel
var title_label: Label
var title_texture_rect: TextureRect

var board_panel: Panel
var hud_panel: Panel
var well_panel: Panel
var safe_area_root: Control
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
var header_right_section: MarginContainer
var btn_skill_freeze: TextureButton
var btn_skill_clear: TextureButton
var btn_skill_invuln: TextureButton
var board_overlay_right: Control
var settings_popup: Control
var popup_exit: Control
var modal_holder: Control
var modal_layer: CanvasLayer
var overlay_dim_modal: ColorRect
var modal_stack: Array = []
var drop_status_label: Label
var drop_status_text := ""
var drop_status_anim_tween: Tween = null
var drop_status_locked_until_ms := 0
var drop_status_base_pos := Vector2.ZERO
var _dbg_next_check_ms := 0

const HEADER_BASE_LEFT := 20
const HEADER_BASE_RIGHT := 20
const HEADER_BASE_TOP := 14
const HEADER_BASE_BOTTOM := 108
const CONTENT_BASE_LEFT := 24
const CONTENT_BASE_RIGHT := 24
const CONTENT_BASE_TOP := 118
const CONTENT_BASE_BOTTOM := 24

# Game Over overlay
var overlay_dim: ColorRect
var overlay_text: Label
var is_game_over: bool = false
var fx_layer: CanvasLayer
var time_slow_overlay: ColorRect
var pending_invalid_piece = null
var pending_invalid_from_pile_index: int = -1
var pending_invalid_source_slot := 0
var pending_invalid_piece_id := -1
var pending_invalid_root: Control
var pending_invalid_until_ms = 0
var pending_invalid_timer: Timer
var next_piece_state_id: int = 1
var expected_next_preview_kind: String = ""
var grace_piece_by_id: Dictionary = {}
var invalid_drop_slow_until_ms = 0
var next_punish_due_ms: int = 0
var punish_interval_ms: int = 60000
var toast_layer: CanvasLayer
var toast_panel: Panel
var toast_label: Label

# ----------------------------
# Colors
# ----------------------------
const COLOR_EMPTY := Color(0.15, 0.15, 0.15, 1.0)
const COLOR_FILLED := Color(0.82, 0.82, 0.90, 1.0)
const COLOR_STONE := Color(0.45, 0.45, 0.50, 1.0)
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
const HEADER_CLUSTER_GAP := 16
const DROP_STATUS_RESERVED_H := 30.0
const STATUS_NEUTRAL := 0
const STATUS_GOOD := 1
const STATUS_BAD := 2

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
const MUSIC_ATTENUATION_LINEAR = 0.2
const GAME_OVER_SFX_PATH = "res://Assets/Audio/SFX/game_over.ogg"
const MENU_ICON_SETTINGS_TRES = "res://Assets/UI/icons/menu/icon_settings.tres"
const MENU_ICON_CLOSE_TRES = "res://Assets/UI/icons/menu/icon_close.tres"
const MENU_ICON_BACK_PNG = "res://Assets/UI/icons/menu/icon_back.png"
const FREEZE_CD_MS := 30000
const CLEAR_CD_MS := 45000
const SAFE_WELL_CD_MS := 60000
const AUTO_SNAP_COOLDOWN_MS := 3000
const AUTO_SNAP_RADIUS := 2
const AUTO_SNAP_TRAIL_POINTS := 8
const AUTO_SNAP_MIN_DRAG_PX_FACTOR := 0.35
const AUTO_SNAP_MIN_DOT := 0.65
var suppress_invalid_sfx_once: bool = false # Used to prevent invalid SFX when auto-snap will attempt
# Per-round perks (optional: keep buttons later if you want)
var reroll_uses_left: int = 1
var freeze_uses_left: int = 1
var freeze_charges_max := 3
var freeze_charges_current := 1
var clear_charges_max := 2
var clear_charges_current := 1
var safe_well_charges_max := 1
var safe_well_charges_current := 1
var freeze_cd_until_ms := 0
var clear_cd_until_ms := 0
var safe_well_cd_until_ms := 0
var prev_freeze_ready := false
var prev_clear_ready := false
var prev_safe_ready := false
var ghost_shake_phase := 0.0
var ghost_shake_strength_px := 2.0
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

const TIME_SLOW_W_COLLAPSED := 34.0
const TIME_SLOW_W_MIN_VISIBLE := 34.0
const TIME_SLOW_W_EXPAND_MIN := 34.0
const TIME_SLOW_W_EXPAND_MAX := 44.0


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

	music_manager = get_node_or_null("/root/Music")
	if music_manager != null:
		music_manager.play_game_music()
	else:
		push_error("MusicManager autoload not found at /root/MusicManager")

	_apply_balance_well_settings()

	board = core.call("CreateBoard")
	board.call("Reset")

	start_ms = Time.get_ticks_msec()
	_load_audio_settings()

	_audio_setup()
	_apply_audio_settings()

	_build_ui()
	await get_tree().process_frame
	_build_board_grid()
	_log_global_tint_state_once()
	_setup_skill_vfx_controller()

	_start_round()
	set_process(true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		call_deferred("_apply_safe_area_margins")
		call_deferred("_sync_time_slow_column_width")
		call_deferred("_apply_header_label_fits")


func _fit_header_label(label: Label, min_size: int = 16, max_size: int = 32) -> void:
	# Fit font size so current label.text fits label.size.x (with a small padding).
	if label == null:
		return
	var font := label.get_theme_font("font")
	if font == null:
		return
	var pad := 12.0
	var available = max(10.0, label.size.x - pad)
	var best := max_size
	while best > min_size:
		var w := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, best).x
		if w <= available:
			break
		best -= 1
	label.add_theme_font_size_override("font_size", best)


func _apply_header_label_fits() -> void:
	_fit_header_label(lbl_score, 16, 32)
	_fit_header_label(lbl_time, 16, 32)
	_fit_header_label(lbl_speed, 16, 32)
	_fit_header_label(lbl_level, 16, 32)


func _apply_safe_area_margins() -> void:
	if safe_area_root == null:
		return
	var header := safe_area_root.get_node_or_null("header_row") as Control
	var root_margin := safe_area_root.get_node_or_null("root_margin") as MarginContainer
	if header == null or root_margin == null:
		return

	header.offset_left = HEADER_BASE_LEFT
	header.offset_right = -HEADER_BASE_RIGHT
	header.offset_top = HEADER_BASE_TOP
	header.offset_bottom = HEADER_BASE_BOTTOM
	root_margin.add_theme_constant_override("margin_left", CONTENT_BASE_LEFT)
	root_margin.add_theme_constant_override("margin_right", CONTENT_BASE_RIGHT)
	root_margin.add_theme_constant_override("margin_top", CONTENT_BASE_TOP)
	root_margin.add_theme_constant_override("margin_bottom", CONTENT_BASE_BOTTOM)
	if header_right_section != null:
		header_right_section.add_theme_constant_override("margin_right", 0)

	var is_mobile := OS.has_feature("android") or OS.has_feature("ios") or OS.has_feature("mobile")
	if not is_mobile:
		return

	var viewport_rect := get_viewport_rect()
	var win_size := DisplayServer.window_get_size()
	if viewport_rect.size.x <= 0.0 or viewport_rect.size.y <= 0.0 or win_size.x <= 0 or win_size.y <= 0:
		return
	var safe_rect := DisplayServer.get_display_safe_area()
	if safe_rect.size.x <= 0 or safe_rect.size.y <= 0:
		return
	if safe_rect.position == Vector2i.ZERO and safe_rect.size == win_size:
		return

	var scale_x := viewport_rect.size.x / float(win_size.x)
	var scale_y := viewport_rect.size.y / float(win_size.y)
	var safe_left = max(0.0, float(safe_rect.position.x) * scale_x)
	var safe_top = max(0.0, float(safe_rect.position.y) * scale_y)
	var safe_right = max(0.0, float(win_size.x - (safe_rect.position.x + safe_rect.size.x)) * scale_x)

	var max_x := viewport_rect.size.x * 0.12
	var max_y := viewport_rect.size.y * 0.12
	safe_left = clamp(safe_left, 0.0, max_x)
	safe_right = clamp(safe_right, 0.0, max_x)
	safe_top = clamp(safe_top, 0.0, max_y)

	header.offset_left = HEADER_BASE_LEFT + safe_left
	header.offset_right = -(HEADER_BASE_RIGHT + safe_right)
	header.offset_top = HEADER_BASE_TOP + safe_top
	header.offset_bottom = HEADER_BASE_BOTTOM + safe_top
	root_margin.add_theme_constant_override("margin_top", CONTENT_BASE_TOP + safe_top)
	if header_right_section != null:
		header_right_section.add_theme_constant_override("margin_right", safe_right)


func _time_slow_gap_w() -> float:
	var w = get_viewport_rect().size.x
	var expanded = clamp(w * 0.10, TIME_SLOW_W_EXPAND_MIN, TIME_SLOW_W_EXPAND_MAX)
	var now_ms = Time.get_ticks_msec()
	if _is_time_slow_column_expanded(now_ms):
		return max(expanded, TIME_SLOW_W_MIN_VISIBLE)
	return max(TIME_SLOW_W_COLLAPSED, TIME_SLOW_W_MIN_VISIBLE)


func _is_time_slow_column_expanded(now_ms: int) -> bool:
	# Expand after the mechanic was ever triggered in this run, or while it is visually relevant.
	if time_slow_effect_until_ms > now_ms:
		return true
	if time_slow_overlay != null and time_slow_overlay.visible:
		return true
	# After first trigger, cooldown_until will be > 0 for rest of the run.
	if time_slow_cooldown_until_ms > 0:
		return true
	return false


func _sync_time_slow_column_width() -> void:
	if time_slow_mid == null:
		return
	var w = _time_slow_gap_w()
	time_slow_mid.custom_minimum_size.x = w

	var has_frame_assets := time_slow_frame_rect != null and time_slow_frame_rect.texture != null
	var has_glass_assets := time_slow_glass_rect != null and time_slow_glass_rect.material != null
	var has_sand_assets := time_slow_sand_rect != null and time_slow_sand_rect.material != null
	var has_advanced_assets := has_frame_assets and has_glass_assets and has_sand_assets
	if time_slow_frame_rect != null:
		time_slow_frame_rect.visible = has_frame_assets
	if time_slow_glass_rect != null:
		time_slow_glass_rect.visible = has_glass_assets
	if time_slow_sand_rect != null:
		time_slow_sand_rect.visible = has_sand_assets
	if bar_time_slow != null:
		bar_time_slow.visible = not has_advanced_assets

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

var skill_ready_sfx_armed := false

func _sync_skill_ready_latches() -> void:
	var now = Time.get_ticks_msec()
	prev_freeze_ready = Save.is_unlock_enabled("freeze_unlocked") and freeze_charges_current > 0 and now >= freeze_cd_until_ms
	prev_clear_ready = Save.is_unlock_enabled("clear_board_unlocked") and clear_charges_current > 0 and now >= clear_cd_until_ms
	prev_safe_ready = Save.is_unlock_enabled("safe_well_unlocked") and safe_well_charges_current > 0 and now >= safe_well_cd_until_ms
	
func _start_round() -> void:
	_close_all_modals(false)
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
	drop_status_locked_until_ms = 0
	drop_status_text = ""
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
	freeze_charges_current = freeze_charges_max
	clear_charges_current = clear_charges_max
	safe_well_charges_current = safe_well_charges_max
	freeze_cd_until_ms = 0
	clear_cd_until_ms = 0
	safe_well_cd_until_ms = 0
	prev_freeze_ready = false
	prev_clear_ready = false
	prev_safe_ready = false
	Engine.time_scale = 1.0
	core.call("ResetRuntimeClock")
	sfx_blocked_by_game_over = false
	game_over_sfx_played = false
	_apply_audio_settings()
	_update_skill_icon_states()
	_sync_skill_ready_latches()
	if music_manager != null:
		music_manager.on_new_run_resume()

	pile.clear()
	var punish_now = Time.get_ticks_msec()
	punish_interval_ms = 30000 if pile.size() == 0 else 60000
	next_punish_due_ms = punish_now + punish_interval_ms
	board.call("Reset")
	_clear_color_grid()
	_refresh_board_visual()

	selected_piece = null
	selected_from_pile_index = -1
	_set_drop_status(_current_drop_status_text())
	dragging = false
	auto_snap_cooldown_until_ms = 0
	drag_trail.clear()
	ghost_valid_state = 0
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
	skill_ready_sfx_armed = false
	_update_skill_icon_states()    
	_sync_skill_ready_latches()    
	skill_ready_sfx_armed = true    



func _trigger_game_over() -> void:
	if is_game_over:
		return
	_close_all_modals(false)
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
	_ensure_sfx("pick", "res://Assets/Audio/pick_piece.wav", -15.0)
	_ensure_sfx("place", "res://Assets/Audio/place_piece.wav", -19.0)
	_ensure_sfx("invalid", "res://Assets/Audio/invalid_drop.wav", -20.0)
	_ensure_sfx("well_enter", "res://Assets/Audio/well_enter.wav", -9.0)
	_ensure_sfx("clear", "res://Assets/Audio/clear.wav", -9.0)
	_ensure_sfx("skill_freeze", "res://Assets/Audio/skill_freeze.wav", -14.0)
	_ensure_sfx("skill_safe_well", "res://Assets/Audio/skill_safe_well.wav", -14.0)
	_ensure_sfx("freeze_cast", "res://Assets/Audio/Skills/Freeze/freeze_cast.ogg", -8.0)
	_ensure_sfx("safe_well_cast", "res://Assets/Audio/Skills/SafeWell/safewell_cast.ogg", -19.0)
	_ensure_sfx("safe_well_doors_open", "res://Assets/Audio/Skills/SafeWell/doors_open.ogg", -12.0)
	_ensure_sfx("safe_well_doors_close", "res://Assets/Audio/Skills/SafeWell/doors_close.ogg", -16.0)
	_ensure_sfx("safe_well_lock_clink", "res://Assets/Audio/Skills/SafeWell/lock_clink.ogg", -16.0)
	_ensure_sfx("panic", "res://Assets/Audio/panic_tick.wav", -14.0)
	_ensure_sfx("skill_ready", "res://Assets/Audio/SFX/skill_ready.ogg", -14.0)
	_ensure_sfx("game_over", GAME_OVER_SFX_PATH, -17.0)
	var ts_path = String(core.call("GetTimeSlowReadySfxPath"))
	if ts_path != "":
		_ensure_sfx("time_slow", ts_path, -8.0)


func _setup_skill_vfx_controller() -> void:
	if skill_vfx_controller != null and is_instance_valid(skill_vfx_controller):
		return
	skill_vfx_controller = SkillVFXControllerScript.new()
	add_child(skill_vfx_controller)
	skill_vfx_controller.setup(self, board_panel, well_panel, drop_zone_panel, well_slots_panel, root_frame)
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

const STATUS_UPDATE_INTERVAL_MS := 120
var _next_status_update_ms := 0
var _last_status_sent := ""

func _maybe_update_drop_status(force: bool = false) -> void:
	var now = Time.get_ticks_msec()
	if now < drop_status_locked_until_ms:
		return
	if not force and now < _next_status_update_ms:
		return
	_next_status_update_ms = now + STATUS_UPDATE_INTERVAL_MS

	var t = _current_drop_status_text()
	if not force and t == _last_status_sent:
		return

	_last_status_sent = t
	_set_drop_status(t, STATUS_NEUTRAL)	
	
func _update_status_hud() -> void:
	var now = Time.get_ticks_msec()
	var cooldown_sec = float(core.call("GetTimeSlowCooldownSec"))
	var remaining_ms = max(0, time_slow_cooldown_until_ms - now)
	var cooldown_remaining = float(remaining_ms) / 1000.0
	if not time_slow_ui_ready and cooldown_sec > 0.0:
		time_slow_ui_ready = true
	if bar_time_slow != null:
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
	call_deferred("_sync_time_slow_column_width")
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


	safe_area_root = Control.new()
	safe_area_root.name = "SafeAreaRoot"
	safe_area_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe_area_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_frame.add_child(safe_area_root)

	var header_row = HBoxContainer.new()
	header_row.name = "header_row"
	header_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header_row.offset_left = 20
	header_row.offset_right = -20
	header_row.offset_top = 14
	header_row.offset_bottom = 108
	header_row.add_theme_constant_override("separation", 14)
	header_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe_area_root.add_child(header_row)

	var left_button_section = MarginContainer.new()
	left_button_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_button_section.size_flags_stretch_ratio = 1.0
	left_button_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_button_section.add_theme_constant_override("margin_left", 12)
	left_button_section.add_theme_constant_override("margin_right", 12)
	left_button_section.add_theme_constant_override("margin_top", 5)
	left_button_section.add_theme_constant_override("margin_bottom", 5)
	left_button_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(left_button_section)

	btn_exit = TextureButton.new()
	btn_exit.custom_minimum_size = Vector2(EXIT_BUTTON_SIZE, EXIT_BUTTON_SIZE)
	btn_exit.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn_exit.ignore_texture_size = true
	btn_exit.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	btn_exit.offset_left = -EXIT_BUTTON_SIZE * 0.5
	btn_exit.offset_top = -EXIT_BUTTON_SIZE * 0.5
	btn_exit.offset_right = EXIT_BUTTON_SIZE * 0.5
	btn_exit.offset_bottom = EXIT_BUTTON_SIZE * 0.5
	btn_exit.mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_header_button_icon(btn_exit, MENU_ICON_BACK_PNG, "←", 34)
	btn_exit.pressed.connect(_on_exit)
	_wire_button_sfx(btn_exit)
	left_button_section.add_child(btn_exit)

	var score_section = MarginContainer.new()
	score_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score_section.size_flags_stretch_ratio = 1.0
	score_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	score_section.add_theme_constant_override("margin_left", 12)
	score_section.add_theme_constant_override("margin_right", 12)
	score_section.add_theme_constant_override("margin_top", 5)
	score_section.add_theme_constant_override("margin_bottom", 5)
	score_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(score_section)

	lbl_score = Label.new()
	lbl_score.text = "Score: 0"
	lbl_score.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_score.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_score.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_score.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lbl_score.add_theme_font_size_override("font_size", 32)
	lbl_score.add_theme_color_override("font_color", _skin_color("text_primary", Color(0.10, 0.10, 0.10, 1)))
	lbl_score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_section.add_child(lbl_score)

	var time_section = MarginContainer.new()
	time_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_section.size_flags_stretch_ratio = 1.0
	time_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	time_section.add_theme_constant_override("margin_left", 12)
	time_section.add_theme_constant_override("margin_right", 12)
	time_section.add_theme_constant_override("margin_top", 5)
	time_section.add_theme_constant_override("margin_bottom", 5)
	time_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(time_section)

	lbl_time = Label.new()
	lbl_time.text = "Time: 00:00"
	lbl_time.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_time.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_time.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_time.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lbl_time.add_theme_font_size_override("font_size", 32)
	lbl_time.add_theme_color_override("font_color", _skin_color("text_primary", Color(0.10, 0.10, 0.10, 1)))
	lbl_time.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_section.add_child(lbl_time)

	var speed_section = MarginContainer.new()
	speed_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_section.size_flags_stretch_ratio = 1.0
	speed_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	speed_section.add_theme_constant_override("margin_left", 12)
	speed_section.add_theme_constant_override("margin_right", 12)
	speed_section.add_theme_constant_override("margin_top", 5)
	speed_section.add_theme_constant_override("margin_bottom", 5)
	speed_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(speed_section)

	lbl_speed = Label.new()
	lbl_speed.text = "Speed: 1.00"
	lbl_speed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_speed.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_speed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_speed.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lbl_speed.add_theme_font_size_override("font_size", 32)
	lbl_speed.add_theme_color_override("font_color", _skin_color("text_primary", Color(0.10, 0.10, 0.10, 1)))
	lbl_speed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speed_section.add_child(lbl_speed)

	var level_section = MarginContainer.new()
	level_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_section.size_flags_stretch_ratio = 1.0
	level_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	level_section.add_theme_constant_override("margin_left", 12)
	level_section.add_theme_constant_override("margin_right", 12)
	level_section.add_theme_constant_override("margin_top", 5)
	level_section.add_theme_constant_override("margin_bottom", 5)
	level_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(level_section)

	lbl_level = Label.new()
	lbl_level.text = "Level: 1"
	lbl_level.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_level.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lbl_level.add_theme_font_size_override("font_size", 32)
	lbl_level.add_theme_color_override("font_color", _skin_color("text_primary", Color(0.10, 0.10, 0.10, 1)))
	lbl_level.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_section.add_child(lbl_level)

	var right_button_section = MarginContainer.new()
	header_right_section = right_button_section
	right_button_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_button_section.size_flags_stretch_ratio = 1.0
	right_button_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_button_section.add_theme_constant_override("margin_left", 12)
	right_button_section.add_theme_constant_override("margin_right", 12)
	right_button_section.add_theme_constant_override("margin_top", 5)
	right_button_section.add_theme_constant_override("margin_bottom", 5)
	right_button_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(right_button_section)

	btn_settings = TextureButton.new()
	btn_settings.custom_minimum_size = Vector2(HEADER_BUTTON_SIZE, HEADER_BUTTON_SIZE)
	btn_settings.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn_settings.ignore_texture_size = true
	btn_settings.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	btn_settings.offset_left = -HEADER_BUTTON_SIZE * 0.5
	btn_settings.offset_top = -HEADER_BUTTON_SIZE * 0.5
	btn_settings.offset_right = HEADER_BUTTON_SIZE * 0.5
	btn_settings.offset_bottom = HEADER_BUTTON_SIZE * 0.5
	btn_settings.mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_header_button_icon(btn_settings, MENU_ICON_SETTINGS_TRES, "⚙", 40)
	btn_settings.pressed.connect(_on_settings)
	_wire_button_sfx(btn_settings)
	right_button_section.add_child(btn_settings)

	call_deferred("_apply_header_label_fits")

	var root_margin = MarginContainer.new()
	root_margin.name = "root_margin"
	root_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_margin.add_theme_constant_override("margin_left", 24)
	root_margin.add_theme_constant_override("margin_right", 24)
	root_margin.add_theme_constant_override("margin_top", 118)
	root_margin.add_theme_constant_override("margin_bottom", 24)
	safe_area_root.add_child(root_margin)
	_apply_safe_area_margins()

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
	# Clip falling pieces so they can spawn above and slide in
	drop_zone_panel.clip_contents = true
	well_draw.add_child(drop_zone_panel)

	var TIME_SLOW_GAP_W = _time_slow_gap_w()
	time_slow_mid = PanelContainer.new()
	time_slow_mid.name = "time_slow_mid"
	time_slow_mid.custom_minimum_size = Vector2(TIME_SLOW_GAP_W, 0)
	time_slow_mid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
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
	time_slow_stack.clip_contents = true
	time_slow_frame_panel.add_child(time_slow_stack)

	time_slow_sand_rect = TextureRect.new()
	time_slow_sand_rect.name = "sand_rect"
	time_slow_sand_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	time_slow_sand_rect.offset_left = 0
	time_slow_sand_rect.offset_top = 0
	time_slow_sand_rect.offset_right = 0
	time_slow_sand_rect.offset_bottom = 0
	time_slow_sand_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_slow_sand_rect.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
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
	time_slow_glass_rect.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
	time_slow_glass_rect.stretch_mode = TextureRect.STRETCH_SCALE
	time_slow_glass_rect.visible = false
	time_slow_stack.add_child(time_slow_glass_rect)

	time_slow_frame_rect = TextureRect.new()
	time_slow_frame_rect.name = "frame_rect"
	time_slow_frame_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	time_slow_frame_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_slow_frame_rect.z_index = 2
	time_slow_frame_rect.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
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
	# Never show default green fill (make fill fully transparent)
	var time_slow_fill = StyleBoxFlat.new()
	time_slow_fill.bg_color = Color(0, 0, 0, 0)
	bar_time_slow.add_theme_stylebox_override("fill", time_slow_fill)
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
	drop_zone_draw.offset_left = 14
	drop_zone_draw.offset_right = -14
	drop_zone_draw.offset_top = 14
	drop_zone_draw.offset_bottom = -14
	drop_zone_draw.mouse_filter = Control.MOUSE_FILTER_STOP
	drop_zone_panel.add_child(drop_zone_draw)

	var dz_static = Control.new()
	dz_static.name = "dz_static"
	dz_static.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dz_static.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drop_zone_draw.add_child(dz_static)

	var dz_dynamic = Control.new()
	dz_dynamic.name = "dz_dynamic"
	dz_dynamic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dz_dynamic.mouse_filter = Control.MOUSE_FILTER_STOP
	drop_zone_draw.add_child(dz_dynamic)

	var drop_header_row = HBoxContainer.new()
	drop_header_row.name = "drop_header_row"
	drop_header_row.position = Vector2(0, 4)
	drop_header_row.size = Vector2(drop_zone_draw.size.x, 28)
	drop_header_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	drop_header_row.offset_left = 0
	drop_header_row.offset_right = 0
	drop_header_row.offset_top = 4
	drop_header_row.offset_bottom = 32
	drop_header_row.add_theme_constant_override("separation", 8)
	drop_header_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dz_static.add_child(drop_header_row)

	# Status label replaces "DROP"
	var status_label = Label.new()
	status_label.name = "drop_status"
	status_label.text = ""
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.custom_minimum_size = Vector2(220, 0)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 25)
	status_label.add_theme_constant_override("outline_size", 3)
	status_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	status_label.add_theme_color_override("font_color", _skin_color("text_muted", Color(0.92, 0.92, 0.92, 1.0)))
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drop_header_row.add_child(status_label)

	var header_spacer = Control.new()
	header_spacer.name = "status_spacer"
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drop_header_row.add_child(header_spacer)

	var phase_box = HBoxContainer.new()
	phase_box.name = "phase_box"
	phase_box.add_theme_constant_override("separation", 6)
	phase_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drop_header_row.add_child(phase_box)

	var phase_label = Label.new()
	phase_label.name = "phase_label"
	phase_label.add_theme_font_size_override("font_size", _skin_font_size("tiny", 22))
	phase_label.add_theme_color_override("font_color", _skin_color("text_muted", Color(0.84, 0.84, 0.84)))
	phase_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	phase_box.add_child(phase_label)

	var phase_progress = ProgressBar.new()
	phase_progress.name = "phase_progress"
	phase_progress.custom_minimum_size = Vector2(58, 12)
	phase_progress.max_value = 1.0
	phase_progress.show_percentage = false
	phase_progress.value = 0.0
	phase_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var phase_bg = StyleBoxFlat.new()
	phase_bg.bg_color = Color(0.10, 0.12, 0.14, 0.35)
	phase_progress.add_theme_stylebox_override("background", phase_bg)
	var phase_fill = StyleBoxFlat.new()
	phase_fill.bg_color = Color(0.92, 0.70, 0.30, 0.95)
	phase_progress.add_theme_stylebox_override("fill", phase_fill)
	phase_box.add_child(phase_progress)

	drop_status_label = status_label
	_set_drop_status(_current_drop_status_text(), STATUS_NEUTRAL)

	well_slots_draw = Control.new()
	well_slots_draw.clip_contents = false
	well_slots_draw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	well_slots_draw.offset_left = 14
	well_slots_draw.offset_right = -14
	well_slots_draw.offset_top = 14
	well_slots_draw.offset_bottom = -14
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
	fx_layer.layer = -20
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
	UIStyle.apply_panel_9slice(toast_panel)
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
	toast_label.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	toast_label.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.85))
	toast_label.add_theme_constant_override("outline_size", 2)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.add_theme_font_size_override("font_size", 25)
	toast_label.add_theme_constant_override("outline_size", 3)
	toast_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	toast_margin.add_child(toast_label)

	overlay_dim = ColorRect.new()
	overlay_dim.color = Color(0, 0, 0, 0.55)
	overlay_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_dim.visible = false
	overlay_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_frame.add_child(overlay_dim)

	overlay_dim_modal = ColorRect.new()
	overlay_dim_modal.color = Color(0, 0, 0, 0.55)
	overlay_dim_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_dim_modal.visible = false
	overlay_dim_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay_dim_modal.gui_input.connect(_on_modal_overlay_input)

	# Modal layer ABOVE all HUD/board UI
	modal_layer = CanvasLayer.new()
	modal_layer.layer = 200  # high enough to be above everything in this scene
	add_child(modal_layer)
	modal_holder = Control.new()
	modal_holder.theme = root_frame.theme
	modal_holder.name = "ModalHolder"
	modal_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal_layer.add_child(modal_holder)
	modal_holder.add_child(overlay_dim_modal)

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

	popup_exit = CenterContainer.new()
	popup_exit.name = "ExitPopup"
	popup_exit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup_exit.mouse_filter = Control.MOUSE_FILTER_STOP
	popup_exit.visible = false
	modal_holder.add_child(popup_exit)

	var exit_panel = PanelContainer.new()
	exit_panel.custom_minimum_size = Vector2(676, 338)
	exit_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	UIStyle.apply_popup_vertical_offset(exit_panel)
	UIStyle.apply_panel_9slice(exit_panel)
	popup_exit.add_child(exit_panel)

	var exit_margin = UIStyle.wrap_popup_content(exit_panel)

	var exit_v = VBoxContainer.new()
	exit_v.add_theme_constant_override("separation", 18)
	exit_margin.add_child(exit_v)


	var exit_subtitle = Label.new()
	exit_subtitle.text = "What would you like to do?"
	exit_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	exit_subtitle.add_theme_font_size_override("font_size", _skin_font_size("small", 22))
	UIStyle.apply_label_text_palette(exit_subtitle, "subtitle")
	exit_v.add_child(exit_subtitle)

	UIStyle.ensure_popup_chrome_with_header(
		exit_panel,
		exit_v,
		"",
		Callable(self, "_on_exit_cancel"),
		func() -> void:
			_play_sfx("ui_hover"),
		func() -> void:
			_play_sfx("ui_click")
	)
	
	# Make Exit popup header bigger (only this popup)
	var exit_title = exit_v.get_node_or_null("PopupHeader/PopupTitle") as Label
	if exit_title != null:
		exit_title.text = ""
		exit_title.visible = false

	# Make subtitle bigger
	exit_subtitle.add_theme_font_size_override("font_size", 30)

	exit_v.add_spacer(false)

	var exit_buttons = HBoxContainer.new()
	exit_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	exit_buttons.add_theme_constant_override("separation", 16)
	exit_v.add_child(exit_buttons)

	var btn_restart_popup = Button.new()
	btn_restart_popup.text = "Restart"
	btn_restart_popup.custom_minimum_size = Vector2(200, 62)
	UIStyle.apply_button_9slice(btn_restart_popup, "small")
	UIStyle.apply_button_text_palette(btn_restart_popup)
	btn_restart_popup.add_theme_font_size_override("font_size", 26) 
	btn_restart_popup.pressed.connect(_on_exit_restart)
	_wire_button_sfx(btn_restart_popup)
	exit_buttons.add_child(btn_restart_popup)

	var btn_main_menu_popup = Button.new()
	btn_main_menu_popup.text = "Main Menu"
	btn_main_menu_popup.custom_minimum_size = Vector2(200, 62)
	UIStyle.apply_button_9slice(btn_main_menu_popup, "small")
	UIStyle.apply_button_text_palette(btn_main_menu_popup)
	btn_main_menu_popup.add_theme_font_size_override("font_size", 26) 
	btn_main_menu_popup.pressed.connect(_on_exit_main_menu)
	_wire_button_sfx(btn_main_menu_popup)
	exit_buttons.add_child(btn_main_menu_popup)

	var btn_cancel_popup = Button.new()
	btn_cancel_popup.text = "Cancel"
	btn_cancel_popup.custom_minimum_size = Vector2(200, 62)
	UIStyle.apply_button_9slice(btn_cancel_popup, "small")
	UIStyle.apply_button_text_palette(btn_cancel_popup)
	btn_cancel_popup.add_theme_font_size_override("font_size", 26) 
	btn_cancel_popup.pressed.connect(_on_exit_cancel)
	_wire_button_sfx(btn_cancel_popup)
	exit_buttons.add_child(btn_cancel_popup)
	
	

	settings_popup = SettingsPanel.build(modal_holder, Callable(self, "_on_settings_popup_close_requested"), {
		"wire_button_sfx": Callable(self, "_wire_button_sfx"),
		"sfx_hover": func() -> void:
			_play_sfx("ui_hover"),
		"sfx_click": func() -> void:
			_play_sfx("ui_click"),
		"state_getter": Callable(self, "_get_audio_settings_state"),
		"on_music_enabled": Callable(self, "_on_music_enabled_toggled"),
		"on_sfx_enabled": Callable(self, "_on_sfx_enabled_toggled"),
		"on_music_volume": Callable(self, "_on_music_volume_changed"),
		"on_sfx_volume": Callable(self, "_on_sfx_volume_changed")
	})

	if OS.is_debug_build():
		if drop_status_label == null:
			push_error("drop_status_label is null after _build_ui()")
		if title_label == null and (title_texture_rect == null or not title_texture_rect.visible):
			push_error("Title missing: both label and texture are not visible")


func _hud_line(k: String, v: String) -> Label:
	var l = Label.new()
	l.text = "%s: %s" % [k, v]
	l.add_theme_font_size_override("font_size", _skin_font_size("normal", 24))
	l.add_theme_color_override("font_color", _skin_color("text_primary", Color(0.10, 0.10, 0.10)))
	return l


func _hud_metric_row(parent: Control, metric_key: String, prefix: String, value: String) -> Label:
	var wrap = HBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_FILL
	wrap.custom_minimum_size = Vector2(210, 0)
	wrap.alignment = BoxContainer.ALIGNMENT_BEGIN
	wrap.add_theme_constant_override("separation", 6)
	parent.add_child(wrap)
	var value_label = Label.new()
	value_label.text = "%s: %s" % [prefix, value]
	value_label.add_theme_font_size_override("font_size", _skin_font_size("small", 18))
	value_label.add_theme_color_override("font_color", _skin_color("text_primary", Color(0.10, 0.10, 0.10)))
	wrap.add_child(value_label)
	return value_label

func _hud_metric_cell(parent: Control, prefix: String, value: String, align: int) -> Label:
	var l = Label.new()
	l.text = "%s: %s" % [prefix, value]
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Fixed row height for consistent baseline
	l.custom_minimum_size = Vector2(220, 24)
	l.add_theme_font_size_override("font_size", _skin_font_size("small", 18))
	l.add_theme_color_override("font_color", _skin_color("text_primary", Color(0.10, 0.10, 0.10)))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


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
	btn.texture_normal = null
	btn.texture_pressed = null
	btn.texture_hover = null
	btn.texture_disabled = null
	if ResourceLoader.exists(icon_path):
		var icon_resource = load(icon_path)
		var tex: Texture2D = null
		if icon_resource is Texture2D:
			tex = icon_resource as Texture2D
		elif icon_resource is AtlasTexture:
			tex = icon_resource as AtlasTexture
		if tex != null:
			btn.texture_normal = tex
			btn.texture_pressed = tex
			btn.texture_hover = tex
			btn.texture_disabled = tex
			return
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
	# If advanced assets are not available, do NOT show default progress bar
	bar_time_slow.visible = false
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


func _create_skill_overlay(button: TextureButton) -> void:
	if button == null:
		return
	var overlay = Control.new()
	overlay.name = "SkillOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(overlay)

	var radial = CooldownRadial.new()
	radial.name = "CooldownRadial"
	radial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	radial.visible = false
	radial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(radial)

	var charges = Label.new()
	charges.name = "ChargesLabel"
	charges.text = "1×"
	# Charges (TOP-RIGHT)
	charges.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	charges.offset_left = -44   
	charges.offset_top = -20
	charges.offset_right = 10
	charges.offset_bottom = 28   
	charges.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	charges.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	charges.add_theme_font_size_override("font_size", 24)
	charges.add_theme_constant_override("outline_size", 3)
	charges.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	charges.add_theme_color_override("font_color", Color(1.0, 0.95, 0.55, 1.0))
	overlay.add_child(charges)

	var state = Label.new()
	state.name = "StateLabel"
	state.text = "Ready"
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	# State (BOTTOM-CENTER)
	state.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	state.offset_left = 2
	state.offset_right = -2
	state.offset_top = -24
	state.offset_bottom = -2
	state.add_theme_font_size_override("font_size", 24)
	state.add_theme_constant_override("outline_size", 3)
	state.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	state.add_theme_color_override("font_color", Color(1.0, 0.95, 0.55, 1.0))
	overlay.add_child(state)


func _set_skill_overlay(button: TextureButton, state_text: String, charges_value: int, radial_remaining_01: float, color_alpha: float) -> void:
	if button == null:
		return
	var overlay = button.get_node_or_null("SkillOverlay")
	if overlay == null:
		return
	var charges = overlay.get_node_or_null("ChargesLabel") as Label
	if charges != null:
		charges.text = "%d×" % charges_value
		charges.modulate = Color(1, 1, 1, color_alpha)
	var state = overlay.get_node_or_null("StateLabel") as Label
	if state != null:
		state.text = state_text
		state.modulate = Color(1, 1, 1, color_alpha)
	var radial = overlay.get_node_or_null("CooldownRadial") as CooldownRadial
	if radial != null:
		if charges_value <= 0:
			radial.progress_remaining_01 = 0.0
			radial.visible = false
		else:
			radial.progress_remaining_01 = radial_remaining_01
	button.tooltip_text = ""


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
	_create_skill_overlay(b)
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
	if freeze_charges_current <= 0:
		show_toast("No Freeze charges", 1.9)
		return false
	apply_freeze(FREEZE_DURATION_MS, FREEZE_MULTIPLIER)
	if skill_vfx_controller != null:
		skill_vfx_controller.on_freeze_cast(FREEZE_DURATION_MS)
	freeze_charges_current = max(0, freeze_charges_current - 1)
	freeze_cd_until_ms = Time.get_ticks_msec() + FREEZE_CD_MS
	_update_skill_icon_states()
	show_toast("Freeze active for 5s", 1.6)
	_play_sfx("skill_freeze")
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
	if clear_charges_current <= 0:
		show_toast("No Clear Board charges", 1.9)
		return false
	var filled_cells = _clear_board_bulk()
	if skill_vfx_controller != null:
		skill_vfx_controller.on_clear_board_cast()
	clear_charges_current = max(0, clear_charges_current - 1)
	clear_cd_until_ms = Time.get_ticks_msec() + CLEAR_CD_MS
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
	if safe_well_charges_current <= 0:
		show_toast("No Safe Well charges", 1.9)
		return false
	pile.clear()
	apply_safe_well(SAFE_WELL_DURATION_MS)
	if skill_vfx_controller != null:
		skill_vfx_controller.on_safe_well_cast(SAFE_WELL_DURATION_MS)
	safe_well_charges_current = max(0, safe_well_charges_current - 1)
	safe_well_cd_until_ms = Time.get_ticks_msec() + SAFE_WELL_CD_MS
	show_toast("Safe Well active for 7s", 1.6)
	_play_sfx("skill_safe_well")
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


func _set_skill_button_state(button: TextureButton, unlock_key: String, _used_this_round: bool, _default_tooltip: String) -> void:
	if button == null:
		return
	var now = Time.get_ticks_msec()
	var unlock_ready = Save.is_unlock_enabled(unlock_key)
	var cd_until = 0
	var cd_total = 1
	var active = false
	var charges = 1
	if unlock_key == "freeze_unlocked":
		cd_until = freeze_cd_until_ms
		cd_total = FREEZE_CD_MS
		active = is_freeze_active()
		charges = freeze_charges_current
	elif unlock_key == "clear_board_unlocked":
		cd_until = clear_cd_until_ms
		cd_total = CLEAR_CD_MS
		active = false
		charges = clear_charges_current
	else:
		cd_until = safe_well_cd_until_ms
		cd_total = SAFE_WELL_CD_MS
		active = is_safe_well_active()
		charges = safe_well_charges_current
	var cd_remaining_01 = clamp(float(max(0, cd_until - now)) / float(max(1, cd_total)), 0.0, 1.0)
	var state_text = "Ready"
	var alpha = 1.0
	if not unlock_ready:
		state_text = "Locked"
		button.disabled = true
		alpha = 0.45
		cd_remaining_01 = 0.0
	elif cd_until > now:
		state_text = "CD"
		button.disabled = true
		alpha = 0.65
	elif active:
		state_text = "Active"
		button.disabled = false
		alpha = 1.0
	elif charges <= 0:
		state_text = "Used"
		button.disabled = true
		alpha = 0.45
	else:
		state_text = "Ready"
		button.disabled = false
		alpha = 1.0
	button.modulate = Color(1, 1, 1, alpha)
	_set_skill_overlay(button, state_text, charges, cd_remaining_01, alpha)
	button.tooltip_text = ""


func _update_skill_icon_states() -> void:
	if btn_skill_freeze == null or btn_skill_clear == null or btn_skill_invuln == null:
		return
	_set_skill_button_state(btn_skill_freeze, "freeze_unlocked", used_freeze_this_round, "")
	_set_skill_button_state(btn_skill_clear, "clear_board_unlocked", used_clear_board_this_round, "")
	_set_skill_button_state(btn_skill_invuln, "safe_well_unlocked", used_safe_well_this_round, "")
	var now = Time.get_ticks_msec()
	var freeze_ready = Save.is_unlock_enabled("freeze_unlocked") and freeze_charges_current > 0 and now >= freeze_cd_until_ms
	var clear_ready = Save.is_unlock_enabled("clear_board_unlocked") and clear_charges_current > 0 and now >= clear_cd_until_ms
	var safe_ready = Save.is_unlock_enabled("safe_well_unlocked") and safe_well_charges_current > 0 and now >= safe_well_cd_until_ms
	if skill_ready_sfx_armed:
		if not prev_freeze_ready and freeze_ready:
			_play_sfx("skill_ready")
		if not prev_clear_ready and clear_ready:
			_play_sfx("skill_ready")
		if not prev_safe_ready and safe_ready:
			_play_sfx("skill_ready")
	prev_freeze_ready = freeze_ready
	prev_clear_ready = clear_ready
	prev_safe_ready = safe_ready


func show_toast(text: String, duration_sec: float = 1.9) -> void:
	if toast_panel == null or toast_label == null:
		return
	toast_label.text = text
	toast_panel.modulate.a = 0.0
	toast_panel.visible = true
	create_tween().tween_property(toast_panel, "modulate:a", 1.0, 0.12)
	toast_hide_at_ms = Time.get_ticks_msec() + int(max(0.1, duration_sec) * 1000.0)


func _update_toast() -> void:
	if toast_panel == null:
		return
	if not toast_panel.visible:
		return
	if toast_hide_at_ms > 0 and Time.get_ticks_msec() >= toast_hide_at_ms:
		toast_hide_at_ms = -1
		var tw = create_tween()
		tw.tween_property(toast_panel, "modulate:a", 0.0, 0.12)
		tw.finished.connect(func(): toast_panel.visible = false)


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


func _is_modal_open() -> bool:
	return modal_stack.size() > 0


func _is_gameplay_input_blocked() -> bool:
	return is_game_over or _is_modal_open()


func _pause_gameplay_for_modal() -> void:
	if dragging:
		_force_cancel_drag("ModalOpen", true)
	set_process(false)


func _resume_gameplay_after_modal() -> void:
	if is_game_over:
		return
	set_process(true)


func _open_modal(panel: Control) -> void:
	if panel == null or is_game_over or _is_modal_open():
		return
	overlay_dim_modal.visible = true
	panel.visible = true
	modal_stack.append(panel)
	_pause_gameplay_for_modal()


func _close_modal(panel: Control) -> void:
	if panel == null:
		return
	panel.visible = false
	modal_stack.erase(panel)
	if modal_stack.is_empty():
		overlay_dim_modal.visible = false
		_resume_gameplay_after_modal()


func _close_all_modals(resume_gameplay: bool = true) -> void:
	if settings_popup != null:
		settings_popup.visible = false
	if popup_exit != null:
		popup_exit.visible = false
	modal_stack.clear()
	if overlay_dim_modal != null:
		overlay_dim_modal.visible = false
	if resume_gameplay:
		_resume_gameplay_after_modal()


func _on_modal_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if modal_stack.is_empty():
			return
		var panel = modal_stack[modal_stack.size() - 1]
		if panel == settings_popup or panel == popup_exit:
			_close_modal(panel)


func _on_settings_popup_close_requested() -> void:
	_close_modal(settings_popup)


func _on_settings() -> void:
	if settings_popup == null or _is_gameplay_input_blocked():
		return
	if settings_popup.has_meta("sync_settings"):
		var sync_settings = settings_popup.get_meta("sync_settings")
		if sync_settings is Callable:
			(sync_settings as Callable).call()
	_open_modal(settings_popup)



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
	if _is_gameplay_input_blocked():
		return
	_open_modal(popup_exit)


func _on_exit_restart() -> void:
	_close_modal(popup_exit)
	if get_tree().current_scene != null and get_tree().current_scene.scene_file_path == MAIN_SCENE:
		get_tree().reload_current_scene()
	else:
		_start_round()
		set_process(true)


func _on_exit_main_menu() -> void:
	_close_modal(popup_exit)
	if music_manager != null:
		music_manager.play_menu_music() 
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _on_exit_cancel() -> void:
	_close_modal(popup_exit)


# ============================================================
# Board build + colors
# ============================================================
func _clear_color_grid() -> void:
	color_grid.clear()
	sticky_grid.clear()
	board_stone_overlay_revealed.clear()
	for y in range(BOARD_SIZE):
		var row := []
		var sticky_row := []
		var stone_revealed_row := []
		for x in range(BOARD_SIZE):
			row.append(null)
			sticky_row.append(false)
			stone_revealed_row.append(false)
		color_grid.append(row)
		sticky_grid.append(sticky_row)
		board_stone_overlay_revealed.append(stone_revealed_row)


func _build_board_side_overlays(screen_bezel: Panel, board_px: float) -> void:
	if screen_bezel == null:
		return
	const SKILLS_W = 96.0
	const SKILLS_GAP = 12.0

	var skills_holder = Control.new()
	skills_holder.name = "skills_holder"
	skills_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skills_holder.modulate = Color(1, 1, 1, 1)
	skills_holder.position = Vector2(14 + board_px + SKILLS_GAP, 14)
	skills_holder.size = Vector2(SKILLS_W, board_px)
	screen_bezel.add_child(skills_holder)
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
	btn_skill_freeze.pressed.connect(func(): _on_skill_icon_pressed(btn_skill_freeze, "freeze_unlocked", "Reach player level 5"))
	skills_v.add_child(btn_skill_freeze)
	var mid1 = skills_v.add_spacer(false)
	mid1.size_flags_vertical = Control.SIZE_EXPAND_FILL

	btn_skill_clear = _build_skill_icon_button("clear")
	btn_skill_clear.pressed.connect(func(): _on_skill_icon_pressed(btn_skill_clear, "clear_board_unlocked", "Reach player level 10"))
	skills_v.add_child(btn_skill_clear)
	var mid2 = skills_v.add_spacer(false)
	mid2.size_flags_vertical = Control.SIZE_EXPAND_FILL

	btn_skill_invuln = _build_skill_icon_button("safe_well")
	btn_skill_invuln.pressed.connect(func(): _on_skill_icon_pressed(btn_skill_invuln, "safe_well_unlocked", "Reach player level 20"))
	skills_v.add_child(btn_skill_invuln)
	var bot_sp = skills_v.add_spacer(false)
	bot_sp.size_flags_vertical = Control.SIZE_EXPAND_FILL


func _build_board_grid() -> void:
	for ch in board_panel.get_children():
		ch.queue_free()

	board_cells.clear()
	board_hl.clear()
	board_block_faces.clear()
	board_stone_overlay.clear()
	_clear_color_grid()

	var board_px = min(board_panel.size.x - 160.0, board_panel.size.y) - 40.0
	cell_size = int(floor(board_px / float(BOARD_SIZE)))
	board_px = float(cell_size * BOARD_SIZE)

	const SKILLS_W = 96.0
	const SKILLS_GAP = 12.0
	var bezel_w = board_px + 28 + SKILLS_GAP + SKILLS_W
	var bezel_h = board_px + 28

	# Center bezel + integrated skills in board panel
	var bezel_pos = Vector2(
		int((board_panel.size.x - bezel_w) * 0.5),
		int((board_panel.size.y - bezel_h) * 0.55)
	)
	board_start = bezel_pos + Vector2(14, 14)

	var screen_bezel = Panel.new()
	screen_bezel.position = bezel_pos
	screen_bezel.size = Vector2(bezel_w, bezel_h)
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

	board_content_root = Control.new()
	board_content_root.name = "BoardContentRoot"
	board_content_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board_content_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_panel.add_child(board_content_root)

	for y in range(BOARD_SIZE):
		var row := []
		var row2 := []
		var row_face := []
		var row3 := []
		for x in range(BOARD_SIZE):
			var cell := Panel.new()
			cell.position = board_start + Vector2(x * cell_size, y * cell_size)
			cell.size = Vector2(cell_size - 2, cell_size - 2)
			cell.mouse_filter = Control.MOUSE_FILTER_STOP
			cell.gui_input.connect(func(ev): _on_board_cell_input(ev, x, y))
			cell.add_theme_stylebox_override("panel", _style_cell_empty(x, y))
			var face = _bevel_block(Color(1, 1, 1, 1), cell_size - 2, false)
			face.name = "BlockFace"
			face.position = Vector2.ZERO
			face.visible = false
			face.mouse_filter = Control.MOUSE_FILTER_IGNORE
			face.z_index = 1
			cell.add_child(face)
			var stone_overlay := TextureRect.new()
			stone_overlay.name = "StoneOverlay"
			stone_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			stone_overlay.offset_left = 0
			stone_overlay.offset_top = 0
			stone_overlay.offset_right = 0
			stone_overlay.offset_bottom = 0
			stone_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			stone_overlay.z_index = 50
			stone_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			stone_overlay.stretch_mode = TextureRect.STRETCH_SCALE
			stone_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			stone_overlay.texture = _get_stone_overlay_tex()
			stone_overlay.material = null
			stone_overlay.modulate = Color(1, 1, 1, 0)
			stone_overlay.visible = false
			cell.add_child(stone_overlay)
			board_content_root.add_child(cell)
			row.append(cell)
			row_face.append(face)
			row3.append(stone_overlay)

			var hl := ColorRect.new()
			hl.position = cell.position
			hl.size = cell.size
			hl.color = Color(0, 0, 0, 0)
			hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			board_content_root.add_child(hl)
			row2.append(hl)

		board_cells.append(row)
		board_hl.append(row2)
		board_block_faces.append(row_face)
		board_stone_overlay.append(row3)

	board_grid_overlay = BoardGridOverlay.new()
	board_grid_overlay.position = board_start
	board_grid_overlay.size = Vector2(BOARD_SIZE * cell_size, BOARD_SIZE * cell_size)
	board_grid_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_grid_overlay.call("configure", BOARD_SIZE, cell_size)
	var grid_col = _skin_color("grid_border", Color(0.90, 0.66, 0.34, 0.95))
	board_grid_overlay.thin_color = Color(grid_col.r, grid_col.g, grid_col.b, 0.40)
	board_grid_overlay.thick_color = Color(grid_col.r, grid_col.g, grid_col.b, 0.92)
	board_content_root.add_child(board_grid_overlay)

	var glare = ColorRect.new()
	glare.position = board_start
	glare.size = Vector2(BOARD_SIZE * cell_size, BOARD_SIZE * cell_size)
	glare.color = Color(1, 1, 1, 0.04)
	glare.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_content_root.add_child(glare)

	_build_board_side_overlays(screen_bezel, board_px)
	_refresh_board_visual()


func _refresh_board_visual() -> void:
	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			var v := int(board.call("GetCell", x, y))
			var face = board_block_faces[y][x] as Control
			if v == 1 or v == 2:
				var c = color_grid[y][x]
				if c == null:
					c = COLOR_STONE if v == 2 else COLOR_FILLED
				board_cells[y][x].add_theme_stylebox_override("panel", _style_cell_filled_colored(c))
				if face != null:
					face.visible = true
					face.modulate = COLOR_STONE if v == 2 else c
			else:
				board_cells[y][x].add_theme_stylebox_override("panel", _style_cell_empty(x, y))
				color_grid[y][x] = null
				sticky_grid[y][x] = false
				if face != null:
					face.visible = false

			var stone_overlay = board_stone_overlay[y][x] as TextureRect
			if stone_overlay != null:
				var is_stone_now := (v == 2) or sticky_grid[y][x]
				if is_stone_now:
					if stone_overlay.texture == null:
						stone_overlay.texture = _get_stone_overlay_tex()
					if board_stone_overlay_revealed[y][x] == false:
						_animate_stone_overlay_show(stone_overlay, 0.72)
						board_stone_overlay_revealed[y][x] = true
					else:
						stone_overlay.visible = stone_overlay.texture != null
						stone_overlay.material = null
						stone_overlay.modulate = Color(1, 1, 1, 0.72)
						stone_overlay.scale = Vector2.ONE
				else:
					board_stone_overlay_revealed[y][x] = false
					_hide_stone_overlay(stone_overlay)

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
	if next_piece != null:
		expected_next_preview_kind = String(next_piece.get("Kind"))
	else:
		expected_next_preview_kind = ""
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
	var infected = _is_piece_sticky(piece)
	for c in piece.get("Cells"):
		var b = _bevel_block(col, preview_cell_size - 2, infected)
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


func _piece_bbox_cells(piece) -> Vector2i:
	if piece == null:
		push_error("_piece_bbox_cells: piece is null")
		return Vector2i.ONE
	var min_x := 999
	var min_y := 999
	var max_x := -999
	var max_y := -999
	for c in piece.get("Cells"):
		min_x = min(min_x, int(c.x))
		min_y = min(min_y, int(c.y))
		max_x = max(max_x, int(c.x))
		max_y = max(max_y, int(c.y))
	return Vector2i(max(1, max_x - min_x + 1), max(1, max_y - min_y + 1))


# Returns the fitted cell size used to render falling pieces in drop zone.
func _fall_piece_cell_size(piece) -> int:
	var geom = _well_geometry()
	var drop_w = float(geom.get("drop_w", 300.0))
	var drop_cell = int(clamp(float(cell_size) * 0.98, 18.0, float(cell_size)))
	var fall_frame = Vector2(drop_w - 20.0, 260.0)
	return _fitted_cell_size(piece, drop_cell, fall_frame, 0.98)


# Returns the rendered height (px) of a falling piece using the same fit logic as _redraw_well().
func _fall_piece_height_px(piece) -> float:
	if piece == null:
		return 0.0
	var bb = _piece_bbox_cells(piece)
	var fitted = _fall_piece_cell_size(piece)
	return float(bb.y * fitted)


# Compute a visually consistent spawn Y so different piece heights appear to enter similarly.
func _compute_spawn_y_for_piece(piece, fall_top: float) -> float:
	if piece == null:
		return fall_top - 24.0

	var fitted = _fall_piece_cell_size(piece)
	var piece_h = _fall_piece_height_px(piece)

	# Target center position above the visible area (tuned with fitted size)
	var target_center_y = fall_top - 24.0 - float(fitted) * 1.25 - 60

	# Place piece so its center matches target_center_y
	var y = target_center_y - piece_h * 0.5

	# Ensure the piece starts fully hidden (at least 8px above)
	var fully_hidden_y = fall_top - piece_h - 8.0
	y = min(y, fully_hidden_y)
	return y

const DEBUG_FORCE_STICKY_100 := false
const DEBUG_LOG_GLOBAL_TINT_STATE := false

func _spawn_falling_piece() -> void:
	fall_piece = core.call("PopNextPieceForBoard", board)
	
	if OS.is_debug_build() and DEBUG_FORCE_STICKY_100 and fall_piece != null:
		# Do NOT rely on piece.set("IsSticky", true) — can be non-writable
		fall_piece.set_meta("debug_force_sticky", true)
		
	if fall_piece == null:
		push_error("_spawn_falling_piece: PopNextPieceForBoard returned null")
		pending_spawn_piece = false
		return
	if expected_next_preview_kind != "":
		var spawned_kind = String(fall_piece.get("Kind"))
		if spawned_kind != expected_next_preview_kind:
			push_error("Preview/pop mismatch for primary spawn: expected=" + expected_next_preview_kind + ", got=" + spawned_kind)
	# Spawn above the visible drop zone so it slides in
	var geom = _well_geometry()
	var fall_top = float(geom.get("fall_top", FALL_PAD))
	# Start above: fully hidden + small gap
	fall_y = _compute_spawn_y_for_piece(fall_piece, fall_top)
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


func _log_global_tint_state_once() -> void:
	if not OS.is_debug_build() or not DEBUG_LOG_GLOBAL_TINT_STATE:
		return
	var board_mat = board_panel.material if board_panel != null else null
	var drop_mat = drop_zone_panel.material if drop_zone_panel != null else null
	print("[TINT_DEBUG] board_panel modulate=", (board_panel.modulate if board_panel != null else "null"),
		" self_modulate=", (board_panel.self_modulate if board_panel != null else "null"),
		" material=", board_mat)
	print("[TINT_DEBUG] drop_zone_panel modulate=", (drop_zone_panel.modulate if drop_zone_panel != null else "null"),
		" self_modulate=", (drop_zone_panel.self_modulate if drop_zone_panel != null else "null"),
		" material=", drop_mat)

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
	var expected_piece = core.call("PeekNextPieceForBoard", board)
	var expected_kind = ""
	if expected_piece != null:
		expected_kind = String(expected_piece.get("Kind"))
	var p2 = core.call("PopNextPieceForBoard", board)
	if p2 == null:
		push_error("_spawn_second_falling_piece: PopNextPieceForBoard returned null")
		pending_dual_spawn_ms = 0
		pending_dual_fallback_ms = 0
		dual_drop_waiting_for_gap = false
		return
	if expected_kind != "":
		var popped_kind = String(p2.get("Kind"))
		if popped_kind != expected_kind:
			push_error("Preview/pop mismatch for secondary spawn: expected=" + expected_kind + ", got=" + popped_kind)
	if fall_piece == null:
		fall_piece = p2
		var geom = _well_geometry()
		var fall_top = float(geom.get("fall_top", FALL_PAD))
		var piece_h_px = _fall_piece_height_px(fall_piece)
		fall_y = fall_top - piece_h_px - 24.0
	else:
		fall_piece_2 = p2
		var geom2 = _well_geometry()
		var fall_top_2 = float(geom2.get("fall_top", FALL_PAD))
		var piece_h_px_2 = _fall_piece_height_px(fall_piece_2)
		fall_y_2 = _compute_spawn_y_for_piece(fall_piece_2, fall_top_2)
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
	var fall_bottom = drop_h - (120.0 + DROP_STATUS_RESERVED_H)
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
	var dz_static := drop_zone_draw.get_node_or_null("dz_static") as Control
	var dz_dynamic := drop_zone_draw.get_node_or_null("dz_dynamic") as Control
	if dz_static == null or dz_dynamic == null:
		return
	for ch in dz_dynamic.get_children():
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

	var elapsed_min = float(core.call("GetElapsedMinutesForDebug"))
	var phase_label = dz_static.get_node_or_null("drop_header_row/phase_box/phase_label") as Label
	var phase_progress = dz_static.get_node_or_null("drop_header_row/phase_box/phase_progress") as ProgressBar
	if phase_label != null and phase_progress != null:
		if elapsed_min < 3.0:
			phase_label.text = "CALM"
			phase_progress.value = clamp(elapsed_min / 3.0, 0.0, 1.0)
		elif elapsed_min < 6.0:
			phase_label.text = "FAST"
			phase_progress.value = clamp((elapsed_min - 3.0) / 3.0, 0.0, 1.0)
		else:
			phase_label.text = "INSANE"
			phase_progress.value = clamp((elapsed_min - 6.0) / 4.0, 0.0, 1.0)

	var drop_marker = ColorRect.new()
	drop_marker.color = Color(1.0, 1.0, 1.0, 0.10)
	drop_marker.position = Vector2(0, fall_top - 10)
	drop_marker.size = Vector2(drop_w, 8)
	drop_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dz_dynamic.add_child(drop_marker)

	var slots_header_row = HBoxContainer.new()
	slots_header_row.position = Vector2(14, 4)
	slots_header_row.size = Vector2(max(0.0, slots_w - 28.0), 28)
	slots_header_row.add_theme_constant_override("separation", 10)
	slots_header_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well_slots_draw.add_child(slots_header_row)

	var top_lbl = Label.new()
	top_lbl.text = "TOP %d" % pile_selectable
	top_lbl.add_theme_font_size_override("font_size", _skin_font_size("tiny", 12))
	top_lbl.add_theme_color_override("font_color", _skin_color("text_muted", Color(0.84, 0.84, 0.84)))
	top_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_lbl.custom_minimum_size = Vector2(54, 0)
	slots_header_row.add_child(top_lbl)

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
	var slot_w = max(0.0, slots_w - 28.0)
	var active_count = clamp(pile_selectable, 0, pile_max)
	var locked_count = max(0, pile_max - active_count)
	var available_h = max(140.0, pile_bottom - slots_top)
	var total_gap_h = SLOT_GAP * float(max(0, pile_max - 1))
	var content_h = max(1.0, available_h - total_gap_h)
	var active_h = 0.0
	var locked_h = 0.0
	if active_count <= 0:
		locked_h = clamp(content_h / float(max(1, pile_max)), 54.0, 132.0)
	else:
		var active_weight = 1.35
		var locked_weight = 1.0
		var total_weight = float(active_count) * active_weight + float(locked_count) * locked_weight
		var base_unit = content_h / max(0.001, total_weight)
		active_h = clamp(base_unit * active_weight, 54.0, 132.0)
		locked_h = clamp(base_unit * locked_weight, 54.0, 132.0)
		var used_h = active_h * float(active_count) + locked_h * float(locked_count)
		var residual = content_h - used_h
		if abs(residual) > 0.01:
			if locked_count > 0:
				locked_h = clamp(locked_h + residual / float(locked_count), 54.0, 132.0)
			else:
				active_h = clamp(active_h + residual / float(max(1, active_count)), 54.0, 132.0)

	var total_stack_h = active_h * float(active_count) + locked_h * float(locked_count) + total_gap_h
	var y_cursor = slots_top + max(0.0, available_h - total_stack_h)

	var slot_preview_cell = int(clamp(float(cell_size) * 0.95, 14.0, 52.0))
	var neon_min = float(core.call("GetWellNeonMinAlpha"))
	var neon_max = float(core.call("GetWellNeonMaxAlpha"))

	for slot_i in range(pile_max):
		var is_active = active_count > 0 and slot_i < active_count
		var h = active_h if is_active else locked_h

		var slot = Panel.new()
		slot.size = Vector2(slot_w, h)
		slot.position = Vector2(14, y_cursor)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		well_slots_draw.add_child(slot)
		y_cursor += h + SLOT_GAP

		var pile_index = (pile.size() - 1) - slot_i

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

	if fall_piece != null and not is_game_over:
		var drop_cell = int(clamp(float(cell_size) * 0.98, 18.0, float(cell_size)))
		var fall_frame = Vector2(drop_w - 20.0, (fall_bottom - fall_top) + 40.0)
		var fitted = _fitted_cell_size(fall_piece, drop_cell, fall_frame, 0.98)
		var fall = _make_piece_preview(fall_piece, fitted, fall_frame)
		var fx = (drop_w - fall.size.x) * 0.5
		# Allow negative Y so the piece can enter from above; only clamp bottom.
		var fy = fall_y
		if fy > fall_bottom:
			fy = fall_bottom
		fall.position = Vector2(fx, fy)
		var block_fall_1 = pending_invalid_piece != null and pending_invalid_source_slot == 1 and (pending_invalid_piece_id < 0 or int(fall_piece.get_meta("piece_id", -1)) == pending_invalid_piece_id)
		if block_fall_1:
			fall.mouse_filter = Control.MOUSE_FILTER_IGNORE
			fall.modulate = Color(1, 1, 1, 0.55)
		else:
			fall.mouse_filter = Control.MOUSE_FILTER_STOP
			fall.gui_input.connect(func(ev): _on_falling_piece_input(ev, 1))
		dz_dynamic.add_child(fall)

	if fall_piece_2 != null and not is_game_over:
		var drop_cell_2 = int(clamp(float(cell_size) * 0.98, 18.0, float(cell_size)))
		var fall_frame_2 = Vector2(drop_w - 20.0, (fall_bottom - fall_top) + 40.0)
		var fitted_2 = _fitted_cell_size(fall_piece_2, drop_cell_2, fall_frame_2, 0.98)
		var fall2 = _make_piece_preview(fall_piece_2, fitted_2, fall_frame_2)
		var fx2 = (drop_w - fall2.size.x) * 0.5
		# Allow negative Y so the piece can enter from above; only clamp bottom.
		var fy2 = fall_y_2
		if fy2 > fall_bottom:
			fy2 = fall_bottom
		fall2.position = Vector2(fx2, fy2)
		var block_fall_2 = pending_invalid_piece != null and pending_invalid_source_slot == 2 and (pending_invalid_piece_id < 0 or int(fall_piece_2.get_meta("piece_id", -1)) == pending_invalid_piece_id)
		if block_fall_2:
			fall2.mouse_filter = Control.MOUSE_FILTER_IGNORE
			fall2.modulate = Color(1, 1, 1, 0.55)
		else:
			fall2.mouse_filter = Control.MOUSE_FILTER_STOP
			fall2.gui_input.connect(func(ev): _on_falling_piece_input(ev, 2))
		dz_dynamic.add_child(fall2)


func _current_drop_status_text() -> String:
	var now_ms = Time.get_ticks_msec()
	if now_ms < drop_status_locked_until_ms and drop_status_text != "":
		return drop_status_text
	if dragging:
		return "Dragging…"
	if rescue_from_well_pending and now_ms <= rescue_eligible_until_ms:
		return "Rescue ready"
	return "Tap to grab"

const STATUS_EVENT_HOLD_MS := 700 

func _show_status_for_ms(text: String, kind: int, hold_ms: int = STATUS_EVENT_HOLD_MS) -> void:
	drop_status_locked_until_ms = Time.get_ticks_msec() + max(0, hold_ms)
	_set_drop_status(text, kind)
	_last_status_sent = text
	_next_status_update_ms = Time.get_ticks_msec() + STATUS_UPDATE_INTERVAL_MS


func _set_drop_status(text: String, kind: int = STATUS_NEUTRAL) -> void:
	drop_status_text = text
	if drop_status_label == null or not is_instance_valid(drop_status_label):
		return

	# Always keep it alive/visible (tweens or theme changes must not "hide" it)
	drop_status_label.visible = true
	if drop_status_label.modulate.a <= 0.001:
		drop_status_label.modulate.a = 1.0

	# Cache base position once (for shake restore)
	if drop_status_base_pos == Vector2.ZERO:
		drop_status_base_pos = drop_status_label.position

	# Kill previous animation tween
	if drop_status_anim_tween != null and is_instance_valid(drop_status_anim_tween):
		drop_status_anim_tween.kill()
	drop_status_anim_tween = null

	var changed = (drop_status_label.text != text)
	drop_status_label.text = text

	# Base style
	var tap_col = Color(1.0, 0.92, 0.35, 1.0) # bright yellow
	var neutral_col = _skin_color("text_muted", Color(0.92, 0.92, 0.92, 1.0))
	var good_col = Color(0.10, 1.00, 0.20, 1.0) # vivid green
	var bad_col  = Color(1.00, 0.15, 0.15, 1.0) # vivid red

	# Reset transforms
	drop_status_label.position = drop_status_base_pos
	drop_status_label.scale = Vector2.ONE
	drop_status_label.rotation = 0.0

	var idle_texts = ["Tap to grab", "Tap to drag"]
	var is_idle = text in idle_texts

	if changed and not is_idle:
		drop_status_label.modulate.a = 0.0
		drop_status_anim_tween = create_tween()
		drop_status_anim_tween.tween_property(drop_status_label, "modulate:a", 1.0, 0.12)
	else:
		drop_status_label.modulate.a = 1.0

	# Apply kind effects
	if kind == STATUS_GOOD:
		drop_status_label.add_theme_color_override("font_color", good_col)
		var tw = create_tween()
		tw.tween_property(drop_status_label, "scale", Vector2(1.08, 1.08), 0.08)
		tw.tween_property(drop_status_label, "scale", Vector2.ONE, 0.12)
	elif kind == STATUS_BAD:
		drop_status_label.add_theme_color_override("font_color", bad_col)
		var tw2 = create_tween()
		var a = drop_status_base_pos
		tw2.tween_property(drop_status_label, "position", a + Vector2(-6, 0), 0.04)
		tw2.tween_property(drop_status_label, "position", a + Vector2(6, 0), 0.04)
		tw2.tween_property(drop_status_label, "position", a + Vector2(-4, 0), 0.04)
		tw2.tween_property(drop_status_label, "position", a + Vector2(4, 0), 0.04)
		tw2.tween_property(drop_status_label, "position", a, 0.05)
	else:
		if text in idle_texts:
			drop_status_label.add_theme_color_override("font_color", tap_col)
		else:
			drop_status_label.add_theme_color_override("font_color", neutral_col)
			
func _on_pile_slot_input(event: InputEvent, pile_index: int) -> void:
	if _is_gameplay_input_blocked():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected_piece = pile[pile_index]
		selected_from_pile_index = pile_index
		_play_sfx("pick")
		_start_drag_selected()


func _on_falling_piece_input(event: InputEvent, slot: int) -> void:
	if _is_gameplay_input_blocked():
		return
	if pending_invalid_piece != null and pending_invalid_source_slot == slot:
		if pending_invalid_piece_id < 0:
			return
		var slot_piece = fall_piece if slot == 1 else fall_piece_2
		if slot_piece == null or int(slot_piece.get_meta("piece_id", -1)) == pending_invalid_piece_id:
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
	drag_trail.clear()
	drag_trail.append(get_viewport().get_mouse_position())
	_build_ghost_for_piece(selected_piece)
	ghost_root.visible = true
	_set_drop_status("Dragging…", STATUS_NEUTRAL)


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
	var auto_snapped := false
	var auto_snap_succeeded := false

	if anchor.x != -999 and was_selected:
		# Precompute whether we may attempt auto-snap, so we can suppress the first invalid SFX.
		var will_attempt_auto_snap := false
		var snapped := Vector2i(-1, -1)
		if source_snapshot < 0:
			snapped = _find_best_snap_anchor(selected_piece, anchor, AUTO_SNAP_RADIUS)
			if snapped.x >= 0 and _auto_snap_trajectory_allows(release_mouse, snapped):
				will_attempt_auto_snap = true

		# Suppress invalid sound on the first attempt if auto-snap will be tried.
		suppress_invalid_sfx_once = will_attempt_auto_snap

		placed = _try_place_piece(selected_piece, anchor.x, anchor.y)

		if not placed and will_attempt_auto_snap:
			auto_snapped = true
			placed = _try_place_piece(selected_piece, snapped.x, snapped.y)
			auto_snap_succeeded = placed
			if auto_snap_succeeded:
				auto_snap_cooldown_until_ms = Time.get_ticks_msec() + AUTO_SNAP_COOLDOWN_MS

	# Only play invalid here if we ended up not placed AND auto-snap didn't succeed.
	if was_selected and not placed and (not auto_snapped or not auto_snap_succeeded):
		_play_sfx("invalid")
		_show_status_for_ms("Invalid", STATUS_BAD, 900)
		core.call("RegisterCancelledDrag")
		_spawn_pending_invalid_piece(selected_snapshot, source_snapshot, release_mouse)

	if was_selected:
		_set_piece_in_hand_state(selected_snapshot, false)

	selected_piece = null
	selected_from_pile_index = -1


func _find_best_snap_anchor(piece, preferred: Vector2i, max_radius: int) -> Vector2i:
	if piece == null:
		return Vector2i(-1, -1)
	if preferred.x < 0 or preferred.x >= BOARD_SIZE or preferred.y < 0 or preferred.y >= BOARD_SIZE:
		return Vector2i(-1, -1)
	var best := Vector2i(-1, -1)
	var best_score := 1 << 30
	for radius in range(max(0, max_radius) + 1):
		for y in range(max(0, preferred.y - radius), min(BOARD_SIZE - 1, preferred.y + radius) + 1):
			for x in range(max(0, preferred.x - radius), min(BOARD_SIZE - 1, preferred.x + radius) + 1):
				var ring_distance = abs(x - preferred.x) + abs(y - preferred.y)
				if ring_distance > radius:
					continue
				if not bool(board.call("CanPlace", piece, x, y)):
					continue
				var dx = x - preferred.x
				var dy = y - preferred.y
				var score = dx * dx + dy * dy
				if score < best_score:
					best_score = score
					best = Vector2i(x, y)
		if best.x >= 0:
			return best
	return best


func _auto_snap_trajectory_allows(release_mouse: Vector2, target_cell: Vector2i) -> bool:
	if Time.get_ticks_msec() < auto_snap_cooldown_until_ms:
		return false
	if drag_trail.size() < 2:
		return false
	var dir = drag_trail[drag_trail.size() - 1] - drag_trail[0]
	if dir.length() < float(cell_size) * AUTO_SNAP_MIN_DRAG_PX_FACTOR:
		return false
	var target_world = board_panel.global_position + board_start + Vector2(target_cell.x * cell_size, target_cell.y * cell_size)
	var target_center = target_world + Vector2(cell_size, cell_size) * 0.5
	var to_target = target_center - release_mouse
	if to_target.length() < 0.001:
		return false
	var dot = dir.normalized().dot(to_target.normalized())
	return dot >= AUTO_SNAP_MIN_DOT


func _set_ghost_validity(is_valid: bool) -> void:
	if ghost_root == null:
		return
	var desired = 1 if is_valid else -1
	if ghost_valid_state == desired:
		return
	ghost_valid_state = desired
	var tint = Color(0.35, 1.00, 0.45, 0.70) if is_valid else Color(1.00, 0.25, 0.25, 0.78)
	for ch in ghost_root.get_children():
		if ch is CanvasItem:
			(ch as CanvasItem).modulate = tint


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
	pending_invalid_source_slot = 0
	pending_invalid_piece_id = -1
	if source_index >= 0:
		pending_invalid_source_slot = 3
	else:
		if piece == fall_piece:
			pending_invalid_source_slot = 1
		elif piece == fall_piece_2:
			pending_invalid_source_slot = 2
		if pending_invalid_source_slot == 1 or pending_invalid_source_slot == 2:
			pending_invalid_piece_id = int(piece.get_meta("piece_id", -1))
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

	var frame = Vector2(max(72.0, float(cell_size) * 2.8), max(72.0, float(cell_size) * 2.8))
	pending_invalid_root = Control.new()
	pending_invalid_root.size = frame
	pending_invalid_root.mouse_filter = Control.MOUSE_FILTER_STOP
	pending_invalid_root.z_index = 1200
	pending_invalid_root.z_as_relative = false
	pending_invalid_root.position = screen_pos - frame * 0.5
	pending_invalid_root.gui_input.connect(_on_pending_invalid_input)

	var pv = _make_piece_preview(piece, max(18, int(float(cell_size) * 0.92)), frame)
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
	pending_invalid_source_slot = 0
	pending_invalid_piece_id = -1
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
		if not suppress_invalid_sfx_once:
			_play_sfx("invalid")
			_show_status_for_ms("Invalid", STATUS_BAD, 900)
		else:
			suppress_invalid_sfx_once = false # consume the suppression
		return false

	var w_hole = int(core.call("GetDeadZoneWeightHole1x1"))
	var w_pocket = int(core.call("GetDeadZoneWeightPocket1x2"))
	var w_overhang = int(core.call("GetDeadZoneWeightOverhang"))
	var dz_margin = int(core.call("GetDeadZoneMargin"))
	board.call("BeginDeadZoneEvaluation", piece, ax, ay, dz_margin, w_hole, w_pocket, w_overhang)

	var sticky_delay_moves = int(core.call("GetStickyDelayMoves"))
	var sticky_stones_to_create = 0
	if _is_piece_sticky(piece):
		sticky_stones_to_create = int(core.call("GetStickyStonesForPieceSize", int(piece.get("Cells").size())))

	var result: Dictionary = board.call("PlaceAndClear", piece, ax, ay, sticky_delay_moves, sticky_stones_to_create)
	var dead_zone_delta = int(board.call("EndDeadZoneEvaluation", w_hole, w_pocket, w_overhang))
	core.call("RegisterDeadZoneDelta", dead_zone_delta)

	# Paint placed cells
	var kind = String(piece.get("Kind"))
	var col = _color_for_kind(kind)
	var is_sticky_piece := _is_piece_sticky(piece)
	for c in piece.get("Cells"):
		var x = ax + int(c.x)
		var y = ay + int(c.y)
		if x >= 0 and x < BOARD_SIZE and y >= 0 and y < BOARD_SIZE:
			color_grid[y][x] = col
			sticky_grid[y][x] = is_sticky_piece

	# Clear colors for cleared cells
	var cleared = result.get("cleared", [])
	for pos in cleared:
		var px = int(pos.x)
		var py = int(pos.y)
		if px >= 0 and px < BOARD_SIZE and py >= 0 and py < BOARD_SIZE:
			color_grid[py][px] = null
			sticky_grid[py][px] = false

	var sticky_cells = result.get("sticky_triggered_cells", [])
	for spos in sticky_cells:
		var sx = int(spos.x)
		var sy = int(spos.y)
		if sx >= 0 and sx < BOARD_SIZE and sy >= 0 and sy < BOARD_SIZE:
			color_grid[sy][sx] = COLOR_STONE
			sticky_grid[sy][sx] = true
			_reveal_stone_overlay_at(sx, sy)

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
		_show_status_for_ms("Nice!", STATUS_GOOD, 750)
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


func _maybe_trigger_no_well_entry_punish(now_ms: int) -> void:
	if _is_gameplay_input_blocked() or is_game_over:
		return
	var interval_ms = 30000 if pile.size() == 0 else 60000
	if interval_ms != punish_interval_ms:
		punish_interval_ms = interval_ms
		next_punish_due_ms = now_ms + punish_interval_ms
	if now_ms < next_punish_due_ms:
		return
	_do_board_shake()
	_stoneify_random_filled_cells_by_difficulty()
	next_punish_due_ms = now_ms + punish_interval_ms


func _count_stone_cells_on_board() -> int:
	var count = 0
	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			if int(board.call("GetCell", x, y)) == 2:
				count += 1
	return count


func _max_stone_cells_allowed() -> int:
	return int(floor(float(BOARD_SIZE * BOARD_SIZE) * 0.70))


func _stone_budget_remaining() -> int:
	return max(0, _max_stone_cells_allowed() - _count_stone_cells_on_board())


func _difficulty_stoneify_ratio() -> float:
	var diff = String(Save.get_current_difficulty()).to_lower()
	if diff == "easy":
		return 0.10
	if diff == "hard" or diff == "hardcore":
		return 0.30
	return 0.20


func _stoneify_random_filled_cells_by_difficulty() -> void:
	var filled_non_stone: Array[Vector2i] = []
	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			if int(board.call("GetCell", x, y)) == 1:
				filled_non_stone.append(Vector2i(x, y))
	if filled_non_stone.is_empty():
		return
	var stone_budget = _stone_budget_remaining()
	if stone_budget <= 0:
		if OS.is_debug_build():
			push_warning("Stoneify skipped: stone cap reached (%d/%d)." % [_count_stone_cells_on_board(), _max_stone_cells_allowed()])
		return
	var ratio = _difficulty_stoneify_ratio()
	var requested_count = int(ceil(float(filled_non_stone.size()) * ratio))
	var count = max(1, min(requested_count, filled_non_stone.size()))
	count = min(count, stone_budget)
	if count <= 0:
		if OS.is_debug_build():
			push_warning("Stoneify skipped: clamped to 0 by stone cap.")
		return
	if OS.is_debug_build() and count < requested_count:
		push_warning("Stoneify clamped by stone cap: requested %d, applied %d." % [requested_count, count])
	filled_non_stone.shuffle()
	for i in range(count):
		var pos = filled_non_stone[i]
		board.call("SetCell", pos.x, pos.y, 2)
		color_grid[pos.y][pos.x] = COLOR_STONE
		sticky_grid[pos.y][pos.x] = true
	_refresh_board_visual()


func _do_board_shake() -> void:
	if board_content_root == null:
		return
	var tw = create_tween()
	for i in range(6):
		var off = Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0))
		tw.tween_property(board_content_root, "position", off, 0.05)
	tw.tween_property(board_content_root, "position", Vector2.ZERO, 0.08)


func _on_board_cell_input(event: InputEvent, x: int, y: int) -> void:
	if _is_gameplay_input_blocked():
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
	_dbg_ui_check()
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
	_maybe_trigger_no_well_entry_punish(now_ms)
	if pending_spawn_piece and now_ms >= spawn_wait_until_ms:
		_spawn_falling_piece()
	if pending_dual_spawn_ms > 0 and _dual_drop_can_spawn(now_ms):
		_spawn_second_falling_piece()

	var geom = _well_geometry()
	var fall_bottom = float(geom["fall_bottom"])
	if fall_piece != null:
		fall_y += fall_speed * delta
		# Commit when the BOTTOM of the piece touches the bottom boundary.
		var h1 = _fall_piece_height_px(fall_piece)
		if (fall_y + h1) >= fall_bottom:
			# Snap visually to the touch point before commit (avoid 1-frame overshoot).
			fall_y = fall_bottom - h1
			if OS.is_debug_build():
				print("[DROP_COMMIT] slot=1 touch_y=", (fall_y + h1), " fall_bottom=", fall_bottom, " fall_y=", fall_y, " h=", h1)
			_lock_falling_to_pile()
	if fall_piece_2 != null:
		fall_y_2 += fall_speed * delta
		var h2 = _fall_piece_height_px(fall_piece_2)
		if (fall_y_2 + h2) >= fall_bottom:
			fall_y_2 = fall_bottom - h2
			if OS.is_debug_build():
				print("[DROP_COMMIT] slot=2 touch_y=", (fall_y_2 + h2), " fall_bottom=", fall_bottom, " fall_y=", fall_y_2, " h=", h2)
			_commit_piece_to_well(fall_piece_2)
			if is_game_over:
				return

	_redraw_well()
	_update_status_hud()
	_maybe_update_drop_status(false)
	_update_time_slow_overlay()
	_update_skill_icon_states()

	# Drag: ghost always visible
	if dragging and selected_piece != null:
		var mouse = get_viewport().get_mouse_position()
		if drag_trail.is_empty():
			drag_trail.append(mouse)
		elif mouse.distance_to(drag_trail[drag_trail.size() - 1]) >= 6.0:
			drag_trail.append(mouse)
		while drag_trail.size() > AUTO_SNAP_TRAIL_POINTS:
			drag_trail.remove_at(0)
		var cell = _mouse_to_board_cell(mouse)

		if cell.x == -1:
			drag_anchor = Vector2i(-999, -999)
			_clear_highlight()
			if ghost_valid_state != 0:
				ghost_valid_state = 0
				for ch in ghost_root.get_children():
					if ch is CanvasItem:
						(ch as CanvasItem).modulate = Color(1, 1, 1, 1)
			ghost_root.visible = true
			ghost_root.global_position = mouse - ghost_bbox_size * 0.5
			ghost_shake_phase = 0.0
		else:
			var top_left = board_panel.global_position + board_start + Vector2(cell.x * cell_size, cell.y * cell_size)
			ghost_root.visible = true
			ghost_root.global_position = top_left
			drag_anchor = cell
			var is_invalid_anchor = not bool(board.call("CanPlace", selected_piece, cell.x, cell.y))
			if is_invalid_anchor:
				ghost_shake_phase += delta * 30.0
				ghost_root.global_position += Vector2(sin(ghost_shake_phase) * ghost_shake_strength_px, 0)
			else:
				ghost_shake_phase = 0.0
			_set_ghost_validity(not is_invalid_anchor)
			_highlight_piece(selected_piece, cell.x, cell.y)

		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_finish_drag()


func _dbg_ui_check() -> void:
	if not OS.is_debug_build():
		return
	var now = Time.get_ticks_msec()
	if now < _dbg_next_check_ms:
		return
	_dbg_next_check_ms = now + 2000

	# 1) Title exists and visible
	var title_ok = (title_label != null and title_label.visible) or (title_texture_rect != null and title_texture_rect.visible)
	print("[UI_CHECK] title_ok=", title_ok)

	# 2) Falling piece can spawn above (fall_y should start < fall_top sometimes)
	var geom = _well_geometry()
	var fall_top = float(geom.get("fall_top", 0.0))
	print("[UI_CHECK] fall_y=", fall_y, " fall_top=", fall_top)

	# 3) Status exists and has text
	var st_ok = (drop_status_label != null and is_instance_valid(drop_status_label) and drop_status_label.text.length() > 0)
	print("[UI_CHECK] status_ok=", st_ok, " text='", (drop_status_label.text if drop_status_label != null else "null"), "'")


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
	_update_skill_icon_states()


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

	ghost_valid_state = 0
	var base_col := _color_for_kind(String(piece.get("Kind")))
	var ghost_col := Color(base_col.r, base_col.g, base_col.b, 0.55)

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
	var infected := _is_piece_sticky(piece)
	for c in piece.get("Cells"):
		var px := int(c.x) - min_x
		var py := int(c.y) - min_y
		var b := _bevel_block(col, mini - 2, infected)
		b.position = Vector2(start_x + px * mini, start_y + py * mini)
		root.add_child(b)

	return root


func _color_for_kind(kind: String) -> Color:
	return _skin_piece_color(kind)


func _is_piece_sticky(piece) -> bool:
	if piece == null:
		return false
	if piece.has_meta("debug_force_sticky") and bool(piece.get_meta("debug_force_sticky")):
		return true
	var has_meta_access = piece.has_method("has_meta") and piece.has_method("get_meta")
	if piece.has_method("get"):
		var sticky_value = piece.get("IsSticky")
		if sticky_value != null and bool(sticky_value):
			return true
	if has_meta_access and piece.has_meta("IsSticky"):
		return bool(piece.get_meta("IsSticky"))
	if OS.is_debug_build() and not _sticky_piece_access_warned and not piece.has_method("get") and not has_meta_access:
		_sticky_piece_access_warned = true
		push_warning("_is_piece_sticky: piece does not support IsSticky property or metadata access")
	return false


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


func _bevel_block(base: Color, size_px: int, infected: bool = false) -> Control:
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
	if infected:
		var overlay = TextureRect.new()
		overlay.name = "StoneOverlay"
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.offset_left = 2
		overlay.offset_top = 2
		overlay.offset_right = -2
		overlay.offset_bottom = -2
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		overlay.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		overlay.texture = _get_stone_overlay_tex()
		overlay.visible = overlay.texture != null
		overlay.z_index = 50
		overlay.material = null
		overlay.modulate = Color(1, 1, 1, 0.72)
		p.add_child(overlay)
	return p


func _get_stone_overlay_tex() -> Texture2D:
	if _stone_overlay_tex_cache != null:
		return _stone_overlay_tex_cache
	if not ResourceLoader.exists(STONE_OVERLAY_TEX_PATH):
		if OS.is_debug_build():
			push_warning("Stone overlay texture not found: %s" % STONE_OVERLAY_TEX_PATH)
		return null
	var tex = load(STONE_OVERLAY_TEX_PATH)
	if tex is Texture2D:
		_stone_overlay_tex_cache = tex as Texture2D
		return _stone_overlay_tex_cache
	if OS.is_debug_build():
		push_warning("Stone overlay texture is not Texture2D: %s" % STONE_OVERLAY_TEX_PATH)
	return null


func _animate_stone_overlay_show(overlay: TextureRect, target_alpha: float = 0.72) -> void:
	if overlay == null:
		return
	overlay.visible = true
	overlay.material = null
	var prev_tw = overlay.get_meta("stone_tw", null)
	if prev_tw is Tween:
		(prev_tw as Tween).kill()
	overlay.modulate = Color(1, 1, 1, 0)
	overlay.scale = Vector2(0.92, 0.92)
	var tw = create_tween()
	tw.tween_property(overlay, "modulate:a", target_alpha, 0.20).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(overlay, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	overlay.set_meta("stone_tw", tw)


func _hide_stone_overlay(overlay: TextureRect) -> void:
	if overlay == null:
		return
	var prev_tw = overlay.get_meta("stone_tw", null)
	if prev_tw is Tween:
		(prev_tw as Tween).kill()
	overlay.set_meta("stone_tw", null)
	overlay.material = null
	overlay.visible = false
	overlay.modulate = Color(1, 1, 1, 0)
	overlay.scale = Vector2.ONE


func _reveal_stone_overlay_at(sx: int, sy: int) -> void:
	if sy < 0 or sy >= board_stone_overlay.size():
		return
	var row = board_stone_overlay[sy]
	if sx < 0 or sx >= row.size():
		return
	var overlay = row[sx] as TextureRect
	if overlay == null:
		return
	if overlay.texture == null:
		overlay.texture = _get_stone_overlay_tex()
	if overlay.texture == null:
		overlay.visible = false
		return
	if sy >= 0 and sy < board_stone_overlay_revealed.size() and sx >= 0 and sx < board_stone_overlay_revealed[sy].size():
		board_stone_overlay_revealed[sy][sx] = false
	_animate_stone_overlay_show(overlay, 0.72)
	board_hl[sy][sx].color = Color(1.0, 0.35, 0.18, 0.34)
	var hl_tw = create_tween()
	hl_tw.tween_property(board_hl[sy][sx], "color", Color(0, 0, 0, 0), 0.12)


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
