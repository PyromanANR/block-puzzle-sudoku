extends RefCounted


static func build(menu: Node, panel: Panel, ui: Dictionary) -> void:
	var ensure_panel_content = ui.get("ensure_panel_content", Callable())
	if ensure_panel_content == Callable():
		return
	var content = ensure_panel_content.call(panel)
	if content == null:
		return

	var scroll = content.get_parent()
	if scroll == null:
		return
	var body = scroll.get_parent()
	if not (body is VBoxContainer):
		return
	var body_v = body as VBoxContainer
	body_v.remove_child(scroll)
	scroll.queue_free()

	var root = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	body_v.add_child(root)

	var tabs_row = HBoxContainer.new()
	tabs_row.add_theme_constant_override("separation", 8)
	root.add_child(tabs_row)

	var tab_host = TabContainer.new()
	tab_host.tabs_visible = false
	tab_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tab_host)

	var pages = [
		{"title":"Sudoku Style Skin", "subtitle":"Classic Sudoku-inspired look", "key":"sudoku"},
		{"title":"Legacy of Rome", "subtitle":"Roman-themed visual set", "key":"rome"}
	]

	var buttons: Array = []
	for i in range(pages.size()):
		var cfg = pages[i]
		var b = Button.new()
		b.text = cfg["title"]
		b.custom_minimum_size = Vector2(0, 48)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if ui.get("apply_button_style", Callable()) != Callable():
			ui["apply_button_style"].call(b, "small")
		b.mouse_entered.connect(func() -> void:
			if ui.get("play_hover", Callable()) != Callable():
				ui["play_hover"].call()
		)
		var index = i
		b.pressed.connect(func() -> void:
			if ui.get("play_click", Callable()) != Callable():
				ui["play_click"].call()
			tab_host.current_tab = index
			_update_tab_button_state(buttons, tab_host.current_tab)
		)
		tabs_row.add_child(b)
		buttons.append(b)

		var page_root = ScrollContainer.new()
		page_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tab_host.add_child(page_root)

		var page_content = VBoxContainer.new()
		page_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		page_content.add_theme_constant_override("separation", 10)
		page_root.add_child(page_content)

		_build_skin_section(page_content, cfg["title"], cfg["subtitle"], cfg["key"], ui)

	tab_host.tab_changed.connect(func(idx: int) -> void:
		_update_tab_button_state(buttons, idx)
	)
	_update_tab_button_state(buttons, 0)

	var swipe_state = {"active":false, "start":Vector2.ZERO}
	tab_host.gui_input.connect(func(event: InputEvent) -> void:
		_on_swipe_input(event, tab_host, swipe_state)
	)


static func _build_skin_section(content: VBoxContainer, section_title: String, section_subtitle: String, section_key: String, ui: Dictionary) -> void:
	if content == null:
		return
	var card = Panel.new()
	if ui.get("apply_panel_style", Callable()) != Callable():
		ui["apply_panel_style"].call(card)
	content.add_child(card)

	var margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	card.add_child(margin)

	var v = VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)

	var title = Label.new()
	title.text = section_title
	title.add_theme_font_size_override("font_size", 30)
	if ui.get("apply_label_text_palette", Callable()) != Callable():
		ui["apply_label_text_palette"].call(title, "body")
	v.add_child(title)

	var subtitle = Label.new()
	subtitle.text = section_subtitle
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if ui.get("apply_label_text_palette", Callable()) != Callable():
		ui["apply_label_text_palette"].call(subtitle, "subtitle")
	v.add_child(subtitle)

	_build_skin_item_row(v, "Title art", "res://Assets/UI/skins/%s/title.png" % section_key, ui)
	_build_skin_item_row(v, "Game background", "res://Assets/UI/skins/%s/bg.png" % section_key, ui)
	_build_skin_item_row(v, "Block pieces", "res://Assets/UI/skins/%s/blocks.png" % section_key, ui)
	_build_skin_item_row(v, "Board background", "res://Assets/UI/skins/%s/board.png" % section_key, ui)
	_build_skin_item_row(v, "Well + Drop Zone background", "res://Assets/UI/skins/%s/well.png" % section_key, ui)


static func _build_skin_item_row(parent: VBoxContainer, item_name: String, preview_path: String, ui: Dictionary) -> void:
	if parent == null:
		return
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var label = Label.new()
	label.text = item_name
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if ui.get("apply_label_text_palette", Callable()) != Callable():
		ui["apply_label_text_palette"].call(label, "body")
	row.add_child(label)

	var preview = Panel.new()
	preview.custom_minimum_size = Vector2(120, 68)
	preview.size_flags_horizontal = Control.SIZE_SHRINK_END
	if ui.get("apply_panel_style", Callable()) != Callable():
		ui["apply_panel_style"].call(preview)
	row.add_child(preview)

	var preview_tex = TextureRect.new()
	preview_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.add_child(preview_tex)

	var tex = null
	if ui.get("load_icon_any", Callable()) != Callable():
		tex = ui["load_icon_any"].call(preview_path)
	if tex != null:
		preview_tex.texture = tex
	else:
		var ph = Label.new()
		ph.text = "Missing preview"
		ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if ui.get("apply_label_text_palette", Callable()) != Callable():
			ui["apply_label_text_palette"].call(ph, "subtitle")
		preview.add_child(ph)

	var btn = Button.new()
	btn.text = "Equip"
	btn.custom_minimum_size = Vector2(96, 44)
	if ui.get("apply_button_style", Callable()) != Callable():
		ui["apply_button_style"].call(btn, "small")
	btn.mouse_entered.connect(func() -> void:
		if ui.get("play_hover", Callable()) != Callable():
			ui["play_hover"].call()
	)
	btn.pressed.connect(func() -> void:
		if ui.get("play_click", Callable()) != Callable():
			ui["play_click"].call()
		if ui.get("show_message", Callable()) != Callable():
			ui["show_message"].call("Skins", "Skin action pending: %s" % item_name)
	)
	row.add_child(btn)


static func _update_tab_button_state(buttons: Array, active_index: int) -> void:
	for i in range(buttons.size()):
		var b = buttons[i]
		if not (b is Button):
			continue
		(b as Button).add_theme_color_override("font_color", Color(0, 0, 0, 1) if i == active_index else Color(0.35, 0.35, 0.35, 1))


static func _on_swipe_input(event: InputEvent, tab_host: TabContainer, swipe_state: Dictionary) -> void:
	if event is InputEventScreenTouch:
		var touch = event as InputEventScreenTouch
		if touch.pressed:
			swipe_state["active"] = true
			swipe_state["start"] = touch.position
		elif bool(swipe_state.get("active", false)):
			swipe_state["active"] = false
			_handle_swipe_delta(touch.position - swipe_state.get("start", Vector2.ZERO), tab_host)
	elif event is InputEventMouseButton:
		var mouse_button = event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			if mouse_button.pressed:
				swipe_state["active"] = true
				swipe_state["start"] = mouse_button.position
			elif bool(swipe_state.get("active", false)):
				swipe_state["active"] = false
				_handle_swipe_delta(mouse_button.position - swipe_state.get("start", Vector2.ZERO), tab_host)


static func _handle_swipe_delta(delta: Vector2, tab_host: TabContainer) -> void:
	if abs(delta.x) <= 60.0:
		return
	if abs(delta.x) <= abs(delta.y):
		return
	if delta.x < 0:
		tab_host.current_tab = clamp(tab_host.current_tab + 1, 0, tab_host.get_tab_count() - 1)
	else:
		tab_host.current_tab = clamp(tab_host.current_tab - 1, 0, tab_host.get_tab_count() - 1)
