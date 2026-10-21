extends MeshInstance3D



@export_group("Player References")
@export var player: CharacterBody3D
@export var camera: Camera3D
@export var spring_arm: SpringArm3D

@export_group("Shooting")
@export_range(0.01, 2.0, 0.01) var shot_interval: float = 0.2
@export_range(1.0, 1000.0, 1.0) var shot_range: float = 20.0
@export_flags_3d_physics var shot_collision_mask: int = 1
@export var detect_areas: bool = false

@export_group("Aiming")
@export var aiming_offset: Vector3 = Vector3(1.0, 0.0, -1.0)
@export_range(1.0, 179.0, 1.0) var aiming_fov: float = 65.0
@export_range(0.1, 40.0, 0.1) var aiming_transition_speed: float = 10.0

@export_group("World Crosshair")
@export var crosshair: Sprite3D

@export_group("Hit Markers")
@export var hit_parent: Node3D
@export var hit_marker_scene: PackedScene
@export_range(0.0, 60.0, 0.5) var hit_marker_lifetime: float = 3.0
@export var hit_marker_offset: float = 0.01

var can_shoot: bool = true
var aiming: bool = false
var resting_arm_position: Vector3 = Vector3.ZERO
var resting_fov: float = 75.0
var next_local_shot_time: int = 0
var next_server_shot_time: int = 0
var ray_exclusions: Array[RID] = []
var references_valid: bool = false

func _ready() -> void:
	if player == null:
		player = _find_player()
		
	resting_arm_position = spring_arm.position
	resting_fov = camera.fov
	aiming = false
	
	_collect_collision_exclusions(player)
	
	if crosshair != null:
		var color: Color = crosshair.modulate
		color.a = 0.0
		crosshair.modulate = color
		
	references_valid = true
	
	
func _find_player() -> CharacterBody3D:
	var ancestor: Node = get_parent()
	
	while ancestor != null:
		if ancestor is CharacterBody3D:
			return ancestor as CharacterBody3D
		
		ancestor = ancestor.get_parent()
		
	return null
	
	
func _is_networked() -> bool:
	return bool(player.get("networked"))
	
	
func _is_local_player() -> bool:
	return not _is_networked() or player.is_multiplayer_authority()
	
	
func _physics_process(delta: float) -> void:
	# Make sure that only local player can access
	if not references_valid or not _is_local_player():
		return
		
	# Check if we can shoot
	var mouse_captured: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	
	aiming = can_shoot and mouse_captured and Input.is_action_pressed("aim")
	
	_update_aiming(delta)
	
	if aiming and Input.is_action_just_pressed("shoot"):
		shoot()
		
		
func _update_aiming(delta: float) -> void:
	var weight: float = 1.0 - exp(-aiming_transition_speed * delta) # easing (fast then slow)
	var target_arm_position: Vector3 = resting_arm_position + aiming_offset if aiming else resting_arm_position
	var target_fov: float = aiming_fov if aiming else resting_fov
	
	spring_arm.position = spring_arm.position.lerp(target_arm_position, weight)
	camera.fov = lerp(camera.fov, target_fov, weight)
	
	# Animate crosshair while aiming
	if crosshair != null:
		var color: Color = crosshair.modulate
		var target_alpha: float = 1.0 if aiming else 0.0
		
		color.a = lerpf(color.a, target_alpha, weight)
		crosshair.modulate = color
		
		
func shoot() -> void:
	if not references_valid or not _is_local_player() or not can_shoot or not aiming:
		return
		
	# Determine Fire Rate
	var current_time: int = Time.get_ticks_msec()
	
	if current_time < next_local_shot_time:
		return
		
	next_local_shot_time = current_time + int(shot_interval * 1000.0)
	
	var shot_view: Transform3D = camera.get_camera_transform() # Multiple cameras + adjusting viewport = grab camera transform
	var ray_origin: Vector3 = shot_view.origin
	var ray_direction: Vector3 = -shot_view.basis.z.normalized()
	
	if not _is_networked() or multiplayer.is_server():
		_resolve_shot(ray_origin, ray_direction) # Host shoot
	else:
		_request_shot.rpc_id(1, ray_origin, ray_direction) # Client requests to shoot


@rpc("any_peer", "call_remote", "reliable")
func _request_shot(ray_origin: Vector3, ray_direction: Vector3) -> void:
	if not references_valid or not _is_networked() or not multiplayer.is_server():
		return
		
	var sender_id: int = multiplayer.get_remote_sender_id()
	
	# Sender should be the host
	if sender_id != player.get_multiplayer_authority():
		return
		
	_resolve_shot(ray_origin, ray_direction)
	
	
func _resolve_shot(ray_origin: Vector3, ray_direction: Vector3) -> void:
	if not can_shoot:
		return
		
	if _is_networked() and not multiplayer.is_server(): # Only host can process shooting
		return
		
	var current_time: int = Time.get_ticks_msec()
	
	if current_time < next_server_shot_time:
		return
		
	next_server_shot_time = current_time + int(shot_interval * 1000.0)
	
	var ray_end: Vector3 = ray_origin + ray_direction.normalized() * shot_range
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_end, shot_collision_mask, ray_exclusions)
	
	query.collide_with_bodies = true
	query.collide_with_areas = detect_areas
	
	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	
	if result.is_empty():
		return
		
	# Record hit data to use elsewhere
	var hit_position: Vector3 = result["position"]
	var hit_normal: Vector3 = result["normal"]
	var hit_collider: Node = result["collider"] as Node
	var hit_receiver: Node = _find_hit_receiver(hit_collider)
	
	if hit_receiver != null:
		hit_receiver.call("_hit")
	else:
		_spawn_hit_marker(hit_position, hit_normal)
		
		if _is_networked():
			_receive_hit_marker.rpc(hit_position, hit_normal)
			
			
func _find_hit_receiver(collider: Node) -> Node:
	var candidate: Node = collider

	while candidate != null:
		if candidate.has_method("_hit"):
			return candidate

		candidate = candidate.get_parent()

	return null
	
	
func _collect_collision_exclusions(node: Node) -> void:
	if node is CollisionObject3D:
		ray_exclusions.append((node as CollisionObject3D).get_rid())

	for child in node.get_children():
		_collect_collision_exclusions(child)
		
		
@rpc("any_peer", "call_remote", "reliable")
func _receive_hit_marker(hit_position: Vector3, hit_normal: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return

	_spawn_hit_marker(hit_position, hit_normal)


func _spawn_hit_marker(hit_position: Vector3, hit_normal: Vector3) -> void:
	if hit_marker_scene == null:
		return
		
	var hit_instance: Node3D = hit_marker_scene.instantiate()

	var hit_parent: Node = get_tree().current_scene

	hit_parent.add_child(hit_instance)

	hit_instance.global_position = hit_position + hit_normal * hit_marker_offset

	# Delete object after delay
	if hit_marker_lifetime > 0.0:
		get_tree().create_timer(hit_marker_lifetime).timeout.connect(hit_instance.queue_free)
