extends Node3D


@export_group("Character")
@export var character_scene: PackedScene

@export_group("Spawning")
@export var spawn_points: Array[Marker3D] = []

@export_group("Replication")
@export_range(1.0, 60.0, 1.0) var synchronization_rate: float = 30.0


var ready_peers: Dictionary = {}
var players_spawned: bool = false


@export var players: Node3D
@export var spawner: MultiplayerSpawner


func _ready() -> void:
	if character_scene == null:
		push_error("PlayerSpawnManager: assign your character scene.")
		return

	if spawn_points.is_empty():
		push_error("PlayerSpawnManager: assign at least one spawn point.")
		return

	for spawn_point in spawn_points:
		if spawn_point == null:
			push_error("PlayerSpawnManager: a spawn point entry is empty.")
			return

	spawner.spawn_path = spawner.get_path_to(players)
	spawner.spawn_function = _spawn_player_from_data

	_announce_scene_ready.call_deferred()


func _announce_scene_ready() -> void:
	if SteamNetworkManager.singleplayer_running:
		players_spawned = true
		_spawn_player(1, 0)
		return

	if not SteamNetworkManager.game_running:
		return

	if multiplayer.is_server():
		ready_peers[multiplayer.get_unique_id()] = true
		_try_spawn_multiplayer_players()
	else:
		_client_scene_ready.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _client_scene_ready() -> void:
	if not multiplayer.is_server() or SteamNetworkManager.singleplayer_running:
		return

	if not SteamNetworkManager.game_running:
		return

	var sender_id: int = multiplayer.get_remote_sender_id()

	if not multiplayer.get_peers().has(sender_id):
		return

	ready_peers[sender_id] = true

	_try_spawn_multiplayer_players()


func _try_spawn_multiplayer_players() -> void:
	if players_spawned or not multiplayer.is_server():
		return

	var player_ids: Array[int] = [multiplayer.get_unique_id()]

	for peer_id in multiplayer.get_peers():
		player_ids.append(peer_id)

	player_ids.sort()

	for peer_id in player_ids:
		if not ready_peers.has(peer_id):
			return

	if spawn_points.size() < player_ids.size():
		push_error("PlayerSpawnManager: assign a separate spawn point for each player.")
		return

	players_spawned = true

	for index in range(player_ids.size()):
		_spawn_player(player_ids[index], index)


func _spawn_player(peer_id: int, spawn_index: int) -> void:
	var spawn_point: Marker3D = spawn_points[spawn_index]
	var spawn_transform: Transform3D = players.global_transform.affine_inverse() * spawn_point.global_transform
	var data: Dictionary = {"peer_id": peer_id, "transform": spawn_transform, "networked": not SteamNetworkManager.singleplayer_running}

	if SteamNetworkManager.singleplayer_running:
		var player: Node = _spawn_player_from_data(data)

		if player != null:
			players.add_child(player)
	else:
		spawner.spawn(data)


func _spawn_player_from_data(data: Variant) -> Node:
	var spawn_data: Dictionary = data
	var instance: Node = character_scene.instantiate()
	var player: CharacterBody3D = instance as CharacterBody3D

	if player == null:
		instance.free()
		push_error("PlayerSpawnManager: the character scene root must be CharacterBody3D.")
		return null

	var peer_id: int = int(spawn_data["peer_id"])
	var networked_player: bool = bool(spawn_data["networked"])

	player.name = str(peer_id)
	player.transform = spawn_data["transform"]
	player.set("networked", networked_player)
	player.add_to_group("players")

	player.set_multiplayer_authority(peer_id, true)

	return player
