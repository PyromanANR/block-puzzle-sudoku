extends RefCounted


static func build(menu: Node, panel: Panel, ui: Dictionary) -> void:
	var ensure_panel_content = ui.get("ensure_panel_content", Callable())
	if ensure_panel_content == Callable():
		return
	var content = ensure_panel_content.call(panel)
	if content == null:
		return

	for item_name in ["Remove Ads", "Sudoku Pack", "Rome Pack"]:
		var card = Panel.new()
		card.custom_minimum_size = Vector2(0, 96)
		content.add_child(card)
		if ui.get("apply_panel_style", Callable()) != Callable():
			ui["apply_panel_style"].call(card)
		var label = Label.new()
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.offset_left = 12
		label.offset_top = 12
		label.text = "%s\nComing soon" % item_name
		if ui.get("apply_label_text_palette", Callable()) != Callable():
			ui["apply_label_text_palette"].call(label, "body")
		card.add_child(label)
