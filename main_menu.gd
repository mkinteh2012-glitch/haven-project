extends Control

@export var options_scene: String = ""

@onready var play_button: TextureButton = $TextureButton
@onready var options_button: TextureButton = $TextureButton2
@onready var quit_button: TextureButton = $TextureButton3

func _ready() -> void:
	Engine.time_scale = 1.0
	play_button.pressed.connect(_on_play)
	options_button.pressed.connect(_on_options)
	quit_button.pressed.connect(_on_quit)
	for b in [play_button, options_button, quit_button]:
		b.pivot_offset = b.size / 2
		b.mouse_entered.connect(_hover.bind(b, 1.1))
		b.mouse_exited.connect(_hover.bind(b, 1.0))
	if OS.has_feature("web"):
		quit_button.hide()

func _hover(b: TextureButton, s: float) -> void:
	create_tween().tween_property(b, "scale", Vector2(s, s), 0.08)

func _on_play() -> void:
	GameManager.restart_game()

func _on_options() -> void:
	if options_scene != "":
		get_tree().change_scene_to_file(options_scene)
	elif DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _on_quit() -> void:
	get_tree().quit()
