extends Control

const GAME_SCENE := "res://Scenes/Main.tscn"

var lbl_difficulty: Label
var popup_difficulty: PopupPanel
var opt_difficulty: OptionButton
var chk_no_mercy: CheckBox
var lbl_no_mercy_help: Label


func _ready() -> void:
	_build_ui()
	_refresh_difficulty_label()


func _build_ui() -> void:
	for ch in get_children():
		ch.queue_free()

	var root := Panel.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if SkinManager != null and SkinManager.get_theme() != null:
		root.theme = SkinManager.get_theme()
	add_child(root)

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


func _menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(380, 56)
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
	v.add_child(opt_difficulty)

	chk_no_mercy = CheckBox.new()
	chk_no_mercy.text = "No Mercy"
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
	apply.pressed.connect(_on_apply_difficulty)
	btns.add_child(apply)

	var cancel := Button.new()
	cancel.text = "Cancel"
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
	var d := AcceptDialog.new()
	d.title = "Rewards"
	d.dialog_text = "Coming soon"
	add_child(d)
	d.popup_centered()


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
