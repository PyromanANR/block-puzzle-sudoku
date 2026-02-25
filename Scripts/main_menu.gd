extends Control

const GAME_SCENE := "res://Scenes/Main.tscn"

var lbl_difficulty: Label
var btn_player_level: Button
var rewards_popup: PopupPanel
var rewards_level_label: Label
var rewards_status_labels: Dictionary = {}
var popup_difficulty: PopupPanel
var opt_difficulty: OptionButton
var chk_no_mercy: CheckBox
var lbl_no_mercy_help: Label
var sfx_players = {}
var missing_sfx_warned = {}


func _skin_manager():
	return get_node_or_null("/root/SkinManager")



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

func _ready() -> void:
	_audio_setup()
	_build_ui()
	_refresh_difficulty_label()
	_refresh_rewards_stub()


func _build_ui() -> void:
	for ch in get_children():
		if ch is AudioStreamPlayer:
			continue
		ch.queue_free()

	var root := Panel.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var skin_manager = _skin_manager()
	if skin_manager != null and skin_manager.get_theme() != null:
		root.theme = skin_manager.get_theme()
	add_child(root)

	btn_player_level = Button.new()
	btn_player_level.text = "Level %d" % Save.get_player_level()
	btn_player_level.custom_minimum_size = Vector2(130, 40)
	btn_player_level.size = Vector2(130, 40)
	btn_player_level.anchor_left = 1.0
	btn_player_level.anchor_right = 1.0
	btn_player_level.anchor_top = 0.0
	btn_player_level.anchor_bottom = 0.0
	btn_player_level.offset_left = -150
	btn_player_level.offset_right = -20
	btn_player_level.offset_top = 20
	btn_player_level.offset_bottom = 60
	btn_player_level.mouse_entered.connect(func(): _play_sfx("ui_hover"))
	btn_player_level.pressed.connect(func(): _play_sfx("ui_click"))
	btn_player_level.pressed.connect(_open_rewards_stub)
	root.add_child(btn_player_level)

	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	v.position = Vector2(-220, -300)
	v.size = Vector2(440, 600)
	v.add_theme_constant_override("separation", 14)
	root.add_child(v)

	var title := Label.new()
	title.text = "TETRIS SUDOKU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	v.add_child(title)

	lbl_difficulty = Label.new()
	lbl_difficulty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_difficulty.add_theme_font_size_override("font_size", 24)
	v.add_child(lbl_difficulty)

	v.add_child(_menu_button("Start", _on_start))
	v.add_child(_menu_button("Rewards", _on_rewards))
	v.add_child(_menu_button("Settings", _on_settings))
	v.add_child(_menu_button("Change difficulty", _on_change_difficulty))
	v.add_child(_menu_button("Exit", _on_exit))

	_build_difficulty_popup(root)
	_build_rewards_popup(root)


func _menu_button(text: String, cb: Callable) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(380, 56)
	b.mouse_entered.connect(func(): _play_sfx("ui_hover"))
	b.pressed.connect(func(): _play_sfx("ui_click"))
	b.pressed.connect(cb)
	return b


func _build_difficulty_popup(root: Control) -> void:
	popup_difficulty = PopupPanel.new()
	popup_difficulty.size = Vector2(520, 380)
	popup_difficulty.visible = false
	root.add_child(popup_difficulty)

	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 18
	v.offset_top = 18
	v.offset_right = -18
	v.offset_bottom = -18
	v.add_theme_constant_override("separation", 10)
	popup_difficulty.add_child(v)

	var t := Label.new()
	t.text = "Difficulty"
	t.add_theme_font_size_override("font_size", 26)
	v.add_child(t)

	opt_difficulty = OptionButton.new()
	opt_difficulty.add_item("Easy")
	opt_difficulty.add_item("Medium")
	opt_difficulty.add_item("Hard")
	opt_difficulty.item_selected.connect(_on_difficulty_selected)
	opt_difficulty.mouse_entered.connect(func(): _play_sfx("ui_hover"))
	v.add_child(opt_difficulty)

	chk_no_mercy = CheckBox.new()
	chk_no_mercy.text = "No Mercy"
	chk_no_mercy.mouse_entered.connect(func(): _play_sfx("ui_hover"))
	chk_no_mercy.pressed.connect(func(): _play_sfx("ui_click"))
	v.add_child(chk_no_mercy)

	lbl_no_mercy_help = Label.new()
	lbl_no_mercy_help.text = "No Mercy removes all reserve slots (TopSelectable=0)."
	lbl_no_mercy_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(lbl_no_mercy_help)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	v.add_child(btns)

	var apply := Button.new()
	apply.text = "Apply"
	apply.mouse_entered.connect(func(): _play_sfx("ui_hover"))
	apply.pressed.connect(func(): _play_sfx("ui_click"))
	apply.pressed.connect(_on_apply_difficulty)
	btns.add_child(apply)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.mouse_entered.connect(func(): _play_sfx("ui_hover"))
	cancel.pressed.connect(func(): _play_sfx("ui_click"))
	cancel.pressed.connect(func(): popup_difficulty.hide())
	btns.add_child(cancel)


func _refresh_difficulty_label() -> void:
	var difficulty := Save.get_current_difficulty()
	var no_mercy := Save.get_no_mercy()
	if difficulty == "Hard" and no_mercy:
		lbl_difficulty.text = "Difficulty: Hard (No Mercy)"
	else:
		lbl_difficulty.text = "Difficulty: %s" % difficulty


func _on_start() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_rewards() -> void:
	_open_rewards_stub()


func _build_rewards_popup(root: Control) -> void:
	rewards_popup = PopupPanel.new()
	rewards_popup.size = Vector2(520, 360)
	rewards_popup.visible = false
	root.add_child(rewards_popup)

	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 18
	v.offset_top = 18
	v.offset_right = -18
	v.offset_bottom = -18
	v.add_theme_constant_override("separation", 8)
	rewards_popup.add_child(v)

	var title := Label.new()
	title.text = "Rewards"
	title.add_theme_font_size_override("font_size", 26)
	v.add_child(title)

	rewards_level_label = Label.new()
	v.add_child(rewards_level_label)

	var milestones = [5, 10, 20, 50]
	for m in milestones:
		var line := Label.new()
		line.name = "milestone_%d" % m
		v.add_child(line)
		rewards_status_labels[m] = line

	var close := Button.new()
	close.text = "Close"
	close.mouse_entered.connect(func(): _play_sfx("ui_hover"))
	close.pressed.connect(func(): _play_sfx("ui_click"))
	close.pressed.connect(func(): rewards_popup.hide())
	v.add_child(close)


func _open_rewards_stub() -> void:
	if rewards_popup == null:
		return
	_refresh_rewards_stub()
	rewards_popup.popup_centered()


func _refresh_rewards_stub() -> void:
	var level = Save.get_player_level()
	if btn_player_level != null:
		btn_player_level.text = "Level %d" % level
	if rewards_popup == null:
		return
	if rewards_level_label != null:
		rewards_level_label.text = "Player Level: %d" % level
	for m in rewards_status_labels.keys():
		var status = "Unlocked" if level >= int(m) else "Locked"
		rewards_status_labels[m].text = "Level %d checkpoint: %s" % [int(m), status]


func _on_settings() -> void:
	var d := AcceptDialog.new()
	d.title = "Settings"
	d.dialog_text = "Settings popup placeholder"
	add_child(d)
	d.popup_centered()


func _on_change_difficulty() -> void:
	var current := Save.get_current_difficulty()
	match current:
		"Easy": opt_difficulty.select(0)
		"Medium": opt_difficulty.select(1)
		_: opt_difficulty.select(2)

	chk_no_mercy.button_pressed = Save.get_no_mercy()
	_update_no_mercy_visibility()
	popup_difficulty.popup_centered()


func _on_difficulty_selected(index: int) -> void:
	_update_no_mercy_visibility()


func _update_no_mercy_visibility() -> void:
	var is_hard := opt_difficulty.get_selected_id() == 2
	chk_no_mercy.visible = is_hard
	lbl_no_mercy_help.visible = is_hard
	if not is_hard:
		chk_no_mercy.button_pressed = false


func _on_apply_difficulty() -> void:
	var difficulty := "Medium"
	match opt_difficulty.get_selected_id():
		0: difficulty = "Easy"
		1: difficulty = "Medium"
		2: difficulty = "Hard"

	Save.set_difficulty(difficulty)
	Save.set_no_mercy(chk_no_mercy.button_pressed and difficulty == "Hard")
	Save.save()

	var core = get_node_or_null("/root/Core")
	if core != null:
		core.call("ApplyDifficultyFromSave")

	_refresh_difficulty_label()
	popup_difficulty.hide()


func _on_exit() -> void:
	get_tree().quit()
