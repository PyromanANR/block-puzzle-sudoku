extends RefCounted
class_name UIStyle


static func stylebox_9slice(path: String) -> StyleBoxTexture:
	if not ResourceLoader.exists(path):
		return null
	var resource = load(path)
	if resource is StyleBoxTexture:
		return resource as StyleBoxTexture
	if resource is StyleBox:
		return null
	if not (resource is Texture2D):
		return null
	var style = StyleBoxTexture.new()
	style.texture = resource as Texture2D
	style.texture_margin_left = 12
	style.texture_margin_right = 12
	style.texture_margin_top = 12
	style.texture_margin_bottom = 12
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return style


static func apply_panel_9slice(panel: Control, panel_9patch_path: String) -> void:
	if panel == null:
		return
	var style = stylebox_9slice(panel_9patch_path)
	if style == null:
		return
	panel.add_theme_stylebox_override("panel", style)


static func apply_button_9slice(button: Button, kind: String, primary_path: String, small_path: String) -> void:
	if button == null:
		return
	var path = primary_path
	if kind == "small":
		path = small_path
	var style = stylebox_9slice(path)
	if style == null:
		return
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style.duplicate())
	button.add_theme_stylebox_override("pressed", style.duplicate())
	button.add_theme_stylebox_override("hover_pressed", style.duplicate())
	button.add_theme_stylebox_override("disabled", style.duplicate())
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.focus_mode = Control.FOCUS_NONE


static func apply_button_text_defaults(button: Button, kind: String) -> void:
	if button == null:
		return
	button.clip_text = true
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	if kind == "primary":
		button.add_theme_constant_override("content_margin_left", 26)
		button.add_theme_constant_override("content_margin_right", 26)
		button.add_theme_constant_override("content_margin_top", 7)
		button.add_theme_constant_override("content_margin_bottom", 7)
		button.add_theme_font_size_override("font_size", 34)
