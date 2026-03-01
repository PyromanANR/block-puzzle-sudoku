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

	var tab_host = TabContainer.new()
	tab_host.tabs_visible = false
	tab_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_host.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var tabs_row = HBoxContainer.new()
	tabs_row.add_theme_constant_override("separation", 8)
	root.add_child(tabs_row)
	root.add_child(tab_host)

	var tab_buttons: Array = []
	for tab_name in ["Skills", "Rewards Track"]:
		var btn = Button.new()
		btn.text = tab_name
		btn.custom_minimum_size = Vector2(0, 48)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if ui.get("apply_button_style", Callable()) != Callable():
			ui["apply_button_style"].call(btn, "small")
		tabs_row.add_child(btn)
		tab_buttons.append(btn)

	var skills_page = VBoxContainer.new()
	skills_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skills_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_host.add_child(skills_page)
	_build_skills_page(skills_page, ui)

	var rewards_track_page = CenterContainer.new()
	rewards_track_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rewards_track_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_host.add_child(rewards_track_page)

	var track_content = VBoxContainer.new()
	track_content.visible = false
	rewards_track_page.add_child(track_content)

	var in_progress = Label.new()
	in_progress.text = "In progress"
	in_progress.add_theme_font_size_override("font_size", 36)
	in_progress.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	rewards_track_page.add_child(in_progress)

	for i in range(tab_buttons.size()):
		var idx = i
		var btn = tab_buttons[i]
		btn.mouse_entered.connect(func() -> void:
			if ui.get("play_hover", Callable()) != Callable():
				ui["play_hover"].call()
		)
		btn.pressed.connect(func() -> void:
			if ui.get("play_click", Callable()) != Callable():
				ui["play_click"].call()
			tab_host.current_tab = idx
			_update_top_tabs(tab_buttons, tab_host.current_tab)
		)

	tab_host.tab_changed.connect(func(idx: int) -> void:
		_update_top_tabs(tab_buttons, idx)
	)
	_update_top_tabs(tab_buttons, 0)


static func _build_skills_page(parent: VBoxContainer, ui: Dictionary) -> void:
	var skill_host = TabContainer.new()
	skill_host.tabs_visible = false
	skill_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skill_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(skill_host)

	var skills = [
		{"name":"Freeze", "charges":"lvl 0/1/2: 1 / 2 / 4", "desc":"Level 0: briefly freezes incoming pressure for safer planning."},
		{"name":"Clear Board", "charges":"lvl 0/1/2: 1 / 2 / 3", "desc":"Level 0: clears a selected board section to restore space."},
		{"name":"Safe Well", "charges":"lvl 0/1/2: 1 / 1 / 2", "desc":"Level 0: protects the well from risky fills for a short time."}
	]

	for skill in skills:
		skill_host.add_child(_build_skill_card(skill, ui))

	var is_windows = OS.get_name() == "Windows"
	if is_windows:
		var nav = HBoxContainer.new()
		nav.add_theme_constant_override("separation", 8)
		nav.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		parent.add_child(nav)

		var prev = Button.new()
		prev.text = "Prev"
		prev.custom_minimum_size = Vector2(96, 44)
		if ui.get("apply_button_style", Callable()) != Callable():
			ui["apply_button_style"].call(prev, "small")
		nav.add_child(prev)

		var pages = HBoxContainer.new()
		pages.alignment = BoxContainer.ALIGNMENT_CENTER
		pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pages.add_theme_constant_override("separation", 6)
		nav.add_child(pages)

		var page_buttons: Array = []
		for i in range(skills.size()):
			var pb = Button.new()
			pb.text = str(i + 1)
			pb.custom_minimum_size = Vector2(44, 44)
			if ui.get("apply_button_style", Callable()) != Callable():
				ui["apply_button_style"].call(pb, "small")
			pages.add_child(pb)
			page_buttons.append(pb)
			var idx = i
			pb.pressed.connect(func() -> void:
				skill_host.current_tab = idx
				_update_page_buttons(page_buttons, idx)
			)

		var next = Button.new()
		next.text = "Next"
		next.custom_minimum_size = Vector2(96, 44)
		if ui.get("apply_button_style", Callable()) != Callable():
			ui["apply_button_style"].call(next, "small")
		nav.add_child(next)

		prev.pressed.connect(func() -> void:
			skill_host.current_tab = clamp(skill_host.current_tab - 1, 0, skill_host.get_tab_count() - 1)
		)
		next.pressed.connect(func() -> void:
			skill_host.current_tab = clamp(skill_host.current_tab + 1, 0, skill_host.get_tab_count() - 1)
		)
		skill_host.tab_changed.connect(func(idx: int) -> void:
			_update_page_buttons(page_buttons, idx)
		)
		_update_page_buttons(page_buttons, 0)

	var swipe_state = {"active":false, "start":Vector2.ZERO}
	skill_host.gui_input.connect(func(event: InputEvent) -> void:
		_on_swipe_input(event, skill_host, swipe_state)
	)


static func _build_skill_card(skill: Dictionary, ui: Dictionary) -> Control:
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 14)

	var left = VBoxContainer.new()
	left.custom_minimum_size = Vector2(280, 0)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	row.add_child(left)

	var preview_panel = Panel.new()
	preview_panel.custom_minimum_size = Vector2(0, 220)
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if ui.get("apply_panel_style", Callable()) != Callable():
		ui["apply_panel_style"].call(preview_panel)
	left.add_child(preview_panel)

	var preview_label = Label.new()
	preview_label.text = "Preview"
	preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_panel.add_child(preview_label)

	var skill_name = Label.new()
	skill_name.text = skill["name"]
	skill_name.add_theme_font_size_override("font_size", 26)
	skill_name.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	left.add_child(skill_name)

	var charges = Label.new()
	charges.text = skill["charges"]
	charges.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	charges.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	left.add_child(charges)

	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(right)

	var desc_title = Label.new()
	desc_title.text = "Description"
	desc_title.add_theme_font_size_override("font_size", 24)
	desc_title.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	right.add_child(desc_title)

	var desc = Label.new()
	desc.text = skill["desc"]
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	right.add_child(desc)

	return row


static func _update_top_tabs(tab_buttons: Array, active_idx: int) -> void:
	for i in range(tab_buttons.size()):
		var b = tab_buttons[i]
		if b is Button:
			(b as Button).add_theme_color_override("font_color", Color(0, 0, 0, 1) if i == active_idx else Color(0.35, 0.35, 0.35, 1))


static func _update_page_buttons(buttons: Array, active_idx: int) -> void:
	for i in range(buttons.size()):
		if buttons[i] is Button:
			(buttons[i] as Button).add_theme_color_override("font_color", Color(0, 0, 0, 1) if i == active_idx else Color(0.35, 0.35, 0.35, 1))


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
