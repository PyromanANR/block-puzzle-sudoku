extends RefCounted

const PAGE_FONT_SIZE = 28


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

	var pad_l = int(ui.get("FAQ_PAD_L", 18))
	var pad_r = int(ui.get("FAQ_PAD_R", 18))
	var pad_t = int(ui.get("FAQ_PAD_T", 16))
	var pad_b = int(ui.get("FAQ_PAD_B", 16))
	var swipe_threshold = float(ui.get("FAQ_SWIPE_THRESHOLD", 60.0))

	var root = MarginContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("margin_left", pad_l)
	root.add_theme_constant_override("margin_top", pad_t)
	root.add_theme_constant_override("margin_right", pad_r)
	root.add_theme_constant_override("margin_bottom", pad_b)
	body_v.add_child(root)

	var v = VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	root.add_child(v)

	var tab_host = TabContainer.new()
	tab_host.tabs_visible = false
	tab_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_host.clip_contents = true
	v.add_child(tab_host)

	var faq_pages = [
		{"title":"What is this game?", "body":"Place offered blocks onto the board to fill lines and 3x3 areas. Make smart placements and keep space open for future shapes.", "image":"res://Assets/UI/faq/faq_1.png"},
		{"title":"Drop Zone", "body":"Drop Zone is where incoming shapes appear. Plan around upcoming pieces and avoid locking yourself out of legal placements.", "image":"res://Assets/UI/faq/faq_2.png"},
		{"title":"Board (Sudoku clear rules)", "body":"Clear full rows, full columns, and full 3x3 boxes. Combining multiple clears at once gives better momentum and score.", "image":"res://Assets/UI/faq/faq_3.png"},
		{"title":"Well (benefits)", "body":"The Well stores utility items and progress tools. Use it to stabilize difficult runs and maintain board control.", "image":"res://Assets/UI/faq/faq_4.png"},
		{"title":"Time Warp (hourglass)", "body":"Time Warp can slow pressure moments and gives breathing room to decide your next move when the board is tight.", "image":"res://Assets/UI/faq/faq_5.png"},
		{"title":"Special blocks: Stone", "body":"Stone blocks are obstacles that require repeated clears around them to break. Prioritize nearby clears early.", "image":"res://Assets/UI/faq/faq_6.png"},
		{"title":"Skills", "body":"Skills provide tactical effects to recover from bad situations or extend combos. Use them deliberately for maximum value.", "image":"res://Assets/UI/faq/faq_7.png"}
	]

	var load_icon_any = ui.get("load_icon_any", Callable())
	var apply_label_text_palette = ui.get("apply_label_text_palette", Callable())
	for i in range(faq_pages.size()):
		var page = faq_pages[i]
		tab_host.add_child(_build_faq_page(page["title"], page["body"], page["image"], i + 1, pad_l, pad_r, pad_t, pad_b, load_icon_any, apply_label_text_palette))

	var nav = _build_nav_row(tab_host, faq_pages.size(), ui)
	v.add_child(nav)
	_update_page_buttons(nav.get_meta("page_buttons"), tab_host.current_tab)

	var swipe_state = {"active":false, "start":Vector2.ZERO}
	tab_host.gui_input.connect(func(event: InputEvent) -> void:
		_on_swipe_input(event, tab_host, swipe_state, swipe_threshold)
	)
	tab_host.tab_changed.connect(func(idx: int) -> void:
		_update_page_buttons(nav.get_meta("page_buttons"), idx)
	)


static func _build_nav_row(tab_host: TabContainer, total_pages: int, ui: Dictionary) -> HBoxContainer:
	var apply_button_style = ui.get("apply_button_style", Callable())
	var play_hover = ui.get("play_hover", Callable())
	var play_click = ui.get("play_click", Callable())

	var nav = HBoxContainer.new()
	nav.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_theme_constant_override("separation", 8)

	var prev = Button.new()
	prev.text = "◀"
	prev.custom_minimum_size = Vector2(72, 48)
	if apply_button_style != Callable():
		apply_button_style.call(prev, "small")
	prev.mouse_entered.connect(func() -> void:
		if play_hover != Callable():
			play_hover.call()
	)
	prev.pressed.connect(func() -> void:
		if play_click != Callable():
			play_click.call()
		tab_host.current_tab = clamp(tab_host.current_tab - 1, 0, total_pages - 1)
	)
	nav.add_child(prev)

	var pages_center = HBoxContainer.new()
	pages_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages_center.alignment = BoxContainer.ALIGNMENT_CENTER
	pages_center.add_theme_constant_override("separation", 6)
	nav.add_child(pages_center)

	var page_buttons: Array = []
	for i in range(total_pages):
		var page_btn = Button.new()
		page_btn.text = str(i + 1)
		page_btn.custom_minimum_size = Vector2(52, 48)
		if apply_button_style != Callable():
			apply_button_style.call(page_btn, "small")
		page_btn.mouse_entered.connect(func() -> void:
			if play_hover != Callable():
				play_hover.call()
		)
		var target_index = i
		page_btn.pressed.connect(func() -> void:
			if play_click != Callable():
				play_click.call()
			tab_host.current_tab = target_index
		)
		pages_center.add_child(page_btn)
		page_buttons.append(page_btn)

	var next = Button.new()
	next.text = "▶"
	next.custom_minimum_size = Vector2(72, 48)
	if apply_button_style != Callable():
		apply_button_style.call(next, "small")
	next.mouse_entered.connect(func() -> void:
		if play_hover != Callable():
			play_hover.call()
	)
	next.pressed.connect(func() -> void:
		if play_click != Callable():
			play_click.call()
		tab_host.current_tab = clamp(tab_host.current_tab + 1, 0, total_pages - 1)
	)
	nav.add_child(next)
	nav.set_meta("page_buttons", page_buttons)
	return nav


static func _update_page_buttons(page_buttons: Variant, active_index: int) -> void:
	if not (page_buttons is Array):
		return
	for i in range((page_buttons as Array).size()):
		var btn = (page_buttons as Array)[i]
		if not (btn is Button):
			continue
		(btn as Button).add_theme_color_override("font_color", Color(0, 0, 0, 1) if i == active_index else Color(0.35, 0.35, 0.35, 1))
		(btn as Button).add_theme_constant_override("outline_size", 0 if i == active_index else 1)


static func _on_swipe_input(event: InputEvent, tab_host: TabContainer, swipe_state: Dictionary, swipe_threshold: float) -> void:
	if event is InputEventScreenTouch:
		var touch = event as InputEventScreenTouch
		if touch.pressed:
			swipe_state["active"] = true
			swipe_state["start"] = touch.position
		elif bool(swipe_state.get("active", false)):
			swipe_state["active"] = false
			_handle_swipe_delta(touch.position - swipe_state.get("start", Vector2.ZERO), tab_host, swipe_threshold)
	elif event is InputEventMouseButton:
		var mouse_button = event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			if mouse_button.pressed:
				swipe_state["active"] = true
				swipe_state["start"] = mouse_button.position
			elif bool(swipe_state.get("active", false)):
				swipe_state["active"] = false
				_handle_swipe_delta(mouse_button.position - swipe_state.get("start", Vector2.ZERO), tab_host, swipe_threshold)


static func _handle_swipe_delta(delta: Vector2, tab_host: TabContainer, swipe_threshold: float) -> void:
	if abs(delta.x) <= swipe_threshold:
		return
	if abs(delta.x) <= abs(delta.y):
		return
	if delta.x < 0:
		tab_host.current_tab = clamp(tab_host.current_tab + 1, 0, tab_host.get_tab_count() - 1)
	else:
		tab_host.current_tab = clamp(tab_host.current_tab - 1, 0, tab_host.get_tab_count() - 1)


static func _build_faq_page(title_text: String, body_text: String, image_path: String, page_index: int, pad_l: int, pad_r: int, pad_t: int, pad_b: int, load_icon_any: Callable, apply_label_text_palette: Callable) -> Control:
	var page = PanelContainer.new()
	page.name = "FaqPage%d" % page_index
	var page_style = StyleBoxFlat.new()
	page_style.bg_color = Color(0.96, 0.93, 0.86, 0.98)
	page_style.border_color = Color(0.45, 0.36, 0.24, 0.65)
	page_style.border_width_left = 2
	page_style.border_width_top = 2
	page_style.border_width_right = 2
	page_style.border_width_bottom = 2
	page_style.corner_radius_top_left = 10
	page_style.corner_radius_top_right = 10
	page_style.corner_radius_bottom_left = 10
	page_style.corner_radius_bottom_right = 10
	page_style.shadow_color = Color(0, 0, 0, 0.18)
	page_style.shadow_size = 6
	page_style.shadow_offset = Vector2(0, 2)
	page.add_theme_stylebox_override("panel", page_style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", pad_l)
	margin.add_theme_constant_override("margin_top", pad_t)
	margin.add_theme_constant_override("margin_right", pad_r)
	margin.add_theme_constant_override("margin_bottom", pad_b)
	page.add_child(margin)

	var v = VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)

	var title = Label.new()
	title.text = title_text
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", PAGE_FONT_SIZE)
	title.add_theme_color_override("font_color", Color(0.14, 0.10, 0.06, 1.0))
	v.add_child(title)

	var image_holder = Panel.new()
	image_holder.custom_minimum_size = Vector2(0, 230)
	image_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var image_style = StyleBoxFlat.new()
	image_style.bg_color = Color(1.0, 1.0, 1.0, 0.82)
	image_style.border_color = Color(0.3, 0.3, 0.3, 0.3)
	image_style.border_width_left = 1
	image_style.border_width_top = 1
	image_style.border_width_right = 1
	image_style.border_width_bottom = 1
	image_style.corner_radius_top_left = 8
	image_style.corner_radius_top_right = 8
	image_style.corner_radius_bottom_left = 8
	image_style.corner_radius_bottom_right = 8
	image_holder.add_theme_stylebox_override("panel", image_style)
	v.add_child(image_holder)

	var image_rect = TextureRect.new()
	image_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image_holder.add_child(image_rect)

	var image_tex = null
	if load_icon_any != Callable():
		image_tex = load_icon_any.call(image_path)
	if image_tex != null:
		image_rect.texture = image_tex
	else:
		var placeholder = Label.new()
		placeholder.text = "Image placeholder: faq_%d.png" % page_index
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		placeholder.add_theme_color_override("font_color", Color(0.2, 0.2, 0.2, 0.85))
		image_holder.add_child(placeholder)

	var body = Label.new()
	body.text = body_text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("font_size", 22)
	body.add_theme_color_override("font_color", Color(0.14, 0.10, 0.06, 1.0))
	if apply_label_text_palette != Callable():
		apply_label_text_palette.call(body, "body")
	v.add_child(body)

	return page
