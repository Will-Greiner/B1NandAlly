extends Control


@export_group("Scenes")
@export var game_scene: PackedScene

@export_group("Panels")
@export var main_panel: Control
@export var invite_panel: Control

@export_group("Buttons")
@export var new_game_button: Button
@export var singleplayer_button: Button
@export var invite_button: Button
@export var begin_button: Button
@export var back_button: Button
@export var quit_button: Button

@export_group("Lobby")
@export var player_list: ItemList
@export var status_label: Label


var game_instance: Node = null


func _ready() -> void:
	new_game_button.pressed.connect(_on_new_game_pressed)
	invite_button.pressed.connect(SteamNetworkManager.invite_friend)
	begin_button.pressed.connect(_on_begin_pressed)
	back_button.pressed.connect(_on_back_pressed)
	quit_button.pressed.connect(SteamNetworkManager.quit_game)
	singleplayer_button.pressed.connect(_on_singleplayer_pressed)

	SteamNetworkManager.status_changed.connect(_on_status_changed)
	SteamNetworkManager.session_changed.connect(_refresh_ui)
	SteamNetworkManager.session_started.connect(_on_session_started)
	SteamNetworkManager.session_ended.connect(_on_session_ended)
	SteamNetworkManager.game_started.connect(_on_game_started)

	status_label.text = SteamNetworkManager.status_text

	_refresh_ui()


func _on_new_game_pressed() -> void:
	if game_scene == null:
		status_label.text = "Assign a Game Scene in the Inspector."
		push_error("No game scene has been assigned.")
		return

	SteamNetworkManager.new_game()
	
	
func _on_singleplayer_pressed() -> void:
	if game_scene == null:
		status_label.text = "Assign a Game Scene in the Inspector."
		push_error("No game scene has been assigned.")
		return

	SteamNetworkManager.start_singleplayer()


func _on_session_started() -> void:
	_refresh_ui()


func _on_begin_pressed() -> void:
	if game_scene == null:
		status_label.text = "Assign a Game Scene in the Inspector."
		push_error("No game scene has been assigned.")
		return

	SteamNetworkManager.begin_game()


func _on_game_started() -> void:
	if game_scene == null:
		SteamNetworkManager.leave_game()
		status_label.text = "Assign a Game Scene in the Inspector."
		push_error("No game scene has been assigned.")
		return

	if game_instance != null:
		return

	game_instance = game_scene.instantiate()
	game_instance.name = "Game"

	add_child(game_instance)

	_refresh_ui()


func _on_session_ended() -> void:
	if game_instance != null:
		game_instance.queue_free()
		game_instance = null

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_refresh_ui()


func _on_status_changed(message: String) -> void:
	status_label.text = message


func _refresh_ui() -> void:
	var in_lobby: bool = SteamNetworkManager.busy or SteamNetworkManager.lobby_id != 0 or SteamNetworkManager.peer != null
	var game_running: bool = SteamNetworkManager.game_running
	status_label.visible = not SteamNetworkManager.singleplayer_running

	main_panel.visible = not in_lobby and not game_running
	invite_panel.visible = in_lobby and not game_running

	new_game_button.disabled = not SteamNetworkManager.steam_ready or SteamNetworkManager.busy
	
	singleplayer_button.disabled = SteamNetworkManager.busy or game_running
	mouse_filter = Control.MOUSE_FILTER_IGNORE if game_running else Control.MOUSE_FILTER_STOP

	invite_button.visible = SteamNetworkManager.hosting
	invite_button.disabled = SteamNetworkManager.get_lobby_members().size() >= SteamNetworkManager.MAX_PLAYERS

	begin_button.visible = SteamNetworkManager.hosting
	begin_button.disabled = not SteamNetworkManager.can_begin_game()

	_refresh_player_list()


func _refresh_player_list() -> void:
	player_list.clear()

	var members: Array[Dictionary] = SteamNetworkManager.get_lobby_members()

	for member in members:
		var display_name: String = str(member["name"])

		player_list.add_item(display_name)


func _on_back_pressed() -> void:
	SteamNetworkManager.leave_game()
