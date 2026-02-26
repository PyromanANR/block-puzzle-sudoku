extends RefCounted
class_name SkinAssets

const DEFAULT_SKIN_ID = "Default"
const BASE_PATH = "res://Assets/Skins"


static func icon_path(skin_id: String, icon_name: String) -> String:
	return _resolve_or_default(skin_id, "UI/Icons/%s" % icon_name)


static func frame_9patch_path(skin_id: String, frame_name: String) -> String:
	return _resolve_or_default(skin_id, "UI/9patch/%s" % frame_name)


static func background_anim_frame_path(skin_id: String, frame_name: String) -> String:
	return _resolve_or_default(skin_id, "Background/%s" % frame_name)


static func board_material_path(skin_id: String, material_name: String) -> String:
	return _resolve_or_default(skin_id, "Board/%s" % material_name)


static func piece_material_path(skin_id: String, material_name: String) -> String:
	return _resolve_or_default(skin_id, "Pieces/%s" % material_name)


static func _resolve_or_default(skin_id: String, relative_path: String) -> String:
	var selected = "%s/%s/%s" % [BASE_PATH, skin_id, relative_path]
	if ResourceLoader.exists(selected):
		return selected
	var fallback = "%s/%s/%s" % [BASE_PATH, DEFAULT_SKIN_ID, relative_path]
	if ResourceLoader.exists(fallback):
		return fallback
	return ""
