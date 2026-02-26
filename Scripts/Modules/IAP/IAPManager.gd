extends Node
const KEY_REMOVE_ADS = "iap_remove_ads_owned"
const KEY_SUDOKU_PACK = "iap_sudoku_pack_owned"
const KEY_ROME_PACK = "iap_rome_pack_owned"

var remove_ads_owned: bool = false
var sudoku_pack_owned: bool = false
var rome_pack_owned: bool = false


func _ready() -> void:
	_load_flags()


func _load_flags() -> void:
	if Save == null:
		return
	remove_ads_owned = bool(Save.data.get(KEY_REMOVE_ADS, false))
	sudoku_pack_owned = bool(Save.data.get(KEY_SUDOKU_PACK, false))
	rome_pack_owned = bool(Save.data.get(KEY_ROME_PACK, false))


func _persist_flags() -> void:
	if Save == null:
		return
	Save.data[KEY_REMOVE_ADS] = remove_ads_owned
	Save.data[KEY_SUDOKU_PACK] = sudoku_pack_owned
	Save.data[KEY_ROME_PACK] = rome_pack_owned
	Save.save()


func is_owned(product_id: String) -> bool:
	match product_id:
		"remove_ads":
			return remove_ads_owned
		"sudoku_pack":
			return sudoku_pack_owned
		"rome_pack":
			return rome_pack_owned
		_:
			return false


func debug_set_owned(product_id: String, owned: bool) -> void:
	match product_id:
		"remove_ads":
			remove_ads_owned = owned
		"sudoku_pack":
			sudoku_pack_owned = owned
		"rome_pack":
			rome_pack_owned = owned
		_:
			return
	_persist_flags()
