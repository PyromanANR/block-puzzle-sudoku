extends RefCounted
class_name MainMenuPopups

const UIStyle = preload("res://Scripts/Modules/UI/Common/UIStyle.gd")


static func build_difficulty_popup(root: Control, menu_owner: Control, on_hover: Callable, on_click: Callable) -> Dictionary:
	var popup_difficulty = PopupPanel.new()
	popup_difficulty.size = Vector2(520, 380)
	popup_difficulty.visible = false
	root.add_child(popup_difficulty)
	UIStyle.apply_panel_9slice(popup_difficulty)

	var margin = UIStyle.wrap_popup_content(popup_difficulty)
	var v = VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)

	UIStyle.ensure_popup_chrome(popup_difficulty, v, "Difficulty", func(): popup_difficulty.hide(), on_hover, on_click)

	var opt_difficulty = OptionButton.new()
	opt_difficulty.add_item("Easy")
	opt_difficulty.add_item("Medium")
	opt_difficulty.add_item("Hard")
	opt_difficulty.item_selected.connect(Callable(menu_owner, "_on_difficulty_selected"))
	opt_difficulty.mouse_entered.connect(on_hover)
	v.add_child(opt_difficulty)

	var chk_no_mercy = CheckBox.new()
	chk_no_mercy.text = "No Mercy"
	chk_no_mercy.mouse_entered.connect(on_hover)
	chk_no_mercy.pressed.connect(on_click)
	v.add_child(chk_no_mercy)

	var lbl_no_mercy_help = Label.new()
	lbl_no_mercy_help.text = "No Mercy removes all reserve slots (TopSelectable=0)."
	lbl_no_mercy_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIStyle.apply_label_text_palette(lbl_no_mercy_help, "body")
	v.add_child(lbl_no_mercy_help)

	var btns = HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	v.add_child(btns)

	var apply = Button.new()
	apply.text = "Apply"
	UIStyle.apply_button_9slice(apply, "small")
	UIStyle.apply_button_text_palette(apply)
	apply.mouse_entered.connect(on_hover)
	apply.pressed.connect(on_click)
	apply.pressed.connect(Callable(menu_owner, "_on_apply_difficulty"))
	btns.add_child(apply)

	var cancel = Button.new()
	cancel.text = "Cancel"
	UIStyle.apply_button_9slice(cancel, "small")
	UIStyle.apply_button_text_palette(cancel)
	cancel.mouse_entered.connect(on_hover)
	cancel.pressed.connect(on_click)
	cancel.pressed.connect(func(): popup_difficulty.hide())
	btns.add_child(cancel)

	return {
		"popup_difficulty": popup_difficulty,
		"opt_difficulty": opt_difficulty,
		"chk_no_mercy": chk_no_mercy,
		"lbl_no_mercy_help": lbl_no_mercy_help,
	}


static func build_rewards_popup(root: Control, on_hover: Callable, on_click: Callable) -> Dictionary:
	var rewards_popup = PopupPanel.new()
	rewards_popup.size = Vector2(520, 360)
	rewards_popup.visible = false
	root.add_child(rewards_popup)
	UIStyle.apply_panel_9slice(rewards_popup)

	var margin = UIStyle.wrap_popup_content(rewards_popup)
	var v = VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 8)
	margin.add_child(v)

	UIStyle.ensure_popup_chrome(rewards_popup, v, "Rewards", func(): rewards_popup.hide(), on_hover, on_click)

	var rewards_level_label = Label.new()
	UIStyle.apply_label_text_palette(rewards_level_label, "body")
	v.add_child(rewards_level_label)

	var rewards_status_labels: Dictionary = {}
	var milestones = [5, 10, 20, 50]
	for m in milestones:
		var line = Label.new()
		line.name = "milestone_%d" % m
		UIStyle.apply_label_text_palette(line, "body")
		v.add_child(line)
		rewards_status_labels[m] = line

	var close = Button.new()
	close.text = "Close"
	UIStyle.apply_button_9slice(close, "small")
	UIStyle.apply_button_text_palette(close)
	close.mouse_entered.connect(on_hover)
	close.pressed.connect(on_click)
	close.pressed.connect(func(): rewards_popup.hide())
	v.add_child(close)

	return {
		"rewards_popup": rewards_popup,
		"rewards_level_label": rewards_level_label,
		"rewards_status_labels": rewards_status_labels,
	}


static func build_leaderboards_popup(root: Control, menu_owner: Control, on_hover: Callable, on_click: Callable) -> Dictionary:
	var popup_leaderboards = PopupPanel.new()
	popup_leaderboards.size = Vector2(520, 360)
	popup_leaderboards.visible = false
	root.add_child(popup_leaderboards)
	UIStyle.apply_panel_9slice(popup_leaderboards)

	var margin = UIStyle.wrap_popup_content(popup_leaderboards)
	var v = VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 8)
	margin.add_child(v)

	UIStyle.ensure_popup_chrome(popup_leaderboards, v, "Leaderboards", func(): popup_leaderboards.hide(), on_hover, on_click)

	v.add_child(_leaderboard_button("Easy", "easy", menu_owner, on_hover, on_click))
	v.add_child(_leaderboard_button("Medium", "medium", menu_owner, on_hover, on_click))
	v.add_child(_leaderboard_button("Hard", "hard", menu_owner, on_hover, on_click))
	v.add_child(_leaderboard_button("Hard+NoMercy", "hard_plus_no_mercy", menu_owner, on_hover, on_click))

	var close = Button.new()
	close.text = "Close"
	UIStyle.apply_button_9slice(close, "small")
	UIStyle.apply_button_text_palette(close)
	close.mouse_entered.connect(on_hover)
	close.pressed.connect(on_click)
	close.pressed.connect(func(): popup_leaderboards.hide())
	v.add_child(close)

	return {
		"popup_leaderboards": popup_leaderboards,
	}


static func _leaderboard_button(text: String, diff_key: String, menu_owner: Control, on_hover: Callable, on_click: Callable) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(380, 50)
	UIStyle.apply_button_9slice(b, "small")
	UIStyle.apply_button_text_palette(b)
	b.mouse_entered.connect(on_hover)
	b.pressed.connect(on_click)
	b.pressed.connect(func(): menu_owner.call("_on_select_leaderboard", diff_key))
	return b
