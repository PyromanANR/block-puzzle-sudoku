extends RefCounted
class_name MainMenuTopBar


static func build(root: Control, menu_owner: Control, on_rewards: Callable, on_hover: Callable, on_click: Callable) -> Dictionary:
	var btn_player_level = Button.new()
	btn_player_level.text = "Level %d" % menu_owner.call("_get_player_level")
	btn_player_level.custom_minimum_size = Vector2(130, 40)
	btn_player_level.size = Vector2(130, 40)
	btn_player_level.anchor_left = 1.0
	btn_player_level.anchor_right = 1.0
	btn_player_level.anchor_top = 0.0
	btn_player_level.anchor_bottom = 0.0
	btn_player_level.offset_left = -150
	btn_player_level.offset_right = -20
	btn_player_level.offset_top = 20
	btn_player_level.offset_bottom = 60
	btn_player_level.mouse_entered.connect(on_hover)
	btn_player_level.pressed.connect(on_click)
	btn_player_level.pressed.connect(on_rewards)
	root.add_child(btn_player_level)
	return {"btn_player_level": btn_player_level}
