extends Node3D
@export_category("Current Stats")
@export var health:= 100.0
@export var dying := false
@export var current_cover: Marker3D
@export var cover_speed: int = 1

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
		# sets current cover if available
	if current_cover  != null:
		current_cover.global_position = Vector3(current_cover.global_position.x, global_position.y, current_cover.global_position.z)
		global_position = global_position.move_toward(current_cover.global_position, cover_speed * delta)

func set_cover_goal(goal: Marker3D) -> void:
	#takes cover from spawner when instantiated
	current_cover = goal
