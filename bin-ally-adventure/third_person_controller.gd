extends CharacterBody3D


signal dash_started
signal dash_finished
signal traversal_started(is_mantle: bool)
signal traversal_finished(completed: bool)
signal wall_run_started
signal wall_run_finished

enum MovementState { NORMAL, DASH, TRAVERSAL, WALL_RUN }


@export_group("Movement")
@export var walk_speed: float = 2.2
@export var run_speed: float = 4.6
@export var acceleration: float = 14.0
@export var braking: float = 20.0
@export var air_acceleration: float = 3.0
@export var turning_speed: float = 12.0

@export_group("Ground")
@export var gravity: float = 20.0
@export var maximum_fall_speed: float = 35.0
@export var ground_snap_distance: float = 0.3
@export var maximum_slope_degrees: float = 45.0

@export_group("Dash")
@export var dash_enabled: bool = false
@export var dash_speed: float = 10.0
@export var dash_duration: float = 0.2
@export var dash_cooldown: float = 0.65
@export_range(0.0, 500.0, 1.0) var dash_braking: float = 150.0
@export var allow_air_dash: bool = false

@export_group("Traversal Detection")
@export_flags_3d_physics var traversal_collision_mask: int = 1
@export var traversal_reach: float = 0.55
@export var traversal_minimum_height: float = 0.25
@export var traversal_clearance: float = 0.08

@export_group("Low Vault")
@export var vault_enabled: bool = true
@export var low_vault_maximum_height: float = 0.8
@export var low_vault_maximum_depth: float = 1.2
@export var low_vault_maximum_drop: float = 0.6
@export var low_vault_duration: float = 0.45

@export_group("Ledge Climb")
@export var mantle_enabled: bool = true
@export var mantle_maximum_height: float = 1.6
@export var mantle_duration: float = 0.7

@export_group("Wall Run")
@export var wall_run_enabled: bool = true
@export var wall_run_speed: float = 4.6
@export var wall_run_acceleration: float = 5.0
@export var wall_run_minimum_entry_speed: float = 2.8
@export var wall_run_maximum_speed: float = 7.0
@export var wall_run_support_duration: float = 0.35
@export var wall_run_maximum_duration: float = 2.0
@export var wall_run_gravity: float = 8.0
@export var wall_run_maximum_slide_speed: float = 6.0
@export var wall_run_maximum_entry_fall_speed: float = 5.0
@export var wall_run_wall_reach: float = 0.25
@export var wall_run_wall_pressure: float = 1.5
@export var wall_run_reattach_delay: float = 0.35

@export_group("Magnet")
@export var pulling:bool = false
@export var pushing:bool = false
@export var holding:bool = false
@export var attracting:bool = false
@export var magnet_speed:float = 12.0
@export var magnet_grab_range:float = 500.0
@export var hold_distance: float = 0.5
@export var magnetized_object: RigidBody3D
@export var hold_point: Marker3D
@export var projection_shape: ShapeCast3D

@export_group("Controls")
@export var movement_enabled: bool = true
@export var sprint_toggle: bool = false
@export var camera: Camera3D

@export_group("Multiplayer")
@export var networked: bool = false


var move_input: Vector2 = Vector2.ZERO
var move_direction: Vector3 = Vector3.ZERO

var sprint_toggled: bool = false

var dash_direction: Vector3 = Vector3.ZERO
var dash_time_remaining: float = 0.0
var dash_cooldown_remaining: float = 0.0

var movement_state: MovementState = MovementState.NORMAL

var traversal_points: Array[Vector3] = []
var traversal_point_index: int = 0
var traversal_speed: float = 0.0
var traversal_direction: Vector3 = Vector3.ZERO
var traversal_exit_velocity: Vector3 = Vector3.ZERO
var traversal_retry_remaining: float = 0.0

var wall_run_direction: Vector3 = Vector3.ZERO
var wall_run_normal: Vector3 = Vector3.ZERO
var wall_run_current_speed: float = 0.0
var wall_run_elapsed: float = 0.0
var wall_run_reattach_remaining: float = 0.0
var wall_run_wall_rid: RID = RID()


@onready var visual_root: Node3D = $VisualRoot
@onready var camera_rig: ThirdPersonCamera = $CameraRig
@onready var character_collision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	floor_snap_length = ground_snap_distance
	floor_max_angle = deg_to_rad(maximum_slope_degrees)
	floor_stop_on_slope = true
	floor_constant_speed = true
	
	camera_rig.set_controls_enabled(_is_local_player())
	
	
func _physics_process(delta: float) -> void:
	if not _is_local_player():
		return
	
	if not _is_local_player():
		return

	dash_cooldown_remaining = maxf(dash_cooldown_remaining - delta, 0.0)
	traversal_retry_remaining = maxf(traversal_retry_remaining - delta, 0.0)
	wall_run_reattach_remaining = maxf(wall_run_reattach_remaining - delta, 0.0)

	_read_movement_input()

	if not movement_enabled:
		_finish_dash()
		_end_wall_run()
		_end_traversal(false)

	if movement_enabled and movement_state != MovementState.TRAVERSAL:
		if Input.is_action_just_pressed("dash"):
			_try_start_dash()

		var manual_traversal: bool = Input.is_action_just_pressed("traverse")
		_try_start_traversal(manual_traversal, delta)

		if movement_state == MovementState.NORMAL:
			_try_start_wall_run()

	floor_snap_length = ground_snap_distance if movement_state == MovementState.NORMAL else 0.0

	var traversal_frame: bool = movement_state == MovementState.TRAVERSAL
	var dash_frame: bool = movement_state == MovementState.DASH

	match movement_state:
		MovementState.NORMAL:
			_apply_gravity(delta)
			_update_ground_movement(delta)

		MovementState.DASH:
			_update_dash(delta)

		MovementState.TRAVERSAL:
			_update_traversal(delta)

		MovementState.WALL_RUN:
			if not _update_wall_run(delta):
				_apply_gravity(delta)
				_update_ground_movement(delta)

	if not traversal_frame:
		move_and_slide()

		if is_on_wall() and (dash_frame or movement_state == MovementState.NORMAL):
			var started_traversal: bool = _try_start_traversal(false, delta)

			if not started_traversal:
				var started_wall_run: bool = _try_start_wall_run()

				if not started_wall_run and movement_state == MovementState.DASH:
					_finish_dash()

	_update_visual_rotation(delta)

	if not pulling:
		_magnet_detect()

	if Input.is_action_pressed("trigger"):
		if magnetized_object != null:
			pulling = true
			_magnet_attract(delta)
	elif Input.is_action_just_released("trigger"):
		if magnetized_object != null:
			if holding:
				_magnet_release(delta)
			else:
				_magnet_drop()
	
	
func _is_local_player() -> bool:
	return not networked or is_multiplayer_authority()
	
	
func _read_movement_input() -> void:
	move_input = Vector2.ZERO
	move_direction = Vector3.ZERO
	
	if not movement_enabled:
		sprint_toggled = false
		return
		
	move_input = Input.get_vector("move_left", "move_right", "move_forward", "move_backwards")
	
	if move_input.length_squared() > 0.0:
		move_direction = camera_rig.get_movement_direction(move_input)
		
	if sprint_toggle and Input.is_action_just_pressed("sprint"):
		sprint_toggled = not sprint_toggled
		
	if move_input.length_squared() == 0.0:
		sprint_toggled = false
		
		
func _apply_gravity(delta: float) -> void:
	if is_on_floor() and velocity.y <= 0.0:
		velocity.y = 0.0
	else:
		velocity.y = maxf(velocity.y - gravity * delta, -maximum_fall_speed)
		
		
func _update_ground_movement(delta: float) -> void:
	var sprinting: bool = sprint_toggled if sprint_toggle else Input.is_action_pressed("sprint")
	var selected_speed: float = run_speed if sprinting else walk_speed
	
	var target_velocity: Vector3 = move_direction * selected_speed * move_input.length()
	var horizontal_velocity: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	
	var changing_direction: bool = horizontal_velocity.dot(target_velocity) < 0.0
	var slowing_down: bool = target_velocity.length_squared() < horizontal_velocity.length_squared()
	var movement_rate: float = acceleration
	
	if changing_direction or slowing_down:
		movement_rate = braking
		
	if not is_on_floor():
		movement_rate = air_acceleration
		
	horizontal_velocity = horizontal_velocity.move_toward(target_velocity, movement_rate * delta)
	
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	
	
func _try_start_dash() -> void:
	if not movement_enabled or not dash_enabled:
		return

	if movement_state == MovementState.DASH or movement_state == MovementState.TRAVERSAL:
		return

	if dash_cooldown_remaining > 0.0:
		return

	if not is_on_floor() and not allow_air_dash:
		return

	_end_wall_run()

	dash_direction = camera_rig.get_dash_direction()
	dash_time_remaining = maxf(dash_duration, 0.01)
	dash_cooldown_remaining = dash_time_remaining + dash_cooldown
	movement_state = MovementState.DASH

	dash_started.emit()


func _update_dash(delta: float) -> void:
	var duration: float = maxf(dash_duration, 0.01)
	dash_time_remaining = maxf(dash_time_remaining - delta, 0.0)

	var elapsed: float = duration - dash_time_remaining
	var current_speed: float = maxf(dash_speed - dash_braking * elapsed, 0.0)

	velocity = dash_direction * current_speed

	if dash_time_remaining <= 0.0:
		_finish_dash()


func _finish_dash() -> void:
	if movement_state != MovementState.DASH:
		return

	dash_time_remaining = 0.0
	movement_state = MovementState.NORMAL

	dash_finished.emit()
	
	
func _update_visual_rotation(delta: float) -> void:
	var facing_direction: Vector3 = move_direction

	match movement_state:
		MovementState.DASH:
			facing_direction = dash_direction

		MovementState.TRAVERSAL:
			facing_direction = traversal_direction

		MovementState.WALL_RUN:
			facing_direction = wall_run_direction

	facing_direction.y = 0.0

	if facing_direction.length_squared() < 0.001:
		return

	var target_angle: float = atan2(-facing_direction.x, -facing_direction.z)
	var rotation_weight: float = 1.0 - exp(-turning_speed * delta)

	visual_root.global_rotation.y = lerp_angle(visual_root.global_rotation.y, target_angle, rotation_weight)
	
	
func _get_capsule_radius() -> float:
	return (character_collision.shape as CapsuleShape3D).radius


func _get_feet_position() -> Vector3:
	var capsule: CapsuleShape3D = character_collision.shape as CapsuleShape3D
	return character_collision.global_position - Vector3.UP * capsule.height * 0.5


func _root_position_for_feet(feet_position: Vector3) -> Vector3:
	return feet_position - (_get_feet_position() - global_position)


func _traversal_raycast(from_position: Vector3, to_position: Vector3) -> Dictionary:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from_position, to_position, traversal_collision_mask, [get_rid()])
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(query)


func _is_static_traversal_hit(hit: Dictionary) -> bool:
	if hit.is_empty():
		return false

	return hit["collider"] is StaticBody3D or hit["collider"] is CSGShape3D


func _is_walkable_traversal_hit(hit: Dictionary) -> bool:
	if not _is_static_traversal_hit(hit):
		return false

	var normal: Vector3 = hit["normal"]
	return normal.dot(Vector3.UP) >= cos(floor_max_angle)


func _traversal_position_is_clear(root_position: Vector3) -> bool:
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	var shape_transform: Transform3D = character_collision.global_transform
	shape_transform.origin += root_position - global_position

	query.shape = character_collision.shape
	query.transform = shape_transform
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	query.margin = 0.005
	query.collide_with_areas = false
	query.collide_with_bodies = true

	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _traversal_route_is_clear(points: Array[Vector3]) -> bool:
	var test_transform: Transform3D = global_transform

	for point in points:
		if not _traversal_position_is_clear(point):
			return false

		if test_move(test_transform, point - test_transform.origin):
			return false

		test_transform.origin = point

	return true


func _get_traversal_direction(manual: bool) -> Vector3:
	var direction: Vector3 = move_direction

	if movement_state == MovementState.DASH:
		direction = dash_direction
	elif movement_state == MovementState.WALL_RUN and not manual:
		direction = wall_run_direction

	if direction.length_squared() < 0.001 and manual:
		direction = camera_rig.get_forward_direction()

	direction.y = 0.0

	return direction.normalized()
	
	
func _try_start_traversal(manual: bool, delta: float) -> bool:
	if not movement_enabled or movement_state == MovementState.TRAVERSAL:
		return false

	if manual:
		if not vault_enabled and not mantle_enabled:
			return false
	elif not vault_enabled:
		return false

	if traversal_retry_remaining > 0.0 and not manual:
		return false

	if not manual and movement_state != MovementState.DASH and move_input.length_squared() < 0.01:
		return false

	var direction: Vector3 = _get_traversal_direction(manual)

	if direction.length_squared() < 0.001:
		return false

	traversal_retry_remaining = 0.08

	var feet: Vector3 = _get_feet_position()
	var radius: float = _get_capsule_radius()
	var maximum_height: float = mantle_maximum_height if manual and mantle_enabled else low_vault_maximum_height
	var horizontal_speed: float = Vector3(velocity.x, 0.0, velocity.z).length()
	var probe_distance: float = radius + traversal_reach + horizontal_speed * delta
	var face_hit: Dictionary = {}

	for probe_height in [0.15, 0.65, 1.15]:
		if probe_height > maximum_height:
			continue

		var origin: Vector3 = feet + Vector3.UP * probe_height
		var hit: Dictionary = _traversal_raycast(origin, origin + direction * probe_distance)

		if not _is_static_traversal_hit(hit):
			continue

		var normal: Vector3 = hit["normal"]

		if absf(normal.y) > 0.2 or direction.dot(-normal) < 0.5:
			continue

		face_hit = hit
		break

	if face_hit.is_empty():
		return false

	var face_position: Vector3 = face_hit["position"]
	var top_probe: Vector3 = face_position + direction * 0.06
	var top_from: Vector3 = Vector3(top_probe.x, feet.y + maximum_height + 0.15, top_probe.z)
	var top_to: Vector3 = Vector3(top_probe.x, feet.y + 0.05, top_probe.z)
	var top_hit: Dictionary = _traversal_raycast(top_from, top_to)

	if not _is_walkable_traversal_hit(top_hit):
		return false

	if top_hit["collider"] != face_hit["collider"]:
		return false

	var top_position: Vector3 = top_hit["position"]
	var obstacle_height: float = top_position.y - feet.y

	if obstacle_height < traversal_minimum_height or obstacle_height > maximum_height:
		return false

	var is_low_obstacle: bool = vault_enabled and obstacle_height <= low_vault_maximum_height

	if is_low_obstacle:
		var sample_count: int = ceili(low_vault_maximum_depth / 0.2) + 2

		for index in range(sample_count):
			var distance: float = radius + 0.12 + float(index) * 0.2

			if distance > low_vault_maximum_depth + radius + 0.15:
				break

			var sample_position: Vector3 = face_position + direction * distance
			var landing_from: Vector3 = Vector3(sample_position.x, top_position.y + 0.15, sample_position.z)
			var landing_to: Vector3 = Vector3(sample_position.x, feet.y - low_vault_maximum_drop, sample_position.z)
			var landing_hit: Dictionary = _traversal_raycast(landing_from, landing_to)

			if not _is_walkable_traversal_hit(landing_hit):
				continue

			var landing_position: Vector3 = landing_hit["position"]

			if landing_position.y > top_position.y - 0.12:
				continue

			if _begin_traversal(landing_position, top_position.y, direction, false):
				return true

	if not is_low_obstacle and (not manual or not mantle_enabled):
		return false

	var standing_probe: Vector3 = face_position + direction * (radius + 0.12)
	var standing_from: Vector3 = Vector3(standing_probe.x, top_position.y + 0.15, standing_probe.z)
	var standing_to: Vector3 = Vector3(standing_probe.x, top_position.y - 0.15, standing_probe.z)
	var standing_hit: Dictionary = _traversal_raycast(standing_from, standing_to)

	if not _is_walkable_traversal_hit(standing_hit):
		return false

	if standing_hit["collider"] != top_hit["collider"]:
		return false

	var standing_position: Vector3 = standing_hit["position"]

	if absf(standing_position.y - top_position.y) > 0.1:
		return false

	return _begin_traversal(standing_position, top_position.y, direction, not is_low_obstacle)
	
	
func _begin_traversal(destination_feet: Vector3, obstacle_top_y: float, direction: Vector3, is_mantle: bool) -> bool:
	var feet: Vector3 = _get_feet_position()
	var destination: Vector3 = _root_position_for_feet(destination_feet + Vector3.UP * traversal_clearance)
	var raised_feet_y: float = maxf(obstacle_top_y, destination_feet.y) + traversal_clearance
	var raised_start: Vector3 = global_position + Vector3.UP * (raised_feet_y - feet.y)
	var raised_finish: Vector3 = Vector3(destination.x, raised_start.y, destination.z)
	var route: Array[Vector3] = [raised_start, raised_finish, destination]

	if not _traversal_route_is_clear(route):
		return false

	var route_length: float = global_position.distance_to(raised_start)
	route_length += raised_start.distance_to(raised_finish)
	route_length += raised_finish.distance_to(destination)

	var duration: float = mantle_duration if is_mantle else low_vault_duration
	var entry_speed: float = Vector3(velocity.x, 0.0, velocity.z).length()
	var sprinting: bool = sprint_toggled if sprint_toggle else Input.is_action_pressed("sprint")
	var desired_exit_speed: float = run_speed if sprinting else walk_speed
	var exit_speed: float = minf(maxf(entry_speed, desired_exit_speed * move_input.length()), run_speed)

	_finish_dash()
	_end_wall_run()

	traversal_points = route
	traversal_point_index = 0
	traversal_speed = route_length / maxf(duration, 0.05)
	traversal_direction = direction
	traversal_exit_velocity = Vector3.ZERO if is_mantle else direction * exit_speed
	movement_state = MovementState.TRAVERSAL
	floor_snap_length = 0.0
	velocity = Vector3.ZERO

	traversal_started.emit(is_mantle)

	return true


func _update_traversal(delta: float) -> void:
	var movement_budget: float = traversal_speed * delta
	var frame_start: Vector3 = global_position

	while movement_budget > 0.0 and traversal_point_index < traversal_points.size():
		var target: Vector3 = traversal_points[traversal_point_index]
		var offset: Vector3 = target - global_position
		var distance: float = offset.length()

		if distance < 0.001:
			traversal_point_index += 1
			continue

		var step_distance: float = minf(distance, movement_budget)
		var motion: Vector3 = offset / distance * step_distance
		var collision: KinematicCollision3D = move_and_collide(motion)

		if collision != null:
			_end_traversal(false)
			return

		movement_budget -= step_distance

		if step_distance >= distance - 0.001:
			traversal_point_index += 1

	if traversal_point_index >= traversal_points.size():
		_end_traversal(true)
	else:
		velocity = (global_position - frame_start) / maxf(delta, 0.0001)


func _end_traversal(completed: bool) -> void:
	if movement_state != MovementState.TRAVERSAL:
		return

	movement_state = MovementState.NORMAL
	velocity = traversal_exit_velocity if completed else Vector3.ZERO
	traversal_points.clear()
	traversal_point_index = 0
	traversal_retry_remaining = 0.2

	traversal_finished.emit(completed)
	
	
func _find_wall_run_surface(travel_direction: Vector3) -> Dictionary:
	var capsule: CapsuleShape3D = character_collision.shape as CapsuleShape3D
	var feet: Vector3 = _get_feet_position()
	var side_direction: Vector3 = Vector3.UP.cross(travel_direction).normalized()
	var probe_distance: float = capsule.radius + wall_run_wall_reach

	for side_sign in [-1.0, 1.0]:
		var probe_direction: Vector3 = side_direction * side_sign
		var upper_origin: Vector3 = feet + Vector3.UP * capsule.height * 0.65
		var lower_origin: Vector3 = feet + Vector3.UP * capsule.height * 0.35
		var upper_hit: Dictionary = _traversal_raycast(upper_origin, upper_origin + probe_direction * probe_distance)
		var lower_hit: Dictionary = _traversal_raycast(lower_origin, lower_origin + probe_direction * probe_distance)

		if not _is_static_traversal_hit(upper_hit) or not _is_static_traversal_hit(lower_hit):
			continue

		if upper_hit["collider"] != lower_hit["collider"]:
			continue

		var normal: Vector3 = upper_hit["normal"]
		var lower_normal: Vector3 = lower_hit["normal"]

		if absf(normal.y) > 0.15 or normal.dot(lower_normal) < 0.95:
			continue

		if absf(travel_direction.dot(normal)) > 0.7:
			continue

		if movement_state == MovementState.WALL_RUN:
			if normal.dot(wall_run_normal) < 0.85:
				continue
		elif wall_run_reattach_remaining > 0.0:
			if upper_hit["rid"] == wall_run_wall_rid and normal.dot(wall_run_normal) > 0.85:
				continue

		return upper_hit

	return {}


func _wall_run_has_ground_below() -> bool:
	var feet: Vector3 = _get_feet_position()
	var hit: Dictionary = _traversal_raycast(feet + Vector3.UP * 0.04, feet - Vector3.UP * 0.2)
	return _is_walkable_traversal_hit(hit)


func _try_start_wall_run() -> bool:
	if not wall_run_enabled or not movement_enabled:
		return false

	if movement_state != MovementState.NORMAL and movement_state != MovementState.DASH:
		return false

	if is_on_floor() or move_input.length_squared() < 0.01:
		return false

	if velocity.y < -wall_run_maximum_entry_fall_speed or _wall_run_has_ground_below():
		return false

	var horizontal_velocity: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	var entry_speed: float = horizontal_velocity.length()

	if entry_speed < wall_run_minimum_entry_speed:
		return false

	var travel_direction: Vector3 = horizontal_velocity.normalized()
	var hit: Dictionary = _find_wall_run_surface(travel_direction)

	if hit.is_empty():
		return false

	var normal: Vector3 = hit["normal"]
	var tangent: Vector3 = horizontal_velocity.slide(normal)
	tangent.y = 0.0

	if tangent.length() < wall_run_minimum_entry_speed:
		return false

	tangent = tangent.normalized()

	if move_direction.dot(normal) > 0.25 or move_direction.dot(tangent) < 0.2:
		return false

	_finish_dash()

	wall_run_normal = normal
	wall_run_direction = tangent
	wall_run_wall_rid = hit["rid"]
	wall_run_current_speed = minf(horizontal_velocity.slide(normal).length(), wall_run_maximum_speed)
	wall_run_elapsed = 0.0
	velocity.y = clampf(velocity.y, -1.0, 1.5)
	movement_state = MovementState.WALL_RUN
	floor_snap_length = 0.0

	wall_run_started.emit()

	return true


func _update_wall_run(delta: float) -> bool:
	if not wall_run_enabled or not movement_enabled or is_on_floor():
		_end_wall_run()
		return false

	if move_input.length_squared() < 0.01 or _wall_run_has_ground_below():
		_end_wall_run()
		return false

	var hit: Dictionary = _find_wall_run_surface(wall_run_direction)

	if hit.is_empty():
		_end_wall_run()
		return false

	var normal: Vector3 = hit["normal"]
	var tangent: Vector3 = wall_run_direction.slide(normal)
	tangent.y = 0.0

	if tangent.length_squared() < 0.001:
		_end_wall_run()
		return false

	tangent = tangent.normalized()

	if move_direction.dot(normal) > 0.25 or move_direction.dot(tangent) < 0.2:
		_end_wall_run()
		return false

	wall_run_elapsed += delta

	if wall_run_elapsed >= wall_run_maximum_duration:
		_end_wall_run()
		return false

	wall_run_normal = normal
	wall_run_direction = tangent
	wall_run_wall_rid = hit["rid"]

	var target_speed: float = clampf(wall_run_speed, wall_run_minimum_entry_speed, wall_run_maximum_speed)
	wall_run_current_speed = move_toward(wall_run_current_speed, target_speed, wall_run_acceleration * delta)

	var vertical_speed: float = velocity.y

	if wall_run_elapsed <= wall_run_support_duration:
		vertical_speed = move_toward(vertical_speed, 0.0, gravity * delta)
	else:
		vertical_speed = maxf(vertical_speed - wall_run_gravity * delta, -wall_run_maximum_slide_speed)

	velocity = wall_run_direction * wall_run_current_speed - wall_run_normal * wall_run_wall_pressure
	velocity.y = vertical_speed

	return true


func _end_wall_run() -> void:
	if movement_state != MovementState.WALL_RUN:
		return

	movement_state = MovementState.NORMAL
	wall_run_reattach_remaining = wall_run_reattach_delay

	var horizontal_velocity: Vector3 = wall_run_direction * wall_run_current_speed
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z

	wall_run_finished.emit()
		
		
func _magnet_detect() -> void:
	if not projection_shape.shape is ConvexPolygonShape3D:
		push_error("projection_shape must have a ConvexPolygonShape3D assigned!")
		return
	var fov_rad: float = deg_to_rad(camera.fov)
	var aspect_ratio: float = get_viewport().get_visible_rect().size.x / get_viewport().get_visible_rect().size.y
	
	var half_height: float = magnet_grab_range * tan(fov_rad * 0.5)
	var half_width: float = half_height * aspect_ratio
	
	var apex = Vector3.ZERO
	var top_left = Vector3(-half_width, half_height, -magnet_grab_range)
	var top_right = Vector3(half_width, half_height, -magnet_grab_range)
	var bottom_left = Vector3(-half_width, -half_height, -magnet_grab_range)
	var bottom_right = Vector3(half_width, -half_height, -magnet_grab_range)
	
	var points: PackedVector3Array = [apex, top_left, top_right, bottom_left, bottom_right]
	projection_shape.shape.points = points

	projection_shape.target_position = Vector3.ZERO
	projection_shape.force_shapecast_update()
	
	if projection_shape.is_colliding():
		var best_target: RigidBody3D = null
		var smallest_angle: float = INF
		
		var camera_forward: Vector3 = -camera.global_transform.basis.z
		
		var collision_count = projection_shape.get_collision_count()
		for i in range(collision_count):
			var collider = projection_shape.get_collider(i)
			
			if collider is RigidBody3D:
				# Vector from camera straight to the object
				var to_object: Vector3 = (collider.global_position - camera.global_position).normalized()
				
				# Calculate the angle deviation from the center of the screen
				# (Using angle_to yields radians; smaller = closer to your crosshair)
				var angle_deviation: float = camera_forward.angle_to(to_object)
				
				# If this object is tighter to the center line than the previous best, select it
				if angle_deviation < smallest_angle:
					smallest_angle = angle_deviation
					best_target = collider
		magnetized_object = best_target
		
	else:
		magnetized_object = null

func _magnet_attract(delta: float) -> void:
	if magnetized_object != null:
		var distance_vector = hold_point.global_position - magnetized_object.global_position
		if distance_vector.length() <= hold_distance:
			holding = true
		else:
			holding = false
		var target_velocity = distance_vector * magnet_speed
		magnetized_object.linear_velocity = magnetized_object.linear_velocity.lerp(target_velocity, magnet_speed*delta)
		
func _magnet_release(delta:float) -> void:
	if magnetized_object != null:
		var look_direction = -camera.global_transform.basis.z
		magnetized_object.linear_velocity = Vector3.ZERO
		magnetized_object.apply_central_impulse(look_direction * 20)
	holding = false
	pulling = false
	magnetized_object = null
func _magnet_drop() -> void:
	holding = false
	pulling = false
	magnetized_object = null
