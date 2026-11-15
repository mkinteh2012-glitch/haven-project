extends Area2D

@export var next_scene: String = ""
@export var delay: float = 1.0

var triggered = false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var particles: CPUParticles2D = $CPUParticles2D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	sprite.play("default")

func _on_body_entered(body: Node) -> void:
	if triggered or not body.is_in_group("Player"):
		return
	triggered = true
	if body.has_method("reach_goal"):
		body.reach_goal(global_position)
	if sprite.sprite_frames.has_animation("complete"):
		sprite.play("complete")
	particles.restart()
	await get_tree().create_timer(delay).timeout
	if next_scene != "":
		get_tree().change_scene_to_file(next_scene)
	else:
		GameManager.next_floor()
