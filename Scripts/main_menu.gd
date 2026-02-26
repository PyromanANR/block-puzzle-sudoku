extends Control

const GAME_SCENE = "res://Scenes/Main.tscn"
const FORCE_DEBUG_PANEL = false
const MusicManagerScript = preload("res://Scripts/Audio/MusicManager.gd")
const MainMenuTopBar = preload("res://Scripts/Modules/UI/MainMenu/TopBar.gd")
const MainMenuPrimaryButtons = preload("res://Scripts/Modules/UI/MainMenu/PrimaryButtons.gd")
const MainMenuPopups = preload("res://Scripts/Modules/UI/MainMenu/Popups.gd")
const DialogFactory = preload("res://Scripts/Modules/UI/Common/DialogFactory.gd")
const DebugMenu = preload("res://Scripts/Modules/Debug/DebugMenu.gd")

const ICON_SETTINGS = "res://Assets/UI/Icons/icon_settings.png"
const ICON_SHOP = "res://Assets/UI/Icons/icon_shop.png"
const ICON_LEADERBOARD = "res://Assets/UI/Icons/icon_leaderboard.png"
const ICON_QUESTS = "res://Assets/UI/Icons/icon_quests.png"
const ICON_PROFILE = "res://Assets/UI/Icons/icon_profile.png"

const BG_FRAMES_DIR = "res://Assets/UI/Background/FallingBlocks/frames"
const NO_MERCY_OVERLAY_PATH = "res://Assets/UI/Background/NoMercy/overlay.png"

var music_manager: MusicManager = null
var sfx_players = {}
var missing_sfx_warned = {}

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
var profile_chip_label: Label
var mode_description_label: Label
var no_mercy_toggle: CheckBox
var no_mercy_help: Label
var difficulty_chip_buttons: Dictionary = {}
var difficulty_glow: ColorRect
var no_mercy_overlay: ColorRect

var rewards_panel: Panel
var rewards_level_label: Label
var rewards_status_labels: Dictionary = {}

var settings_panel: Panel
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
	music_manager.play_menu_music()
	_audio_setup()
	_build_ui()
	_refresh_all_ui()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_safe_area()


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
	var skin_manager = _skin_manager()
	if skin_manager != null and skin_manager.get_theme() != null:
		root_layer.theme = skin_manager.get_theme()
	add_child(root_layer)

	background_layer = Control.new()
	background_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_layer.add_child(background_layer)
	_build_background_layer()

	content_layer = Control.new()
	content_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_layer.add_child(content_layer)

	bottom_nav_layer = Control.new()
	bottom_nav_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_layer.add_child(bottom_nav_layer)

	modal_layer = Control.new()
	modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_layer.add_child(modal_layer)

	_build_top_bar()
	_build_play_card()
	_build_bottom_nav()
	_build_modal_layer()
	_apply_safe_area()


func _build_background_layer() -> void:
	var bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.07, 0.08, 0.11, 1.0)
	background_layer.add_child(bg)

	var sprite_layer = Node2D.new()
	background_layer.add_child(sprite_layer)

	var sprite = AnimatedSprite2D.new()
	sprite.centered = false
	sprite.position = Vector2.ZERO
	sprite_layer.add_child(sprite)

	var frames = _build_background_frames()
	if frames != null:
		sprite.sprite_frames = frames
		sprite.animation = "default"
		sprite.play("default")
	else:
		var fallback = ColorRect.new()
		fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fallback.color = Color(0.14, 0.15, 0.19, 0.55)
		background_layer.add_child(fallback)

	difficulty_glow = ColorRect.new()
	difficulty_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	difficulty_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background_layer.add_child(difficulty_glow)

	no_mercy_overlay = ColorRect.new()
	no_mercy_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	no_mercy_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(NO_MERCY_OVERLAY_PATH):
		var texture = load(NO_MERCY_OVERLAY_PATH)
		if texture != null:
			var mat = CanvasItemMaterial.new()
			mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX
			no_mercy_overlay.material = mat
			no_mercy_overlay.color = Color(1, 1, 1, 0.14)
	else:
		no_mercy_overlay.color = Color(1.0, 0.35, 0.2, 0.08)
	background_layer.add_child(no_mercy_overlay)


func _build_background_frames() -> SpriteFrames:
	if not DirAccess.dir_exists_absolute(BG_FRAMES_DIR):
		return null
	var files = []
	var dir = DirAccess.open(BG_FRAMES_DIR)
	if dir == null:
		return null
	dir.list_dir_begin()
	while true:
		var file_name = dir.get_next()
		if file_name == "":
			break
		if dir.current_is_dir():
			continue
		if not (file_name.ends_with(".png") or file_name.ends_with(".webp")):
			continue
		files.append(file_name)
	dir.list_dir_end()
	files.sort()
	if files.is_empty():
		return null

	var frames = SpriteFrames.new()
	frames.add_animation("default")
	frames.set_animation_speed("default", 8.0)
	for file_name in files:
		var path = "%s/%s" % [BG_FRAMES_DIR, file_name]
		if not ResourceLoader.exists(path):
			continue
		var tex = load(path)
		if tex != null:
			frames.add_frame("default", tex)
	if frames.get_frame_count("default") <= 0:
		return null
	return frames


func _build_top_bar() -> void:
	var top = HBoxContainer.new()
	top.name = "TopBar"
	top.anchor_left = 0.0
	top.anchor_top = 0.0
	top.anchor_right = 1.0
	top.anchor_bottom = 0.0
	top.offset_left = 24
	top.offset_right = -24
	top.offset_top = 16
	top.offset_bottom = 96
	top.add_theme_constant_override("separation", 12)
	content_layer.add_child(top)

	var btn_settings = Button.new()
	btn_settings.custom_minimum_size = Vector2(80, 64)
	_set_button_icon(btn_settings, ICON_SETTINGS, "⚙", "Settings")
	btn_settings.mouse_entered.connect(func(): _play_sfx("ui_hover"))
	btn_settings.pressed.connect(func(): _play_sfx("ui_click"))
	btn_settings.pressed.connect(func(): _open_panel(settings_panel))
	top.add_child(btn_settings)

	var center = VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(center)

	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	center.add_child(row)

	var title = Label.new()
	title.text = "Tetris Sudoku"
	title.add_theme_font_size_override("font_size", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(title)

	difficulty_chip_label = Label.new()
	difficulty_chip_label.custom_minimum_size = Vector2(96, 36)
	difficulty_chip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	difficulty_chip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(difficulty_chip_label)

	var subtitle = Label.new()
	subtitle.text = "Classic block strategy"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(0.9, 0.9, 0.95, 0.75)
	center.add_child(subtitle)

	var btn_profile = Button.new()
	btn_profile.custom_minimum_size = Vector2(170, 64)
	btn_profile.mouse_entered.connect(func(): _play_sfx("ui_hover"))
	btn_profile.pressed.connect(func(): _play_sfx("ui_click"))
	btn_profile.pressed.connect(func(): _open_panel(rewards_panel))
	top.add_child(btn_profile)

	var profile_row = HBoxContainer.new()
	profile_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	profile_row.offset_left = 8
	profile_row.offset_right = -8
	profile_row.offset_top = 8
	profile_row.offset_bottom = -8
	btn_profile.add_child(profile_row)

	var profile_icon = Label.new()
	profile_icon.text = "👤"
	if ResourceLoader.exists(ICON_PROFILE):
		profile_icon.text = ""
	profile_row.add_child(profile_icon)

	profile_chip_label = Label.new()
	profile_chip_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_chip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	profile_row.add_child(profile_chip_label)


func _build_play_card() -> void:
	var card = Panel.new()
	card.name = "PlayCard"
	card.anchor_left = 0.5
	card.anchor_top = 0.5
	card.anchor_right = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -260
	card.offset_top = -270
	card.offset_right = 260
	card.offset_bottom = 180
	content_layer.add_child(card)

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	card.add_child(margin)

	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	margin.add_child(v)

	var play_button = Button.new()
	play_button.text = "PLAY"
	play_button.custom_minimum_size = Vector2(0, 88)
	play_button.add_theme_font_size_override("font_size", 40)
	play_button.mouse_entered.connect(func(): _play_sfx("ui_hover"))
	play_button.pressed.connect(func(): _play_sfx("ui_click"))
	play_button.pressed.connect(_on_start)
	v.add_child(play_button)

	var difficulty_title = Label.new()
	difficulty_title.text = "Select Difficulty"
	v.add_child(difficulty_title)

	var chips = HBoxContainer.new()
	chips.add_theme_constant_override("separation", 10)
	v.add_child(chips)
	for diff in ["Easy", "Medium", "Hard"]:
		var chip = Button.new()
		chip.text = diff
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.custom_minimum_size = Vector2(0, 52)
		chip.mouse_entered.connect(func(): _play_sfx("ui_hover"))
		chip.pressed.connect(func(): _play_sfx("ui_click"))
		chip.pressed.connect(func(): _apply_difficulty_selection(diff))
		chips.add_child(chip)
		difficulty_chip_buttons[diff] = chip

	no_mercy_toggle = CheckBox.new()
	no_mercy_toggle.text = "No Mercy"
	no_mercy_toggle.custom_minimum_size = Vector2(0, 52)
	no_mercy_toggle.mouse_entered.connect(func(): _play_sfx("ui_hover"))
	no_mercy_toggle.pressed.connect(func(): _play_sfx("ui_click"))
	no_mercy_toggle.toggled.connect(_on_no_mercy_toggled)
	v.add_child(no_mercy_toggle)

	no_mercy_help = Label.new()
	no_mercy_help.text = "No Mercy removes reserve slots."
	no_mercy_help.modulate = Color(1, 0.92, 0.85, 0.9)
	v.add_child(no_mercy_help)

	mode_description_label = Label.new()
	mode_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_description_label.modulate = Color(0.9, 0.9, 1.0, 0.84)
	v.add_child(mode_description_label)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)

	var rewards_btn = Button.new()
	rewards_btn.text = "Rewards"
	rewards_btn.custom_minimum_size = Vector2(0, 52)
	rewards_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rewards_btn.mouse_entered.connect(func(): _play_sfx("ui_hover"))
	rewards_btn.pressed.connect(func(): _play_sfx("ui_click"))
	rewards_btn.pressed.connect(func(): _open_panel(rewards_panel))
	row.add_child(rewards_btn)

	var exit_btn = Button.new()
	exit_btn.text = "Exit"
	exit_btn.custom_minimum_size = Vector2(0, 52)
	exit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exit_btn.mouse_entered.connect(func(): _play_sfx("ui_hover"))
	exit_btn.pressed.connect(func(): _play_sfx("ui_click"))
	exit_btn.pressed.connect(_on_exit)
	row.add_child(exit_btn)


func _build_bottom_nav() -> void:
	var nav = HBoxContainer.new()
	nav.name = "BottomNavBar"
	nav.anchor_left = 0.0
	nav.anchor_top = 1.0
	nav.anchor_right = 1.0
	nav.anchor_bottom = 1.0
	nav.offset_left = 24
	nav.offset_right = -24
	nav.offset_top = -112
	nav.offset_bottom = -18
	nav.add_theme_constant_override("separation", 10)
	bottom_nav_layer.add_child(nav)

	_add_nav_button(nav, "Shop", ICON_SHOP, "🛍", func(): _open_panel(shop_panel))
	_add_nav_button(nav, "Leaderboard", ICON_LEADERBOARD, "🏆", func(): _open_panel(leaderboard_panel))
	_add_nav_button(nav, "Quests", ICON_QUESTS, "📜", func(): _open_panel(quests_panel))
	if _is_debug_panel_visible():
		_add_nav_button(nav, "Debug", "", "🧪", func(): _open_panel(debug_panel))


func _add_nav_button(parent: HBoxContainer, label_text: String, icon_path: String, fallback_glyph: String, callback: Callable) -> void:
	var b = Button.new()
	b.custom_minimum_size = Vector2(0, 82)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.mouse_entered.connect(func(): _play_sfx("ui_hover"))
	b.pressed.connect(func(): _play_sfx("ui_click"))
	b.pressed.connect(callback)
	parent.add_child(b)

	var v = VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 6
	v.offset_right = -6
	v.offset_top = 6
	v.offset_bottom = -6
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	b.add_child(v)

	var icon_label = Label.new()
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if ResourceLoader.exists(icon_path):
		icon_label.text = ""
	else:
		icon_label.text = fallback_glyph
	v.add_child(icon_label)

	var text_label = Label.new()
	text_label.text = label_text
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(text_label)


func _build_modal_layer() -> void:
	popup_overlay = ColorRect.new()
	popup_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup_overlay.color = Color(0, 0, 0, 0.52)
	popup_overlay.visible = false
	popup_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	popup_overlay.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			_close_all_panels()
	)
	modal_layer.add_child(popup_overlay)

	rewards_panel = _create_modal_panel("Rewards")
	leaderboard_panel = _create_modal_panel("Leaderboard")
	quests_panel = _create_modal_panel("Quests")
	shop_panel = _create_modal_panel("Shop")
	settings_panel = _create_modal_panel("Settings")
	debug_panel = _create_modal_panel("Debug")

	_build_rewards_content(rewards_panel)
	_build_leaderboard_content(leaderboard_panel)
	_build_quests_content(quests_panel)
	_build_shop_content(shop_panel)
	_build_settings_content(settings_panel)
	_build_debug_content(debug_panel)


func _create_modal_panel(title_text: String) -> Panel:
	var panel = Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -460
	panel.offset_top = -520
	panel.offset_right = 460
	panel.offset_bottom = 520
	panel.visible = false
	modal_layer.add_child(panel)

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var v = VBoxContainer.new()
	v.name = "Body"
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)

	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	v.add_child(header)

	var title = Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn = Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(56, 48)
	close_btn.mouse_entered.connect(func(): _play_sfx("ui_hover"))
	close_btn.pressed.connect(func(): _play_sfx("ui_click"))
	close_btn.pressed.connect(func(): _close_all_panels())
	header.add_child(close_btn)

	var scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)

	var content = VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)

	var footer = HBoxContainer.new()
	footer.name = "Footer"
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 8)
	v.add_child(footer)

	var close_footer = Button.new()
	close_footer.text = "Close"
	close_footer.custom_minimum_size = Vector2(140, 52)
	close_footer.mouse_entered.connect(func(): _play_sfx("ui_hover"))
	close_footer.pressed.connect(func(): _play_sfx("ui_click"))
	close_footer.pressed.connect(func(): _close_all_panels())
	footer.add_child(close_footer)

	return panel


func _build_rewards_content(panel: Panel) -> void:
	var content = panel.get_node("Body/Scroll/Content")
	rewards_level_label = Label.new()
	content.add_child(rewards_level_label)
	for m in [5, 10, 20, 50]:
		var line = Label.new()
		content.add_child(line)
		rewards_status_labels[m] = line


func _build_leaderboard_content(panel: Panel) -> void:
	var content = panel.get_node("Body/Scroll/Content")
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
	var content = panel.get_node("Body/Scroll/Content")
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
	var content = panel.get_node("Body/Scroll/Content")
	for item_name in ["Remove Ads", "Sudoku Pack", "Rome Pack"]:
		var card = Panel.new()
		card.custom_minimum_size = Vector2(0, 96)
		content.add_child(card)
		var label = Label.new()
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.offset_left = 12
		label.offset_top = 12
		label.text = "%s\nComing soon" % item_name
		card.add_child(label)


func _build_settings_content(panel: Panel) -> void:
	var content = panel.get_node("Body/Scroll/Content")
	var message = Label.new()
	message.text = "Settings popup placeholder"
	content.add_child(message)

	var difficulty_btn = Button.new()
	difficulty_btn.text = "Open Rewards"
	difficulty_btn.custom_minimum_size = Vector2(0, 52)
	difficulty_btn.mouse_entered.connect(func(): _play_sfx("ui_hover"))
	difficulty_btn.pressed.connect(func(): _play_sfx("ui_click"))
	difficulty_btn.pressed.connect(func(): _open_panel(rewards_panel))
	content.add_child(difficulty_btn)


func _build_debug_content(panel: Panel) -> void:
	var content = panel.get_node("Body/Scroll/Content")
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
	_refresh_profile_chip()
	_refresh_difficulty_chip()
	_refresh_mode_description()
	_refresh_rewards_panel()
	_refresh_debug_cloud_status()


func _refresh_profile_chip() -> void:
	if profile_chip_label == null:
		return
	var level = _get_player_level()
	var day = _get_player_day()
	if day > 0:
		profile_chip_label.text = "Level %d\nDay %d" % [level, day]
	else:
		profile_chip_label.text = "Level %d" % level


func _refresh_difficulty_chip() -> void:
	if difficulty_chip_label == null:
		return
	var difficulty = Save.get_current_difficulty()
	difficulty_chip_label.text = difficulty
	var chip_color = _difficulty_color(difficulty)
	difficulty_chip_label.modulate = chip_color
	_update_difficulty_buttons(difficulty)
	if difficulty_glow != null:
		var alpha = 0.13
		if difficulty == "Hard":
			alpha = 0.20
		difficulty_glow.color = Color(chip_color.r, chip_color.g, chip_color.b, alpha)
	_update_no_mercy_visibility()


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
		mode_description_label.text = "Hard + No Mercy: no reserve slots, constant pressure."
	else:
		mode_description_label.text = "Hard mode with faster pressure and tighter decisions."


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


func _on_no_mercy_toggled(enabled: bool) -> void:
	var is_hard = Save.get_current_difficulty() == "Hard"
	if not is_hard:
		no_mercy_toggle.button_pressed = false
		return
	Save.set_no_mercy(enabled)
	Save.save()
	var core = get_node_or_null("/root/Core")
	if core != null:
		core.call("ApplyDifficultyFromSave")
	_refresh_all_ui()


func _update_difficulty_buttons(selected: String) -> void:
	for key in difficulty_chip_buttons.keys():
		var button = difficulty_chip_buttons[key]
		if button == null:
			continue
		button.disabled = String(key) == selected


func _update_no_mercy_visibility() -> void:
	if no_mercy_toggle == null:
		return
	var is_hard = Save.get_current_difficulty() == "Hard"
	no_mercy_toggle.visible = is_hard
	no_mercy_help.visible = is_hard
	if is_hard:
		no_mercy_toggle.button_pressed = Save.get_no_mercy()
	if no_mercy_overlay != null:
		no_mercy_overlay.visible = is_hard and Save.get_no_mercy()


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
	safe_bottom = float(max(0, int(vp.size.y) - (safe.position.y + safe.size.y)))

	var top_bar = content_layer.get_node_or_null("TopBar")
	if top_bar != null:
		top_bar.offset_left = 16 + safe_left
		top_bar.offset_right = -16 - safe_right
		top_bar.offset_top = 12 + safe_top

	var play_card = content_layer.get_node_or_null("PlayCard")
	if play_card != null:
		var max_width = min(640.0, vp.size.x - (safe_left + safe_right + 36.0))
		play_card.offset_left = -max_width * 0.5
		play_card.offset_right = max_width * 0.5

	var nav = bottom_nav_layer.get_node_or_null("BottomNavBar")
	if nav != null:
		nav.offset_left = 16 + safe_left
		nav.offset_right = -16 - safe_right
		nav.offset_bottom = -12 - safe_bottom
		nav.offset_top = nav.offset_bottom - 94


func _difficulty_color(difficulty: String) -> Color:
	match difficulty:
		"Easy":
			return Color(0.32, 0.92, 0.56)
		"Hard":
			return Color(0.98, 0.35, 0.33)
		_:
			return Color(1.0, 0.76, 0.26)


func _set_button_icon(button: Button, path: String, fallback: String, label_text: String) -> void:
	if ResourceLoader.exists(path):
		var tex = load(path)
		if tex != null:
			button.icon = tex
			button.text = ""
			button.tooltip_text = label_text
			return
	button.text = fallback
	button.tooltip_text = label_text


func _skin_manager():
	return get_node_or_null("/root/SkinManager")


func _open_panel(panel: Panel) -> void:
	if panel == null:
		return
	popup_overlay.visible = true
	for p in [rewards_panel, settings_panel, leaderboard_panel, quests_panel, shop_panel, debug_panel]:
		if p != null:
			p.visible = (p == panel)


func _close_all_panels() -> void:
	popup_overlay.visible = false
	for p in [rewards_panel, settings_panel, leaderboard_panel, quests_panel, shop_panel, debug_panel]:
		if p != null:
			p.visible = false


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
