extends Control

const BoardGridOverlay = preload("res://Scripts/BoardGridOverlay.gd")
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
var lbl_panic: Label
var lbl_rescue: Label
var lbl_dual: Label
var next_box: Panel

var btn_settings: Button
var btn_exit: Button
var exit_dialog: AcceptDialog

# Game Over overlay
var overlay_dim: ColorRect
var overlay_text: Label
var is_game_over: bool = false

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
var sfx_players = {}
var missing_sfx_warned = {}
var next_preview_kind = ""
var next_pending_kind = ""
var last_dual_drop_min = -1.0

const NORMAL_RESPAWN_DELAY_MS = 260

# Per-round perks (optional: keep buttons later if you want)
var reroll_uses_left: int = 1
var freeze_uses_left: int = 1


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
	_audio_setup()

	_build_ui()
	await get_tree().process_frame
	_build_board_grid()

	_start_round()
	set_process(true)


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
	Engine.time_scale = 1.0

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
	Engine.time_scale = 1.0
	set_process(false)

	# Save global progress (Stage 1)
	Save.mark_played_today_if_needed()
	Save.update_best(score, level)
	Save.save()

	_show_game_over_overlay()




func _wire_button_sfx(btn) -> void:
	btn.mouse_entered.connect(func(): _play_sfx("ui_hover"))
	btn.pressed.connect(func(): _play_sfx("ui_click"))

func _audio_setup() -> void:
	_ensure_sfx("ui_hover", "res://Assets/Audio/ui_hover.wav", -12.0)
	_ensure_sfx("ui_click", "res://Assets/Audio/ui_click.wav", -10.0)
	_ensure_sfx("pick", "res://Assets/Audio/pick_piece.wav", -11.0)
	_ensure_sfx("place", "res://Assets/Audio/place_piece.wav", -9.0)
	_ensure_sfx("invalid", "res://Assets/Audio/invalid_drop.wav", -9.0)
	_ensure_sfx("well_enter", "res://Assets/Audio/well_enter.wav", -6.0)
	_ensure_sfx("clear", "res://Assets/Audio/clear.wav", -7.0)
	_ensure_sfx("panic", "res://Assets/Audio/panic_tick.wav", -14.0)


func _ensure_sfx(key, path, volume_db) -> void:
	if sfx_players.has(key):
		return
	if not ResourceLoader.exists(path):
		_warn_missing_sfx_once(key, path)
		return
	var p = AudioStreamPlayer.new()
	p.bus = "Master"
	p.volume_db = volume_db
	p.stream = load(path)
	if p.stream == null:
		_warn_missing_sfx_once(key, path)
		return
	add_child(p)
	sfx_players[key] = p


func _warn_missing_sfx_once(key, path) -> void:
	if missing_sfx_warned.has(key):
		return
	missing_sfx_warned[key] = true
	if OS.is_debug_build():
		push_warning("Missing SFX '%s' at %s (audio skipped)." % [key, path])


func _play_sfx(key) -> void:
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


func _update_pending_next_kind() -> void:
	var pending_piece = core.call("PeekNextPieceForBoard", board)
	next_pending_kind = ""
	if pending_piece != null:
		next_pending_kind = String(pending_piece.get("Kind"))


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
	if lbl_panic == null or lbl_rescue == null or lbl_dual == null:
		return
	var now = Time.get_ticks_msec()
	var well_fill = _well_fill_ratio()
	var danger = well_fill >= danger_start_ratio or time_scale_reason == "NoMercyExtra" or time_scale_reason == "WellDrag"
	var pulse = 0.5 + 0.5 * sin(float(now) / 220.0)
	if danger:
		lbl_panic.modulate = Color(1.0, 0.35 + 0.35 * pulse, 0.35 + 0.35 * pulse, 1.0)
		lbl_panic.text = "PANIC %.0f%%" % (well_fill * 100.0)
	else:
		lbl_panic.modulate = Color(0.82, 0.94, 0.86, 1.0)
		lbl_panic.text = "Panic %.0f%%" % (well_fill * 100.0)
	var rescue_left = max(0, rescue_eligible_until_ms - now)
	if rescue_from_well_pending and rescue_left > 0:
		lbl_rescue.text = "RESCUE READY %.1fs" % (float(rescue_left) / 1000.0)
		lbl_rescue.modulate = Color(0.60, 1.0, 0.70, 1.0)
	else:
		lbl_rescue.text = "Rescue cooldown"
		lbl_rescue.modulate = Color(0.80, 0.84, 0.88, 1.0)
	var dual_text = "Dual x%d" % _active_falling_count()
	if pending_dual_spawn_ms > 0:
		var left = max(0, pending_dual_spawn_ms - now)
		dual_text = "Dual x2 pending %.1fs" % (float(left) / 1000.0)
		var dp = 0.5 + 0.5 * sin(float(now) / 180.0)
		lbl_dual.modulate = Color(1.0, 0.95, 0.60 + 0.35 * dp, 1.0)
	elif dual_drop_cycle_pending or dual_drop_waiting_for_gap:
		dual_text = "Dual x2 queued"
		lbl_dual.modulate = Color(1.0, 0.92, 0.62, 1.0)
	else:
		lbl_dual.modulate = Color(0.86, 0.88, 0.92, 1.0)
	lbl_dual.text = dual_text


# ============================================================
# UI build (new layout)
# ============================================================
func _build_ui() -> void:
	for ch in get_children():
		if ch is AudioStreamPlayer:
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

	title_label = Label.new()
	title_label.text = "TETRIS SUDOKU"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.clip_text = true
	title_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title_label.offset_top = 8
	title_label.offset_left = 20
	title_label.offset_right = -20
	title_label.offset_bottom = 72
	title_label.add_theme_font_size_override("font_size", _skin_font_size("title", 48))
	title_label.add_theme_color_override("font_color", _skin_color("text_primary", Color(0.10, 0.10, 0.10)))
	root_frame.add_child(title_label)

	var root_margin = MarginContainer.new()
	root_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_margin.add_theme_constant_override("margin_left", 24)
	root_margin.add_theme_constant_override("margin_right", 24)
	root_margin.add_theme_constant_override("margin_top", 80)
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
	top_row.add_theme_constant_override("separation", 16)
	main_v.add_child(top_row)

	board_panel = Panel.new()
	board_panel.custom_minimum_size = Vector2(620, 680)
	board_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_panel.add_theme_stylebox_override("panel", _style_board_panel())
	top_row.add_child(board_panel)

	hud_panel = Panel.new()
	hud_panel.custom_minimum_size = Vector2(360, 0)
	hud_panel.size_flags_horizontal = Control.SIZE_FILL
	hud_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hud_panel.add_theme_stylebox_override("panel", _style_hud_panel())
	top_row.add_child(hud_panel)

	var hud_scroll = ScrollContainer.new()
	hud_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hud_scroll.clip_contents = true
	hud_panel.add_child(hud_scroll)

	var hv_margin = MarginContainer.new()
	hv_margin.custom_minimum_size = Vector2(0, 640)
	hv_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv_margin.add_theme_constant_override("margin_left", 14)
	hv_margin.add_theme_constant_override("margin_right", 14)
	hv_margin.add_theme_constant_override("margin_top", 14)
	hv_margin.add_theme_constant_override("margin_bottom", 14)
	hud_scroll.add_child(hv_margin)

	var hv = VBoxContainer.new()
	hv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hv.add_theme_constant_override("separation", 10)
	hv_margin.add_child(hv)

	lbl_score = _hud_line("Score", "0"); hv.add_child(lbl_score)
	lbl_speed = _hud_line("Speed", "1.00"); hv.add_child(lbl_speed)
	lbl_level = _hud_line("Level", "1"); hv.add_child(lbl_level)
	lbl_time  = _hud_line("Time", "00:00"); hv.add_child(lbl_time)

	var next_title = Label.new()
	next_title.text = "NEXT"
	next_title.add_theme_font_size_override("font_size", _skin_font_size("normal", 24))
	next_title.add_theme_color_override("font_color", _skin_color("text_primary", Color(0.12, 0.12, 0.12)))
	hv.add_child(next_title)

	next_box = Panel.new()
	next_box.custom_minimum_size = Vector2(0, 180)
	next_box.add_theme_stylebox_override("panel", _style_preview_box())
	hv.add_child(next_box)

	lbl_panic = Label.new()
	lbl_panic.add_theme_font_size_override("font_size", _skin_font_size("normal", 22))
	hv.add_child(lbl_panic)

	lbl_rescue = Label.new()
	lbl_rescue.add_theme_font_size_override("font_size", _skin_font_size("small", 16))
	hv.add_child(lbl_rescue)

	lbl_dual = Label.new()
	lbl_dual.add_theme_font_size_override("font_size", _skin_font_size("small", 18))
	hv.add_child(lbl_dual)

	var skills_title = Label.new()
	skills_title.text = "Skills"
	skills_title.add_theme_font_size_override("font_size", _skin_font_size("normal", 24))
	hv.add_child(skills_title)
	hv.add_child(_build_skill_card("Reroll", 5, 1))
	hv.add_child(_build_skill_card("Freeze", 10, 3))
	hv.add_child(_build_skill_card("Clear", 20, 6))

	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hv.add_child(spacer)

	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 10)
	hv.add_child(btn_row)

	btn_settings = Button.new()
	btn_settings.text = "⚙ Settings"
	btn_settings.custom_minimum_size = Vector2(140, 52)
	btn_settings.add_theme_stylebox_override("normal", _style_gamepad_button_normal())
	btn_settings.add_theme_stylebox_override("hover", _style_gamepad_button_hover())
	btn_settings.add_theme_stylebox_override("pressed", _style_gamepad_button_pressed())
	btn_settings.add_theme_stylebox_override("focus", _style_gamepad_button_hover())
	btn_settings.pressed.connect(_on_settings)
	_wire_button_sfx(btn_settings)
	btn_row.add_child(btn_settings)

	btn_exit = Button.new()
	btn_exit.text = "⨯ Exit"
	btn_exit.custom_minimum_size = Vector2(120, 52)
	btn_exit.add_theme_stylebox_override("normal", _style_gamepad_button_normal())
	btn_exit.add_theme_stylebox_override("hover", _style_gamepad_button_hover())
	btn_exit.add_theme_stylebox_override("pressed", _style_gamepad_button_pressed())
	btn_exit.add_theme_stylebox_override("focus", _style_gamepad_button_hover())
	btn_exit.pressed.connect(_on_exit)
	_wire_button_sfx(btn_exit)
	btn_row.add_child(btn_exit)

	well_panel = Panel.new()
	well_panel.custom_minimum_size = Vector2(0, 760)
	well_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	well_panel.size_flags_vertical = Control.SIZE_FILL
	well_panel.add_theme_stylebox_override("panel", _style_bottom_panel())
	well_panel.clip_contents = true
	main_v.add_child(well_panel)

	well_draw = HBoxContainer.new()
	well_draw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	well_draw.offset_left = 14
	well_draw.offset_right = -14
	well_draw.offset_top = 14
	well_draw.offset_bottom = -14
	well_draw.add_theme_constant_override("separation", 12)
	well_panel.add_child(well_draw)

	drop_zone_panel = Panel.new()
	drop_zone_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drop_zone_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	drop_zone_panel.size_flags_stretch_ratio = 6.0
	drop_zone_panel.add_theme_stylebox_override("panel", _style_preview_box())
	well_draw.add_child(drop_zone_panel)

	drop_zone_draw = Control.new()
	drop_zone_draw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	drop_zone_draw.offset_left = 10
	drop_zone_draw.offset_right = -10
	drop_zone_draw.offset_top = 10
	drop_zone_draw.offset_bottom = -10
	drop_zone_draw.mouse_filter = Control.MOUSE_FILTER_STOP
	drop_zone_panel.add_child(drop_zone_draw)

	well_slots_panel = Panel.new()
	well_slots_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	well_slots_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	well_slots_panel.size_flags_stretch_ratio = 4.0
	well_slots_panel.add_theme_stylebox_override("panel", _style_preview_box())
	well_draw.add_child(well_slots_panel)

	well_slots_draw = Control.new()
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

	overlay_dim = ColorRect.new()
	overlay_dim.color = Color(0, 0, 0, 0.55)
	overlay_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_dim.visible = false
	overlay_dim.mouse_filter = Control.MOUSE_FILTER_STOP
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


func _hud_line(k: String, v: String) -> Label:
	var l = Label.new()
	l.text = "%s: %s" % [k, v]
	l.add_theme_font_size_override("font_size", _skin_font_size("normal", 24))
	l.add_theme_color_override("font_color", _skin_color("text_primary", Color(0.10, 0.10, 0.10)))
	return l


func _build_skill_card(label_text: String, req_level: int, progress_level: int) -> Control:
	var panel = Panel.new()
	panel.custom_minimum_size = Vector2(0, 84)
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
		col.add_child(pb)
		var lock = Label.new()
		lock.text = "Locked until Lv.%d" % req_level
		lock.add_theme_font_size_override("font_size", _skin_font_size("tiny", 12))
		col.add_child(lock)

	return panel


func _show_game_over_overlay() -> void:
	overlay_dim.visible = true
	overlay_text.visible = true
	overlay_dim.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_start_round()
			set_process(true)
	)


func _hide_game_over_overlay() -> void:
	overlay_dim.visible = false
	overlay_text.visible = false


func _on_settings() -> void:
	# Reserved for settings panel.
	return


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
	var next_piece = core.call("PeekNextPieceForBoard", board)
	next_preview_kind = ""
	if next_piece != null:
		next_preview_kind = String(next_piece.get("Kind"))
	_draw_preview(next_box, next_piece)
	_update_pending_next_kind()


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
	var preview_cell_size = _fitted_cell_size(piece, desired_cell, preview_size, 0.92)

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
	next_box.queue_redraw()
	_update_previews()


func _lock_falling_to_pile() -> void:
	if selected_piece == fall_piece:
		_force_cancel_drag("CommittedToWell", true)
	pile.append(fall_piece)
	fall_piece = null
	_play_sfx("well_enter")
	_trigger_micro_freeze()
	well_header_pulse_left = 0.35
	if pile.size() > pile_max:
		_trigger_game_over()
		return
	if _active_falling_count() == 0 and pending_dual_spawn_ms == 0:
		_schedule_next_falling_piece()


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
	var well_ready = pile.size() > 0 and min(pile_selectable, pile.size()) > 0
	var neon = 0.5 + 0.5 * sin(float(now_ms) / 280.0)

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

	var drop_label = Label.new()
	drop_label.text = "DROP"
	drop_label.position = Vector2(8, fall_top - 28)
	drop_label.add_theme_font_size_override("font_size", _skin_font_size("tiny", 12))
	drop_label.add_theme_color_override("font_color", _skin_color("text_muted", Color(0.82, 0.82, 0.82)))
	drop_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drop_zone_draw.add_child(drop_label)

	var slots_header = Label.new()
	slots_header.text = "WELL: %d / %d" % [pile.size(), pile_max]
	slots_header.position = Vector2(8, 4)
	slots_header.add_theme_font_size_override("font_size", _skin_font_size("normal", 22))
	var pulse_alpha = clamp(well_header_pulse_left * 2.4, 0.0, 0.75)
	var neon_alpha = 0.20 * neon if well_ready else 0.0
	slots_header.add_theme_color_override("font_color", Color(1.0, 0.78 + neon_alpha, 0.45, 0.85 + pulse_alpha * 0.2 + neon_alpha * 0.5))
	slots_header.scale = Vector2(1.0 + pulse_alpha * 0.08 + neon_alpha * 0.10, 1.0 + pulse_alpha * 0.08 + neon_alpha * 0.10)
	slots_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well_slots_draw.add_child(slots_header)

	var slots_progress_bg = ColorRect.new()
	slots_progress_bg.color = Color(1, 1, 1, 0.12)
	slots_progress_bg.position = Vector2(8, 34)
	slots_progress_bg.size = Vector2(slots_w - 16, 10)
	slots_progress_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well_slots_draw.add_child(slots_progress_bg)

	var slots_progress_fg = ColorRect.new()
	slots_progress_fg.position = slots_progress_bg.position
	slots_progress_fg.size = Vector2(slots_progress_bg.size.x * fill_ratio, slots_progress_bg.size.y)
	if fill_ratio >= danger_end_ratio:
		slots_progress_fg.color = _skin_color("danger", Color(0.95, 0.20, 0.20))
	elif fill_ratio >= danger_start_ratio:
		slots_progress_fg.color = Color(0.95, 0.82, 0.28, 0.90)
	else:
		slots_progress_fg.color = Color(0.32, 0.85, 0.45, 0.90)
	slots_progress_fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well_slots_draw.add_child(slots_progress_fg)

	if well_ready:
		var ring = Label.new()
		ring.text = "⟳"
		ring.position = Vector2(slots_w - 34, 4)
		ring.rotation = float(now_ms % 2000) / 2000.0 * TAU
		ring.add_theme_font_size_override("font_size", _skin_font_size("normal", 22))
		ring.add_theme_color_override("font_color", Color(1.0, 0.95, 0.55, 0.65 + 0.35 * neon))
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		well_slots_draw.add_child(ring)

	var loop_bg = ColorRect.new()
	loop_bg.color = Color(1, 1, 1, 0.08)
	loop_bg.position = Vector2(8, 48)
	loop_bg.size = Vector2(slots_w - 16, 4)
	loop_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well_slots_draw.add_child(loop_bg)

	var loop_fg = ColorRect.new()
	loop_fg.color = Color(1.0, 0.92, 0.52, 0.45 + 0.35 * neon)
	var travel = max(1.0, loop_bg.size.x - 30.0)
	var phase = fmod(float(now_ms) * 0.12, travel)
	loop_fg.position = Vector2(loop_bg.position.x + phase, loop_bg.position.y)
	loop_fg.size = Vector2(30, 4)
	loop_fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well_slots_draw.add_child(loop_fg)

	var slots_top = max(pile_top, 52.0)
	var slot_w = slots_w - 16.0
	var available_h = max(140.0, pile_bottom - slots_top)
	var per_slot = available_h / float(max(1, pile_max))
	var dynamic_h = max(46.0, min(76.0, per_slot - SLOT_GAP))
	var slot_preview_cell = int(clamp(float(cell_size) * 0.64, 12.0, 34.0))

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
			var lock_lbl = Label.new()
			lock_lbl.text = "🔒 Locked"
			lock_lbl.add_theme_font_size_override("font_size", _skin_font_size("small", 16))
			lock_lbl.position = Vector2(10, 10)
			lock_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(lock_lbl)

		if pile_index >= 0:
			var p = pile[pile_index]
			if is_active:
				slot.gui_input.connect(func(ev): _on_pile_slot_input(ev, pile_index))

			var slot_frame = Vector2(slot.size.x - 10, slot.size.y - 10)
			var slot_cell = _fitted_cell_size(p, slot_preview_cell, slot_frame, 0.9)
			var preview = _make_piece_preview(p, slot_cell, slot_frame)
			preview.position = Vector2((slot.size.x - preview.size.x) * 0.5, (slot.size.y - preview.size.y) * 0.5)
			slot.add_child(preview)
		elif is_active:
			var empty = Label.new()
			empty.text = "Empty"
			empty.add_theme_font_size_override("font_size", _skin_font_size("small", 16))
			empty.position = Vector2(10, 12)
			empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(empty)

	if fall_piece != null and not is_game_over:
		var drop_cell_size = int(clamp(float(cell_size) * 0.66, 14.0, 34.0))
		var fall_frame_w = min(drop_w - 20.0, 230.0)
		var fall_frame = Vector2(fall_frame_w, 120)
		var fitted_drop_cell = _fitted_cell_size(fall_piece, drop_cell_size, fall_frame, 0.9)
		var fall = _make_piece_preview(fall_piece, fitted_drop_cell, fall_frame)
		var fx = (drop_w - fall.size.x) * 0.5
		var fy = clamp(fall_y, fall_top, fall_bottom)
		fall.position = Vector2(fx, fy)
		fall.mouse_filter = Control.MOUSE_FILTER_STOP
		fall.gui_input.connect(func(ev): _on_falling_piece_input(ev, 1))
		drop_zone_draw.add_child(fall)

	if fall_piece_2 != null and not is_game_over:
		var drop_cell_size_2 = int(clamp(float(cell_size) * 0.66, 14.0, 34.0))
		var fall_frame_w_2 = min(drop_w - 20.0, 230.0)
		var fall_frame_2 = Vector2(fall_frame_w_2, 120)
		var fitted_drop_cell_2 = _fitted_cell_size(fall_piece_2, drop_cell_size_2, fall_frame_2, 0.9)
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
	drag_anchor = Vector2i(-999, -999)
	_clear_highlight()

	var was_selected := selected_piece != null
	var placed := false
	if anchor.x != -999 and was_selected:
		placed = _try_place_piece(selected_piece, anchor.x, anchor.y)

	if was_selected and not placed:
		_play_sfx("invalid")
		core.call("RegisterCancelledDrag")

	selected_piece = null
	selected_from_pile_index = -1


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
	if selected_from_pile_index >= 0 and selected_from_pile_index < pile.size():
		pile.remove_at(selected_from_pile_index)
		_force_cancel_drag("CommittedToBoard", true)
	else:
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
	speed_ui = fall_speed / 16.0
	lbl_speed.text = "Speed: %.2f" % speed_ui

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
			pile.append(fall_piece_2)
			fall_piece_2 = null
			_play_sfx("well_enter")
			_trigger_micro_freeze()
			well_header_pulse_left = 0.35
			if pile.size() > pile_max:
				_trigger_game_over()
				return
			if _active_falling_count() == 0 and pending_dual_spawn_ms == 0:
				_schedule_next_falling_piece()

	_redraw_well()
	_update_status_hud()

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
