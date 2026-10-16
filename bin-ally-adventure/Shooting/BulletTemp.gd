extends MeshInstance3D

func _ready() -> void:
	# Wait for 3 seconds, then destroy this object
	await get_tree().create_timer(3.0).timeout
	queue_free()
