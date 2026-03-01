extends RefCounted


static func build(menu: Node, panel: Panel, ui: Dictionary) -> void:
	var ensure_panel_content = ui.get("ensure_panel_content", Callable())
	if ensure_panel_content == Callable():
		return
	var content = ensure_panel_content.call(panel)
	if content == null:
		return

	var chips = HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	content.add_child(chips)
	for pair in [["Easy", "easy"], ["Medium", "medium"], ["Hard", "hard"], ["Hard+NoMercy", "hard_plus_no_mercy"]]:
		var tab = Button.new()
		tab.text = pair[0]
		tab.custom_minimum_size = Vector2(0, 48)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if ui.get("apply_button_style", Callable()) != Callable():
			ui["apply_button_style"].call(tab, "small")
		tab.mouse_entered.connect(func() -> void:
			if ui.get("play_hover", Callable()) != Callable():
				ui["play_hover"].call()
		)
		var diff_key = pair[1]
		tab.pressed.connect(func() -> void:
			if ui.get("play_click", Callable()) != Callable():
				ui["play_click"].call()
			if menu.has_method("_on_select_leaderboard"):
				menu.call("_on_select_leaderboard", diff_key)
		)
		chips.add_child(tab)

	var msg = Label.new()
	msg.text = "Rank  Name        Score\n1     ---         ---\n2     ---         ---\n3     ---         ---"
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if ui.get("apply_label_text_palette", Callable()) != Callable():
		ui["apply_label_text_palette"].call(msg, "body")
	content.add_child(msg)

	var sign_in = Button.new()
	sign_in.text = "Play Games: Sign In"
	sign_in.custom_minimum_size = Vector2(0, 52)
	if ui.get("apply_button_style", Callable()) != Callable():
		ui["apply_button_style"].call(sign_in, "small")
	sign_in.mouse_entered.connect(func() -> void:
		if ui.get("play_hover", Callable()) != Callable():
			ui["play_hover"].call()
	)
	sign_in.pressed.connect(func() -> void:
		if ui.get("play_click", Callable()) != Callable():
			ui["play_click"].call()
		if menu.has_method("_on_play_games_sign_in"):
			menu.call("_on_play_games_sign_in")
	)
	content.add_child(sign_in)
