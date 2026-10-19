extends Node3D
@export_category("Current Stats")
@export var health:= 100.0
@export var dying := false
@export var current_cover: Marker3D
@export var cover_speed: int = 1
@onready var b1n = get_node("/root/GameScene/b1n")
@onready var ally = get_node("/root/GameScene/ally")
#if hit, calls function to reduce health by some amount, toggles dying state otherwise
func _hit() -> void:
	health -= 100.0
	if health <= 0:
		dying = true
	

func _process(delta) -> void:
	if dying:
		#shows temporary effect. Eventually will explode or whatever we choose
		scale.y = lerpf(scale.y, 0, 0.05)
		if scale.y < 0.1:
			queue_free()
		return
	if b1n and ally:
		var distance_bin = b1n.global_position.distance_to(global_position)
		var distance_ally = ally.global_position.distance_to(global_position)
		var target = b1n if distance_bin <= distance_ally else ally
		var target_position = target.global_position
		target_position.y = global_position.y
		if global_position.distance_to(target_position) > 0.01:
			var target_transform = global_transform.looking_at(target_position, Vector3.UP)
			var turn_speed: float = 5.0
			quaternion = quaternion.slerp(target_transform.basis.get_rotation_quaternion(), turn_speed * delta)
		# sets current cover if available
	if current_cover  != null:
		current_cover.global_position = Vector3(current_cover.global_position.x, global_position.y, current_cover.global_position.z)
		global_position = global_position.move_toward(current_cover.global_position, cover_speed * delta)

func set_cover_goal(goal: Marker3D) -> void:
	#takes cover from spawner when instantiated
	current_cover = goal
	
func shoot() -> void:
	pass
