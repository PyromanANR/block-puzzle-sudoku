extends Node
class_name AdsManager

var admin_mode_no_ads: bool = false
var interstitial_cooldown_ms: int = 90000
var last_interstitial_ms: int = 0


func _ready() -> void:
	admin_mode_no_ads = OS.is_debug_build()


func set_admin_mode_no_ads(enabled: bool) -> void:
	admin_mode_no_ads = enabled


func is_ads_disabled() -> bool:
	var iap = get_node_or_null("/root/IAPManager")
	if admin_mode_no_ads:
		return true
	if iap != null and iap.has_method("is_owned"):
		return bool(iap.call("is_owned", "remove_ads"))
	return false


func can_show_interstitial(now_ms: int) -> bool:
	if is_ads_disabled():
		return false
	if now_ms < last_interstitial_ms + interstitial_cooldown_ms:
		return false
	return false


func request_rewarded(reward_type: String) -> Dictionary:
	if admin_mode_no_ads:
		return {"success": true, "reward_type": reward_type, "simulated": true}
	return {"success": false, "reward_type": reward_type, "simulated": true}
