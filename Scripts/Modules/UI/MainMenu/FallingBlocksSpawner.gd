extends Node2D

@export var source_dirs: Array[String] = [
	"res://Assets/UI/Background/FallingBlocks/frames",
	"res://Assets/UI/Background/FallingBlocks"
]
@export var spawn_delay_min: float = 0.25
@export var spawn_delay_max: float = 0.65
@export var fall_speed_min: float = 55.0
@export var fall_speed_max: float = 95.0
@export var spawn_margin_y: float = 40.0
@export var despawn_margin_y: float = 80.0
@export var alpha: float = 0.35
@export var scale_min: float = 0.55
@export var scale_max: float = 0.85
@export var max_live: int = 80

var textures: Array[Texture2D] = []
var live: Array[Node2D] = []
var spawn_timer: Timer


func _ready() -> void:
	randomize()
	_load_textures()
	if textures.is_empty():
		push_error("[FallingBlocksSpawner] No textures found in FallingBlocks dirs")
		set_process(false)
		return
	spawn_timer = Timer.new()
	spawn_timer.one_shot = true
	spawn_timer.timeout.connect(_on_spawn_timeout)
	add_child(spawn_timer)
	_schedule_next_spawn()


func _load_textures() -> void:
	textures.clear()
	var seen_paths := {}
	for dir_path in source_dirs:
		var dir = DirAccess.open(dir_path)
		if dir == null:
			continue
		for file_name in dir.get_files():
			var lowered = file_name.to_lower()
			if lowered.ends_with(".import"):
				continue
			if not (lowered.ends_with(".png") or lowered.ends_with(".webp") or lowered.ends_with(".jpg")):
				continue
			var texture_path = dir_path + "/" + file_name
			if not ResourceLoader.exists(texture_path):
				continue
			var texture = load(texture_path)
			if not (texture is Texture2D):
				continue
			var resource_path = (texture as Texture2D).resource_path
			if resource_path != "" and seen_paths.has(resource_path):
				continue
			if resource_path != "":
				seen_paths[resource_path] = true
			textures.append(texture as Texture2D)


func _on_spawn_timeout() -> void:
	_spawn_one()
	_schedule_next_spawn()


func _schedule_next_spawn() -> void:
	if spawn_timer == null:
		return
	spawn_timer.wait_time = randf_range(spawn_delay_min, spawn_delay_max)
	spawn_timer.start()


func _spawn_one() -> void:
	if textures.is_empty():
		return
	if live.size() >= max_live:
		var oldest = live[0]
		live.remove_at(0)
		if is_instance_valid(oldest):
			oldest.queue_free()
	var viewport_size = get_viewport_rect().size
	var sprite = Sprite2D.new()
	sprite.texture = textures[randi() % textures.size()]
	sprite.modulate = Color(1, 1, 1, alpha)
	var scale_value = randf_range(scale_min, scale_max)
	sprite.scale = Vector2.ONE * scale_value
	sprite.position = Vector2(randf_range(0.0, viewport_size.x), -spawn_margin_y)
	sprite.set_meta("fall_speed", randf_range(fall_speed_min, fall_speed_max))
	sprite.set_meta("drift_x", randf_range(-6.0, 6.0))
	sprite.set_meta("rot_speed", randf_range(-0.25, 0.25))
	add_child(sprite)
	live.append(sprite)


func _process(delta: float) -> void:
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
