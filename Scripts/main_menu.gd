extends Control

const GAME_SCENE = "res://Scenes/Main.tscn"
const FORCE_DEBUG_PANEL = false
const MusicManagerScript = preload("res://Scripts/Audio/MusicManager.gd")
const MainMenuTopBar = preload("res://Scripts/Modules/UI/MainMenu/TopBar.gd")
const MainMenuPrimaryButtons = preload("res://Scripts/Modules/UI/MainMenu/PrimaryButtons.gd")
const MainMenuPopups = preload("res://Scripts/Modules/UI/MainMenu/Popups.gd")
const DialogFactory = preload("res://Scripts/Modules/UI/Common/DialogFactory.gd")
const DebugMenu = preload("res://Scripts/Modules/Debug/DebugMenu.gd")

const ICON_SETTINGS_TRES = "res://Assets/UI/icons/menu/icon_settings.tres"
const ICON_SHOP_TRES = "res://Assets/UI/icons/menu/icon_shop.tres"
const ICON_LEADERBOARD_TRES = "res://Assets/UI/icons/menu/icon_leaderboard.tres"
const ICON_QUESTS_TRES = "res://Assets/UI/icons/menu/icon_quests.tres"
const ICON_REWARDS_PNG = "res://Assets/UI/icons/menu/rewards.png"
const ICON_DEBUG_TRES = "res://Assets/UI/icons/menu/icon_debug.tres"
const ICON_CLOSE_TRES = "res://Assets/UI/icons/menu/icon_close.tres"
const ICON_BADGE_TRES = "res://Assets/UI/icons/menu/icon_badge.tres"

const SETTINGS_PATH = "user://settings.cfg"
const MUSIC_ATTENUATION_LINEAR = 0.05

const UI_ICON_MAX = 28
const UI_ICON_MAX_LARGE = 36

const UI_MARGIN = 16
const UI_GAP = 8
const TOPBAR_H = 140
const BOTTOMBAR_H = 140
const TOPBAR_SIDE_W = 280
const TOPBAR_BTN = 80
const TITLE_FONT = 68
const SUBTITLE_FONT = 23
const HERO_TITLE_HEIGHT = 140

const NAV_HEIGHT = BOTTOMBAR_H
const NAV_SIDE_MARGIN = UI_MARGIN
const NAV_SEPARATION = UI_GAP
const NAV_ICON_SIZE = 108

const PLAYCARD_MAX_W = 728
const PLAYCARD_INNER_PAD = 12
const PLAYCARD_FRAME_PAD_X = 65
const PLAYCARD_FRAME_PAD_Y = 40
const PLAYCARD_GAP = 2
const PLAYCARD_BUTTON_H = 78
const PLAYCARD_CHIP_H = 60

const TITLE_IMAGE_PATH = "res://Assets/UI/Title/Title_Tetris.png"
const MARBLE_BG_PATH = "res://Assets/UI/Background/marble/Marble.png"
const MARBLE_BG_DIR = "res://Assets/UI/Background/marble"
const NO_MERCY_SPARKS_PATH = "res://Assets/UI/Background/NoMercy/Sparks.png"
const MENU_EDGE_FRAME_SHADER_PATH = "res://Assets/Shaders/Menu/ui_difficulty_edge_frame.gdshader"
const NINEPATCH_BOTTOM_BAR_PATH = "res://Assets/UI/9patch/bottom_bar.png"
const NINEPATCH_BUTTON_PRIMARY_PATH = "res://Assets/UI/9patch/button_primary.png"
const NINEPATCH_BUTTON_SMALL_PATH = "res://Assets/UI/9patch/button_small.png"
const NINEPATCH_PANEL_DEFAULT_PATH = "res://Assets/UI/9patch/panel_default.png"
const NINEPATCH_TOP_CHIP_PATH = "res://Assets/UI/9patch/top_chip.png"
const XP_BAR_BG_PATH = "res://Assets/UI/9patch/xp_bar_bg.tres"
const XP_BAR_FILL_PATH = "res://Assets/UI/9patch/xp_bar_fill.tres"

var music_manager: MusicManager = null
var sfx_players = {}
var missing_sfx_warned = {}
var music_enabled: bool = true
var sfx_enabled: bool = true
var music_volume: float = 0.5
var sfx_volume: float = 1.0

var root_layer: Control
var background_layer: Control
var content_layer: Control
var bottom_nav_layer: Control
var modal_layer: Control

var safe_top: float = 0.0
var safe_bottom: float = 0.0
var safe_left: float = 0.0
var safe_right: float = 0.0

var difficulty_chip_label: Label
var level_chip_label: Label
var level_chip_progress: ProgressBar
var hero_title_zone: Control
var hero_title_label: Label
var hero_title_texture: TextureRect
var hero_subtitle_label: Label
var mode_description_label: Label
var no_mercy_panel: Panel
var no_mercy_toggle: CheckBox
var no_mercy_help: Label
var difficulty_chip_buttons: Dictionary = {}
var difficulty_glow: ColorRect
var no_mercy_edge_sparks_holder: Node2D
var no_mercy_sparks_pollen: GPUParticles2D
var menu_palette_cache: Dictionary = {}
var _marble_bg_chosen_path: String = ""
var _marble_bg_texture: Texture2D = null
var _marble_bg_initialized: bool = false
var _no_mercy_sparks_missing_logged: bool = false
var _play_idle_tween: Tween = null
var current_nav: String = ""
var nav_buttons: Dictionary = {}

var rewards_panel: Panel
var rewards_level_label: Label
var rewards_status_labels: Dictionary = {}

var settings_panel: Control
var leaderboard_panel: Panel
var quests_panel: Panel
var shop_panel: Panel
var debug_panel: Panel
var popup_overlay: ColorRect

var debug_body: VBoxContainer
var lbl_cloud_status: Label
var chk_admin_mode_no_ads: CheckBox


func _ready() -> void:
	if music_manager == null:
		music_manager = MusicManagerScript.new()
		add_child(music_manager)
	_load_audio_settings()
	_apply_audio_settings()
	music_manager.play_menu_music()
	_audio_setup()
	_build_ui()
	_refresh_all_ui()
	_update_menu_fx()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_safe_area()
		_sync_particles_to_viewport()



func _load_audio_settings() -> void:
	var cfg = ConfigFile.new()
	var err = cfg.load(SETTINGS_PATH)
	if err != OK:
		return
	music_enabled = bool(cfg.get_value("audio", "music_enabled", true))
	sfx_enabled = bool(cfg.get_value("audio", "sfx_enabled", true))
	music_volume = clamp(float(cfg.get_value("audio", "music_volume", 0.5)), 0.0, 1.0)
	sfx_volume = clamp(float(cfg.get_value("audio", "sfx_volume", 1.0)), 0.0, 1.0)


func _save_audio_settings() -> void:
	var cfg = ConfigFile.new()
	cfg.set_value("audio", "music_enabled", music_enabled)
	cfg.set_value("audio", "sfx_enabled", sfx_enabled)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.save(SETTINGS_PATH)


func _get_audio_manager() -> Node:
	var manager = get_node_or_null("/root/AudioManager")
	if manager == null:
		var audio_manager_script = load("res://Scripts/Modules/Audio/AudioManager.gd")
		if audio_manager_script != null:
			manager = audio_manager_script.new()
			manager.name = "AudioManager"
			get_tree().root.add_child(manager)
	return manager


func _apply_audio_settings() -> void:
	var effective_music_volume = clamp(music_volume * MUSIC_ATTENUATION_LINEAR, 0.0, 1.0)
	var audio_manager = _get_audio_manager()
	if audio_manager != null:
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

func _audio_setup() -> void:
	_ensure_sfx("ui_hover", "res://Assets/Audio/ui_hover.wav", -12.0)
	_ensure_sfx("ui_click", "res://Assets/Audio/ui_click.wav", -10.0)


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


func _build_ui() -> void:
	for ch in get_children():
		if ch is AudioStreamPlayer or ch == music_manager:
			continue
		ch.queue_free()

	root_layer = Control.new()
	root_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var skin_manager = _skin_manager()
	if skin_manager != null and skin_manager.get_theme() != null:
		root_layer.theme = skin_manager.get_theme()
	add_child(root_layer)

	background_layer = Control.new()
	background_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_layer.add_child(background_layer)
	_build_background_layer()

	content_layer = Control.new()
	content_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_layer.add_child(content_layer)

	bottom_nav_layer = Control.new()
	bottom_nav_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bottom_nav_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_layer.add_child(bottom_nav_layer)

	modal_layer = Control.new()
	modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_layer.add_child(modal_layer)

	_build_top_bar()
	_build_hero_title()
	_build_play_card()
	_build_bottom_nav()
	_build_modal_layer()
	_apply_safe_area()


func _build_background_layer() -> void:
	var bg_base = ColorRect.new()
	bg_base.name = "bg_base"
	bg_base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_base.color = Color(0.96, 0.95, 0.93, 1.0)
	bg_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background_layer.add_child(bg_base)

	var bg_marble = TextureRect.new()
	bg_marble.name = "bg_marble"
	bg_marble.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_marble.stretch_mode = TextureRect.STRETCH_SCALE
	bg_marble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(MARBLE_BG_PATH):
		var t = load(MARBLE_BG_PATH)
		if t is Texture2D:
			bg_marble.texture = t
			bg_marble.visible = true
	if bg_marble.texture == null:
		var marble_dir = DirAccess.open(MARBLE_BG_DIR)
		if marble_dir == null:
			bg_marble.visible = false
			push_error("[MainMenu] Marble dir open failed: " + MARBLE_BG_DIR)
			background_layer.add_child(bg_marble)
			return
		for file_name in marble_dir.get_files():
			var lowered = file_name.to_lower()
			if lowered.ends_with(".import"):
				continue
			if not (lowered.ends_with(".png") or lowered.ends_with(".webp") or lowered.ends_with(".jpg")):
				continue
			var marble_path = MARBLE_BG_DIR + "/" + file_name
			if not ResourceLoader.exists(marble_path):
				continue
			var marble_texture = load(marble_path)
			if marble_texture is Texture2D:
				bg_marble.texture = marble_texture
				bg_marble.visible = true
				break
	if bg_marble.texture == null:
		bg_marble.visible = false
		push_error("[MainMenu] Marble background not found in: " + MARBLE_BG_DIR)
	background_layer.add_child(bg_marble)

	var particles_holder = Control.new()
	particles_holder.name = "FallingBlocksHolder"
	particles_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	particles_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background_layer.add_child(particles_holder)

	var spawner_script = preload("res://Scripts/Modules/UI/MainMenu/FallingBlocksSpawner.gd")
	var spawner = spawner_script.new()
	spawner.name = "FallingBlocksSpawner"
	particles_holder.add_child(spawner)

	_ensure_ui_vignette()

	difficulty_glow = ColorRect.new()
	difficulty_glow.name = "difficulty_edge_frame"
	difficulty_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	difficulty_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var edge_shader_material = _build_edge_frame_shader_material()
	if edge_shader_material != null:
		difficulty_glow.material = edge_shader_material
	background_layer.add_child(difficulty_glow)

	no_mercy_edge_sparks_holder = Node2D.new()
	no_mercy_edge_sparks_holder.name = "no_mercy_edge_sparks_holder"
	background_layer.add_child(no_mercy_edge_sparks_holder)

	no_mercy_sparks_pollen = _create_no_mercy_pollen_sparks("NoMercySparks_Pollen")
	if no_mercy_sparks_pollen != null:
		no_mercy_edge_sparks_holder.add_child(no_mercy_sparks_pollen)

	_sync_particles_to_viewport()


func _build_edge_frame_shader_material() -> ShaderMaterial:
	if not ResourceLoader.exists(MENU_EDGE_FRAME_SHADER_PATH):
		return null
	var shader = load(MENU_EDGE_FRAME_SHADER_PATH)
	if not (shader is Shader):
		return null

	var mat = ShaderMaterial.new()
	mat.shader = shader

	# Default "thin glass glow" settings (can be overridden later)
	mat.set_shader_parameter("edge_width", 0.075)
	mat.set_shader_parameter("softness", 0.50)
	mat.set_shader_parameter("intensity", 0.26)
	mat.set_shader_parameter("core_boost", 1.55)
	mat.set_shader_parameter("core_power", 2.8)
	mat.set_shader_parameter("halo_boost", 0.95)
	mat.set_shader_parameter("halo_width_mul", 2.8)
	mat.set_shader_parameter("halo_power", 1.15)

	return mat


func _create_no_mercy_pollen_sparks(node_name: String) -> GPUParticles2D:
	if not ResourceLoader.exists(NO_MERCY_SPARKS_PATH):
		if not _no_mercy_sparks_missing_logged:
			_no_mercy_sparks_missing_logged = true
			push_error("[MainMenu] Missing No Mercy sparks texture: " + NO_MERCY_SPARKS_PATH)
		return null
	var spark_texture = load(NO_MERCY_SPARKS_PATH)
	if not (spark_texture is Texture2D):
		if not _no_mercy_sparks_missing_logged:
			_no_mercy_sparks_missing_logged = true
			push_error("[MainMenu] Invalid No Mercy sparks texture: " + NO_MERCY_SPARKS_PATH)
		return null
	var particles = GPUParticles2D.new()
	particles.name = node_name
	particles.texture = spark_texture
	particles.amount = 160
	particles.lifetime = 3.0
	particles.one_shot = false
	particles.explosiveness = 0.0
	particles.randomness = 0.35
	particles.emitting = false
	particles.visible = false
	particles.modulate = Color(1, 1, 1, 0.3)

	var process_material = ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.direction = Vector3(0.0, 1.0, 0.0)
	process_material.spread = 25.0
	process_material.initial_velocity_min = 8.0
	process_material.initial_velocity_max = 28.0
	process_material.gravity = Vector3(0.0, 2.0, 0.0)
	process_material.scale_min = 0.18
	process_material.scale_max = 0.45
	process_material.angular_velocity_min = -1.2
	process_material.angular_velocity_max = 1.2
	particles.process_material = process_material
	var spark_canvas_material = CanvasItemMaterial.new()
	spark_canvas_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	particles.material = spark_canvas_material
	return particles


func _sync_particles_to_viewport() -> void:
	var viewport_size = get_viewport_rect().size
	if no_mercy_sparks_pollen != null:
		no_mercy_sparks_pollen.position = viewport_size * 0.5
		if no_mercy_sparks_pollen.process_material is ParticleProcessMaterial:
			var pollen_material = no_mercy_sparks_pollen.process_material as ParticleProcessMaterial
			pollen_material.emission_box_extents = Vector3(viewport_size.x * 0.5, viewport_size.y * 0.5, 0.0)

func _build_top_bar() -> void:
	var top = Control.new()
	top.name = "TopBar"
	top.anchor_left = 0.0
	top.anchor_top = 0.0
	top.anchor_right = 1.0
	top.anchor_bottom = 0.0
	top.offset_top = 0
	top.offset_bottom = TOPBAR_H
	content_layer.add_child(top)

	var row = HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(row)

	var left_slot = Control.new()
	left_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_slot.custom_minimum_size = Vector2(TOPBAR_SIDE_W, TOPBAR_H)
	row.add_child(left_slot)

	var center_slot = Control.new()
	center_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_slot.custom_minimum_size = Vector2(0, TOPBAR_H)
	row.add_child(center_slot)

	var right_slot = Control.new()
	right_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_slot.custom_minimum_size = Vector2(TOPBAR_SIDE_W, TOPBAR_H)
	row.add_child(right_slot)

	var level_chip = Button.new()
	level_chip.text = ""
	level_chip.custom_minimum_size = Vector2(int(TOPBAR_SIDE_W * 0.9), int(TOPBAR_H * 0.9))
	level_chip.anchor_left = 0.0
	level_chip.anchor_top = 0.0
	level_chip.anchor_right = 0.0
	level_chip.anchor_bottom = 1.0
	level_chip.offset_left = 0
	level_chip.offset_right = TOPBAR_SIDE_W
	level_chip.mouse_entered.connect(func(): _play_sfx("ui_hover"))
	level_chip.pressed.connect(func(): _play_sfx("ui_click"))
	level_chip.pressed.connect(func(): _open_panel(rewards_panel))
	left_slot.add_child(level_chip)
	_apply_top_chip_style(level_chip)

	var chip_margin = MarginContainer.new()
	chip_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chip_margin.add_theme_constant_override("margin_left", 10)
	chip_margin.add_theme_constant_override("margin_right", 10)
	chip_margin.add_theme_constant_override("margin_top", 6)
	chip_margin.add_theme_constant_override("margin_bottom", 6)
	level_chip.add_child(chip_margin)

		# Replace the old chip_col layout with a 2-column layout: 40% badge / 60% info.
	var cols = HBoxContainer.new()
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 4)
	chip_margin.add_child(cols)

	# --- Left column (badge) 40% ---
	var left_col = Control.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.size_flags_stretch_ratio = 0.40
	cols.add_child(left_col)

	var badge_icon = TextureRect.new()
	badge_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH
	badge_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge_icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	badge_icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	badge_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var badge_tex = _load_icon(ICON_BADGE_TRES)
	if badge_tex != null:
		badge_icon.texture = badge_tex
	left_col.add_child(badge_icon)

	# --- Right column (Level + XP + Rank) 60% ---
	var right_col = VBoxContainer.new()
	var top_spacer = Control.new()
	top_spacer.custom_minimum_size = Vector2(0, 22)
	right_col.add_child(top_spacer)
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.size_flags_stretch_ratio = 0.60
	right_col.add_theme_constant_override("separation", 1)
	cols.add_child(right_col)

	# Row 1: Level (centered)
	level_chip_label = Label.new()
	level_chip_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_chip_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	level_chip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_chip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level_chip_label.add_theme_font_size_override("font_size", 14)
	level_chip_label.clip_text = true
	level_chip_label.add_theme_color_override("font_color", Color(0.22, 0.16, 0.10, 1.0))
	right_col.add_child(level_chip_label)

	# Shared horizontal padding for XP + RANK so they align perfectly
	var bar_pad_l = 15
	var bar_pad_r = 15

	# Row 2: XP bar (shorter, never touches edges)
	var xp_margin = MarginContainer.new()
	xp_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_margin.add_theme_constant_override("margin_left", bar_pad_l)
	xp_margin.add_theme_constant_override("margin_right", bar_pad_r)
	right_col.add_child(xp_margin)

	level_chip_progress = ProgressBar.new()
	level_chip_progress.min_value = 0.0
	level_chip_progress.max_value = 1.0
	level_chip_progress.value = 0.35
	level_chip_progress.show_percentage = false
	level_chip_progress.custom_minimum_size = Vector2(0, 12) # thickness; try 12-14
	level_chip_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_chip_progress.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if ResourceLoader.exists(XP_BAR_BG_PATH):
		var xp_bg = load(XP_BAR_BG_PATH)
		if xp_bg is StyleBox:
			level_chip_progress.add_theme_stylebox_override("background", xp_bg)
	if ResourceLoader.exists(XP_BAR_FILL_PATH):
		var xp_fill = load(XP_BAR_FILL_PATH)
		if xp_fill is StyleBox:
			level_chip_progress.add_theme_stylebox_override("fill", xp_fill)
	xp_margin.add_child(level_chip_progress)

	# Row 3: RANK (centered to the same width as XP bar)
	var rank_margin = MarginContainer.new()
	rank_margin.add_theme_constant_override("margin_bottom", 25) 
	rank_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rank_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rank_margin.add_theme_constant_override("margin_left", bar_pad_l)
	rank_margin.add_theme_constant_override("margin_right", bar_pad_r)
	right_col.add_child(rank_margin)

	var rank_center = CenterContainer.new()
	rank_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rank_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rank_margin.add_child(rank_center)

	var rank_label = Label.new()
	rank_label.text = "RANK"
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rank_label.add_theme_font_size_override("font_size", 16)
	rank_label.add_theme_color_override("font_color", Color(0.22, 0.16, 0.10, 1.0))
	rank_center.add_child(rank_label)


	var center_spacer = Control.new()
	center_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_spacer.custom_minimum_size = Vector2(0, TOPBAR_H)
	center_slot.add_child(center_spacer)

	var right_center = CenterContainer.new()
	right_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	right_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_slot.add_child(right_center)

	var right_row = HBoxContainer.new()
	right_row.alignment = BoxContainer.ALIGNMENT_END
	right_row.add_theme_constant_override("separation", 8)
	right_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_center.add_child(right_row)

	if _is_debug_panel_visible():
		var btn_debug = Button.new()
		btn_debug.custom_minimum_size = Vector2(TOPBAR_BTN, TOPBAR_BTN)
		btn_debug.expand_icon = true
		btn_debug.add_theme_constant_override("icon_max_width", TOPBAR_BTN - 12)
		_apply_top_icon_button_style(btn_debug)
		_set_button_icon(btn_debug, ICON_DEBUG_TRES, "🧪", "Debug", TOPBAR_BTN - 12)
		btn_debug.mouse_entered.connect(func(): _play_sfx("ui_hover"))
		btn_debug.pressed.connect(func(): _play_sfx("ui_click"))
		btn_debug.pressed.connect(func(): _open_panel(debug_panel))
		right_row.add_child(btn_debug)

	var btn_settings = Button.new()
	btn_settings.custom_minimum_size = Vector2(TOPBAR_BTN, TOPBAR_BTN)
	_apply_top_icon_button_style(btn_settings)
	_set_button_icon(btn_settings, ICON_SETTINGS_TRES, "⚙", "Settings", TOPBAR_BTN - 12)
	btn_settings.expand_icon = true
	btn_settings.add_theme_constant_override("icon_max_width", TOPBAR_BTN - 12)
	btn_settings.mouse_entered.connect(func(): _play_sfx("ui_hover"))
	btn_settings.pressed.connect(func(): _play_sfx("ui_click"))
	btn_settings.pressed.connect(func(): _open_panel(settings_panel))
	right_row.add_child(btn_settings)


func _build_play_card() -> void:
	var card = Panel.new()
	card.name = "PlayCard"
	card.anchor_left = 0.5
	card.anchor_top = 0.0
	card.anchor_right = 0.5
	card.anchor_bottom = 0.0
	card.custom_minimum_size = Vector2(PLAYCARD_MAX_W, 0)
	content_layer.add_child(card)
	_apply_panel_style(card)

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", PLAYCARD_INNER_PAD)
	margin.add_theme_constant_override("margin_right", PLAYCARD_INNER_PAD)
	margin.add_theme_constant_override("margin_top", PLAYCARD_INNER_PAD - 10)
	margin.add_theme_constant_override("margin_bottom", PLAYCARD_INNER_PAD)
	card.add_child(margin)

	var inner = MarginContainer.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.add_theme_constant_override("margin_left", PLAYCARD_FRAME_PAD_X)
	inner.add_theme_constant_override("margin_right", PLAYCARD_FRAME_PAD_X)
	inner.add_theme_constant_override("margin_top", PLAYCARD_FRAME_PAD_Y)
	inner.add_theme_constant_override("margin_bottom", PLAYCARD_FRAME_PAD_Y)
	margin.add_child(inner)

	var v = VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", PLAYCARD_GAP)
	inner.add_child(v)


	var play_wrap = CenterContainer.new()
	play_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(play_wrap)

	var play_button = Button.new()
	play_button.text = ""  # texture already has PLAY
	play_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	play_button.custom_minimum_size = Vector2(560, PLAYCARD_BUTTON_H + 45)
	play_button.clip_text = true
	play_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	play_button.mouse_entered.connect(func(): _play_sfx("ui_hover"))
	play_button.pressed.connect(func(): _play_sfx("ui_click"))
	play_button.pressed.connect(_on_start)
	play_wrap.add_child(play_button)
	_apply_button_style(play_button, "primary")
	_start_play_idle_animation(play_button)

	var after_play_spacer = Control.new()
	after_play_spacer.custom_minimum_size = Vector2(0, 4)
	v.add_child(after_play_spacer)

	var difficulty_title = Label.new()
	difficulty_title.text = "Select Difficulty"
	difficulty_title.add_theme_font_size_override("font_size", 24)
	_apply_label_readability(difficulty_title, "strong")
	v.add_child(difficulty_title)

	var chips = HBoxContainer.new()
	chips.add_theme_constant_override("separation", PLAYCARD_GAP)
	v.add_child(chips)
	for diff in ["Easy", "Medium", "Hard"]:
		var chip = Button.new()
		chip.text = diff
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.custom_minimum_size = Vector2(0, PLAYCARD_CHIP_H)
		chip.add_theme_font_size_override("font_size", 24)
		chip.mouse_entered.connect(func(): _play_sfx("ui_hover"))
		chip.pressed.connect(func(): _play_sfx("ui_click"))
		chip.pressed.connect(func(): _apply_difficulty_selection(diff))
		chips.add_child(chip)
		_apply_button_style(chip, "small")
		difficulty_chip_buttons[diff] = chip

	no_mercy_panel = Panel.new()
	no_mercy_panel.custom_minimum_size = Vector2(0, PLAYCARD_CHIP_H)
	no_mercy_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	no_mercy_panel.focus_mode = Control.FOCUS_NONE
	no_mercy_panel.mouse_entered.connect(func(): _play_sfx("ui_hover"))
	v.add_child(no_mercy_panel)

	var no_mercy_margin = MarginContainer.new()
	no_mercy_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	no_mercy_margin.add_theme_constant_override("margin_left", 18)
	no_mercy_margin.add_theme_constant_override("margin_right", 18)
	no_mercy_margin.add_theme_constant_override("margin_top", 10)
	no_mercy_margin.add_theme_constant_override("margin_bottom", 10)
	no_mercy_panel.add_child(no_mercy_margin)

	var no_mercy_row = HBoxContainer.new()
	no_mercy_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no_mercy_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	no_mercy_row.add_theme_constant_override("separation", 10)
	no_mercy_margin.add_child(no_mercy_row)

	var no_mercy_label = Label.new()
	no_mercy_label.text = "No Mercy"
	no_mercy_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	no_mercy_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	no_mercy_label.add_theme_font_size_override("font_size", 22)
	no_mercy_row.add_child(no_mercy_label)

	var no_mercy_spacer = Control.new()
	no_mercy_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no_mercy_row.add_child(no_mercy_spacer)

	no_mercy_toggle = CheckBox.new()
	no_mercy_toggle.button_pressed = Save.get_no_mercy()
	no_mercy_toggle.text = ""
	no_mercy_toggle.focus_mode = Control.FOCUS_NONE
	no_mercy_toggle.mouse_entered.connect(func(): _play_sfx("ui_hover"))
	no_mercy_toggle.pressed.connect(func(): _play_sfx("ui_click"))
	no_mercy_toggle.toggled.connect(_on_no_mercy_toggled)
	no_mercy_row.add_child(no_mercy_toggle)

	no_mercy_panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton:
			var mouse_event := event as InputEventMouseButton
			if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
				if no_mercy_toggle.get_global_rect().has_point(get_global_mouse_position()):
					return
				_play_sfx("ui_click")
				no_mercy_toggle.button_pressed = not no_mercy_toggle.button_pressed
	)
	_apply_no_mercy_checkbox_style(no_mercy_toggle, no_mercy_panel, no_mercy_label)
	_apply_label_readability(no_mercy_label, "normal")

	no_mercy_help = Label.new()
	no_mercy_help.text = " No Mercy removes reserve slots."
	no_mercy_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	no_mercy_help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no_mercy_help.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	no_mercy_help.custom_minimum_size = Vector2(0, 28)
	no_mercy_help.add_theme_font_size_override("font_size", 22)
	_apply_label_readability(no_mercy_help, "normal")
	v.add_child(no_mercy_help)

	mode_description_label = Label.new()
	mode_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_description_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_description_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mode_description_label.custom_minimum_size = Vector2(0, 34)
	mode_description_label.add_theme_font_size_override("font_size", 22)
	_apply_label_readability(mode_description_label, "muted")
	v.add_child(mode_description_label)

func _build_hero_title() -> void:
	hero_title_zone = Control.new()
	hero_title_zone.name = "HeroTitle"
	hero_title_zone.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hero_title_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_title_zone.offset_top = TOPBAR_H + 32
	hero_title_zone.offset_bottom = TOPBAR_H + 32 + HERO_TITLE_HEIGHT
	content_layer.add_child(hero_title_zone)

	var center_container = CenterContainer.new()
	center_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_title_zone.add_child(center_container)

	var center = VBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", UI_GAP)
	center_container.add_child(center)

	hero_title_label = null

	hero_title_texture = TextureRect.new()
	hero_title_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_title_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hero_title_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hero_title_texture.custom_minimum_size = Vector2(int(round(560.0 * 1.8)), int(round((HERO_TITLE_HEIGHT) * 1.8)))
	hero_title_texture.visible = false
	center.add_child(hero_title_texture)

	var has_title_image = false
	if ResourceLoader.exists(TITLE_IMAGE_PATH):
		var title_texture = load(TITLE_IMAGE_PATH)
		if title_texture is Texture2D:
			hero_title_texture.texture = title_texture
			hero_title_texture.visible = true
			has_title_image = true

	if not has_title_image:
		hero_title_label = Label.new()
		hero_title_label.text = "BLOCK PUZZLE"
		hero_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hero_title_label.add_theme_font_size_override("font_size", TITLE_FONT)
		hero_title_label.modulate = _palette_color("text_primary", Color(0.96, 0.96, 1.0, 1.0))
		hero_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(hero_title_label)

	var subtitle = Label.new()
	subtitle.text = "Classic block strategy"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var subtitle_label_settings = LabelSettings.new()
	subtitle_label_settings.font_size = SUBTITLE_FONT
	subtitle.label_settings = subtitle_label_settings
	subtitle.modulate = Color(0.9, 0.9, 0.95, 0.75)
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle.visible = not has_title_image
	center.add_child(subtitle)
	hero_subtitle_label = subtitle


func _build_bottom_nav() -> void:
	nav_buttons.clear()
	var bottom_bar = Control.new()
	bottom_bar.name = "BottomBar"
	bottom_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_bar.offset_left = UI_MARGIN + safe_left
	bottom_bar.offset_right = -UI_MARGIN - safe_right
	bottom_bar.offset_bottom = 0
	bottom_bar.offset_top = -BOTTOMBAR_H
	bottom_nav_layer.add_child(bottom_bar)

	var background_panel = Panel.new()
	background_panel.name = "BackgroundPanel"
	background_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bar_style = _stylebox_9slice(NINEPATCH_BOTTOM_BAR_PATH)
	if bar_style != null:
		background_panel.add_theme_stylebox_override("panel", bar_style)
	else:
		background_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	bottom_bar.add_child(background_panel)

	var safe_margin = MarginContainer.new()
	safe_margin.name = "SafeMargin"
	safe_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background_panel.add_child(safe_margin)

	var nav_row = HBoxContainer.new()
	nav_row.name = "NavRow"
	nav_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav_row.add_theme_constant_override("separation", NAV_SEPARATION)
	safe_margin.add_child(nav_row)

	_add_nav_button(nav_row, "Shop", ICON_SHOP_TRES, "🛍", func(): _open_panel(shop_panel))
	_add_nav_button(nav_row, "Rewards", ICON_REWARDS_PNG, "🎁", func(): _open_panel(rewards_panel))
	_add_nav_button(nav_row, "Leaderboard", ICON_LEADERBOARD_TRES, "🏆", func(): _open_panel(leaderboard_panel))
	_add_nav_button(nav_row, "Quests", ICON_QUESTS_TRES, "📜", func(): _open_panel(quests_panel))
	if current_nav == "":
		_set_active_nav("Shop")
	else:
		_set_active_nav(current_nav)


func _add_nav_button(parent: HBoxContainer, label_text: String, icon_path: String, fallback_glyph: String, callback: Callable) -> void:
	var b = Button.new()
	b.custom_minimum_size = Vector2(0, NAV_HEIGHT)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_FILL
	b.size_flags_stretch_ratio = 1.0
	b.expand_icon = true
	b.add_theme_constant_override("icon_max_width", NAV_ICON_SIZE)
	b.add_theme_constant_override("h_separation", 0)
	b.add_theme_constant_override("icon_margin", 0)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.text = ""
	b.tooltip_text = label_text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_apply_button_style(b, "small")
	var active_underline = ColorRect.new()
	active_underline.name = "ActiveUnderline"
	active_underline.anchor_left = 0.2
	active_underline.anchor_right = 0.8
	active_underline.anchor_top = 1.0
	active_underline.anchor_bottom = 1.0
	active_underline.offset_top = -8
	active_underline.offset_bottom = -3
	active_underline.color = Color(1.0, 0.88, 0.50, 0.88)
	active_underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	active_underline.visible = false
	b.add_child(active_underline)
	if icon_path != "":
		var tex = _load_icon_any(icon_path)
		if tex != null:
			b.icon = tex
	if b.icon == null:
		var fallback = Label.new()
		fallback.text = fallback_glyph
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.add_theme_font_size_override("font_size", 48)
		fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(fallback)
	b.mouse_entered.connect(func(): _play_sfx("ui_hover"))
	b.pressed.connect(func(): _play_sfx("ui_click"))
	b.pressed.connect(func(): _set_active_nav(label_text))
	b.pressed.connect(callback)
	parent.add_child(b)
	nav_buttons[label_text] = b


func _build_modal_layer() -> void:
	popup_overlay = ColorRect.new()
	popup_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup_overlay.color = Color(0, 0, 0, 0.52)
	popup_overlay.visible = false
	popup_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup_overlay.gui_input.connect(func(event):
		if OS.is_debug_build() and popup_overlay.visible:
			print("[MainMenu] popup_overlay received input: %s" % [event])
		if event is InputEventMouseButton and event.pressed:
			_close_all_panels()
	)
	modal_layer.add_child(popup_overlay)

	rewards_panel = _create_modal_panel("Rewards")
	leaderboard_panel = _create_modal_panel("Leaderboard")
	quests_panel = _create_modal_panel("Quests")
	shop_panel = _create_modal_panel("Shop")
	debug_panel = _create_modal_panel("Debug")

	settings_panel = _create_modal_panel("Audio Settings")

	_build_rewards_content(rewards_panel)
	_build_leaderboard_content(leaderboard_panel)
	_build_quests_content(quests_panel)
	_build_shop_content(shop_panel)
	_build_debug_content(debug_panel)
	_build_settings_content(settings_panel)


func _create_modal_panel(title_text: String) -> Panel:
	var panel = Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	var vp = get_viewport_rect().size
	var max_w = min(920.0, vp.x - (safe_left + safe_right + 32.0))
	var max_h = min(980.0, vp.y - (safe_top + safe_bottom + 32.0))
	max_w = max(max_w, 320.0)
	max_h = max(max_h, 320.0)
	panel.offset_left = -max_w * 0.5
	panel.offset_top = -max_h * 0.5
	panel.offset_right = max_w * 0.5
	panel.offset_bottom = max_h * 0.5
	panel.visible = false
	modal_layer.add_child(panel)
	_apply_panel_style(panel)
	panel.set_meta("title_text", title_text)

	var content = _ensure_panel_content(panel)
	if content == null:
		push_error("Menu panel content is null: " + panel.name)

	return panel


func _ensure_panel_content(panel: Panel) -> VBoxContainer:
	if panel == null:
		return null

	for child in panel.get_children():
		child.queue_free()

	var margin = MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var body = VBoxContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	margin.add_child(body)

	var header = HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 10)
	body.add_child(header)

	var title = Label.new()
	title.text = String(panel.get_meta("title_text", ""))
	title.add_theme_font_size_override("font_size", 30)
	title.modulate = _palette_color("text_primary", Color(0.96, 0.96, 1.0, 1.0))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn = Button.new()
	_set_button_icon(close_btn, ICON_CLOSE_TRES, "✕", "Close")
	close_btn.custom_minimum_size = Vector2(56, 48)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	close_btn.mouse_entered.connect(func(): _play_sfx("ui_hover"))
	close_btn.pressed.connect(func(): _play_sfx("ui_click"))
	close_btn.pressed.connect(func(): _close_all_panels())
	header.add_child(close_btn)

	var scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)

	var content = VBoxContainer.new()
	content.name = "Content"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	return content


func _build_rewards_content(panel: Panel) -> void:
	var content = _ensure_panel_content(panel)
	if content == null:
		push_error("Menu panel content is null: " + panel.name)
		return
	rewards_level_label = Label.new()
	content.add_child(rewards_level_label)
	for m in [5, 10, 20, 50]:
		var line = Label.new()
		content.add_child(line)
		rewards_status_labels[m] = line


func _build_leaderboard_content(panel: Panel) -> void:
	var content = _ensure_panel_content(panel)
	if content == null:
		push_error("Menu panel content is null: " + panel.name)
		return
	var chips = HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	content.add_child(chips)
	for pair in [["Easy", "easy"], ["Medium", "medium"], ["Hard", "hard"], ["Hard+NoMercy", "hard_plus_no_mercy"]]:
		var tab = Button.new()
		tab.text = pair[0]
		tab.custom_minimum_size = Vector2(0, 48)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.mouse_entered.connect(func(): _play_sfx("ui_hover"))
		tab.pressed.connect(func(): _play_sfx("ui_click"))
		tab.pressed.connect(func(): _on_select_leaderboard(pair[1]))
		chips.add_child(tab)

	var msg = Label.new()
	msg.text = "Rank  Name        Score\n1     ---         ---\n2     ---         ---\n3     ---         ---"
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(msg)

	var sign_in = Button.new()
	sign_in.text = "Play Games: Sign In"
	sign_in.custom_minimum_size = Vector2(0, 52)
	sign_in.mouse_entered.connect(func(): _play_sfx("ui_hover"))
	sign_in.pressed.connect(func(): _play_sfx("ui_click"))
	sign_in.pressed.connect(_on_play_games_sign_in)
	content.add_child(sign_in)


func _build_quests_content(panel: Panel) -> void:
	var content = _ensure_panel_content(panel)
	if content == null:
		push_error("Menu panel content is null: " + panel.name)
		return
	for quest_name in ["Clear 2 lines", "Place 15 blocks", "Finish 1 run"]:
		var wrap = VBoxContainer.new()
		content.add_child(wrap)
		var q = Label.new()
		q.text = quest_name
		wrap.add_child(q)
		var p = ProgressBar.new()
		p.max_value = 100
		p.value = 35
		p.custom_minimum_size = Vector2(0, 24)
		wrap.add_child(p)
		var state = Label.new()
		state.text = "In progress"
		state.modulate = Color(0.8, 0.9, 1.0, 0.9)
		wrap.add_child(state)


func _build_shop_content(panel: Panel) -> void:
	var content = _ensure_panel_content(panel)
	if content == null:
		push_error("Menu panel content is null: " + panel.name)
		return
	for item_name in ["Remove Ads", "Sudoku Pack", "Rome Pack"]:
		var card = Panel.new()
		card.custom_minimum_size = Vector2(0, 96)
		content.add_child(card)
		_apply_panel_style(card)
		var label = Label.new()
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.offset_left = 12
		label.offset_top = 12
		label.text = "%s\nComing soon" % item_name
		card.add_child(label)


func _build_settings_content(panel: Panel) -> void:
	var content = _ensure_panel_content(panel)
	if content == null:
		push_error("Menu panel content is null: " + panel.name)
		return

	var music_toggle = CheckBox.new()
	music_toggle.text = "Music"
	music_toggle.button_pressed = music_enabled
	music_toggle.toggled.connect(_on_music_enabled_toggled)
	content.add_child(music_toggle)

	var music_slider_label = Label.new()
	music_slider_label.text = "Music Volume"
	content.add_child(music_slider_label)

	var music_slider = HSlider.new()
	music_slider.min_value = 0
	music_slider.max_value = 100
	music_slider.step = 1
	music_slider.value = music_volume * 100.0
	music_slider.value_changed.connect(_on_music_volume_changed)
	content.add_child(music_slider)

	var sfx_toggle = CheckBox.new()
	sfx_toggle.text = "SFX"
	sfx_toggle.button_pressed = sfx_enabled
	sfx_toggle.toggled.connect(_on_sfx_enabled_toggled)
	content.add_child(sfx_toggle)

	var sfx_slider_label = Label.new()
	sfx_slider_label.text = "SFX Volume"
	content.add_child(sfx_slider_label)

	var sfx_slider = HSlider.new()
	sfx_slider.min_value = 0
	sfx_slider.max_value = 100
	sfx_slider.step = 1
	sfx_slider.value = sfx_volume * 100.0
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	content.add_child(sfx_slider)


func _build_debug_content(panel: Panel) -> void:
	var content = _ensure_panel_content(panel)
	if content == null:
		push_error("Menu panel content is null: " + panel.name)
		return
	lbl_cloud_status = Label.new()
	content.add_child(lbl_cloud_status)

	chk_admin_mode_no_ads = CheckBox.new()
	chk_admin_mode_no_ads.text = "Admin Mode (No Ads)"
	chk_admin_mode_no_ads.button_pressed = OS.is_debug_build()
	chk_admin_mode_no_ads.toggled.connect(_on_admin_mode_no_ads_toggled)
	content.add_child(chk_admin_mode_no_ads)
	if AdsManager != null:
		AdsManager.set_admin_mode_no_ads(chk_admin_mode_no_ads.button_pressed)

	for item in [
		["+1 Level (DEBUG)", Callable(self, "_on_debug_add_level")],
		["-1 Level (DEBUG)", Callable(self, "_on_debug_remove_level")],
		["Print Save (DEBUG)", Callable(self, "_on_debug_print_save")],
		["Cloud: Sign In (DEBUG)", Callable(self, "_on_debug_cloud_sign_in")],
		["Cloud: Pull (DEBUG)", Callable(self, "_on_debug_cloud_pull")],
		["Cloud: Push (DEBUG)", Callable(self, "_on_debug_cloud_push")],
		["LB: Retry Pending", Callable(self, "_on_debug_lb_retry_pending")],
		["LB: Submit Test Score", Callable(self, "_on_debug_lb_submit_test_score")],
		["Corrupt Local Save (DEBUG)", Callable(self, "_on_debug_corrupt_local")]
	]:
		var b = Button.new()
		b.text = item[0]
		b.custom_minimum_size = Vector2(0, 48)
		b.mouse_entered.connect(func(): _play_sfx("ui_hover"))
		b.pressed.connect(func(): _play_sfx("ui_click"))
		b.pressed.connect(item[1])
		content.add_child(b)


func _refresh_all_ui() -> void:
	_refresh_level_chip()
	_refresh_difficulty_chip()
	_refresh_mode_description()
	_refresh_rewards_panel()
	_refresh_debug_cloud_status()
	_update_menu_fx()


func _refresh_level_chip() -> void:
	if level_chip_label == null:
		return
	var level = _get_player_level()
	level_chip_label.text = "Level %d" % level
	if level_chip_progress != null:
		# TODO: Replace placeholder XP with real progression source once XP data is available.
		level_chip_progress.value = 0.35


func _refresh_difficulty_chip() -> void:
	var difficulty = Save.get_current_difficulty()
	var chip_color = _difficulty_color(difficulty)
	if difficulty_chip_label != null:
		difficulty_chip_label.text = difficulty
		difficulty_chip_label.modulate = chip_color
	_update_difficulty_buttons(difficulty)
	_update_no_mercy_visibility()
	_update_menu_fx()


func _refresh_mode_description() -> void:
	if mode_description_label == null:
		return
	var difficulty = Save.get_current_difficulty()
	var no_mercy = Save.get_no_mercy()
	if difficulty == "Easy":
		mode_description_label.text = "Relaxed pace with forgiving board pressure."
	elif difficulty == "Medium":
		mode_description_label.text = "Balanced mode with classic challenge."
	elif no_mercy:
		mode_description_label.text = " Hard + No Mercy: no reserve slots, constant pressure."
	else:
		mode_description_label.text = " Hard mode with faster pressure and tighter decisions."


func _refresh_rewards_panel() -> void:
	if rewards_level_label == null:
		return
	var level = _get_player_level()
	rewards_level_label.text = "Player Level: %d" % level
	for m in rewards_status_labels.keys():
		var status = "Unlocked" if level >= int(m) else "Locked"
		rewards_status_labels[m].text = "Level %d checkpoint: %s" % [int(m), status]


func _apply_difficulty_selection(difficulty: String) -> void:
	Save.set_difficulty(difficulty)
	if difficulty != "Hard":
		Save.set_no_mercy(false)
	Save.save()
	var core = get_node_or_null("/root/Core")
	if core != null:
		core.call("ApplyDifficultyFromSave")
	_refresh_all_ui()
	_update_menu_fx()


func _on_no_mercy_toggled(enabled: bool) -> void:
	var is_hard = Save.get_current_difficulty() == "Hard"
	if not is_hard:
		no_mercy_toggle.button_pressed = false
		_update_menu_fx()
		return
	Save.set_no_mercy(enabled)
	Save.save()
	var core = get_node_or_null("/root/Core")
	if core != null:
		core.call("ApplyDifficultyFromSave")
	_refresh_all_ui()
	_update_menu_fx()


func _update_difficulty_buttons(selected: String) -> void:
	for key in difficulty_chip_buttons.keys():
		var button = difficulty_chip_buttons[key]
		if button == null:
			continue
		var is_selected = String(key) == selected
		var glow_color = Color(1.00, 0.84, 0.18, 0.55)
		match String(key):
			"Easy":
				glow_color = Color(0.22, 1.00, 0.55, 0.55)
			"Hard":
				glow_color = Color(1.00, 0.22, 0.20, 0.55)
			_:
				glow_color = Color(1.00, 0.84, 0.18, 0.55)
		button.disabled = is_selected
		button.add_theme_color_override("font_color", Color(0.10, 0.07, 0.05, 1.0))
		button.add_theme_color_override("font_hover_color", Color(0.10, 0.07, 0.05, 1.0))
		button.add_theme_color_override("font_pressed_color", Color(0.10, 0.07, 0.05, 1.0))
		if is_selected:
			button.add_theme_constant_override("outline_size", 4)
			button.add_theme_color_override("font_outline_color", glow_color)
		else:
			button.add_theme_constant_override("outline_size", 2)
			button.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.20))


func _update_no_mercy_visibility() -> void:
	if no_mercy_toggle == null:
		return
	var is_hard = Save.get_current_difficulty() == "Hard"
	if no_mercy_panel != null:
		no_mercy_panel.visible = is_hard
	else:
		no_mercy_toggle.visible = is_hard
	no_mercy_help.visible = is_hard
	if is_hard:
		no_mercy_toggle.button_pressed = Save.get_no_mercy()
	var show_no_mercy_sparks = is_hard and Save.get_no_mercy()
	if no_mercy_sparks_pollen != null:
		no_mercy_sparks_pollen.visible = show_no_mercy_sparks
		no_mercy_sparks_pollen.emitting = show_no_mercy_sparks


func _update_menu_fx() -> void:
	var difficulty = Save.get_current_difficulty()
	if difficulty_glow != null:
		difficulty_glow.visible = true
		difficulty_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if difficulty_glow.material is ShaderMaterial:
			var glow_shader_material = difficulty_glow.material as ShaderMaterial
			match difficulty:
				"Easy":
					glow_shader_material.set_shader_parameter("glow_color", Color(0.22, 1.00, 0.55, 1.0))
					glow_shader_material.set_shader_parameter("intensity", 0.24)
				"Hard":
					glow_shader_material.set_shader_parameter("glow_color", Color(1.00, 0.22, 0.20, 1.0))
					glow_shader_material.set_shader_parameter("intensity", 0.28)
				_:
					glow_shader_material.set_shader_parameter("glow_color", Color(1.00, 0.84, 0.18, 1.0))
					glow_shader_material.set_shader_parameter("intensity", 0.26)


	var show_no_mercy_sparks = difficulty == "Hard" and Save.get_no_mercy()
	if no_mercy_sparks_pollen != null:
		no_mercy_sparks_pollen.visible = show_no_mercy_sparks
		no_mercy_sparks_pollen.emitting = show_no_mercy_sparks


func _build_safe_rect() -> Rect2i:
	var safe = DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0:
		return Rect2i(Vector2i.ZERO, get_viewport_rect().size)
	return safe


func _apply_safe_area() -> void:
	if root_layer == null:
		return
	var safe = _build_safe_rect()
	var vp = get_viewport_rect()
	safe_left = float(max(0, safe.position.x))
	safe_top = float(max(0, safe.position.y))
	safe_right = float(max(0, int(vp.size.x) - (safe.position.x + safe.size.x)))
	var computed_safe_bottom = max(0, int(vp.size.y) - (safe.position.y + safe.size.y))
	safe_bottom = 0.0
	if OS.get_name() == "Android" or OS.get_name() == "iOS":
		safe_bottom = float(computed_safe_bottom)

	var top_reserved = safe_top + TOPBAR_H + UI_MARGIN
	var bottom_reserved = BOTTOMBAR_H + safe_bottom + UI_MARGIN
	var usable_top = top_reserved
	var usable_bottom = vp.size.y - bottom_reserved
	var play_card_center_y = lerp(usable_top, usable_bottom, 0.58)
	var title_center_y = lerp(usable_top, play_card_center_y, 0.38)
	var dist_top = title_center_y - 0.0
	var dist_bottom = (vp.size.y - bottom_reserved) - play_card_center_y
	var delta = (dist_top - dist_bottom) * 0.5
	title_center_y -= delta
	play_card_center_y += delta

	var top_bar = content_layer.get_node_or_null("TopBar")
	if top_bar != null:
		top_bar.offset_left = UI_MARGIN + safe_left
		top_bar.offset_right = -UI_MARGIN - safe_right
		top_bar.offset_top = UI_MARGIN + safe_top
		top_bar.offset_bottom = top_bar.offset_top + TOPBAR_H

	var hero_title = content_layer.get_node_or_null("HeroTitle")
	var title_to_play_gap = 3.0 * UI_GAP
	var play_card_half_h = 215.0
	var title_half_h = HERO_TITLE_HEIGHT * 0.5
	var min_play_center = usable_top + play_card_half_h
	var max_play_center = usable_bottom - play_card_half_h
	play_card_center_y = clamp(play_card_center_y, min_play_center, max_play_center)
	var max_title_center = play_card_center_y - (title_half_h + play_card_half_h + title_to_play_gap)
	title_center_y = min(title_center_y, max_title_center)

	if hero_title != null:
		hero_title.anchor_left = 0.5
		hero_title.anchor_right = 0.5
		hero_title.anchor_top = 0.0
		hero_title.anchor_bottom = 0.0
		var title_zone_w = max(320.0, vp.size.x - (safe_left + safe_right + (UI_MARGIN * 2.0)))
		hero_title.offset_left = -title_zone_w * 0.5
		hero_title.offset_right = title_zone_w * 0.5
		hero_title.offset_top = title_center_y - title_half_h
		hero_title.offset_bottom = title_center_y + title_half_h
		if hero_subtitle_label != null:
			if hero_subtitle_label.label_settings != null:
				hero_subtitle_label.label_settings.font_size = SUBTITLE_FONT

	var play_card = content_layer.get_node_or_null("PlayCard")
	if play_card != null:
		var max_w = min(float(PLAYCARD_MAX_W), vp.size.x - (safe_left + safe_right + (UI_MARGIN * 2.0)))
		play_card.anchor_left = 0.5
		play_card.anchor_right = 0.5
		play_card.anchor_top = 0.0
		play_card.anchor_bottom = 0.0
		play_card.offset_left = -max_w * 0.5
		play_card.offset_right = max_w * 0.5
		play_card.offset_top = play_card_center_y - play_card_half_h
		play_card.offset_bottom = play_card_center_y + play_card_half_h

	var bottom_bar = bottom_nav_layer.get_node_or_null("BottomBar")
	if bottom_bar != null:
		bottom_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		bottom_bar.offset_left = UI_MARGIN + safe_left
		bottom_bar.offset_right = -UI_MARGIN - safe_right
		bottom_bar.offset_bottom = 0
		bottom_bar.offset_top = -BOTTOMBAR_H
		var safe_margin = bottom_bar.get_node_or_null("BackgroundPanel/SafeMargin")
		if safe_margin != null:
			safe_margin.add_theme_constant_override("margin_bottom", int(safe_bottom))
			safe_margin.add_theme_constant_override("margin_left", int(NAV_SIDE_MARGIN))
			safe_margin.add_theme_constant_override("margin_right", int(NAV_SIDE_MARGIN))

	for panel in [rewards_panel, leaderboard_panel, quests_panel, shop_panel, debug_panel, settings_panel]:
		if panel != null:
			var max_w = min(920.0, vp.size.x - (safe_left + safe_right + 32.0))
			var max_h = min(980.0, vp.size.y - (safe_top + safe_bottom + 32.0))
			max_w = max(max_w, 320.0)
			max_h = max(max_h, 320.0)
			panel.offset_left = -max_w * 0.5
			panel.offset_right = max_w * 0.5
			panel.offset_top = -max_h * 0.5
			panel.offset_bottom = max_h * 0.5


func _difficulty_color(difficulty: String) -> Color:
	var key = "glow_medium"
	match difficulty:
		"Easy":
			key = "glow_easy"
		"Hard":
			key = "glow_hard"
		_:
			key = "glow_medium"
	return _palette_color(key, Color(1.0, 0.76, 0.26))


func _load_menu_palette() -> Dictionary:
	if not menu_palette_cache.is_empty():
		return menu_palette_cache
	var manager = _skin_manager()
	if manager != null and manager.has_method("get_default_palette"):
		var candidate = manager.call("get_default_palette")
		if typeof(candidate) == TYPE_DICTIONARY:
			menu_palette_cache = candidate
	return menu_palette_cache


func _palette_color(key: String, fallback: Color) -> Color:
	var palette = _load_menu_palette()
	if palette.has("colors"):
		var colors = palette["colors"]
		if typeof(colors) == TYPE_DICTIONARY and colors.has(key):
			return Color.from_string(String(colors[key]), fallback)
	return fallback


func _palette_float(key: String, fallback: float) -> float:
	var palette = _load_menu_palette()
	if palette.has("spacing"):
		var spacing = palette["spacing"]
		if typeof(spacing) == TYPE_DICTIONARY and spacing.has(key):
			return float(spacing[key])
	if palette.has("fx"):
		var fx = palette["fx"]
		if typeof(fx) == TYPE_DICTIONARY and fx.has(key):
			return float(fx[key])
	return fallback


func _stylebox_9slice(path: String) -> StyleBoxTexture:
	if not ResourceLoader.exists(path):
		return null
	var resource = load(path)
	if resource is StyleBoxTexture:
		return resource as StyleBoxTexture
	if resource is StyleBox:
		return null
	var tex = resource
	if not (tex is Texture2D):
		return null
	var style = StyleBoxTexture.new()
	style.texture = tex
	style.texture_margin_left = 12
	style.texture_margin_right = 12
	style.texture_margin_top = 12
	style.texture_margin_bottom = 12
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return style


func _apply_button_style(button: Button, kind: String) -> void:
	if button == null:
		return
	var path = NINEPATCH_BUTTON_PRIMARY_PATH
	if kind == "small":
		path = NINEPATCH_BUTTON_SMALL_PATH
	var style = _stylebox_9slice(path)
	if style == null:
		return
	var hover_style = style.duplicate()
	var pressed_style = style.duplicate()
	var disabled_style = style.duplicate()
	pressed_style.content_margin_top += 2
	pressed_style.content_margin_bottom = max(0.0, pressed_style.content_margin_bottom - 2)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", pressed_style)
	button.add_theme_stylebox_override("hover_pressed", pressed_style)
	button.add_theme_stylebox_override("disabled", disabled_style)
	button.clip_text = true
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	if kind == "primary":
		button.add_theme_constant_override("content_margin_left", 26)
		button.add_theme_constant_override("content_margin_right", 26)
		button.add_theme_constant_override("content_margin_top", 7)
		button.add_theme_constant_override("content_margin_bottom", 7)
		button.add_theme_font_size_override("font_size", 34)
	elif kind == "small":
		_apply_small_button_readability(button)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _apply_small_button_readability(button: Button) -> void:
	if button == null:
		return
	# Small button readability fix: dark text + subtle outline + safe inner padding.
	button.add_theme_color_override("font_color", Color(0.08, 0.06, 0.04, 1))
	button.add_theme_color_override("font_hover_color", Color(0.18, 0.12, 0.08, 1))
	button.add_theme_color_override("font_pressed_color", Color(0.10, 0.07, 0.05, 1))
	button.add_theme_color_override("font_disabled_color", Color(0.40, 0.32, 0.22, 0.9))
	button.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.20))
	button.add_theme_constant_override("outline_size", 6)
	button.add_theme_constant_override("content_margin_left", 18)
	button.add_theme_constant_override("content_margin_right", 18)
	button.add_theme_constant_override("content_margin_top", 10)
	button.add_theme_constant_override("content_margin_bottom", 10)


func _apply_label_readability(label: Label, strength: String) -> void:
	if label == null:
		return
	var font_size = int(label.get_theme_font_size("font_size"))
	if font_size <= 0:
		font_size = 20
	var font_color = Color(0.11, 0.08, 0.06, 1.0)
	var outline_color = Color(1.0, 1.0, 1.0, 0.22)
	var outline_size = 1
	if strength == "strong":
		font_color = Color(0.08, 0.06, 0.04, 1.0)
		outline_size = 2
		font_size += 2
	elif strength == "muted":
		font_color = Color(0.19, 0.15, 0.12, 0.95)
		outline_color = Color(1.0, 1.0, 1.0, 0.18)
		outline_size = 1
		font_size = max(12, font_size - 2)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", font_color)
	label.add_theme_constant_override("outline_size", outline_size)
	label.add_theme_color_override("font_outline_color", outline_color)


func _start_play_idle_animation(play_button: Button) -> void:
	if play_button == null:
		return
	if _play_idle_tween != null and _play_idle_tween.is_valid():
		_play_idle_tween.kill()
	play_button.scale = Vector2.ONE
	play_button.modulate = Color(1, 1, 1, 1)
	_play_idle_tween = create_tween()
	_play_idle_tween.set_loops()
	_play_idle_tween.tween_interval(1.7)
	_play_idle_tween.tween_property(play_button, "scale", Vector2(1.02, 1.02), 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_play_idle_tween.parallel().tween_property(play_button, "modulate", Color(1, 1, 1, 0.93), 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_play_idle_tween.tween_property(play_button, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_play_idle_tween.parallel().tween_property(play_button, "modulate", Color(1, 1, 1, 1), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _set_active_nav(name: String) -> void:
	current_nav = name
	for key in nav_buttons.keys():
		var btn = nav_buttons[key] as Button
		if btn == null:
			continue
		var is_active = String(key) == name
		btn.modulate = Color(1, 1, 1, 1) if is_active else Color(1, 1, 1, 0.92)
		btn.add_theme_constant_override("outline_size", 8 if is_active else 6)
		btn.add_theme_color_override("font_outline_color", Color(1.0, 0.96, 0.80, 0.42) if is_active else Color(1.0, 1.0, 1.0, 0.20))
		var underline = btn.get_node_or_null("ActiveUnderline") as ColorRect
		if underline != null:
			underline.visible = is_active


func _apply_top_icon_button_style(btn: Button) -> void:
	if btn == null:
		return
	_apply_button_style(btn, "small")
	btn.add_theme_constant_override("content_margin_left", 8)
	btn.add_theme_constant_override("content_margin_right", 8)
	btn.add_theme_constant_override("content_margin_top", 8)
	btn.add_theme_constant_override("content_margin_bottom", 8)


func _ensure_ui_vignette() -> void:
	if background_layer == null:
		return
	var existing = background_layer.get_node_or_null("ui_vignette")
	if existing != null:
		existing.queue_free()
	var ui_vignette = ColorRect.new()
	ui_vignette.name = "ui_vignette"
	ui_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_vignette.color = Color(1, 1, 1, 1)
	ui_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

uniform float dim_strength : hint_range(0.0, 1.0) = 0.14;
uniform vec2 center = vec2(0.5, 0.52);
uniform vec2 radius = vec2(0.25, 0.34);

void fragment() {
	vec2 uv = UV;
	vec2 d = (uv - center) / max(radius, vec2(0.001));
	float dist = length(d);
	float mask = 1.0 - smoothstep(0.0, 1.0, dist);
	float alpha = dim_strength * mask;
	COLOR = vec4(0.0, 0.0, 0.0, alpha);
}
"""
	var mat = ShaderMaterial.new()
	mat.shader = shader
	ui_vignette.material = mat
	background_layer.add_child(ui_vignette)


func _apply_playcard_text_style(label: Label) -> void:
	if label == null:
		return
	var current_size = int(label.get_theme_font_size("font_size"))
	if current_size <= 0:
		current_size = 18
	label.add_theme_font_size_override("font_size", current_size + 4)
	label.add_theme_color_override("font_color", Color(0.10, 0.07, 0.05, 1.0))
	label.add_theme_constant_override("outline_size", 2)
	label.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.20))


func _apply_no_mercy_checkbox_style(checkbox: CheckBox, panel: Panel = null, label: Label = null) -> void:
	if checkbox == null:
		return
	if panel != null:
		var chip_style = _stylebox_9slice(NINEPATCH_TOP_CHIP_PATH)
		if chip_style != null:
			panel.add_theme_stylebox_override("panel", chip_style)
	var font_color = Color(0.10, 0.07, 0.05, 1)
	checkbox.add_theme_color_override("font_color", font_color)
	checkbox.add_theme_color_override("font_hover_color", font_color)
	checkbox.add_theme_color_override("font_pressed_color", font_color)
	checkbox.add_theme_color_override("font_hover_pressed_color", font_color)
	checkbox.add_theme_color_override("font_focus_color", font_color)
	checkbox.add_theme_color_override("font_disabled_color", font_color)
	checkbox.add_theme_constant_override("outline_size", 0)
	checkbox.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0))
	checkbox.add_theme_constant_override("h_separation", 0)
	checkbox.modulate = Color(1, 1, 1, 1)
	checkbox.focus_mode = Control.FOCUS_NONE
	if label != null:
		label.add_theme_color_override("font_color", font_color)
		label.add_theme_color_override("font_hover_color", font_color)
		label.add_theme_color_override("font_pressed_color", font_color)
		label.add_theme_color_override("font_hover_pressed_color", font_color)
		label.add_theme_color_override("font_focus_color", font_color)
		label.add_theme_constant_override("outline_size", 2)
		label.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.25))


func _apply_panel_style(panel: Panel) -> void:
	if panel == null:
		return
	var style = _stylebox_9slice(NINEPATCH_PANEL_DEFAULT_PATH)
	if style == null:
		return
	panel.add_theme_stylebox_override("panel", style)


func _apply_top_chip_style(button: Button) -> void:
	if button == null:
		return
	var style = _stylebox_9slice(NINEPATCH_TOP_CHIP_PATH)
	if style == null:
		return
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style.duplicate())
	button.add_theme_stylebox_override("pressed", style.duplicate())
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _load_icon(path_to_tres: String) -> Texture2D:
	if not ResourceLoader.exists(path_to_tres):
		return null
	var resource = load(path_to_tres)
	if resource is Texture2D:
		return resource as Texture2D
	if resource is AtlasTexture:
		return resource as AtlasTexture
	return null


func _load_icon_any(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var resource = load(path)
	if resource is Texture2D:
		return resource as Texture2D
	if resource is AtlasTexture:
		return resource as AtlasTexture
	return null


func _set_button_icon(button: Button, path: String, fallback: String, label_text: String, icon_max: int = UI_ICON_MAX) -> void:
	button.expand_icon = false
	button.add_theme_constant_override("icon_max_width", icon_max)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.custom_minimum_size = Vector2(max(button.custom_minimum_size.x, 64.0), max(button.custom_minimum_size.y, 64.0))
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var tex = _load_icon(path)
	if tex != null:
		button.icon = tex
		button.text = ""
		button.tooltip_text = label_text
		return
	button.text = fallback
	button.tooltip_text = label_text


func _skin_manager():
	return get_node_or_null("/root/SkinManager")


func _open_panel(panel: Control) -> void:
	if panel == null:
		return
	popup_overlay.visible = true
	popup_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	for p in [rewards_panel, leaderboard_panel, quests_panel, shop_panel, debug_panel]:
		if p != null:
			p.visible = (p == panel)
	if settings_panel != null:
		settings_panel.visible = (settings_panel == panel)
	if panel.has_meta("sync_settings"):
		var sync_settings = panel.get_meta("sync_settings")
		if sync_settings is Callable:
			(sync_settings as Callable).call()


func _close_all_panels() -> void:
	popup_overlay.visible = false
	popup_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for p in [rewards_panel, leaderboard_panel, quests_panel, shop_panel, debug_panel]:
		if p != null:
			p.visible = false
	if settings_panel != null:
		settings_panel.visible = false


func _is_debug_panel_visible() -> bool:
	return FORCE_DEBUG_PANEL or OS.is_debug_build()


func _get_player_level() -> int:
	if ProgressManager != null:
		return ProgressManager.get_level()
	return Save.get_player_level()


func _get_player_day() -> int:
	if ProgressManager != null:
		return ProgressManager.get_day()
	var days = Save.data.get("unique_days_played", [])
	if typeof(days) == TYPE_ARRAY:
		return (days as Array).size()
	return 0


func _on_start() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_play_games_sign_in() -> void:
	if not Save.play_games_is_available():
		_show_message("Play Games is unavailable on this platform")
		return
	Save.play_games_sign_in()
	if Save.play_games_is_signed_in():
		_show_message("Signed in to Play Games")
	else:
		_show_message("Play Games sign-in failed or canceled")


func _on_select_leaderboard(diff_key: String) -> void:
	if not Save.play_games_is_signed_in():
		_show_message("Sign in to view leaderboards")
		return
	Save.play_games_show_leaderboard(diff_key)


func _show_message(message: String) -> void:
	DialogFactory.show_message(self, "Play Games", message)


func _on_admin_mode_no_ads_toggled(enabled: bool) -> void:
	if AdsManager != null:
		AdsManager.set_admin_mode_no_ads(enabled)


func _refresh_debug_cloud_status() -> void:
	if lbl_cloud_status == null:
		return
	var mode = "Available" if Save.is_cloud_available() else "Unavailable"
	var signin = "Signed In" if Save.is_cloud_signed_in() else "Signed Out"
	var err = Save.get_cloud_last_error()
	lbl_cloud_status.text = "Cloud: %s / %s / %s" % [mode, signin, err]


func _on_debug_add_level() -> void:
	Save.debug_add_one_level()
	_refresh_all_ui()


func _on_debug_remove_level() -> void:
	Save.debug_remove_one_level()
	_refresh_all_ui()


func _on_debug_print_save() -> void:
	Save.debug_print_save()
	_refresh_debug_cloud_status()


func _on_debug_cloud_sign_in() -> void:
	Save.cloud_sign_in()
	_refresh_debug_cloud_status()


func _on_debug_cloud_pull() -> void:
	Save.cloud_pull_now()
	_refresh_all_ui()


func _on_debug_cloud_push() -> void:
	Save.cloud_push_now()
	_refresh_debug_cloud_status()


func _on_debug_corrupt_local() -> void:
	Save.debug_corrupt_local_save()
	_refresh_debug_cloud_status()


func _on_debug_lb_retry_pending() -> void:
	Save.play_games_retry_pending()


func _on_debug_lb_submit_test_score() -> void:
	var diff_key = Save.get_current_difficulty_key()
	var best = int(Save.get_best_score_by_difficulty().get(diff_key, 0))
	if best <= 0:
		_show_message("No local best score for current difficulty")
		return
	Save.play_games_submit_best_if_needed(diff_key, best)
	_show_message("Leaderboard submit attempt finished")


func _on_exit() -> void:
	get_tree().quit()
