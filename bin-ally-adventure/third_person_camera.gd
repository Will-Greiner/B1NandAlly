extends Node3D
class_name ThirdPersonCamera


@export_group("Mouse")
@export var mouse_sensitivity: float = 0.002
@export var invert_mouse_y: bool = false

@export_group("Controller")
@export var controller_sensitivity: float = 2.5
@export var invert_controller_y: bool = false

@export_group("Vertical Limits")
@export var minimum_pitch_degrees: float = -55.0
@export var maximum_pitch_degrees: float = 65.0
@export var starting_pitch_degrees: float = -12.0

@export_group("Replicated View")
@export var network_view_transform: Transform3D = Transform3D.IDENTITY
@export var network_view_fov: float = 75.0


var controls_enabled: bool = false
var split_screen_enabled: bool = false
var yaw_angle: float = 0.0
var pitch_angle: float = 0.0
var displayed_view_size: Vector2 = Vector2.ZERO


@onready var yaw_pivot: Node3D = $Yaw
@onready var pitch_pivot: Node3D = $Yaw/Pitch
@onready var spring_arm: SpringArm3D = $Yaw/Pitch/SpringArm3D
@onready var camera: Camera3D = $Yaw/Pitch/SpringArm3D/Camera3D


func _ready() -> void:
	yaw_angle = yaw_pivot.rotation.y
	pitch_angle = deg_to_rad(starting_pitch_degrees)
	
	var character: CollisionObject3D = get_parent() as  CollisionObject3D
	
	if character != null:
		spring_arm.add_excluded_object(character.get_rid())
		
		
	# Split screen aspect
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
		
	_apply_rotation()
	
	# Record camera data for network
	network_view_transform = camera.global_transform
	network_view_fov = camera.fov
	
	
# Handy control toggle
func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	camera.current = enabled
	
	if enabled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		
		
func set_split_screen_enabled(endabled: bool) -> void:
	split_screen_enabled = endabled
	camera.current = controls_enabled and not split_screen_enabled
	
	
func set_displayed_View_size(view_size: Vector2) -> void:
	displayed_view_size = view_size
	

# Allows controller to retreive aspect ratio for magnet functionality
func get_displayed_aspect_ratio() -> float:
	var view_size: Vector2 = displayed_view_size
	
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		view_size = get_viewport().get_visible_rect().size
		
	return view_size.x / maxf(view_size.y, 1.0)
	
	
# get the view transform for the local player or the connected player
func get_view_transform() -> Transform3D:
	if controls_enabled:
		return camera.global_transform
		
	return network_view_transform
	

# Get the fov for the local player or connected player
func get_view_fov() -> float:
	if controls_enabled:
		return camera.fov
		
	return network_view_fov
		
		
# Mouse input handling
func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return
		
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
		
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var vertical_sign: float = -1.0 if invert_mouse_y else 1.0
		
		yaw_angle -= event.relative.x * mouse_sensitivity
		pitch_angle -= event.relative.y * mouse_sensitivity * vertical_sign
		
		_apply_rotation()
		
		
func _process(delta: float) -> void:
	if not controls_enabled:
		return
		
	var look_input: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	var vertical_sign: float = -1.0 if invert_controller_y else 1.0
	
	yaw_angle -= look_input.x * controller_sensitivity * delta
	pitch_angle -= look_input.y * controller_sensitivity * vertical_sign * delta
	
	_apply_rotation()
	
	# Record data to pass to the network
	network_view_transform = camera.global_transform
	network_view_fov = camera.fov
	
	
func get_movement_direction(input_vector: Vector2) -> Vector3:
	var direction: Vector3 = yaw_pivot.global_basis * Vector3(input_vector.x, 0.0, input_vector.y)
	
	direction.y = 0.0
	
	return direction.normalized()
	
	
func get_forward_direction() -> Vector3:
	var direction: Vector3 = -yaw_pivot.global_basis.z
	
	direction.y = 0.0
	
	return direction.normalized()
	
	
func _apply_rotation() -> void:
	pitch_angle = clampf(pitch_angle, deg_to_rad(minimum_pitch_degrees), deg_to_rad(maximum_pitch_degrees))
	
	yaw_pivot.rotation.y = yaw_angle
	pitch_pivot.rotation.x = pitch_angle
	
	
func get_dash_direction() -> Vector3:
	return -pitch_pivot.global_basis.z.normalized()
	
