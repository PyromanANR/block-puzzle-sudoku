extends Node

const DEFAULT_SKIN_BASE_PATH = "res://Assets/Skins/Default/"
const DEFAULT_TEXTURES_PATH = DEFAULT_SKIN_BASE_PATH + "textures/"
const DEFAULT_TEXTURES_BOARD_PATH = DEFAULT_TEXTURES_PATH + "Board/"
const DEFAULT_TEXTURES_PIECES_PATH = DEFAULT_TEXTURES_PATH + "Pieces/"
const DEFAULT_TEXTURES_BACKGROUND_PATH = DEFAULT_TEXTURES_PATH + "Background/"
const DEFAULT_TEXTURES_WELL_PATH = DEFAULT_TEXTURES_PATH + "Well/"
const DEFAULT_TEXTURES_DROPZONE_PATH = DEFAULT_TEXTURES_PATH + "DropZone/"

# TODO: Path contract for future default skin texture binding.
const DEFAULT_TEXTURE_PATH_CONTRACT = {
	"board": DEFAULT_TEXTURES_BOARD_PATH,
	"pieces": DEFAULT_TEXTURES_PIECES_PATH,
	"background": DEFAULT_TEXTURES_BACKGROUND_PATH,
	"well": DEFAULT_TEXTURES_WELL_PATH,
	"drop_zone": DEFAULT_TEXTURES_DROPZONE_PATH,
}

var active_skin := "Default"
var palette: Dictionary = {}
var theme: Theme


func _ready() -> void:
	load_skin(active_skin)


func load_skin(name: String) -> void:
	active_skin = name
	var base := "res://Assets/Skins/%s/" % active_skin
	theme = load(base + "theme.tres") as Theme
	palette = _load_palette(base + "palette.json")


func set_skin(name: String) -> void:
	# Stub for future runtime switching.
	load_skin(name)


func get_theme() -> Theme:
	return theme


func get_color(key: String, fallback: Color = Color.WHITE) -> Color:
	var colors: Dictionary = palette.get("colors", {})
	if not colors.has(key):
		return fallback
	return Color.from_string(String(colors[key]), fallback)


func get_piece_color(kind: String) -> Color:
	var pcs: Dictionary = palette.get("piece_colors", {})
	if pcs.has(kind):
		return Color.from_string(String(pcs[kind]), Color(0.85, 0.85, 0.9, 1.0))
	return Color(0.85, 0.85, 0.9, 1.0)


func get_font_size(key: String, fallback: int = 16) -> int:
	var sizes: Dictionary = palette.get("font_sizes", {})
	return int(sizes.get(key, fallback))


func _load_palette(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}


func get_default_palette() -> Dictionary:
	return _load_palette(DEFAULT_SKIN_BASE_PATH + "palette.json")
