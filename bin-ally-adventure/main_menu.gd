extends Control


@export_group("Scenes")
@export var game_scene: PackedScene

@export_group("Panels")
@export var main_panel: Control
@export var online_panel: Control
@export var lobby_panel: Control

@export_group("Main Menu")
@export var play_online_button: Button
@export var singleplayer_button: Button
@export var quit_button: Button

@export_group("Online Menu")
@export var online_friends_list: ItemList
@export var online_empty_label: Label
@export var refresh_online_button: Button
@export var host_button: Button
@export var join_button: Button
@export var online_back_button: Button

@export_group("Lobby")
@export var player_list: ItemList
@export var lobby_help_label: Label
@export var begin_button: Button
@export var lobby_back_button: Button

@export_group("Lobby Invitations")
@export var friend_invite_controls: Control
@export var invite_friends_list: ItemList
@export var invite_empty_label: Label
@export var refresh_invite_button: Button
@export var invite_button: Button

@export_group("Status")
@export var status_label: Label

@export_group("Friends Refresh")
@export_range(2.0, 30.0, 1.0) var friends_refresh_interval: float = 5.0


var game_instance: Node = null
var online_menu_open: bool = false
var friends_refresh_elapsed: float = 0.0


func _ready() -> void:
	play_online_button.pressed.connect(_on_play_online_pressed)
	singleplayer_button.pressed.connect(_on_singleplayer_pressed)
	quit_button.pressed.connect(SteamNetworkManager.quit_game)

	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	online_back_button.pressed.connect(_on_online_back_pressed)
	refresh_online_button.pressed.connect(_on_refresh_friends_pressed)
	online_friends_list.item_selected.connect(_on_online_friend_selected)

	invite_button.pressed.connect(_on_invite_pressed)
	refresh_invite_button.pressed.connect(_on_refresh_friends_pressed)
	invite_friends_list.item_selected.connect(_on_invite_friend_selected)

	begin_button.pressed.connect(_on_begin_pressed)
	lobby_back_button.pressed.connect(_on_lobby_back_pressed)

	SteamNetworkManager.status_changed.connect(_on_status_changed)
	SteamNetworkManager.session_changed.connect(_refresh_ui)
	SteamNetworkManager.session_started.connect(_refresh_ui)
	SteamNetworkManager.session_ended.connect(_on_session_ended)
	SteamNetworkManager.game_started.connect(_on_game_started)
	SteamNetworkManager.friends_updated.connect(_refresh_friend_lists)

	status_label.text = SteamNetworkManager.status_text

	_refresh_ui()


func _process(delta: float) -> void:
	if SteamNetworkManager.game_running or not SteamNetworkManager.steam_ready:
		return

	if not online_panel.visible and not friend_invite_controls.is_visible_in_tree():
		return

	friends_refresh_elapsed += delta

	if friends_refresh_elapsed >= friends_refresh_interval:
		_on_refresh_friends_pressed()


func _has_game_scene() -> bool:
	if game_scene != null:
		return true

	status_label.text = "Assign a Game Scene in the Inspector."
	push_error("MainMenu: assign a Game Scene.")

	return false


func _on_play_online_pressed() -> void:
	online_menu_open = true

	_refresh_ui()
	_on_refresh_friends_pressed()


func _on_online_back_pressed() -> void:
	online_menu_open = false

	_refresh_ui()


func _on_host_pressed() -> void:
	if not _has_game_scene():
		return

	online_menu_open = true

	SteamNetworkManager.new_game()


func _on_join_pressed() -> void:
	if not _has_game_scene():
		return

	var selected_items: PackedInt32Array = online_friends_list.get_selected_items()

	if selected_items.is_empty():
		return

	var friend: Dictionary = online_friends_list.get_item_metadata(selected_items[0])

	if not bool(friend["joinable"]):
		return

	online_menu_open = true

	SteamNetworkManager.join_friend_lobby(int(friend["lobby_id"]))


func _on_singleplayer_pressed() -> void:
	if not _has_game_scene():
		return

	SteamNetworkManager.start_singleplayer()


func _on_begin_pressed() -> void:
	if not _has_game_scene():
		return

	SteamNetworkManager.begin_game()


func _on_lobby_back_pressed() -> void:
	online_menu_open = true

	SteamNetworkManager.leave_game()

	_on_refresh_friends_pressed()


func _on_refresh_friends_pressed() -> void:
	friends_refresh_elapsed = 0.0

	SteamNetworkManager.refresh_friend_lobbies()


func _on_online_friend_selected(_index: int) -> void:
	_update_friend_buttons()


func _on_invite_friend_selected(_index: int) -> void:
	_update_friend_buttons()


func _on_invite_pressed() -> void:
	var selected_items: PackedInt32Array = invite_friends_list.get_selected_items()

	if selected_items.is_empty():
		return

	var friend: Dictionary = invite_friends_list.get_item_metadata(selected_items[0])

	SteamNetworkManager.invite_friend_to_lobby(int(friend["steam_id"]))


func _on_game_started() -> void:
	if not _has_game_scene():
		SteamNetworkManager.leave_game()
		status_label.text = "Assign a Game Scene in the Inspector."
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

	online_menu_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_refresh_ui()


func _on_status_changed(message: String) -> void:
	status_label.text = message


func _refresh_ui() -> void:
	var game_running: bool = SteamNetworkManager.game_running
	var in_session: bool = SteamNetworkManager.busy or SteamNetworkManager.lobby_id != 0 or SteamNetworkManager.peer != null
	var members: Array[Dictionary] = SteamNetworkManager.get_lobby_members()
	var partner_present: bool = members.size() >= SteamNetworkManager.MAX_PLAYERS

	main_panel.visible = not game_running and not in_session and not online_menu_open
	online_panel.visible = not game_running and not in_session and online_menu_open
	lobby_panel.visible = not game_running and in_session
	status_label.visible = not game_running

	mouse_filter = Control.MOUSE_FILTER_IGNORE if game_running else Control.MOUSE_FILTER_STOP

	play_online_button.disabled = not SteamNetworkManager.steam_ready or SteamNetworkManager.busy
	singleplayer_button.disabled = SteamNetworkManager.busy or game_running

	host_button.disabled = not SteamNetworkManager.steam_ready or in_session or game_running
	refresh_online_button.disabled = not SteamNetworkManager.steam_ready

	friend_invite_controls.visible = lobby_panel.visible and SteamNetworkManager.hosting and not SteamNetworkManager.busy and not partner_present

	begin_button.visible = true
	begin_button.disabled = not SteamNetworkManager.can_begin_game()

	if SteamNetworkManager.busy:
		lobby_help_label.text = SteamNetworkManager.status_text
	elif SteamNetworkManager.hosting:
		if SteamNetworkManager.can_begin_game():
			lobby_help_label.text = "Both players are connected. Press Begin."
		elif partner_present:
			lobby_help_label.text = "Your friend is connecting..."
		else:
			lobby_help_label.text = "Invite a friend or wait for them to join."
	else:
		lobby_help_label.text = "Waiting for host to begin."

	_refresh_player_list()
	_refresh_friend_lists()


func _refresh_player_list() -> void:
	player_list.clear()

	var members: Array[Dictionary] = SteamNetworkManager.get_lobby_members()

	for member in members:
		var member_id: int = int(member["steam_id"])
		var display_name: String = str(member["name"])
		var connection_text: String = "Connecting..."

		if bool(member["is_host"]):
			display_name += " — Host"
			connection_text = "Connected"
		elif member_id == SteamNetworkManager.steam_id:
			connection_text = "Connecting..." if SteamNetworkManager.busy else "Connected"
		elif SteamNetworkManager.can_begin_game():
			connection_text = "Connected"

		if member_id == SteamNetworkManager.steam_id:
			display_name += " (You)"

		player_list.add_item(display_name + " — " + connection_text)

	if members.size() == 1:
		player_list.add_item("Waiting for another player...")


func _refresh_friend_lists() -> void:
	var friends: Array[Dictionary] = SteamNetworkManager.get_friends_in_game()
	var online_selection: int = _get_selected_friend_id(online_friends_list)
	var invite_selection: int = _get_selected_friend_id(invite_friends_list)
	var members: Array[Dictionary] = SteamNetworkManager.get_lobby_members()

	online_friends_list.clear()
	invite_friends_list.clear()

	for friend in friends:
		var friend_id: int = int(friend["steam_id"])
		var online_index: int = online_friends_list.add_item(str(friend["name"]) + " — " + str(friend["description"]))

		online_friends_list.set_item_metadata(online_index, friend)

		if friend_id == online_selection:
			online_friends_list.select(online_index)

		var already_in_lobby: bool = false

		for member in members:
			if int(member["steam_id"]) == friend_id:
				already_in_lobby = true
				break

		if already_in_lobby:
			continue

		var invite_index: int = invite_friends_list.add_item(str(friend["name"]))

		invite_friends_list.set_item_metadata(invite_index, friend)

		if friend_id == invite_selection:
			invite_friends_list.select(invite_index)

	online_empty_label.text = "No friends are playing this game. You can host and invite them after they launch it."
	online_empty_label.visible = online_friends_list.item_count == 0
	online_friends_list.visible = online_friends_list.item_count > 0

	invite_empty_label.text = "No friends are available to invite. Ask your friend to launch the game."
	invite_empty_label.visible = invite_friends_list.item_count == 0
	invite_friends_list.visible = invite_friends_list.item_count > 0

	_update_friend_buttons()


func _get_selected_friend_id(list: ItemList) -> int:
	var selected_items: PackedInt32Array = list.get_selected_items()

	if selected_items.is_empty():
		return 0

	var friend: Dictionary = list.get_item_metadata(selected_items[0])

	return int(friend["steam_id"])


func _update_friend_buttons() -> void:
	join_button.disabled = true
	invite_button.disabled = true

	var online_selection: PackedInt32Array = online_friends_list.get_selected_items()

	if online_panel.visible and not online_selection.is_empty():
		var friend: Dictionary = online_friends_list.get_item_metadata(online_selection[0])

		join_button.disabled = not bool(friend["joinable"]) or SteamNetworkManager.busy

	var invite_selection: PackedInt32Array = invite_friends_list.get_selected_items()

	if friend_invite_controls.is_visible_in_tree() and not invite_selection.is_empty():
		invite_button.disabled = SteamNetworkManager.busy
