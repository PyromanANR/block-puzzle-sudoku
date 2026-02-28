extends RefCounted
class_name UIStyle

const PANEL_9PATCH = "res://Assets/UI/9patch/panel_default.png"
const BTN_PRIMARY_9PATCH = "res://Assets/UI/9patch/button_primary.png"
const BTN_SMALL_9PATCH = "res://Assets/UI/9patch/button_small.png"
const TOP_CHIP_9PATCH = "res://Assets/UI/9patch/top_chip.png"
const CLOSE_ICON_TRES = "res://Assets/UI/icons/menu/icon_close.tres"

const POPUP_PAD_LR = 36
const POPUP_PAD_TOP = 34
const POPUP_PAD_BOTTOM = 36
const CLOSE_BTN_W = 72
const CLOSE_BTN_H = 62
const CLOSE_INSET_X = 12
const CLOSE_INSET_Y = 10


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


static func apply_panel_9slice(panel: Control) -> void:
	if panel == null:
		return
	var style = stylebox_9slice(PANEL_9PATCH)
	if style == null:
		return
	panel.add_theme_stylebox_override("panel", style)


static func apply_button_9slice(btn: Button, kind: String) -> void:
	if btn == null:
		return
	var path = BTN_PRIMARY_9PATCH
	if kind == "small":
		path = BTN_SMALL_9PATCH
	var style = stylebox_9slice(path)
	if style == null:
		return
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style.duplicate())
	btn.add_theme_stylebox_override("pressed", style.duplicate())
	btn.add_theme_stylebox_override("hover_pressed", style.duplicate())
	btn.add_theme_stylebox_override("disabled", style.duplicate())
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.focus_mode = Control.FOCUS_NONE


static func apply_button_text_palette(btn: Button) -> void:
	if btn == null:
		return
	var base = Color(0.10, 0.07, 0.05, 1.0)
	btn.add_theme_color_override("font_color", base)
	btn.add_theme_color_override("font_hover_color", base)
	btn.add_theme_color_override("font_pressed_color", base)
	btn.add_theme_color_override("font_hover_pressed_color", base)
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.add_theme_constant_override("outline_size", 2)
	btn.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 0.22))


static func wrap_popup_content(root_panel: Control) -> MarginContainer:
	if root_panel == null:
		return null
	var margin = root_panel.get_node_or_null("PopupMargin") as MarginContainer
	if margin != null and (not is_instance_valid(margin) or margin.is_queued_for_deletion()):
		margin = null
	if margin == null:
		margin = MarginContainer.new()
		margin.name = "PopupMargin"
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var children = root_panel.get_children()
		for child in children:
			if child == margin:
				continue
			if String(child.name) == "PopupCloseOverlay" or String(child.name) == "PopupHeaderOverlay":
				continue
			if child is Node and not child.is_queued_for_deletion():
				root_panel.remove_child(child)
				margin.add_child(child)
		root_panel.add_child(margin)
	margin.add_theme_constant_override("margin_left", POPUP_PAD_LR)
	margin.add_theme_constant_override("margin_right", POPUP_PAD_LR)
	margin.add_theme_constant_override("margin_top", POPUP_PAD_TOP)
	margin.add_theme_constant_override("margin_bottom", POPUP_PAD_BOTTOM)
	return margin


static func apply_label_text_palette(label: Label, kind: String = "body") -> void:
	if label == null:
		return
	var color = Color(0.18, 0.12, 0.09, 1.0)
	var outline = Color(1.0, 1.0, 1.0, 0.16)
	var outline_size = 1
	if kind == "title":
		color = Color(0.14, 0.09, 0.07, 1.0)
		outline = Color(1.0, 1.0, 1.0, 0.26)
		outline_size = 2
	elif kind == "subtitle":
		color = Color(0.19, 0.13, 0.10, 1.0)
		outline = Color(1.0, 1.0, 1.0, 0.18)
		outline_size = 1
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", outline)
	label.add_theme_constant_override("outline_size", outline_size)


static func apply_close_icon(btn: Button) -> void:
	if btn == null:
		return
	btn.text = "✕"
	btn.icon = null
	if not ResourceLoader.exists(CLOSE_ICON_TRES):
		return
	var icon_texture = load(CLOSE_ICON_TRES)
	if not (icon_texture is Texture2D):
		return
	btn.icon = icon_texture
	btn.text = ""
	btn.expand_icon = true
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER


static func ensure_popup_chrome(panel: Control, content_root: Control, title_text: String, on_close: Callable, sfx_hover: Callable = Callable(), sfx_click: Callable = Callable()) -> void:
	if panel == null or content_root == null:
		return
	var header = content_root.get_node_or_null("PopupHeader") as HBoxContainer
	if header == null:
		header = HBoxContainer.new()
		header.name = "PopupHeader"
		header.add_theme_constant_override("separation", 8)
		content_root.add_child(header)
		content_root.move_child(header, 0)

	var left_spacer = header.get_node_or_null("LeftSpacer") as Control
	if left_spacer == null:
		left_spacer = Control.new()
		left_spacer.name = "LeftSpacer"
		left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(left_spacer)

	var title = header.get_node_or_null("PopupTitle") as Label
	if title == null:
		title = Label.new()
		title.name = "PopupTitle"
		title.add_theme_font_size_override("font_size", 30)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.add_child(title)
	title.text = title_text
	apply_label_text_palette(title, "title")

	var right_spacer = header.get_node_or_null("RightSpacer") as Control
	if right_spacer == null:
		right_spacer = Control.new()
		right_spacer.name = "RightSpacer"
		right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(right_spacer)

	var close_btn = panel.get_node_or_null("PopupCloseOverlay") as Button
	if close_btn == null:
		close_btn = Button.new()
		close_btn.name = "PopupCloseOverlay"
		panel.add_child(close_btn)
	close_btn.anchor_left = 1.0
	close_btn.anchor_right = 1.0
	close_btn.anchor_top = 0.0
	close_btn.anchor_bottom = 0.0
	close_btn.offset_left = -float(CLOSE_INSET_X + CLOSE_BTN_W)
	close_btn.offset_top = float(CLOSE_INSET_Y)
	close_btn.offset_right = -float(CLOSE_INSET_X)
	close_btn.offset_bottom = float(CLOSE_INSET_Y + CLOSE_BTN_H)
	close_btn.custom_minimum_size = Vector2(CLOSE_BTN_W, CLOSE_BTN_H)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	close_btn.z_index = 30
	apply_button_9slice(close_btn, "small")
	apply_button_text_palette(close_btn)
	apply_close_icon(close_btn)
	for conn in close_btn.pressed.get_connections():
		close_btn.pressed.disconnect(conn.callable)
	close_btn.pressed.connect(func():
		if on_close.is_valid():
			on_close.call()
	)
	if sfx_hover.is_valid():
		for conn in close_btn.mouse_entered.get_connections():
			close_btn.mouse_entered.disconnect(conn.callable)
		close_btn.mouse_entered.connect(func():
			sfx_hover.call()
		)
	if sfx_click.is_valid():
		close_btn.pressed.connect(func():
			sfx_click.call()
		)


static func center_bottom_button(button: Button, width_px: int) -> CenterContainer:
	if button == null:
		return null
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.custom_minimum_size = Vector2(width_px, button.custom_minimum_size.y)
	var center = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_child(button)
	return center
