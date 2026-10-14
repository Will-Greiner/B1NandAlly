extends Node


signal status_changed(message: String)
signal session_started
signal session_ended
signal session_changed
signal game_started


const APP_ID: int = 480
const STEAM_PORT: int = 0
const MAX_PLAYERS: int = 2


var steam_ready: bool = false
var busy: bool = false
var hosting: bool = false
var game_running: bool = false
var singleplayer_running: bool = false

var lobby_id: int = 0
var steam_id: int = 0
var host_steam_id: int = 0
var client_id: int = 0

var pending_operation: String = ""
var status_text: String = "Initializing Steam..."

var peer: SteamMultiplayerPeer = null


func _ready() -> void:
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.join_requested.connect(_on_join_requested)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)

	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	var result: Dictionary = Steam.steamInitEx(APP_ID, false)

	if int(result.get("status", -1)) != 0:
		_set_status("Steam initialization failed: " + str(result.get("verbal", result)))
		return

	steam_ready = true
	steam_id = Steam.getSteamID()

	_set_status("Ready.")

	_check_launch_invite()


func _process(_delta: float) -> void:
	if steam_ready:
		Steam.run_callbacks()


# Create an invite-only lobby for two players.
func new_game() -> void:
	if not steam_ready or busy or game_running or peer != null or lobby_id != 0:
		return

	busy = true
	pending_operation = "host"

	_set_status("Creating game...")

	Steam.createLobby(Steam.LOBBY_TYPE_PRIVATE, MAX_PLAYERS)
	
	
func start_singleplayer() -> void:
	if busy or game_running or peer != null or lobby_id != 0:
		return

	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

	singleplayer_running = true
	game_running = true

	_set_status("Starting debug singleplayer...")

	game_started.emit()


# Open Steam's friend invitation window.
func invite_friend() -> void:
	if not hosting or lobby_id == 0 or game_running:
		return

	Steam.activateGameOverlayInviteDialog(lobby_id)
	
	
# Get Lobby members to display in ui
func get_lobby_members() -> Array[Dictionary]:
	var members: Array[Dictionary] = []
	
	if lobby_id == 0:
		return members
		
	var member_count: int = Steam.getNumLobbyMembers(lobby_id)
	
	for index in range(member_count):
		var member_id: int = Steam.getLobbyMemberByIndex(lobby_id, index)
		var member_name: String = Steam.getFriendPersonaName(member_id)
		
		if member_name.is_empty():
			member_name = str(member_id)
			
		members.append({"steam_id": member_id, "name": member_name, "is_host": member_id == host_steam_id})
		
	return members
	
	
# Lobby membership and network connection must be ready
func can_begin_game() -> bool:
	if not hosting or busy or game_running or peer == null or lobby_id == 0:
		return false
		
	if Steam.getNumLobbyMembers(lobby_id) != MAX_PLAYERS:
		return false
		
	var connected_peers: PackedInt32Array = multiplayer.get_peers()
	
	return connected_peers.size() == 1 and client_id != 0 and connected_peers.has(client_id)
	
	
func begin_game() -> void:
	if not can_begin_game():
		return
		
	Steam.setLobbyJoinable(lobby_id, false)
	
	_start_game.rpc()
	
	
func leave_game() -> void:
	_close_session()
	
	_set_status("Ready.")
	
	session_ended.emit()


func quit_game() -> void:
	_close_session()

	get_tree().quit()


# Steam automatically puts the creator into new lobby.
func _on_lobby_created(result: int, created_lobby_id: int) -> void:
	# Back may have been pressed while Steam was creating the lobby.
	if pending_operation != "host":
		if result == 1:
			Steam.leaveLobby(created_lobby_id)
		return
		
	if result != 1:
		busy = false
		_set_status("Could not create the Steam lobby.")
		return

	lobby_id = created_lobby_id
	host_steam_id = steam_id

	var new_peer: SteamMultiplayerPeer = SteamMultiplayerPeer.new()
	var error: int = new_peer.create_host(STEAM_PORT)

	if error != OK:
		new_peer.close()
		_close_session()
		_set_status("Could not host: " + error_string(error))
		return

	peer = new_peer
	multiplayer.multiplayer_peer = peer

	hosting = true
	busy = false
	pending_operation = ""

	_set_status("Game started. Invite a friend.")

	session_started.emit()


# Accept an invitation while the game is already running.
func _on_join_requested(invited_lobby_id: int, _friend_id: int) -> void:
	if busy or game_running or peer != null or lobby_id != 0:
		return

	_join_lobby(invited_lobby_id)


func _join_lobby(invited_lobby_id: int) -> void:
	if not steam_ready or invited_lobby_id <= 0:
		return

	busy = true
	pending_operation = "join"

	_set_status("Joining friend's game...")

	Steam.joinLobby(invited_lobby_id)


# Entering a lobby is followed by connecting the multiplayer peer.
func _on_lobby_joined(joined_lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	# The host receives this callback after creating its lobby.
	if hosting and joined_lobby_id == lobby_id:
		session_changed.emit()
		return

	if pending_operation != "join":
		if response == 1:
			Steam.leaveLobby(joined_lobby_id)
		return
		
	if response != 1:
		_close_session()
		_set_status("Could not join the Steam lobby.")
		return

	# The host receives this callback too, but already created its peer.
	if peer != null:
		return

	lobby_id = joined_lobby_id
	host_steam_id = Steam.getLobbyOwner(lobby_id)

	if host_steam_id == steam_id:
		_close_session()
		_set_status("The host is no longer available.")
		return

	var new_peer: SteamMultiplayerPeer = SteamMultiplayerPeer.new()
	var error: int = new_peer.create_client(host_steam_id, STEAM_PORT)

	if error != OK:
		new_peer.close()
		_close_session()
		_set_status("Could not connect: " + error_string(error))
		return

	peer = new_peer
	multiplayer.multiplayer_peer = peer
	pending_operation = ""

	_set_status("Connecting to host...")


func _on_connected_to_server() -> void:
	busy = false

	_set_status("Connected. Waiting for host to begin.")

	session_started.emit()
	
	_client_ready.rpc_id(1)
	
	
# Confirm that the client reached the connected state
@rpc("any_peer", "call_remote", "reliable")
func _client_ready() -> void:
	if not hosting or game_running:
		return
		
	var sender_id: int = multiplayer.get_remote_sender_id()
	
	if not multiplayer.get_peers().has(sender_id):
		return
		
	client_id = sender_id
	
	_set_status("Both players are connected. Press Begin.")
	
	
# Only host can start the game
@rpc("authority", "call_local", "reliable")
func _start_game() -> void:
	if game_running:
		return
		
	game_running = true
	
	_set_status("Starting game...")
	
	game_started.emit()
	
	
func _on_lobby_chat_update(updated_lobby_id: int, _changed_id: int, _changer_id: int, _chat_state: int) -> void:
	if updated_lobby_id != lobby_id:
		return

	# Steam can transfer lobby ownership, but this game keeps the original host.
	if not hosting and Steam.getLobbyOwner(lobby_id) != host_steam_id:
		_close_session()
		_set_status("The host left the lobby.")

		session_ended.emit()
		return

	if hosting and Steam.getNumLobbyMembers(lobby_id) < MAX_PLAYERS:
		client_id = 0

	session_changed.emit()


func _on_peer_connected(_id: int) -> void:
	session_changed.emit()


func _on_peer_disconnected(_id: int) -> void:
	if not hosting:
		return

	if client_id == _id:
		client_id = 0

	if game_running:
		_close_session()
		_set_status("Friend disconnected. The session ended.")

		session_ended.emit()
		return

	_set_status("Friend disconnected. Invite them again.")


func _on_connection_failed() -> void:
	_close_session()
	_set_status("Connection failed.")

	session_ended.emit()


func _on_server_disconnected() -> void:
	_close_session()
	_set_status("The host left the game.")

	session_ended.emit()


# Handle invitations that launch the game through Steam.
func _check_launch_invite() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_args()
	arguments.append_array(OS.get_cmdline_user_args())

	for index in range(arguments.size() - 1):
		if arguments[index] == "+connect_lobby":
			_join_lobby(arguments[index + 1].to_int())
			return


func _close_session() -> void:
	hosting = false
	busy = false
	game_running = false
	singleplayer_running = false
	
	client_id = 0
	host_steam_id = 0
	pending_operation = ""

	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

	if peer != null:
		peer.close()
		peer = null

	if lobby_id != 0:
		Steam.leaveLobby(lobby_id)
		lobby_id = 0

	session_changed.emit()


func _set_status(message: String) -> void:
	status_text = message

	print(message)

	status_changed.emit(message)
	session_changed.emit()
