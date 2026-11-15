extends Node

var floors: Array[String] = [
	"res://Levels/Tutorial.tscn",
	"res://Levels/Level1.tscn",
	"res://Levels/Level2.tscn",
	"res://Levels/Level3.tscn",
	"res://Levels/Level4.tscn",
	"res://Levels/Level5.tscn",
]
var win_scene: String = ""
var current_floor: int = 0

func next_floor() -> void:
	var path: String = get_tree().current_scene.scene_file_path
	var idx: int = floors.find(path)
	if idx != -1:
		current_floor = idx
	current_floor += 1
	if current_floor >= floors.size():
		current_floor = 0
		get_tree().change_scene_to_file(win_scene)
	else:
		get_tree().change_scene_to_file(floors[current_floor])

func restart_game() -> void:
	current_floor = 0
	get_tree().change_scene_to_file(floors[0])
