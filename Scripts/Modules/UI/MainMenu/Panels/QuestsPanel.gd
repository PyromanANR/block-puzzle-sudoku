extends RefCounted


static func build(menu: Node, panel: Panel, ui: Dictionary) -> void:
	var ensure_panel_content = ui.get("ensure_panel_content", Callable())
	if ensure_panel_content == Callable():
		return
	var content = ensure_panel_content.call(panel)
	if content == null:
		return

	for quest_name in ["Clear 2 lines", "Place 15 blocks", "Finish 1 run"]:
		var wrap = VBoxContainer.new()
		content.add_child(wrap)
		var q = Label.new()
		q.text = quest_name
		if ui.get("apply_label_text_palette", Callable()) != Callable():
			ui["apply_label_text_palette"].call(q, "body")
		wrap.add_child(q)
		var p = ProgressBar.new()
		p.max_value = 100
		p.value = 35
		p.custom_minimum_size = Vector2(0, 24)
		wrap.add_child(p)
		var state = Label.new()
		state.text = "In progress"
		if ui.get("apply_label_text_palette", Callable()) != Callable():
			ui["apply_label_text_palette"].call(state, "subtitle")
		wrap.add_child(state)
