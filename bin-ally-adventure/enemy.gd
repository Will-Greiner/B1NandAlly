extends Node3D
@export var health:= 100.0
@export var dying := false

func _hit() -> void:
	health -= 100.0
	if health <= 0:
		dying = true
		
func _process(delta) -> void:
	if dying:
		scale.y = lerpf(scale.y, 0, 0.05)
		if scale.y < 0.1:
			queue_free()
