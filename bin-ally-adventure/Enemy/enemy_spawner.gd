extends Node3D
@export_group("Spawn Information")
@export var shield_enemy_count: int
@export var basic_enemy_count: int
@export var agile_enemy_count: int
@export var cover_markers: Array[Marker3D]
@export var cover_marker_claimed: Array[bool]

# Temp information to help with spawning
var new_enemy
var total_count: int
var next_cover_marker: int = 0

@export_group("Enemy Scenes")
const basic_enemy = preload("res://Enemy/EnemyBasic.tscn")

func _ready() -> void:
	#sets up info to spawn the enemies
	total_count = shield_enemy_count + basic_enemy_count + agile_enemy_count
	for i in cover_markers:
		cover_marker_claimed.append(false)
	if(cover_markers.size() < total_count):
		print("Not enough markers")
	spawn_enemies()

#Change this to properly instantiate the different versions of the enemies
func spawn_enemies() -> void:
	for i in range(total_count):
		if next_cover_marker >= cover_markers.size():
			print("Out of markers")
			break
		#spawns all shields first, then all agile, then all normal
		if shield_enemy_count > 0:
			shield_enemy_count -= 1
			new_enemy = basic_enemy.instantiate()
			print("Spawn shield")
		elif agile_enemy_count > 0:
			agile_enemy_count -=1
			new_enemy = basic_enemy.instantiate()
			print("Spawn agile")
		else:
			basic_enemy_count -=1 
			new_enemy = basic_enemy.instantiate()
			print("Spawn basic")
		add_child(new_enemy)
		new_enemy.global_position = global_position
		claim_cover(new_enemy)

#grabs the enemy logic and sets the cover goal and removes it from the list
func claim_cover(enemy: Node3D) -> void:
	enemy.set_cover_goal(cover_markers[next_cover_marker])
	cover_marker_claimed[next_cover_marker] = true
	next_cover_marker += 1
