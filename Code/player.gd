extends RigidBody2D

@export var max_launch_power = 1200
@export var max_drag_dist = 200
@export var min_drag_dist = 12.0
@export var hover_while_aiming = true
@export var aim_hover_damp = 8.0
@export var trajectory_dots = 12
@export var max_air_charges = 1
@export var max_aim_time = 1.2
@export var refill_grace = 0.1
@export var magnet_radius = 100
@export var magnet_force = 6500
@onready var bounce_particles: CPUParticles2D = $BounceParticle
@export var bounce_sfx_min_speed = 120.0
@export var bounce_sfx_cooldown = 0.06
@onready var bounce_sfx: AudioStreamPlayer2D = $BounceSFX
var was_touching = false
var last_bounce_sfx_ms = 0
var is_in_cannon = false
var is_dragging = false
var drag_start_screen = Vector2.ZERO
var drag_current_screen = Vector2.ZERO
var cracks_level = 0
var max_cracks: int = 3
var base_scale: Vector2
var is_dead = false
var level_complete = false
var can_take_damage = true
var base_gravity_scale: float = 1.0
var air_charges = 1
var aim_start_ms = 0
var last_launch_ms = 0
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	sprite.play("default")
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(on_body_entered)
	var bounce_mat := PhysicsMaterial.new()
	bounce_mat.friction = 0.0
	bounce_mat.bounce = 0.65
	physics_material_override = bounce_mat
	base_scale = sprite.scale
	base_gravity_scale = gravity_scale
	air_charges = max_air_charges
	add_to_group("Player")

func _process(_delta: float) -> void:
	if is_dragging:
		queue_redraw()
		if Time.get_ticks_msec() - aim_start_ms > max_aim_time * 1000.0:
			release_aim()
	if is_dragging and hover_while_aiming:
		linear_damp = aim_hover_damp
	elif Input.is_action_pressed("slow"):
		linear_damp = 6.0
	else:
		linear_damp = 0.0
	sprite.self_modulate.a = 1.0 if air_charges > 0 else 0.5

func _input(event: InputEvent) -> void:
	if is_dead or level_complete:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if air_charges <= 0:
				return
			is_dragging = true
			aim_start_ms = Time.get_ticks_msec()
			drag_start_screen = event.position
			drag_current_screen = event.position
			Engine.time_scale = 0.1 + (cracks_level * 0.15)
			if hover_while_aiming:
				gravity_scale = 0.0
		elif is_dragging:
			drag_current_screen = event.position
			release_aim()
	elif event is InputEventMouseMotion and is_dragging:
		drag_current_screen = event.position
		queue_redraw()

func release_aim() -> void:
	is_dragging = false
	Engine.time_scale = 1.0
	gravity_scale = base_gravity_scale
	launch_player()
	queue_redraw()

func get_drag_vector() -> Vector2:
	var screen_vec: Vector2 = drag_start_screen - drag_current_screen
	var world_vec: Vector2 = get_viewport().get_canvas_transform().affine_inverse().basis_xform(screen_vec)
	return world_vec.limit_length(max_drag_dist)

func get_launch_velocity() -> Vector2:
	var drag_vector: Vector2 = get_drag_vector()
	if drag_vector.length() < min_drag_dist:
		return Vector2.ZERO
	var launch_strength: float = (drag_vector.length() / max_drag_dist) * max_launch_power * (1.0 + (cracks_level * 0.2))
	return drag_vector.normalized() * launch_strength / mass

func launch_player():
	var v: Vector2 = get_launch_velocity()
	if v == Vector2.ZERO:
		return
	air_charges -= 1
	last_launch_ms = Time.get_ticks_msec()
	angular_velocity = 0.0
	linear_velocity = v

func _draw() -> void:
	if not is_dragging:
		return
	var aim: Vector2 = get_drag_vector()
	if aim.length() < min_drag_dist:
		return
	for i in range(1, trajectory_dots + 1):
		var t: float = float(i) / trajectory_dots
		var p: Vector2 = aim * t
		draw_circle(p.rotated(-global_rotation), lerp(4.0, 1.5, t), Color(1, 1, 1, 1.0 - t * 0.7))

func on_body_entered(body: Node):
	if is_dead or level_complete:
		return
	if body.is_in_group("Hazards") and can_take_damage:
		if cracks_level >= max_cracks:
			die()
		else:
			change_crack_level(1)
			trigger_camera_shake(15.0)
			can_take_damage = false
			await get_tree().create_timer(0.4).timeout
			can_take_damage = true
	elif body.is_in_group("shard"):
		change_crack_level(-1)
		body.queue_free()

func change_crack_level(amount: int):
	cracks_level = clamp(cracks_level + amount, 0, max_cracks)
	var shrink_factor: float = 1.0 - (cracks_level * 0.1)
	sprite.scale = base_scale * shrink_factor
	collision_shape.scale = Vector2.ONE * shrink_factor
	physics_material_override.bounce = 0.65 + (cracks_level * 0.1)
	sprite.modulate = Color(1.0, 1.0 - (cracks_level * 0.25), 1.0 - (cracks_level * 0.25))

func get_block_type(tilemap: TileMapLayer, coords: Vector2i) -> String:
	if tilemap.tile_set == null or tilemap.tile_set.get_custom_data_layer_by_name("Block_type") == -1:
		return ""
	var data: TileData = tilemap.get_cell_tile_data(coords)
	if data == null:
		return ""
	return str(data.get_custom_data("Block_type")).to_lower()

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	var current_tilemap = get_parent().get_node_or_null("TileMapLayer")
	if current_tilemap is TileMapLayer:
		var player_cell: Vector2i = current_tilemap.local_to_map(current_tilemap.to_local(global_position))
		for x in range(-3, 4):
			for y in range(-3, 4):
				var check_cell: Vector2i = player_cell + Vector2i(x, y)
				var b_type: String = get_block_type(current_tilemap, check_cell)
				if b_type == "rmagnet" or b_type == "bmagnet":
					var cell_world_pos: Vector2 = current_tilemap.to_global(current_tilemap.map_to_local(check_cell))
					var dist: float = global_position.distance_to(cell_world_pos)
					if dist < magnet_radius and dist > 2.0:
						var away_dir: Vector2 = (global_position - cell_world_pos).normalized()
						var falloff: float = 1.0 - (dist / magnet_radius)
						var force_dir: Vector2 = away_dir if b_type == "rmagnet" else -away_dir
						apply_central_force(force_dir * magnet_force * (0.5 + falloff))

	var impact_speed: float = state.linear_velocity.length()
	var touching: bool = state.get_contact_count() > 0
	if touching and not was_touching and impact_speed > bounce_sfx_min_speed:
		play_bounce_sfx(impact_speed)
	was_touching = touching
	if state.get_contact_count() > 0:
		if Time.get_ticks_msec() - last_launch_ms > refill_grace * 1000.0:
			air_charges = max_air_charges

		var contact_pos: Vector2 = state.get_contact_collider_position(0)
		var collider = state.get_contact_collider_object(0)

		if impact_speed > 150.0:
			bounce_particles.global_position = contact_pos
			bounce_particles.restart()

		if impact_speed > 450.0:
			var shake_amount: float = clamp((impact_speed - 700.0) / 50.0, 4.0, 20.0)
			trigger_camera_shake(shake_amount)

		if collider is TileMapLayer:
			var push_dir: Vector2 = (contact_pos - global_position).normalized()
			var hit_point_inside_tile: Vector2 = contact_pos + (push_dir * 4.0)
			var local_pos: Vector2 = collider.to_local(hit_point_inside_tile)
			var tile_coords: Vector2i = collider.local_to_map(local_pos)
			var block_type: String = get_block_type(collider, tile_coords)
			if block_type != "":
				_apply_tile_effect(state, block_type, collider, tile_coords, impact_speed)

func _apply_tile_effect(state: PhysicsDirectBodyState2D, block_type: String, tilemap: TileMapLayer, coords: Vector2i, speed: float) -> void:
	match block_type:
		"breakable":
			if speed >= 500.0 and cracks_level >= 1:
				tilemap.erase_cell(coords)
				trigger_camera_shake(12.0)
		"slow":
			state.linear_velocity *= 0.3
		"rmagnet":
			var tile_pos: Vector2 = tilemap.to_global(tilemap.map_to_local(coords))
			state.linear_velocity = (global_position - tile_pos).normalized() * 1200.0
		"portal":
			fire_cannon(tilemap, coords)

func trigger_camera_shake(intensity: float) -> void:
	var cam = get_tree().get_first_node_in_group("Camera")
	if cam and cam.has_method("apply_shake"):
		cam.apply_shake(intensity)

func fire_cannon(tilemap: TileMapLayer, coords: Vector2i) -> void:
	if is_in_cannon:
		return
	is_in_cannon = true

	var fire_dir: Vector2 = Vector2.UP
	var transposed: bool = tilemap.is_cell_transposed(coords)
	var flip_v: bool = tilemap.is_cell_flipped_v(coords)

	if transposed:
		fire_dir = Vector2.LEFT if flip_v else Vector2.RIGHT
	elif flip_v:
		fire_dir = Vector2.DOWN

	collision_shape.set_deferred("disabled", true)
	z_index = -1

	var tile_center: Vector2 = tilemap.to_global(tilemap.map_to_local(coords))
	global_position = tile_center
	linear_velocity = Vector2.ZERO
	freeze = true

	await get_tree().create_timer(0.15).timeout

	freeze = false
	air_charges = max_air_charges
	trigger_camera_shake(14.0)
	bounce_particles.global_position = global_position
	bounce_particles.restart()
	apply_central_impulse(fire_dir * 1800.0)

	await get_tree().create_timer(0.08).timeout
	collision_shape.set_deferred("disabled", false)
	z_index = 0

	await get_tree().create_timer(0.15).timeout
	is_in_cannon = false

func reach_goal(target_pos: Vector2) -> void:
	level_complete = true
	is_dragging = false
	Engine.time_scale = 1.0
	gravity_scale = base_gravity_scale
	queue_redraw()
	linear_velocity = Vector2.ZERO
	set_deferred("freeze", true)
	trigger_camera_shake(8.0)
	var tween := create_tween()
	tween.tween_property(self, "global_position", target_pos, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(sprite, "scale", base_scale * 1.4, 0.2)
	tween.tween_property(sprite, "scale", base_scale, 0.2)

func die() -> void:
	if is_dead:
		return
	is_dead = true
	is_dragging = false
	Engine.time_scale = 1.0
	gravity_scale = base_gravity_scale
	queue_redraw()

	linear_velocity = Vector2.ZERO
	freeze = true

	sprite.play("Death")
	await sprite.animation_finished

	sprite.visible = false

	trigger_camera_shake(22.0)
	bounce_particles.global_position = global_position
	bounce_particles.amount = 30
	bounce_particles.restart()

	await get_tree().create_timer(0.8).timeout
	get_tree().call_deferred("reload_current_scene")

func play_bounce_sfx(speed: float) -> void:
	if Time.get_ticks_msec() - last_bounce_sfx_ms < bounce_sfx_cooldown * 1000.0:
		return
	last_bounce_sfx_ms = Time.get_ticks_msec()
	var strength: float = clamp((speed - bounce_sfx_min_speed) / 1000.0, 0.0, 1.0)
	bounce_sfx.volume_db = lerp(-18.0, 0.0, strength)
	bounce_sfx.pitch_scale = 1.0 + cracks_level * 0.15 + randf_range(-0.08, 0.08)
	bounce_sfx.play()
