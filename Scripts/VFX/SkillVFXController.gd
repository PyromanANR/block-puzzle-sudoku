extends Node
class_name SkillVFXController

const FREEZE_SFX_PATH = "res://Assets/Audio/Skills/Freeze/freeze_cast.ogg"
const SAFE_WELL_CAST_SFX_PATH = "res://Assets/Audio/Skills/SafeWell/safewell_cast.ogg"
const SAFE_WELL_ZAP_SFX_PATH = "res://Assets/Audio/Skills/SafeWell/well_zap.ogg"
const SAFE_WELL_DOORS_CLOSE_SFX_PATH = "res://Assets/Audio/Skills/SafeWell/doors_close.ogg"
const SAFE_WELL_DOORS_OPEN_SFX_PATH = "res://Assets/Audio/Skills/SafeWell/doors_open.ogg"
const SAFE_WELL_LOCK_SFX_PATH = "res://Assets/Audio/Skills/SafeWell/lock_clink.ogg"

const FROST_TEXTURE_PATH = "res://Assets/VFX/Skills/Freeze/frost_edge.png"
const SAFE_WELL_DOOR_TEXTURE_PATH = "res://Assets/VFX/Skills/SafeWell/door_metal.png"
const SAFE_WELL_LOCK_TEXTURE_PATH = "res://Assets/VFX/Skills/SafeWell/lock_icon.png"
const SAFE_WELL_LIGHTNING_TEXTURE_PATH = "res://Assets/VFX/Skills/SafeWell/lightning_strip.png"

const FROST_SHADER_PATH = "res://Assets/Shaders/Skills/frost_edge.gdshader"
const VIGNETTE_SHADER_PATH = "res://Assets/Shaders/Skills/vignette.gdshader"
const FLASH_SHADER_PATH = "res://Assets/Shaders/Skills/flash.gdshader"
const LIGHTNING_SHADER_PATH = "res://Assets/Shaders/Skills/lightning.gdshader"
const TIME_SLOW_RIPPLE_SHADER_PATH = "res://Assets/Shaders/Skills/time_slow_ripple.gdshader"

var host_control: Control = null
var board_control: Control = null
var drop_zone_control: Control = null
var well_control: Control = null
var frame_control: Control = null

var overlay_layer: CanvasLayer = null
var overlay_root: Control = null

var rng = RandomNumberGenerator.new()
var sfx_players: Dictionary = {}
var play_main_sfx: Callable = Callable()

var freeze_start_ms = -1
var freeze_end_ms = -1
var freeze_frost_rect: Control = null
var freeze_vignette_rect: Control = null
var freeze_frost_mat: ShaderMaterial = null
var freeze_vignette_mat: ShaderMaterial = null

var clear_flash_start_ms = -1
var clear_flash_end_ms = -1
var clear_flash_rect: ColorRect = null
var clear_flash_mat: ShaderMaterial = null
var shake_start_ms = -1
var shake_end_ms = -1
var shake_origin = Vector2.ZERO

var safe_well_start_ms = -1
var safe_well_end_ms = -1
var safe_well_lightning_end_ms = -1
var safe_well_lightning_rect: Control = null
var safe_well_lightning_mat: ShaderMaterial = null
var safe_well_left_door: Control = null
var safe_well_right_door: Control = null
var safe_well_lock: Control = null
var safe_well_close_end_ms = -1
var safe_well_open_start_ms = -1
var safe_well_open_end_ms = -1
var safe_well_doors_started = false

var time_slow_ripple_start_ms = -1
var time_slow_ripple_end_ms = -1
var time_slow_ripple_rect: ColorRect = null
var time_slow_ripple_mat: ShaderMaterial = null


func setup(host: Control, board: Control, drop_zone: Control, well: Control = null, frame: Control = null) -> void:
	host_control = host
	board_control = board
	drop_zone_control = drop_zone
	well_control = well
	frame_control = frame
	_ensure_overlay_layer()


func setup_sfx_callback(callback: Callable) -> void:
	play_main_sfx = callback


func on_freeze_cast(duration_ms: int) -> void:
	_ensure_overlay_layer()
	_play_optional_sfx("freeze_cast", FREEZE_SFX_PATH)
	freeze_start_ms = Time.get_ticks_msec()
	freeze_end_ms = freeze_start_ms + max(duration_ms, 1)
	_ensure_freeze_nodes()
	set_process(true)


func on_clear_board_cast() -> void:
	_ensure_overlay_layer()
	var now = Time.get_ticks_msec()
	clear_flash_start_ms = now
	clear_flash_end_ms = now + 200
	shake_start_ms = now
	shake_end_ms = now + 80
	if host_control != null:
		shake_origin = host_control.position
	_ensure_clear_flash_node()
	set_process(true)


func on_safe_well_cast(duration_ms: int) -> void:
	_ensure_overlay_layer()
	_play_optional_sfx("safe_well_cast", SAFE_WELL_CAST_SFX_PATH)
	_play_optional_sfx("safe_well_zap", SAFE_WELL_ZAP_SFX_PATH)
	var now = Time.get_ticks_msec()
	safe_well_start_ms = now
	safe_well_end_ms = now + max(duration_ms, 1)
	safe_well_lightning_end_ms = safe_well_start_ms + 1500
	safe_well_close_end_ms = safe_well_lightning_end_ms + 300
	safe_well_open_start_ms = max(safe_well_close_end_ms, safe_well_end_ms - 260)
	safe_well_open_end_ms = safe_well_end_ms
	safe_well_doors_started = false
	_ensure_safe_well_nodes()
	_spawn_safe_well_sparks()
	set_process(true)


func on_time_slow_cast() -> void:
	_ensure_overlay_layer()
	_play_time_slow_sfx()
	var now = Time.get_ticks_msec()
	time_slow_ripple_start_ms = now
	time_slow_ripple_end_ms = now + 1000
	if not _ensure_time_slow_ripple_node():
		time_slow_ripple_start_ms = -1
		time_slow_ripple_end_ms = -1
		return
	time_slow_ripple_rect.visible = true
	set_process(true)


func _ready() -> void:
	rng.randomize()
	set_process(false)


func _process(_delta: float) -> void:
	var now = Time.get_ticks_msec()
	var active = false
	if _update_freeze(now):
		active = true
	if _update_clear_board(now):
		active = true
	if _update_safe_well(now):
		active = true
	if _update_time_slow_ripple(now):
		active = true
	if not active:
		set_process(false)


func _ensure_overlay_layer() -> void:
	if overlay_layer != null and is_instance_valid(overlay_layer):
		return
	if host_control == null:
		return
	overlay_layer = CanvasLayer.new()
	overlay_layer.layer = 30
	overlay_root = Control.new()
	overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_root.offset_left = 0
	overlay_root.offset_top = 0
	overlay_root.offset_right = 0
	overlay_root.offset_bottom = 0
	overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_layer.add_child(overlay_root)
	host_control.add_child(overlay_layer)


func _ensure_audio_player(key: String, path: String) -> AudioStreamPlayer:
	if sfx_players.has(key):
		return sfx_players[key]
	if not ResourceLoader.exists(path):
		return null
	var stream = load(path)
	if stream == null:
		return null
	var player = AudioStreamPlayer.new()
	player.bus = "Master"
	player.stream = stream
	add_child(player)
	sfx_players[key] = player
	return player


func _play_optional_sfx(key: String, path: String) -> void:
	var player = _ensure_audio_player(key, path)
	if player != null and player.stream != null:
		player.play()


func _play_time_slow_sfx() -> void:
	if play_main_sfx.is_valid():
		play_main_sfx.call("time_slow")
		return
	if OS.is_debug_build():
		push_warning("SkillVFXController: time_slow SFX callback is not configured.")


func _shader_from_path(path: String) -> Shader:
	if not ResourceLoader.exists(path):
		return null
	var resource = load(path)
	if resource is Shader:
		return resource
	return null


func _texture_from_path(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var resource = load(path)
	if resource is Texture2D:
		return resource
	return null


func _rect_for(control: Control) -> Rect2:
	if host_control == null or control == null:
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	if not is_instance_valid(control):
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	var global_rect = control.get_global_rect()
	var local_pos = global_rect.position - host_control.global_position
	return Rect2(local_pos, global_rect.size)


func _ensure_freeze_nodes() -> void:
	if overlay_root == null:
		return
	overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_root.offset_left = 0
	overlay_root.offset_top = 0
	overlay_root.offset_right = 0
	overlay_root.offset_bottom = 0
	if freeze_frost_rect == null or not is_instance_valid(freeze_frost_rect):
		var frost_tex = _texture_from_path(FROST_TEXTURE_PATH)
		if frost_tex != null:
			var tex_rect = TextureRect.new()
			tex_rect.texture = frost_tex
			tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
			freeze_frost_rect = tex_rect
		else:
			var fallback = ColorRect.new()
			fallback.color = Color(0.7, 0.85, 1.0, 0.0)
			fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
			freeze_frost_rect = fallback
		freeze_frost_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		freeze_frost_rect.offset_left = 0
		freeze_frost_rect.offset_top = 0
		freeze_frost_rect.offset_right = 0
		freeze_frost_rect.offset_bottom = 0
		overlay_root.add_child(freeze_frost_rect)
		var frost_shader = _shader_from_path(FROST_SHADER_PATH)
		if frost_shader != null:
			freeze_frost_mat = ShaderMaterial.new()
			freeze_frost_mat.shader = frost_shader
			freeze_frost_mat.set_shader_parameter("u_strength", 0.0)
			freeze_frost_rect.material = freeze_frost_mat
	var frame_rect = _freeze_frame_rect()
	overlay_root.position = frame_rect.position
	overlay_root.size = frame_rect.size
	if freeze_vignette_rect == null or not is_instance_valid(freeze_vignette_rect):
		var vignette = ColorRect.new()
		vignette.color = Color(0.0, 0.0, 0.0, 0.0)
		vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		vignette.offset_left = 0
		vignette.offset_top = 0
		vignette.offset_right = 0
		vignette.offset_bottom = 0
		vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay_root.add_child(vignette)
		freeze_vignette_rect = vignette
		var vignette_shader = _shader_from_path(VIGNETTE_SHADER_PATH)
		if vignette_shader != null:
			freeze_vignette_mat = ShaderMaterial.new()
			freeze_vignette_mat.shader = vignette_shader
			freeze_vignette_mat.set_shader_parameter("u_strength", 0.0)
			freeze_vignette_rect.material = freeze_vignette_mat
	freeze_frost_rect.visible = false
	freeze_vignette_rect.visible = false


func _ensure_clear_flash_node() -> void:
	if overlay_root == null:
		return
	if clear_flash_rect == null or not is_instance_valid(clear_flash_rect):
		clear_flash_rect = ColorRect.new()
		clear_flash_rect.color = Color(1, 1, 1, 1)
		clear_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay_root.add_child(clear_flash_rect)
		var flash_shader = _shader_from_path(FLASH_SHADER_PATH)
		if flash_shader != null:
			clear_flash_mat = ShaderMaterial.new()
			clear_flash_mat.shader = flash_shader
			clear_flash_mat.set_shader_parameter("u_strength", 0.0)
			clear_flash_rect.material = clear_flash_mat
	if board_control != null and is_instance_valid(board_control):
		var board_rect = _rect_for(board_control)
		clear_flash_rect.position = board_rect.position
		clear_flash_rect.size = board_rect.size
	else:
		clear_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		clear_flash_rect.offset_left = 0
		clear_flash_rect.offset_top = 0
		clear_flash_rect.offset_right = 0
		clear_flash_rect.offset_bottom = 0
	clear_flash_rect.visible = false


func _ensure_time_slow_ripple_node() -> bool:
	if overlay_root == null:
		return false
	if time_slow_ripple_rect != null and is_instance_valid(time_slow_ripple_rect):
		return true
	var ripple_shader = _shader_from_path(TIME_SLOW_RIPPLE_SHADER_PATH)
	if ripple_shader == null:
		return false
	time_slow_ripple_rect = ColorRect.new()
	time_slow_ripple_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	time_slow_ripple_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_slow_ripple_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	time_slow_ripple_rect.offset_left = 0
	time_slow_ripple_rect.offset_top = 0
	time_slow_ripple_rect.offset_right = 0
	time_slow_ripple_rect.offset_bottom = 0
	time_slow_ripple_mat = ShaderMaterial.new()
	time_slow_ripple_mat.shader = ripple_shader
	time_slow_ripple_mat.set_shader_parameter("u_progress", 0.0)
	time_slow_ripple_mat.set_shader_parameter("u_strength", 0.0)
	time_slow_ripple_mat.set_shader_parameter("u_center", Vector2(0.5, 0.5))
	time_slow_ripple_rect.material = time_slow_ripple_mat
	time_slow_ripple_rect.visible = false
	overlay_root.add_child(time_slow_ripple_rect)
	return true


func _well_rect() -> Rect2:
	if well_control != null and is_instance_valid(well_control):
		return _rect_for(well_control)
	return _rect_for(drop_zone_control)


func _freeze_frame_rect() -> Rect2:
	if frame_control != null and is_instance_valid(frame_control):
		return _rect_for(frame_control)
	return _rect_for(host_control)


func _ensure_safe_well_nodes() -> void:
	if overlay_root == null:
		return
	var well_rect = _well_rect()
	if safe_well_lightning_rect == null or not is_instance_valid(safe_well_lightning_rect):
		var strip_tex = _texture_from_path(SAFE_WELL_LIGHTNING_TEXTURE_PATH)
		if strip_tex != null:
			var strip = TextureRect.new()
			strip.texture = strip_tex
			strip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			strip.stretch_mode = TextureRect.STRETCH_SCALE
			safe_well_lightning_rect = strip
		else:
			var lightning_fallback = ColorRect.new()
			lightning_fallback.color = Color(0.65, 0.85, 1.0, 0.24)
			safe_well_lightning_rect = lightning_fallback
		safe_well_lightning_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay_root.add_child(safe_well_lightning_rect)
		var lightning_shader = _shader_from_path(LIGHTNING_SHADER_PATH)
		if lightning_shader != null:
			safe_well_lightning_mat = ShaderMaterial.new()
			safe_well_lightning_mat.shader = lightning_shader
			safe_well_lightning_mat.set_shader_parameter("u_strength", 0.0)
			safe_well_lightning_mat.set_shader_parameter("u_time", 0.0)
			safe_well_lightning_mat.set_shader_parameter("u_vertical", 1.0)
			safe_well_lightning_rect.material = safe_well_lightning_mat
	safe_well_lightning_rect.position = well_rect.position
	safe_well_lightning_rect.size = well_rect.size
	safe_well_lightning_rect.visible = false
	_ensure_safe_well_doors(well_rect)


func _ensure_safe_well_doors(door_rect: Rect2) -> void:
	var door_tex = _texture_from_path(SAFE_WELL_DOOR_TEXTURE_PATH)
	if safe_well_left_door == null or not is_instance_valid(safe_well_left_door):
		safe_well_left_door = _build_door_panel(door_tex)
		overlay_root.add_child(safe_well_left_door)
	if safe_well_right_door == null or not is_instance_valid(safe_well_right_door):
		safe_well_right_door = _build_door_panel(door_tex)
		overlay_root.add_child(safe_well_right_door)
	if safe_well_lock == null or not is_instance_valid(safe_well_lock):
		safe_well_lock = _build_lock_control(_texture_from_path(SAFE_WELL_LOCK_TEXTURE_PATH))
		overlay_root.add_child(safe_well_lock)
	var panel_width = max(32.0, door_rect.size.x * 0.5)
	safe_well_left_door.size = Vector2(panel_width, door_rect.size.y)
	safe_well_right_door.size = Vector2(panel_width, door_rect.size.y)
	safe_well_left_door.position = Vector2(door_rect.position.x - panel_width, door_rect.position.y)
	safe_well_right_door.position = Vector2(door_rect.position.x + door_rect.size.x, door_rect.position.y)
	safe_well_left_door.visible = false
	safe_well_right_door.visible = false
	safe_well_left_door.set_meta("open_sfx_played", false)
	safe_well_right_door.set_meta("open_sfx_played", false)
	safe_well_left_door.set_meta("close_sfx_played", false)
	safe_well_lock.position = door_rect.position + (door_rect.size * 0.5) - (safe_well_lock.size * 0.5)
	safe_well_lock.scale = Vector2.ONE * 0.1
	safe_well_lock.modulate.a = 0.0
	safe_well_lock.visible = false
	safe_well_lock.set_meta("sfx_played", false)


func _build_door_panel(door_tex: Texture2D) -> Control:
	if door_tex != null:
		var door = TextureRect.new()
		door.texture = door_tex
		door.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		door.stretch_mode = TextureRect.STRETCH_SCALE
		door.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return door
	var fallback = ColorRect.new()
	fallback.color = Color(0.22, 0.24, 0.28, 0.85)
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return fallback


func _build_lock_control(lock_tex: Texture2D) -> Control:
	if lock_tex != null:
		var lock_rect = TextureRect.new()
		lock_rect.texture = lock_tex
		lock_rect.custom_minimum_size = Vector2(42, 42)
		lock_rect.size = Vector2(42, 42)
		lock_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lock_rect.stretch_mode = TextureRect.STRETCH_SCALE
		lock_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return lock_rect
	var fallback = ColorRect.new()
	fallback.custom_minimum_size = Vector2(24, 24)
	fallback.size = Vector2(24, 24)
	fallback.color = Color(0.9, 0.9, 1.0, 0.9)
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return fallback


func _spawn_safe_well_sparks() -> void:
	if overlay_root == null:
		return
	var well_rect = _well_rect()
	if well_rect.size.x <= 1.0 or well_rect.size.y <= 1.0:
		return
	var count = rng.randi_range(2, 4)
	for i in range(count):
		var spark = Line2D.new()
		spark.width = rng.randf_range(1.3, 2.4)
		spark.default_color = Color(0.65, 0.88, 1.0, 0.95)
		spark.position = Vector2.ZERO
		var x0 = well_rect.position.x + rng.randf_range(4.0, well_rect.size.x - 4.0)
		var y0 = well_rect.position.y + rng.randf_range(4.0, min(36.0, well_rect.size.y - 4.0))
		spark.add_point(Vector2(x0, y0))
		spark.add_point(Vector2(x0 + rng.randf_range(-8.0, 8.0), y0 + rng.randf_range(4.0, 14.0)))
		spark.add_point(Vector2(x0 + rng.randf_range(-14.0, 14.0), y0 + rng.randf_range(8.0, 18.0)))
		overlay_root.add_child(spark)
		var t = get_tree().create_timer(0.1, true, false, true)
		t.timeout.connect(func():
			if is_instance_valid(spark):
				spark.queue_free()
		)


func _update_freeze(now: int) -> bool:
	if freeze_start_ms < 0 or freeze_end_ms <= freeze_start_ms:
		return false
	if now >= freeze_end_ms:
		freeze_start_ms = -1
		freeze_end_ms = -1
		if freeze_frost_rect != null and is_instance_valid(freeze_frost_rect):
			freeze_frost_rect.visible = false
		if freeze_vignette_rect != null and is_instance_valid(freeze_vignette_rect):
			freeze_vignette_rect.visible = false
		return false
	var t = float(now - freeze_start_ms) / float(freeze_end_ms - freeze_start_ms)
	var eased_in = clamp(t * 5.5, 0.0, 1.0)
	var eased_out = clamp((1.0 - t) * 1.4, 0.0, 1.0)
	var alpha = min(eased_in, eased_out)
	if freeze_frost_rect != null and is_instance_valid(freeze_frost_rect):
		freeze_frost_rect.visible = true
		freeze_frost_rect.modulate.a = 0.35 * alpha
		if freeze_frost_mat != null:
			freeze_frost_mat.set_shader_parameter("u_strength", clamp(0.9 * alpha, 0.0, 1.0))
	if freeze_vignette_rect != null and is_instance_valid(freeze_vignette_rect):
		freeze_vignette_rect.visible = true
		var v_strength = clamp(0.2 * alpha, 0.0, 1.0)
		if freeze_vignette_rect is ColorRect:
			freeze_vignette_rect.color.a = 1.0
		if freeze_vignette_mat != null:
			freeze_vignette_mat.set_shader_parameter("u_strength", v_strength)
	return true


func _update_clear_board(now: int) -> bool:
	var flash_active = false
	if clear_flash_start_ms >= 0 and clear_flash_end_ms > clear_flash_start_ms:
		if now >= clear_flash_end_ms:
			clear_flash_start_ms = -1
			clear_flash_end_ms = -1
			if clear_flash_rect != null and is_instance_valid(clear_flash_rect):
				clear_flash_rect.visible = false
		else:
			var t = float(now - clear_flash_start_ms) / float(clear_flash_end_ms - clear_flash_start_ms)
			var strength = sin(t * PI)
			if clear_flash_rect != null and is_instance_valid(clear_flash_rect):
				clear_flash_rect.visible = true
				if clear_flash_mat != null:
					clear_flash_mat.set_shader_parameter("u_strength", 0.32 * strength)
					clear_flash_rect.color.a = 1.0
				else:
					clear_flash_rect.color.a = 0.32 * strength
			flash_active = true
	var shake_active = false
	if shake_start_ms >= 0 and shake_end_ms > shake_start_ms:
		if now >= shake_end_ms:
			shake_start_ms = -1
			shake_end_ms = -1
			if host_control != null:
				host_control.position = shake_origin
		else:
			var remaining = float(shake_end_ms - now) / float(shake_end_ms - shake_start_ms)
			var amp = 6.0 * max(0.0, remaining)
			if host_control != null:
				host_control.position = shake_origin + Vector2(rng.randf_range(-amp, amp), rng.randf_range(-amp, amp))
			shake_active = true
	return flash_active or shake_active


func _update_safe_well(now: int) -> bool:
	if safe_well_start_ms < 0 or safe_well_end_ms <= safe_well_start_ms:
		return false
	var active = true
	var total = float(safe_well_end_ms - safe_well_start_ms)
	var t = clamp(float(now - safe_well_start_ms) / total, 0.0, 1.0)
	var well_rect = _well_rect()
	if safe_well_lightning_rect != null and is_instance_valid(safe_well_lightning_rect):
		safe_well_lightning_rect.position = well_rect.position
		safe_well_lightning_rect.size = well_rect.size
	if now < safe_well_lightning_end_ms:
		if safe_well_lightning_rect != null and is_instance_valid(safe_well_lightning_rect):
			safe_well_lightning_rect.visible = true
			var pulse = abs(sin(t * PI * 5.0))
			var alpha = lerp(0.08, 0.40, pulse)
			safe_well_lightning_rect.modulate.a = alpha
			if safe_well_lightning_mat != null:
				safe_well_lightning_mat.set_shader_parameter("u_strength", clamp(alpha * 1.8, 0.0, 1.0))
				safe_well_lightning_mat.set_shader_parameter("u_time", float(now) / 1000.0)
				safe_well_lightning_mat.set_shader_parameter("u_vertical", 1.0)
		safe_well_doors_started = false
		_hide_safe_well_doors_lock()
		return active
	if safe_well_lightning_rect != null and is_instance_valid(safe_well_lightning_rect):
		safe_well_lightning_rect.visible = false
	if not safe_well_doors_started:
		safe_well_doors_started = true
		if safe_well_left_door != null and is_instance_valid(safe_well_left_door):
			safe_well_left_door.set_meta("close_sfx_played", false)
			safe_well_left_door.set_meta("open_sfx_played", false)
		if safe_well_right_door != null and is_instance_valid(safe_well_right_door):
			safe_well_right_door.set_meta("open_sfx_played", false)
		if safe_well_lock != null and is_instance_valid(safe_well_lock):
			safe_well_lock.set_meta("sfx_played", false)
	_update_doors_timeline(now, well_rect)
	if now >= safe_well_end_ms:
		safe_well_start_ms = -1
		safe_well_end_ms = -1
		safe_well_lightning_end_ms = -1
		safe_well_close_end_ms = -1
		safe_well_open_start_ms = -1
		safe_well_open_end_ms = -1
		safe_well_doors_started = false
		if safe_well_lightning_rect != null and is_instance_valid(safe_well_lightning_rect):
			safe_well_lightning_rect.visible = false
		if safe_well_left_door != null and is_instance_valid(safe_well_left_door):
			safe_well_left_door.visible = false
		if safe_well_right_door != null and is_instance_valid(safe_well_right_door):
			safe_well_right_door.visible = false
		if safe_well_lock != null and is_instance_valid(safe_well_lock):
			safe_well_lock.visible = false
		active = false
	return active


func _update_time_slow_ripple(now: int) -> bool:
	if time_slow_ripple_start_ms < 0 or time_slow_ripple_end_ms <= time_slow_ripple_start_ms:
		return false
	if time_slow_ripple_rect == null or not is_instance_valid(time_slow_ripple_rect):
		time_slow_ripple_start_ms = -1
		time_slow_ripple_end_ms = -1
		return false
	if now > time_slow_ripple_end_ms:
		time_slow_ripple_start_ms = -1
		time_slow_ripple_end_ms = -1
		time_slow_ripple_rect.visible = false
		return false
	var t = float(now - time_slow_ripple_start_ms) / 1000.0
	var progress = clamp(t, 0.0, 1.0)
	var strength = (1.0 - progress) * 0.65
	time_slow_ripple_rect.visible = true
	if time_slow_ripple_mat != null:
		time_slow_ripple_mat.set_shader_parameter("u_progress", progress)
		time_slow_ripple_mat.set_shader_parameter("u_strength", strength)
		time_slow_ripple_mat.set_shader_parameter("u_center", Vector2(0.5, 0.5))
	return true


func _hide_safe_well_doors_lock() -> void:
	if safe_well_left_door != null and is_instance_valid(safe_well_left_door):
		safe_well_left_door.visible = false
	if safe_well_right_door != null and is_instance_valid(safe_well_right_door):
		safe_well_right_door.visible = false
	if safe_well_lock != null and is_instance_valid(safe_well_lock):
		safe_well_lock.visible = false


func _update_doors_timeline(now: int, door_rect: Rect2) -> void:
	if safe_well_left_door == null or not is_instance_valid(safe_well_left_door):
		return
	if safe_well_right_door == null or not is_instance_valid(safe_well_right_door):
		return
	var panel_w = safe_well_left_door.size.x
	var left_open_x = door_rect.position.x - panel_w
	var right_open_x = door_rect.position.x + door_rect.size.x
	var left_closed_x = door_rect.position.x
	var right_closed_x = door_rect.position.x + door_rect.size.x - panel_w
	safe_well_left_door.visible = true
	safe_well_right_door.visible = true
	if safe_well_lock != null and is_instance_valid(safe_well_lock):
		safe_well_lock.visible = true
		safe_well_lock.position = door_rect.position + (door_rect.size * 0.5) - (safe_well_lock.size * 0.5)
	if now <= safe_well_close_end_ms:
		if safe_well_left_door.get_meta("close_sfx_played", false) == false:
			safe_well_left_door.set_meta("close_sfx_played", true)
			_play_optional_sfx("doors_close", SAFE_WELL_DOORS_CLOSE_SFX_PATH)
		var close_t = clamp(float(now - safe_well_lightning_end_ms) / float(max(1, safe_well_close_end_ms - safe_well_lightning_end_ms)), 0.0, 1.0)
		safe_well_left_door.position.x = lerp(left_open_x, left_closed_x, close_t)
		safe_well_right_door.position.x = lerp(right_open_x, right_closed_x, close_t)
		if safe_well_lock != null and is_instance_valid(safe_well_lock):
			safe_well_lock.modulate.a = 0.0
			safe_well_lock.scale = Vector2.ONE * 0.1
		return
	if now < safe_well_open_start_ms:
		safe_well_left_door.position.x = left_closed_x
		safe_well_right_door.position.x = right_closed_x
		if safe_well_lock != null and is_instance_valid(safe_well_lock):
			var lock_t = clamp(float(now - safe_well_close_end_ms) / 150.0, 0.0, 1.0)
			safe_well_lock.modulate.a = lock_t
			safe_well_lock.scale = Vector2.ONE * lerp(0.1, 1.0, lock_t)
			if lock_t > 0.02 and safe_well_lock.get_meta("sfx_played", false) == false:
				safe_well_lock.set_meta("sfx_played", true)
				_play_optional_sfx("lock_clink", SAFE_WELL_LOCK_SFX_PATH)
		return
	if now <= safe_well_open_end_ms:
		var open_t = clamp(float(now - safe_well_open_start_ms) / float(max(1, safe_well_open_end_ms - safe_well_open_start_ms)), 0.0, 1.0)
		if safe_well_left_door.get_meta("open_sfx_played", false) == false:
			safe_well_left_door.set_meta("open_sfx_played", true)
			_play_optional_sfx("doors_open", SAFE_WELL_DOORS_OPEN_SFX_PATH)
		safe_well_left_door.position.x = lerp(left_closed_x, left_open_x, open_t)
		safe_well_right_door.position.x = lerp(right_closed_x, right_open_x, open_t)
		if safe_well_lock != null and is_instance_valid(safe_well_lock):
			safe_well_lock.modulate.a = 1.0 - open_t
			safe_well_lock.scale = Vector2.ONE * lerp(1.0, 0.2, open_t)
		return
