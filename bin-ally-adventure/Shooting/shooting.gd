extends MeshInstance3D
@export var aiming := false
@export var hitParent : Node3D
@export var camera: Camera3D
@export var spring_arm: SpringArm3D
@export var crosshair: Sprite3D
const tempHit = preload("res://shooting/tempbullet.tscn")
@export var can_shoot:= false
func _ready() -> void:
	pass
func _process(delta):
	if Input.is_action_pressed("aim"):
		# move camera to more over the shoulder
		# make crosshair appear
		aiming = true
		# allow for shooting
	if Input.is_action_just_released("aim"):
		aiming = false
		# move camera back to normal
		# dissapear crosshair
		# no more shooting
func _physics_process(delta: float) -> void:
	if aiming:
		crosshair.modulate = crosshair.modulate.lerp(Color(0,0,0,1), 0.1)
		spring_arm.position = spring_arm.position.lerp(Vector3(1.0,0,-1.0), 0.1)
		camera.fov = lerpf(camera.fov, 65, 0.1)
		if Input.is_action_just_pressed("shoot"):
			shoot()
		#raycast ahead varied from a point
		# register hit and spawn a temporary object at that point
	if !aiming:
		crosshair.modulate = crosshair.modulate.lerp(Color(0,0,0,0), 0.1)
		spring_arm.position = spring_arm.position.lerp(Vector3.ZERO, 0.1)
		camera.fov = lerpf(camera.fov, 75, 0.1)
func shoot() -> void:
	var exclusions = [self, owner]
	var viewport_center = get_viewport().get_visible_rect().size / 2
	var ray_origin = camera.project_ray_origin(viewport_center)
	var ray_length = 20.0
	var ray_normal = camera.project_ray_normal(viewport_center)
	var ray_end = ray_origin + ray_normal * ray_length
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	for child in owner.get_children(true):
		if child is CollisionShape3D or child is CollisionPolygon3D or child is Area3D:
			exclusions.append(child)
	query.exclude = exclusions
	
	var result = space_state.intersect_ray(query)
	if result: 
		var hit_object = result["collider"]
		hit_object  = hit_object.owner
		if hit_object.has_method("_hit"):
			hit_object._hit()
		else:
			var hit_instance = tempHit.instantiate()
			hit_instance.position = result.position
			if hitParent:
				hitParent.add_child(hit_instance)
			else:
				get_tree().current_scene.add_child(hit_instance)
