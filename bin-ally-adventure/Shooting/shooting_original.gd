extends MeshInstance3D


@export var aiming := false #determines if character is aiming
@export var hit_parent : Node3D #gets whatever the player shoots
@export var camera: Camera3D
@export var spring_arm: SpringArm3D
@export var crosshair: Sprite3D
const temp_hit = preload("res://shooting/tempbullet.tscn")
@export var can_shoot:= false
func _ready() -> void:
	pass
func _process(delta):
	if Input.is_action_pressed("aim"):
		aiming = true #starts the ads and allows for shooting later
	if Input.is_action_just_released("aim"):
		aiming = false #moves camera back, no shooting
func _physics_process(delta: float) -> void:
	if aiming:
		#Starts crosshair appearing, camera moving and changing perspective
		crosshair.modulate = crosshair.modulate.lerp(Color(0,0,0,1), 0.1)
		spring_arm.position = spring_arm.position.lerp(Vector3(1.0,0,-1.0), 0.1)
		camera.fov = lerpf(camera.fov, 65, 0.1)
		if Input.is_action_just_pressed("shoot"):
			shoot()
	if !aiming:
		#Removes crosshair, move camera back
		crosshair.modulate = crosshair.modulate.lerp(Color(0,0,0,0), 0.1)
		spring_arm.position = spring_arm.position.lerp(Vector3.ZERO, 0.1)
		camera.fov = lerpf(camera.fov, 75, 0.1)
		
		
func shoot() -> void:
	var exclusions = [self, owner]
	
	#creates a ray from the center of the screen forward into scene. 
	var viewport_center = get_viewport().get_visible_rect().size / 2
	var ray_origin = camera.project_ray_origin(viewport_center)
	var ray_length = 20.0
	var ray_normal = camera.project_ray_normal(viewport_center)
	var ray_end = ray_origin + ray_normal * ray_length
	var space_state = get_world_3d().direct_space_state
	
	#start the ray. Ignore the player character and all its children
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	for child in owner.get_children(true):
		if child is CollisionShape3D or child is CollisionPolygon3D or child is Area3D:
			exclusions.append(child)
	query.exclude = exclusions
	
	#gets result of hit
	var result = space_state.intersect_ray(query)
	if result: 
		var hit_object = result["collider"]
		hit_object  = hit_object.owner
		#if what you hit has a parent script with a hit function, it calls that function
		if hit_object.has_method("_hit"):
			hit_object._hit()
		#otherwise, makes a temporary hit marker. Will eventually replace with an effect.
		else:
			var hit_instance = temp_hit.instantiate()
			hit_instance.position = result.position
			if hit_parent:
				hit_parent.add_child(hit_instance)
			else:
				get_tree().current_scene.add_child(hit_instance)
