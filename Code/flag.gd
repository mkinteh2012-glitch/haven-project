extends Area2D

@export var next_scene: String = ""
@export var delay: float = 1.0

var triggered = false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var particles: CPUParticles2D = $CPUParticles2D
@onready var clear_sfx: AudioStreamPlayer2D = $AudioStreamPlayer2D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	sprite.play("idle")

func _on_body_entered(body: Node) -> void:
	if triggered or not body.is_in_group("Player"):
		return
	triggered = true
	if body.has_method("reach_goal"):
		body.reach_goal(global_position)
		sprite.play("complete")
	particles.restart()
	clear_sfx.play()
	var wait: float = max(delay, clear_sfx.stream.get_length())
	await get_tree().create_timer(wait).timeout
	if next_scene != "":
		get_tree().change_scene_to_file(next_scene)
	else:
		GameManager.next_floor()
