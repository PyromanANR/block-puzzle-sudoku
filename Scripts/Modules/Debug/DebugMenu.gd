extends RefCounted
class_name DebugMenu


static func build_admin_toggle(parent: VBoxContainer, on_hover: Callable, on_click: Callable, on_toggled: Callable) -> CheckBox:
	var chk_admin_mode = CheckBox.new()
	chk_admin_mode.text = "Admin Mode (No Ads)"
	chk_admin_mode.button_pressed = OS.is_debug_build()
	chk_admin_mode.mouse_entered.connect(on_hover)
	chk_admin_mode.pressed.connect(on_click)
	chk_admin_mode.toggled.connect(on_toggled)
	parent.add_child(chk_admin_mode)
	return chk_admin_mode
