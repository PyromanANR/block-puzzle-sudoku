extends RefCounted
class_name SettingsPanel

const UIStyle = preload("res://Scripts/Modules/UI/Common/UIStyle.gd")

const TARGET_W = 720.0
const TARGET_H = 520.0


static func build(parent: Control, on_close: Callable, config: Dictionary = {}) -> Control:
	var panel = Panel.new()
	panel.name = "SettingsPanel"
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.visible = false
	parent.add_child(panel)
	UIStyle.apply_panel_9slice(panel)
	panel.set_meta("ui_fixed_popup_size", true)
	panel.set_meta("lock_modal_size", true)

	var vp = parent.get_viewport_rect().size
	var max_w = min(TARGET_W, vp.x - 64.0)
	var max_h = min(TARGET_H, vp.y - 64.0)
	max_w = max(max_w, 320.0)
	max_h = max(max_h, 320.0)
	panel.offset_left = -max_w * 0.5
	panel.offset_top = -max_h * 0.5
	panel.offset_right = max_w * 0.5
	panel.offset_bottom = max_h * 0.5
	panel.set_meta("modal_target_size", Vector2(max_w, max_h))

	var wire_button_sfx = config.get("wire_button_sfx", Callable()) as Callable
	var sfx_hover = config.get("sfx_hover", Callable()) as Callable
	var sfx_click = config.get("sfx_click", Callable()) as Callable

	var margin = UIStyle.wrap_popup_content(panel)
	var settings_v = VBoxContainer.new()
	settings_v.name = "SettingsBody"
	settings_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	settings_v.add_theme_constant_override("separation", 10)
	margin.add_child(settings_v)

	UIStyle.ensure_popup_chrome_with_header(panel, settings_v, "Audio Settings", on_close, sfx_hover, sfx_click)
	UIStyle.apply_popup_vertical_offset(panel)

	var audio_content = VBoxContainer.new()
	audio_content.name = "AudioContent"
	audio_content.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	audio_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	audio_content.add_theme_constant_override("separation", 25)
	settings_v.add_child(audio_content)

	# Wider centered content (reduce side margins)
	var content_w = min(600.0, max_w - 40) # was 520 and -80
	audio_content.custom_minimum_size = Vector2(max(content_w, 520.0), 0)

	# Ensure it stays centered
	audio_content.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var chk_music_enabled = CheckBox.new()
	chk_music_enabled.text = "Music Enabled"
	audio_content.add_child(chk_music_enabled)

	var music_row = HBoxContainer.new()
	music_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_row.add_theme_constant_override("separation", 8)
	audio_content.add_child(music_row)
	var music_lbl = Label.new()
	music_lbl.text = "Music Volume"
	UIStyle.apply_label_text_palette(music_lbl, "body")
	music_lbl.custom_minimum_size = Vector2(120, 0)
	music_row.add_child(music_lbl)
	var slider_music_volume = HSlider.new()
	_apply_slider_style(slider_music_volume)
	slider_music_volume.min_value = 0
	slider_music_volume.max_value = 100
	slider_music_volume.step = 1
	slider_music_volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_row.add_child(slider_music_volume)

	var chk_sfx_enabled = CheckBox.new()
	chk_sfx_enabled.text = "SFX Enabled"
	audio_content.add_child(chk_sfx_enabled)

	var sfx_row = HBoxContainer.new()
	sfx_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sfx_row.add_theme_constant_override("separation", 8)
	audio_content.add_child(sfx_row)
	var sfx_lbl = Label.new()
	sfx_lbl.text = "SFX Volume"
	UIStyle.apply_label_text_palette(sfx_lbl, "body")
	sfx_lbl.custom_minimum_size = Vector2(120, 0)
	sfx_row.add_child(sfx_lbl)
	var slider_sfx_volume = HSlider.new()
	slider_sfx_volume.min_value = 0
	slider_sfx_volume.max_value = 100
	slider_sfx_volume.step = 1
	slider_sfx_volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sfx_row.add_child(slider_sfx_volume)


	var close_btn = Button.new()
	close_btn.text = "Cancel"
	close_btn.custom_minimum_size = Vector2(260, 57)
	UIStyle.apply_button_9slice(close_btn, "small")
	UIStyle.apply_button_text_palette(close_btn)
	if wire_button_sfx.is_valid():
		wire_button_sfx.call(close_btn)
	if sfx_hover.is_valid():
		close_btn.mouse_entered.connect(func():
			sfx_hover.call()
		)
	if sfx_click.is_valid():
		close_btn.pressed.connect(func():
			sfx_click.call()
		)
	close_btn.pressed.connect(func():
		if on_close.is_valid():
			on_close.call()
		else:
			panel.visible = false
	)
	var close_center = UIStyle.center_bottom_button(close_btn, 260)
	settings_v.add_child(close_center)
	
	chk_music_enabled.add_theme_font_size_override("font_size", 26)
	music_lbl.add_theme_font_size_override("font_size", 24)
	chk_sfx_enabled.add_theme_font_size_override("font_size", 26)
	sfx_lbl.add_theme_font_size_override("font_size", 24)
	close_btn.add_theme_font_size_override("font_size", 26)

	var sync_state = func() -> void:
		var state = {}
		if config.has("state_getter"):
			state = config["state_getter"].call()
		chk_music_enabled.button_pressed = bool(state.get("music_enabled", true))
		chk_sfx_enabled.button_pressed = bool(state.get("sfx_enabled", true))
		slider_music_volume.value = round(clamp(float(state.get("music_volume", 0.5)), 0.0, 1.0) * 100.0)
		slider_sfx_volume.value = round(clamp(float(state.get("sfx_volume", 1.0)), 0.0, 1.0) * 100.0)

	chk_music_enabled.toggled.connect(func(enabled: bool):
		if config.has("on_music_enabled"):
			config["on_music_enabled"].call(enabled)
	)
	chk_sfx_enabled.toggled.connect(func(enabled: bool):
		if config.has("on_sfx_enabled"):
			config["on_sfx_enabled"].call(enabled)
	)
	slider_music_volume.value_changed.connect(func(value: float):
		if config.has("on_music_volume"):
			config["on_music_volume"].call(value)
	)
	slider_sfx_volume.value_changed.connect(func(value: float):
		if config.has("on_sfx_volume"):
			config["on_sfx_volume"].call(value)
	)

	_apply_slider_style(slider_sfx_volume)
	_apply_checkbox_style(chk_music_enabled)
	_apply_checkbox_style(chk_sfx_enabled)

	panel.set_meta("sync_settings", sync_state)
	sync_state.call()
	return panel
	
static func _apply_slider_style(sl: HSlider) -> void:
	if sl == null:
		return

	# Make the control taller (track thickness)
	sl.custom_minimum_size.y = 34
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# Background of the whole slider track
	var sb_slider := StyleBoxFlat.new()
	sb_slider.bg_color = Color(0.22, 0.24, 0.26, 0.35)
	sb_slider.border_color = Color(0.10, 0.12, 0.14, 0.55)
	sb_slider.corner_radius_top_left = 10
	sb_slider.corner_radius_top_right = 10
	sb_slider.corner_radius_bottom_left = 10
	sb_slider.corner_radius_bottom_right = 10
	sb_slider.content_margin_left = 10
	sb_slider.content_margin_right = 10
	sb_slider.content_margin_top = 12
	sb_slider.content_margin_bottom = 12
	sl.add_theme_stylebox_override("slider", sb_slider)

	# Filled part (left of grabber) - green
	var sb_fill := StyleBoxFlat.new()
	sb_fill.bg_color = Color(0.16, 0.78, 0.88, 0.95)
	sb_fill.corner_radius_top_left = 10
	sb_fill.corner_radius_top_right = 10
	sb_fill.corner_radius_bottom_left = 10
	sb_fill.corner_radius_bottom_right = 10
	sl.add_theme_stylebox_override("grabber_area", sb_fill)

	# Keep highlight same (so it doesn't turn weird on focus/hover)
	var sb_fill_hi := sb_fill.duplicate()
	sl.add_theme_stylebox_override("grabber_area_highlight", sb_fill_hi)

	# Optional: remove focus outline if you don’t want mobile “focus” visuals
	sl.focus_mode = Control.FOCUS_NONE
	
	# --- Grabber (thumb) as a bigger black circle (no external assets) ---
	var grabber_tex = _make_circle_texture(22, 14, Color(0.10, 0.16, 0.22, 1.0), Color(0.10, 0.16, 0.22, 1.0), 2)
	var grabber_hi_tex = _make_circle_texture(32, 16, Color(0.10, 0.16, 0.22, 1.0), Color(0.10, 0.16, 0.22, 1.0), 2)

	sl.add_theme_icon_override("grabber", grabber_tex)
	sl.add_theme_icon_override("grabber_highlight", grabber_hi_tex)
	sl.add_theme_icon_override("grabber_disabled", grabber_tex)



static func _make_circle_texture(size_px: int, radius_px: int, fill: Color, outline: Color, outline_px: int) -> Texture2D:
	var img := Image.create(size_px, size_px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.10, 0.16, 0.22, 1.0))

	var cx := (size_px - 1) * 0.5
	var cy := (size_px - 1) * 0.5
	var r2 := radius_px * radius_px
	var r_in2 = max(0, radius_px - outline_px) * max(0, radius_px - outline_px)

	for y in range(size_px):
		for x in range(size_px):
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d2 := dx * dx + dy * dy
			if d2 <= r2:
				# Outline ring
				if outline_px > 0 and d2 >= r_in2:
					img.set_pixel(x, y, outline)
				else:
					img.set_pixel(x, y, fill)

	return ImageTexture.create_from_image(img)
	
static func _apply_checkbox_style(chk: CheckBox) -> void:
	if chk == null:
		return

	# --- 1) Disable focus/hover behavior (mobile UI) ---
	chk.focus_mode = Control.FOCUS_NONE
	chk.mouse_default_cursor_shape = Control.CURSOR_ARROW

	# Remove any existing hover handlers that may fade alpha
	for c in chk.mouse_entered.get_connections():
		chk.mouse_entered.disconnect(c.callable)
	for c in chk.mouse_exited.get_connections():
		chk.mouse_exited.disconnect(c.callable)

	# Force no-fade on hover (keep fully opaque)
	chk.mouse_entered.connect(func() -> void:
		chk.modulate = Color(1, 1, 1, 1)
		chk.self_modulate = Color(1, 1, 1, 1)
	)
	chk.mouse_exited.connect(func() -> void:
		chk.modulate = Color(1, 1, 1, 1)
		chk.self_modulate = Color(1, 1, 1, 1)
	)

	# Also set immediately (in case it is already faded)
	chk.modulate = Color(1, 1, 1, 1)
	chk.self_modulate = Color(1, 1, 1, 1)

	# --- 2) Make hover styles identical to normal/pressed (backup) ---
	var sb_normal = chk.get_theme_stylebox("normal")
	var sb_pressed = chk.get_theme_stylebox("pressed")
	if sb_pressed == null:
		sb_pressed = sb_normal

	if sb_normal != null:
		chk.add_theme_stylebox_override("normal", sb_normal.duplicate())
		chk.add_theme_stylebox_override("hover", sb_normal.duplicate())
		chk.add_theme_stylebox_override("focus", sb_normal.duplicate())

	if sb_pressed != null:
		chk.add_theme_stylebox_override("pressed", sb_pressed.duplicate())
		chk.add_theme_stylebox_override("hover_pressed", sb_pressed.duplicate())

	# Disabled states too (optional but safe)
	var sb_disabled = chk.get_theme_stylebox("disabled")
	if sb_disabled == null:
		sb_disabled = sb_normal
	if sb_disabled != null:
		chk.add_theme_stylebox_override("disabled", sb_disabled.duplicate())
		chk.add_theme_stylebox_override("disabled_pressed", sb_disabled.duplicate())

	# --- 3) Text colors (keep readable) ---
	chk.add_theme_color_override("font_color", Color(0.18, 0.12, 0.09, 1.0))
	chk.add_theme_color_override("font_hover_color", Color(0.18, 0.12, 0.09, 1.0))
	chk.add_theme_color_override("font_pressed_color", Color(0.18, 0.12, 0.09, 1.0))
	chk.add_theme_color_override("font_disabled_color", Color(0.18, 0.12, 0.09, 0.7))
