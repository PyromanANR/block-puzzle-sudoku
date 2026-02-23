extends Control

const BoardGridOverlay = preload("res://Scripts/BoardGridOverlay.gd")

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

var lbl_score: Label
var lbl_speed: Label
var lbl_level: Label
var lbl_time: Label
var next_box: Panel

var btn_settings: Button
var btn_exit: Button

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
var frozen_left: float = 0.0

# Per-round perks (optional: keep buttons later if you want)
var reroll_uses_left: int = 1
var freeze_uses_left: int = 1


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
	set_process(false)

	# Save global progress (Stage 1)
	Save.mark_played_today_if_needed()
	Save.update_best(score, level)
	Save.save()

	_show_game_over_overlay()


# ============================================================
# UI build (new layout)
# ============================================================
func _build_ui() -> void:
	for ch in get_children():
		ch.queue_free()

	root_frame = Panel.new()
	root_frame.clip_contents = true
	if SkinManager != null and SkinManager.get_theme() != null:
		root_frame.theme = SkinManager.get_theme()
	root_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_frame.add_theme_stylebox_override("panel", _style_cartridge_frame())
	add_child(root_frame)

	# Title
	title_label = Label.new()
	title_label.text = "TETRIS SUDOKU"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.clip_text = true
	title_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title_label.offset_top = 10
	title_label.offset_left = 20
	title_label.offset_right = -20
	title_label.offset_bottom = 70
	title_label.add_theme_font_size_override("font_size", SkinManager.get_font_size("title", 44) if SkinManager != null else 44)
	title_label.add_theme_color_override("font_color", SkinManager.get_color("text_primary", Color(0.08, 0.08, 0.08)) if SkinManager != null else Color(0.08, 0.08, 0.08))
	root_frame.add_child(title_label)

	# Main vertical layout: top row (board+hud) + bottom row (well full width)
	var main_v := VBoxContainer.new()
	main_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_v.offset_top = 80
	main_v.offset_left = 24
	main_v.offset_right = -24
	main_v.offset_bottom = -24
	main_v.add_theme_constant_override("separation", 16)
	root_frame.add_child(main_v)

	# Top row
	var top_row := HBoxContainer.new()
	top_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_theme_constant_override("separation", 18)
	main_v.add_child(top_row)

	# Board panel (left)
	board_panel = Panel.new()
	board_panel.custom_minimum_size = Vector2(820, 720)
	board_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_panel.add_theme_stylebox_override("panel", _style_board_panel())
	top_row.add_child(board_panel)

	# HUD (right)
	hud_panel = Panel.new()
	hud_panel.custom_minimum_size = Vector2(320, 0)
	hud_panel.size_flags_horizontal = Control.SIZE_FILL
	hud_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hud_panel.add_theme_stylebox_override("panel", _style_hud_panel())
	top_row.add_child(hud_panel)

	var hv := VBoxContainer.new()
	hv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hv.offset_left = 16
	hv.offset_right = -16
	hv.offset_top = 16
	hv.offset_bottom = -16
	hv.add_theme_constant_override("separation", 12)
	hud_panel.add_child(hv)

	lbl_score = _hud_line("Score", "0"); hv.add_child(lbl_score)
	lbl_speed = _hud_line("Speed", "1.00"); hv.add_child(lbl_speed)
	lbl_level = _hud_line("Level", "1"); hv.add_child(lbl_level)
	lbl_time  = _hud_line("Time", "00:00"); hv.add_child(lbl_time)

	var next_title := Label.new()
	next_title.text = "NEXT"
	next_title.add_theme_font_size_override("font_size", 18)
	next_title.add_theme_color_override("font_color", Color(0.12, 0.12, 0.12))
	hv.add_child(next_title)

	next_box = Panel.new()
	next_box.custom_minimum_size = Vector2(0, 120)
	next_box.add_theme_stylebox_override("panel", _style_preview_box())
	hv.add_child(next_box)

	# Settings / Exit buttons area
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	hv.add_child(btn_row)

	btn_settings = Button.new()
	btn_settings.text = "Settings"
	btn_settings.pressed.connect(_on_settings)
	btn_row.add_child(btn_settings)

	btn_exit = Button.new()
	btn_exit.text = "Exit"
	btn_exit.pressed.connect(_on_exit)
	btn_row.add_child(btn_exit)

	var skills_title := Label.new()
	skills_title.text = "Skills"
	skills_title.add_theme_font_size_override("font_size", 20)
	hv.add_child(skills_title)
	hv.add_child(_build_skill_card("Reroll", 5, 1))
	hv.add_child(_build_skill_card("Freeze", 10, 3))
	hv.add_child(_build_skill_card("Clear", 20, 6))

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hv.add_child(spacer)

	# Bottom row = full width well
	well_panel = Panel.new()
	well_panel.custom_minimum_size = Vector2(0, 900)
	well_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	well_panel.size_flags_vertical = Control.SIZE_FILL
	well_panel.add_theme_stylebox_override("panel", _style_bottom_panel())
	well_panel.clip_contents = true
	main_v.add_child(well_panel)

	well_draw = Control.new()
	well_draw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	well_draw.offset_left = 16
	well_draw.offset_right = -16
	well_draw.offset_top = 16
	well_draw.offset_bottom = -16
	well_draw.mouse_filter = Control.MOUSE_FILTER_STOP
	well_panel.add_child(well_draw)

	# Ghost layer
	ghost_layer = Control.new()
	ghost_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ghost_layer.z_index = 1000
	root_frame.add_child(ghost_layer)

	ghost_root = Control.new()
	ghost_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost_root.visible = false
	ghost_layer.add_child(ghost_root)

	# Game over overlay
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


func _hud_line(k: String, v: String) -> Label:
	var l := Label.new()
	l.text = "%s: %s" % [k, v]
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color(0.10, 0.10, 0.10))
	return l


func _build_skill_card(label_text: String, req_level: int, progress_level: int) -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(0, 76)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_right = -8
	row.offset_top = 8
	row.offset_bottom = -8
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	var icon := ColorRect.new()
	icon.custom_minimum_size = Vector2(34, 34)
	icon.color = Color(0.95, 0.82, 0.35, 0.95)
	row.add_child(icon)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)

	var t := Label.new()
	t.text = "%s (%d)" % [label_text, req_level]
	col.add_child(t)

	if progress_level >= req_level:
		var ready := Label.new()
		ready.text = "Ready"
		col.add_child(ready)
	else:
		var pb := ProgressBar.new()
		pb.max_value = req_level
		pb.value = progress_level
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(0, 14)
		col.add_child(pb)
		var lock := Label.new()
		lock.text = "Locked until %d" % req_level
		lock.add_theme_font_size_override("font_size", 12)
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
	# Debug utility: quick simulation snapshot from CoreBridge.
	var sim6 = core.call("RunSimulationBatch", 120, 42)
	print("Balance sim default:", sim6)


func _on_exit() -> void:
	get_tree().quit()


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
	board_panel.add_child(board_grid_overlay)

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


# ============================================================
# Next preview
# ============================================================
func _update_previews() -> void:
	_draw_preview(next_box, core.call("PeekNextPieceForBoard", board))


func _draw_preview(target: Panel, piece) -> void:
	for ch in target.get_children():
		ch.queue_free()

	if piece == null:
		return

	var pv := _make_piece_preview(piece, 22)
	pv.position = Vector2(10, 10)
	target.add_child(pv)


# ============================================================
# Well (fall zone + pile zone)
# Fix #1: pile draws all pieces correctly, no 'continue' hiding
# Fix #2: fall zone never overlaps pile zone
# ============================================================
func _spawn_falling_piece() -> void:
	fall_piece = core.call("PopNextPieceForBoard", board)
	fall_y = 10.0
	_update_previews()


func _lock_falling_to_pile() -> void:
	pile.append(fall_piece)
	if pile.size() > pile_max:
		_trigger_game_over()
		return
	_spawn_falling_piece()


func _well_geometry() -> Dictionary:
	var well_h = well_draw.size.y
	var well_w = well_draw.size.x

	# If layout not ready yet, return safe defaults
	if well_h <= 1.0 or well_w <= 1.0:
		return {
			"w": 100.0, "h": 100.0,
			"pile_top": 60.0, "pile_bottom": 90.0,
			"fall_top": 10.0, "fall_bottom": 50.0
		}

	# Pile takes a ratio of the well height (stable across resolutions)
	var pile_zone_h = well_h * 0.55
	var pile_bottom = well_h - PILE_PAD
	var pile_top = pile_bottom - pile_zone_h

	# Fall zone is above pile, with clamps
	var fall_top = FALL_PAD
	var fall_bottom = pile_top - 10.0

	# Safety clamps (critical)
	if fall_bottom < fall_top + 40.0:
		# ensure at least 40px of fall space
		fall_bottom = fall_top + 40.0
		pile_top = fall_bottom + 10.0

	# Also clamp pile_top not too high
	pile_top = max(pile_top, fall_top + 50.0)

	return {
		"w": well_w,
		"h": well_h,
		"pile_top": pile_top,
		"pile_bottom": pile_bottom,
		"fall_top": fall_top,
		"fall_bottom": fall_bottom,
	}


func _redraw_well() -> void:
	for ch in well_draw.get_children():
		ch.queue_free()

	var g = _well_geometry()
	var pile_top = float(g["pile_top"])
	var pile_bottom = float(g["pile_bottom"])
	var fall_top = float(g["fall_top"])
	var fall_bottom = float(g["fall_bottom"])
	var w = float(g["w"])

	# How full the well is
	var fill_ratio = clamp(float(pile.size()) / float(pile_max), 0.0, 1.0)

	# Danger line at pile_top (stronger when near full)
	var danger_h := 4
	var danger_a := 0.25
	if fill_ratio >= danger_start_ratio:
		danger_h = 6
		danger_a = 0.35
	if fill_ratio >= danger_end_ratio:
		danger_h = 10
		danger_a = 0.50

	var danger_shadow := ColorRect.new()
	danger_shadow.color = Color(0.4, 0.0, 0.0, 0.35)
	danger_shadow.position = Vector2(0, pile_top + 2)
	danger_shadow.size = Vector2(w, danger_h + 4)
	danger_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well_draw.add_child(danger_shadow)

	var danger := ColorRect.new()
	danger.color = Color(0.95, 0.20, 0.20, max(0.45, danger_a + 0.15))
	danger.position = Vector2(0, pile_top)
	danger.size = Vector2(w, danger_h + 2)
	danger.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well_draw.add_child(danger)

	var danger_lbl := Label.new()
	danger_lbl.text = "DANGER"
	danger_lbl.add_theme_font_size_override("font_size", 14)
	danger_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.85))
	danger_lbl.position = Vector2(w - 96, pile_top - 18)
	danger_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well_draw.add_child(danger_lbl)

	# Label
	var hint := Label.new()
	hint.text = "Reserve slots: yellow = selectable, grey = locked"
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	hint.position = Vector2(14, 6)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well_draw.add_child(hint)

	# WELL counter (X / MAX)
	var well_stat := Label.new()
	well_stat.text = "WELL: %d / %d" % [pile.size(), pile_max]
	well_stat.add_theme_font_size_override("font_size", 18)
	well_stat.add_theme_color_override("font_color", Color(0.90, 0.90, 0.90))
	well_stat.position = Vector2(14, 26)
	well_stat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well_draw.add_child(well_stat)

	# Fill bar (visual pressure)
	var bar_y = pile_top - 18
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(1, 1, 1, 0.10)
	bar_bg.position = Vector2(14, bar_y)
	bar_bg.size = Vector2(w - 28, 10)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well_draw.add_child(bar_bg)

	var bar_col := Color(0.2, 0.9, 0.2, 0.75)
	if fill_ratio >= danger_start_ratio:
		bar_col = Color(0.95, 0.85, 0.2, 0.75)
	if fill_ratio >= danger_end_ratio:
		bar_col = Color(0.95, 0.2, 0.2, 0.80)

	var bar_fg := ColorRect.new()
	bar_fg.color = bar_col
	bar_fg.position = bar_bg.position
	bar_fg.size = Vector2(bar_bg.size.x * fill_ratio, bar_bg.size.y)
	bar_fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well_draw.add_child(bar_fg)

	# --- Draw stack slots exactly equal to difficulty capacity ---
	var slot_w = w - 20.0
	var available_h = max(120.0, pile_bottom - pile_top - 12.0)
	var per_slot = available_h / float(max(1, pile_max))
	var dynamic_h = max(44.0, min(SLOT_H, per_slot - SLOT_GAP))

	for slot_i in range(pile_max):
		# slot_i=0 is top selectable layer (closest to danger line)
		var y = pile_bottom - dynamic_h - float(slot_i) * (dynamic_h + SLOT_GAP)

		var slot := Panel.new()
		slot.size = Vector2(slot_w, dynamic_h)
		slot.position = Vector2(10, y)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		well_draw.add_child(slot)

		var pile_index = (pile.size() - 1) - slot_i
		var is_active = slot_i < pile_selectable

		if is_active:
			slot.add_theme_stylebox_override("panel", _style_stack_slot_selectable())
		else:
			slot.add_theme_stylebox_override("panel", _style_stack_slot_locked())
			var lock_lbl := Label.new()
			lock_lbl.text = "LOCKED"
			lock_lbl.add_theme_font_size_override("font_size", 11)
			lock_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75, 0.9))
			lock_lbl.position = Vector2(8, 6)
			lock_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(lock_lbl)

		if pile_index >= 0:
			var p = pile[pile_index]
			if is_active:
				slot.gui_input.connect(func(ev): _on_pile_slot_input(ev, pile_index))

			var mini = max(18, int(cell_size * 0.82))
			var preview := _make_piece_preview(p, mini, Vector2(slot.size.x, slot.size.y))
			preview.position = Vector2((slot.size.x - preview.size.x) * 0.5, (slot.size.y - preview.size.y) * 0.5)
			slot.add_child(preview)
		else:
			var empty := Label.new()
			empty.text = "EMPTY"
			empty.add_theme_font_size_override("font_size", 16)
			empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			empty.position = Vector2(10, 18)
			empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(empty)

	# Draw falling piece only within fall zone
	if fall_piece != null and not is_game_over:
		var fall := _make_piece_preview(fall_piece, 20, Vector2(180, 90))
		var fx = (w - fall.size.x) * 0.5
		var fy = clamp(fall_y, fall_top, fall_bottom)
		fall.position = Vector2(fx, fy)
		fall.mouse_filter = Control.MOUSE_FILTER_STOP
		fall.gui_input.connect(func(ev): _on_falling_piece_input(ev))
		well_draw.add_child(fall)


func _on_pile_slot_input(event: InputEvent, pile_index: int) -> void:
	if is_game_over:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected_piece = pile[pile_index]
		selected_from_pile_index = pile_index
		_start_drag_selected()


func _on_falling_piece_input(event: InputEvent) -> void:
	if is_game_over:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected_piece = fall_piece
		selected_from_pile_index = -1
		_start_drag_selected()


# ============================================================
# Drag + place
# ============================================================
func _start_drag_selected() -> void:
	if selected_piece == null:
		return
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
		core.call("RegisterCancelledDrag")

	selected_piece = null
	selected_from_pile_index = -1


func _try_place_piece(piece, ax: int, ay: int) -> bool:
	if not bool(board.call("CanPlace", piece, ax, ay)):
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
	score += int(result.get("cleared_count", 0)) * 2

	# Remove from pile if it came from pile
	if selected_from_pile_index >= 0 and selected_from_pile_index < pile.size():
		pile.remove_at(selected_from_pile_index)
	else:
		# Falling piece is consumed only after successful placement.
		_spawn_falling_piece()

	var move_time_sec = max(0.05, float(Time.get_ticks_msec() - drag_start_ms) / 1000.0)
	core.call("RegisterSuccessfulPlacement", int(result.get("cleared_count", 0)), move_time_sec, _board_fill_ratio())

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

	_update_time()
	_update_difficulty()

	# Falling speed is driven by DifficultyDirector + level curve from Core.
	var fall_speed := float(core.call("GetFallSpeed", float(level)))
	speed_ui = fall_speed / 16.0
	lbl_speed.text = "Speed: %.2f" % speed_ui

	var geom = _well_geometry()
	var fall_bottom = float(geom["fall_bottom"])

	fall_y += fall_speed * delta
	if fall_y > fall_bottom:
		_lock_falling_to_pile()

	_redraw_well()

	# Drag: ghost always visible
	if dragging and selected_piece != null:
		var mouse := get_viewport().get_mouse_position()
		var cell := _mouse_to_board_cell(mouse)

		if cell.x == -1:
			drag_anchor = Vector2i(-999, -999)
			_clear_highlight()
			ghost_root.visible = true
			ghost_root.global_position = mouse - ghost_bbox_size * 0.5
		else:
			var top_left := board_panel.global_position + board_start + Vector2(cell.x * cell_size, cell.y * cell_size)
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


# ============================================================
# Highlight + ghost build
# ============================================================
func _clear_highlight() -> void:
	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			board_hl[y][x].color = Color(0, 0, 0, 0)


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
	if SkinManager != null:
		return SkinManager.get_piece_color(kind)
	return COLOR_FILLED


# ============================================================
# Styles
# ============================================================
func _style_cartridge_frame() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = SkinManager.get_color("cartridge_bg", Color(0.96, 0.86, 0.20)) if SkinManager != null else Color(0.96, 0.86, 0.20)
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
	s.bg_color = SkinManager.get_color("board_bg", Color(0.32, 0.16, 0.06)) if SkinManager != null else Color(0.32, 0.16, 0.06)
	s.border_width_left = 6
	s.border_width_right = 6
	s.border_width_top = 6
	s.border_width_bottom = 6
	s.border_color = Color(0.75, 0.45, 0.18)
	s.corner_radius_top_left = 10
	s.corner_radius_top_right = 10
	s.corner_radius_bottom_left = 10
	s.corner_radius_bottom_right = 10
	return s


func _style_hud_panel() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = SkinManager.get_color("hud_bg", Color(0.92, 0.92, 0.92)) if SkinManager != null else Color(0.92, 0.92, 0.92)
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
	s.bg_color = SkinManager.get_color("well_bg", Color(0.20, 0.20, 0.20)) if SkinManager != null else Color(0.20, 0.20, 0.20)
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
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.85, 0.85, 0.85)
	s.border_width_left = 3
	s.border_width_right = 3
	s.border_width_top = 3
	s.border_width_bottom = 3
	s.border_color = Color(0.20, 0.20, 0.20)
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.corner_radius_bottom_left = 8
	s.corner_radius_bottom_right = 8
	return s


func _style_cell_empty(x: int, y: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	var in_block_dark := ((x / 3) + (y / 3)) % 2 == 1
	s.bg_color = RETRO_GRID_DARK if in_block_dark else RETRO_GRID_BASE

	var thick_left := (x % 3 == 0)
	var thick_top := (y % 3 == 0)
	var thick_right := ((x + 1) % 3 == 0)
	var thick_bottom := ((y + 1) % 3 == 0)

	s.border_width_left = 3 if thick_left else 1
	s.border_width_top = 3 if thick_top else 1
	s.border_width_right = 3 if thick_right else 1
	s.border_width_bottom = 3 if thick_bottom else 1
	s.border_color = RETRO_GRID_BORDER
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
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.10, 0.10, 0.10)
	s.border_width_left = 2
	s.border_width_right = 2
	s.border_width_top = 2
	s.border_width_bottom = 2
	s.border_color = Color(0.25, 0.25, 0.25)
	s.corner_radius_top_left = 6
	s.corner_radius_top_right = 6
	s.corner_radius_bottom_left = 6
	s.corner_radius_bottom_right = 6
	return s


func _style_stack_slot_selectable() -> StyleBoxFlat:
	var s := _style_stack_slot()
	s.border_color = Color(0.92, 0.86, 0.25)
	s.bg_color = Color(0.16, 0.16, 0.18, 1.0)
	return s


func _style_stack_slot_locked() -> StyleBoxFlat:
	var s := _style_stack_slot()
	s.border_color = Color(0.34, 0.34, 0.34)
	s.bg_color = Color(0.06, 0.06, 0.07, 1.0)
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
