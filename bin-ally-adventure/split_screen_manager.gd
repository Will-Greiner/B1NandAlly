extends Control
class_name SplitScreenManager

enum Layout { SIDE_BY_SIDE, TOP_BOTTOM }

@export_group("Players")
@export var players: Node3D
@export var camera_rig_path: NodePath = NodePath("CameraRig")

@export_group("First View")
@export var first_view: SubViewportContainer
@export var first_viewport: SubViewport
@export var first_camera: Camera3D
@export var first_player_hud: Control

@export_group("Second View")
@export var second_view: SubViewportContainer
@export var second_viewport: SubViewport
@export var second_camera: Camera3D
@export var second_player_hud: Control

@export_group("Layout")
@export var starting_layout: Layout = Layout.SIDE_BY_SIDE
@export_range(0.2, 0.8, 0.01) var split_ratio: float = 0.5
@export_range(0.0, 2.0, 0.05) var resize_duration: float = 0.4
@export var divider: ColorRect
@export_range(0.0, 20.0, 1.0) var divider_width: float = 4.0

@export_group("Remote Camera")
@export_range(1.0, 40.0, 1.0) var remote_camera_smoothing: float = 18.0

var current_layout: Layout = Layout.SIDE_BY_SIDE
var first_source: ThirdPersonCamera = null
var second_source: ThirdPersonCamera = null

var first_camera_initialized: bool = false
var second_camera_initialized: bool = false

var ratio_tween: Tween = null
var main_viewport: Viewport = null
var previous_disable_3d: bool = false
var previous_audio_listener: bool = false
var initialized: bool = false



func _ready() -> void:
	process_priority = 100
	current_layout = starting_layout
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Initialize both players viewports
	_configure_viewport(first_view, first_viewport, first_camera)
	_configure_viewport(first_view, first_viewport, first_camera)
	
	players.child_entered_tree.connect(_on_player_tree_changed)
	players.child_exiting_tree.connect(_on_player_tree_changed)
	
	initialized = true
	
	_refresh_players.call_deferred()
	
	
func _configure_viewport(container: SubViewportContainer, viewport: SubViewport, display_camera: Camera3D) -> void:
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	viewport.gui_disable_input = true
	viewport.audio_listener_enable_3d = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	
	display_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	display_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	display_camera.make_current()
	
	
func _on_player_tree_changed(_player: Node) -> void:
	_refresh_players.call_deferred()
	
	
func _refresh_players() -> void:
	var candidates: Array[Node] = []
	
	for player in players.get_children():
		if player.is_queued_for_deletion() or not player.is_inside_tree():
			continue
			
		if player.get_node_or_null(camera_rig_path) is ThirdPersonCamera:
			candidates.append(player)
			
	candidates.sort_custom(_sort_players)
	
	first_source = null
	second_source = null
	
	# Assign the players camera rig to drive each viewport
	
	if candidates.size() >= 1:
		first_source = candidates[0].get_node(camera_rig_path) as ThirdPersonCamera
		first_source.set_split_screen_enabled(true)
		
	if candidates.size() >= 2:
		second_source = candidates[1].get_node(camera_rig_path) as ThirdPersonCamera
		second_source.set_split_screen_enabled(true)
		
	first_camera_initialized = false
	second_camera_initialized = false
	
	_apply_layout()
	
	
# Determine which player holds which view
func _sort_players(first: Node, second: Node) -> bool:
	return first.get_multiplayer_authority() < second.get_multiplayer_authority()
	
	
# Update the camera data each frame
func _process(delta: float) -> void:
	_apply_layout()
	
	if is_instance_valid(first_source):
		_update_camera(first_source, first_camera, first_viewport, delta, first_camera_initialized)
		first_camera_initialized = true

	if is_instance_valid(second_source):
		_update_camera(second_source, second_camera, second_viewport, delta, second_camera_initialized)
		second_camera_initialized = true
		
		
func _update_camera(source: ThirdPersonCamera, display_camera: Camera3D, viewport: SubViewport, delta: float, camera_initialized: bool) -> void:
	# For when we update the viewport sizing
	source.set_displayed_View_size(Vector2(viewport.size))
	
	var target_transform: Transform3D = source.get_view_transform()
	
	if source.controls_enabled or not camera_initialized:
		display_camera.global_transform = target_transform
	else:
		var weight: float = 1.0 - exp(-remote_camera_smoothing * delta)
		display_camera.global_transform = display_camera.global_transform.interpolate_with(target_transform, weight)
		
	# Pass over camera data
	display_camera.fov = source.get_view_fov()
	display_camera.near = source.camera.near
	display_camera.far = source.camera.far
	display_camera.cull_mask = source.camera.cull_mask
	display_camera.environment = source.camera.environment
	display_camera.attributes = source.camera.attributes
	display_camera.h_offset = source.camera.h_offset
	display_camera.v_offset = source.camera.v_offset
	
	viewport.audio_listener_enable_3d = source.controls_enabled
	
	
func set_layout(layout: Layout) -> void:
	current_layout = layout

	_apply_layout()


func set_split_ratio(value: float, animated: bool = true) -> void:
	var target_ratio: float = clampf(value, 0.2, 0.8)

	if ratio_tween != null and ratio_tween.is_valid():
		ratio_tween.kill()

	if not animated or resize_duration <= 0.0:
		split_ratio = target_ratio
		_apply_layout()
		return

	ratio_tween = create_tween()
	ratio_tween.set_trans(Tween.TRANS_SINE)
	ratio_tween.set_ease(Tween.EASE_IN_OUT)
	ratio_tween.tween_property(self, "split_ratio", target_ratio, resize_duration)


func _apply_layout() -> void:
	var has_first: bool = is_instance_valid(first_source)
	var has_second: bool = is_instance_valid(second_source)

	first_view.visible = has_first
	second_view.visible = has_second
	divider.visible = has_first and has_second

	if first_player_hud != null:
		first_player_hud.visible = has_first

	if second_player_hud != null:
		second_player_hud.visible = has_second

	if not has_first:
		return

	var first_rect: Rect2 = Rect2(Vector2.ZERO, size)
	var second_rect: Rect2 = Rect2(Vector2.ZERO, size)
	var divider_rect: Rect2 = Rect2()

	if has_second:
		var ratio: float = clampf(split_ratio, 0.2, 0.8)

		if current_layout == Layout.SIDE_BY_SIDE:
			var boundary_x: float = size.x * ratio

			first_rect = Rect2(0.0, 0.0, boundary_x, size.y)
			second_rect = Rect2(boundary_x, 0.0, size.x - boundary_x, size.y)
			divider_rect = Rect2(boundary_x - divider_width * 0.5, 0.0, divider_width, size.y)
		else:
			var boundary_y: float = size.y * ratio

			first_rect = Rect2(0.0, 0.0, size.x, boundary_y)
			second_rect = Rect2(0.0, boundary_y, size.x, size.y - boundary_y)
			divider_rect = Rect2(0.0, boundary_y - divider_width * 0.5, size.x, divider_width)

	_set_control_rect(first_view, first_rect)
	_set_control_rect(second_view, second_rect)
	_set_control_rect(divider, divider_rect)

	if first_player_hud != null:
		_set_control_rect(first_player_hud, first_rect)

	if second_player_hud != null:
		_set_control_rect(second_player_hud, second_rect)


func _set_control_rect(control: Control, rect: Rect2) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	control.position = rect.position
	control.size = rect.size


func _exit_tree() -> void:
	if not initialized:
		return

	if is_instance_valid(first_source):
		first_source.set_split_screen_enabled(false)

	if is_instance_valid(second_source):
		second_source.set_split_screen_enabled(false)

	if is_instance_valid(main_viewport):
		main_viewport.disable_3d = previous_disable_3d
		main_viewport.audio_listener_enable_3d = previous_audio_listener
	
