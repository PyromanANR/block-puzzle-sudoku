extends Node
class_name PlayGamesLeaderboards

const PlayGamesConfigScript = preload("res://Scripts/Platform/PlayGamesConfig.gd")

var _plugin_node: Node = null
var _initialized = false
var _signed_in = false
var _leaderboard_ids: Dictionary = {}


func _ready() -> void:
	_leaderboard_ids = PlayGamesConfigScript.get_leaderboard_ids()
	_initialize_if_needed()


func is_available() -> bool:
	if OS.get_name() != "Android":
		return false
	return _plugin_node != null


func is_signed_in() -> bool:
	if not is_available():
		return false
	if _plugin_node != null:
		if _plugin_node.has_method("is_signed_in"):
			_signed_in = bool(_plugin_node.call("is_signed_in"))
		elif _plugin_node.has_method("isSignedIn"):
			_signed_in = bool(_plugin_node.call("isSignedIn"))
	return _signed_in


func sign_in() -> void:
	if not _initialize_if_needed():
		return
	if _plugin_node == null:
		return
	if _plugin_node.has_method("sign_in"):
		_plugin_node.call("sign_in")
	elif _plugin_node.has_method("signIn"):
		_plugin_node.call("signIn")
	elif _plugin_node.has_method("manual_sign_in"):
		_plugin_node.call("manual_sign_in")
	is_signed_in()


func show_leaderboard_for_difficulty(diff_key: String) -> void:
	if not _initialize_if_needed():
		return
	if not is_signed_in():
		return
	var leaderboard_id = _leaderboard_id_for(diff_key)
	if leaderboard_id == "":
		return
	if _plugin_node.has_method("show_leaderboard"):
		_plugin_node.call("show_leaderboard", leaderboard_id)
	elif _plugin_node.has_method("showLeaderboard"):
		_plugin_node.call("showLeaderboard", leaderboard_id)
	elif _plugin_node.has_method("show_leaderboard_ui"):
		_plugin_node.call("show_leaderboard_ui", leaderboard_id)


func submit_best_score_if_needed(diff_key: String, score: int) -> bool:
	if score <= 0:
		return false
	if not _initialize_if_needed():
		return false
	if not is_signed_in():
		return false
	var leaderboard_id = _leaderboard_id_for(diff_key)
	if leaderboard_id == "":
		return false
	var ok = false
	if _plugin_node.has_method("submit_leaderboard_score"):
		ok = _result_is_ok(_plugin_node.call("submit_leaderboard_score", leaderboard_id, score))
	elif _plugin_node.has_method("submitLeaderboardScore"):
		ok = _result_is_ok(_plugin_node.call("submitLeaderboardScore", leaderboard_id, score))
	elif _plugin_node.has_method("submit_score"):
		ok = _result_is_ok(_plugin_node.call("submit_score", leaderboard_id, score))
	return ok


func retry_pending_submissions() -> void:
	if not _initialize_if_needed():
		return
	if not is_signed_in():
		return
	Save.retry_pending_leaderboard_submissions()


func _initialize_if_needed() -> bool:
	if _initialized and _plugin_node != null:
		return true
	_initialized = true
	_plugin_node = _resolve_plugin_node()
	if _plugin_node == null:
		return false
	_call_initialize(_plugin_node)
	is_signed_in()
	return true


func _resolve_plugin_node() -> Node:
	var singleton_node = get_node_or_null("/root/GodotPlayGamesServices")
	if singleton_node != null:
		return singleton_node

	if not ClassDB.class_exists("GodotPlayGamesServices"):
		return null

	var node = ClassDB.instantiate("GodotPlayGamesServices")
	if node is Node:
		add_child(node)
		return node
	return null


func _call_initialize(node: Node) -> void:
	if node.has_method("initialize"):
		node.call("initialize")
	elif node.has_method("init"):
		node.call("init")
	elif node.has_method("manual_initialize"):
		node.call("manual_initialize")


func _result_is_ok(result) -> bool:
	if typeof(result) == TYPE_BOOL:
		return bool(result)
	if typeof(result) == TYPE_DICTIONARY:
		return bool((result as Dictionary).get("ok", false))
	# Some plugin methods are fire-and-forget and return null.
	return true


func _leaderboard_id_for(diff_key: String) -> String:
	var key = String(diff_key).strip_edges().to_lower()
	if not _leaderboard_ids.has(key):
		return ""
	var value = String(_leaderboard_ids.get(key, "")).strip_edges()
	if value == "" or value.begins_with("LB_"):
		return ""
	return value

