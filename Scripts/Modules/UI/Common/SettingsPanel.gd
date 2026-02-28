extends RefCounted
class_name SettingsPanel

const PANEL_SIZE = Vector2(420, 300)
const UIStyle = preload("res://Scripts/Modules/UI/Common/UIStyle.gd")
const PANEL_9PATCH_PATH = "res://Assets/UI/9patch/panel_default.png"
const BUTTON_PRIMARY_9PATCH_PATH = "res://Assets/UI/9patch/button_primary.png"
const BUTTON_SMALL_9PATCH_PATH = "res://Assets/UI/9patch/button_small.png"

static func build(parent: Control, on_close: Callable, config: Dictionary = {}) -> Control:
	var center = CenterContainer.new()
	center.name = "SettingsPanel"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_STOP
	center.visible = false
	parent.add_child(center)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = PANEL_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)
	UIStyle.apply_panel_9slice(panel, PANEL_9PATCH_PATH)

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var settings_v = VBoxContainer.new()
	settings_v.add_theme_constant_override("separation", 10)
	margin.add_child(settings_v)

	var settings_title = Label.new()
	settings_title.text = "Audio Settings"
	settings_title.add_theme_font_size_override("font_size", 24)
	settings_v.add_child(settings_title)

	var chk_music_enabled = CheckBox.new()
	chk_music_enabled.text = "Music Enabled"
	settings_v.add_child(chk_music_enabled)

	var music_row = HBoxContainer.new()
	music_row.add_theme_constant_override("separation", 8)
	settings_v.add_child(music_row)
	var music_lbl = Label.new()
	music_lbl.text = "Music Volume"
	music_lbl.custom_minimum_size = Vector2(120, 0)
	music_row.add_child(music_lbl)
	var slider_music_volume = HSlider.new()
	slider_music_volume.min_value = 0
	slider_music_volume.max_value = 100
	slider_music_volume.step = 1
	slider_music_volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_row.add_child(slider_music_volume)

	var chk_sfx_enabled = CheckBox.new()
	chk_sfx_enabled.text = "SFX Enabled"
	settings_v.add_child(chk_sfx_enabled)

	var sfx_row = HBoxContainer.new()
	sfx_row.add_theme_constant_override("separation", 8)
	settings_v.add_child(sfx_row)
	var sfx_lbl = Label.new()
	sfx_lbl.text = "SFX Volume"
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
	UIStyle.apply_button_9slice(close_btn, "small", BUTTON_PRIMARY_9PATCH_PATH, BUTTON_SMALL_9PATCH_PATH)
	close_btn.pressed.connect(func():
		if on_close.is_valid():
			on_close.call()
		else:
			center.visible = false
	)
	settings_v.add_child(close_btn)

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

	center.set_meta("sync_settings", sync_state)
	sync_state.call()
	return center
