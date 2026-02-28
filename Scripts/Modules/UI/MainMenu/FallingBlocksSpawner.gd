extends Node2D

const PRELOADED_TEXTURES: Array[Texture2D] = [
	preload("res://Assets/UI/Background/FallingBlocks/frames/tetris_voxel_particles_sheet_A_6x1-0-0.png"),
	preload("res://Assets/UI/Background/FallingBlocks/frames/tetris_voxel_particles_sheet_A_6x1-1-0.png"),
	preload("res://Assets/UI/Background/FallingBlocks/frames/tetris_voxel_particles_sheet_A_6x1-2-0.png"),
	preload("res://Assets/UI/Background/FallingBlocks/frames/tetris_voxel_particles_sheet_A_6x1-3-0.png"),
	preload("res://Assets/UI/Background/FallingBlocks/frames/tetris_voxel_particles_sheet_A_6x1-4-0.png"),
	preload("res://Assets/UI/Background/FallingBlocks/frames/tetris_voxel_particles_sheet_A_6x1-5-0.png"),
	preload("res://Assets/UI/Background/FallingBlocks/frames/tetris_voxel_particles_sheet_B_6x1-1-1.png"),
	preload("res://Assets/UI/Background/FallingBlocks/frames/tetris_voxel_particles_sheet_B_6x1-2-1.png"),
	preload("res://Assets/UI/Background/FallingBlocks/frames/tetris_voxel_particles_sheet_B_6x1-3-1.png"),
	preload("res://Assets/UI/Background/FallingBlocks/frames/tetris_voxel_particles_sheet_B_6x1-4-1.png"),
	preload("res://Assets/UI/Background/FallingBlocks/frames/tetris_voxel_particles_sheet_B_6x1-5-1.png"),
	preload("res://Assets/UI/Background/FallingBlocks/frames/tetris_voxel_particles_sheet_B_6x1-6-1.png")
]

@export var spawn_delay_min: float = 0.55
@export var spawn_delay_max: float = 0.8

@export var fall_speed_min: float = 55.0
@export var fall_speed_max: float = 95.0

@export var spawn_margin_y: float = 40.0
@export var despawn_margin_y: float = 80.0

# Keep original texture colors (no dimming)
# (alpha removed)

@export var scale_min: float = 0.55
@export var scale_max: float = 0.85

@export var max_live: int = 80

# Anti-clumping settings
@export var lane_count: int = 10
@export var lane_cooldown_sec: float = 3.0
@export var pick_lane_attempts: int = 10

# Optional subtle motion (keep small so it still feels like Tetris pace)
@export var drift_x_min: float = -6.0
@export var drift_x_max: float = 6.0
@export var rot_speed_min: float = -0.25
@export var rot_speed_max: float = 0.25

var textures: Array[Texture2D] = []
var live: Array[Node2D] = []
var spawn_timer: Timer

# lane -> last spawn time (seconds since start)
var lane_last_spawn_time: Array[float] = []
var time_s: float = 0.0


func _ready() -> void:
	randomize()
	_load_textures()
	if textures.is_empty():
		if OS.is_debug_build():
			push_error("[FallingBlocksSpawner] No textures found in preloaded list")
		set_process(false)
		return

	_init_lanes()

	spawn_timer = Timer.new()
	spawn_timer.one_shot = true
	spawn_timer.timeout.connect(_on_spawn_timeout)
	add_child(spawn_timer)

	_schedule_next_spawn()


func _init_lanes() -> void:
	lane_count = max(3, lane_count)
	lane_last_spawn_time.resize(lane_count)
	for i in range(lane_count):
		# Use a very negative time so everything is available at start
		lane_last_spawn_time[i] = -99999.0


func _load_textures() -> void:
	textures.clear()
	for texture in PRELOADED_TEXTURES:
		if texture != null:
			textures.append(texture)
	if OS.is_debug_build():
		print("[FallingBlocksSpawner] Loaded textures: %d" % textures.size())


func _on_spawn_timeout() -> void:
	_spawn_one()
	_schedule_next_spawn()


func _schedule_next_spawn() -> void:
	if spawn_timer == null:
		return
	spawn_timer.wait_time = randf_range(spawn_delay_min, spawn_delay_max)
	spawn_timer.start()


func _pick_lane(viewport_w: float) -> int:
	# Try to find a lane that wasn't used recently
	var best_lane = -1
	var best_age = -1.0

	for attempt in range(pick_lane_attempts):
		var lane = randi() % lane_count
		var age = time_s - lane_last_spawn_time[lane]
		if age >= lane_cooldown_sec:
			return lane
		# Track the "best" (oldest) lane as fallback
		if age > best_age:
			best_age = age
			best_lane = lane

	# Fallback: choose the lane that is "oldest" among attempts
	if best_lane >= 0:
		return best_lane

	# Ultimate fallback
	return randi() % lane_count


func _lane_to_x(lane: int, viewport_w: float) -> float:
	# Convert lane index into an X range, then pick random X inside that lane.
	var lane_w = viewport_w / float(lane_count)
	var x_min = lane_w * float(lane)
	var x_max = x_min + lane_w
	# Keep a small padding so sprites don't spawn partially outside screen
	var pad = max(6.0, lane_w * 0.08)
	return randf_range(x_min + pad, x_max - pad)


func _spawn_one() -> void:
	if textures.is_empty():
		return

	# Safety cap: remove oldest
	if live.size() >= max_live:
		var oldest = live[0]
		live.remove_at(0)
		if is_instance_valid(oldest):
			oldest.queue_free()

	var viewport_size = get_viewport_rect().size
	var vp_w = viewport_size.x
	var vp_h = viewport_size.y
	if vp_w <= 1.0 or vp_h <= 1.0:
		return

	var lane = _pick_lane(vp_w)
	var spawn_x = _lane_to_x(lane, vp_w)
	lane_last_spawn_time[lane] = time_s

	var sprite = Sprite2D.new()
	sprite.texture = textures[randi() % textures.size()]

	# Keep original color + saturation exactly
	sprite.modulate = Color(1, 1, 1, 1)

	var scale_value = randf_range(scale_min, scale_max)
	sprite.scale = Vector2.ONE * scale_value
	sprite.position = Vector2(spawn_x, -spawn_margin_y)

	sprite.set_meta("fall_speed", randf_range(fall_speed_min, fall_speed_max))
	sprite.set_meta("drift_x", randf_range(drift_x_min, drift_x_max))
	sprite.set_meta("rot_speed", randf_range(rot_speed_min, rot_speed_max))

	add_child(sprite)
	live.append(sprite)


func _process(delta: float) -> void:
	time_s += delta

	var viewport_height = get_viewport_rect().size.y
	for i in range(live.size() - 1, -1, -1):
		var node = live[i]
		if not is_instance_valid(node):
			live.remove_at(i)
			continue

		node.position.y += float(node.get_meta("fall_speed", 0.0)) * delta
		node.position.x += float(node.get_meta("drift_x", 0.0)) * delta
		node.rotation += float(node.get_meta("rot_speed", 0.0)) * delta

		if node.position.y > viewport_height + despawn_margin_y:
			node.queue_free()
			live.remove_at(i)
