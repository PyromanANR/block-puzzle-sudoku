extends RefCounted
class_name MainMenuPrimaryButtons


static func build(root: Control, menu_owner: Control, on_hover: Callable, on_click: Callable) -> Dictionary:
	var v = VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	v.position = Vector2(-220, -360)
	v.size = Vector2(440, 720)
	v.add_theme_constant_override("separation", 14)
	root.add_child(v)

	var title = Label.new()
	title.text = "TETRIS SUDOKU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	v.add_child(title)

	var lbl_difficulty = Label.new()
	lbl_difficulty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_difficulty.add_theme_font_size_override("font_size", 24)
	v.add_child(lbl_difficulty)

	v.add_child(_menu_button("Start", Callable(menu_owner, "_on_start"), on_hover, on_click))
	v.add_child(_menu_button("Rewards", Callable(menu_owner, "_on_rewards"), on_hover, on_click))
	v.add_child(_menu_button("Settings", Callable(menu_owner, "_on_settings"), on_hover, on_click))
	v.add_child(_menu_button("Change difficulty", Callable(menu_owner, "_on_change_difficulty"), on_hover, on_click))
	v.add_child(_menu_button("Play Games: Sign In", Callable(menu_owner, "_on_play_games_sign_in"), on_hover, on_click))
	v.add_child(_menu_button("Leaderboard", Callable(menu_owner, "_on_open_leaderboard_popup"), on_hover, on_click))
	v.add_child(_menu_button("Exit", Callable(menu_owner, "_on_exit"), on_hover, on_click))

	return {
		"container": v,
		"lbl_difficulty": lbl_difficulty,
	}


static func _menu_button(text: String, cb: Callable, on_hover: Callable, on_click: Callable) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(380, 56)
	b.mouse_entered.connect(on_hover)
	b.pressed.connect(on_click)
	b.pressed.connect(cb)
	return b
