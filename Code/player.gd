extends RigidBody2D

@export var max_launch_power = 1200
@export var max_drag_dist = 200
@export var magnet_radius = 100
@export var magnet_force = 6500
@onready var bounce_particles: CPUParticles2D = $BounceParticle

var is_in_cannon = false
var is_dragging = false
var drag_start_pos = Vector2.ZERO
var drag_current_pos = Vector2.ZERO

var cracks_level = 0
var max_cracks: int = 3
var base_scale: Vector2
var is_dead = false
var can_take_damage = true

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
	
func _process(_delta: float) -> void:
	if is_dragging:
		drag_current_pos = get_global_mouse_position()
		queue_redraw()
	if Input.is_action_pressed("slow"):
		linear_damp = 6.0
	else:
		linear_damp = 0.0
	
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_dragging = true
			drag_start_pos = get_global_mouse_position()
			drag_current_pos = drag_start_pos
			Engine.time_scale = 0.1 + (cracks_level * 0.15)
		elif is_dragging:
			is_dragging = false
			Engine.time_scale = 1.0
			launch_player()
			queue_redraw()
	elif event is InputEventMouseMotion and is_dragging:
		drag_current_pos = get_global_mouse_position()
		queue_redraw()

func launch_player():
	var drag_vector: Vector2 = drag_start_pos - drag_current_pos
	var clamped_lengh = clamp(drag_vector.length(), 0.0, max_drag_dist)
	var lanch_direction: Vector2 = drag_vector.normalized()
	var launch_strengh: float = (clamped_lengh / max_drag_dist) * max_launch_power * (1.0 + (cracks_level * 0.2))
	
	linear_velocity = Vector2.ZERO
	apply_central_impulse(lanch_direction * launch_strengh)

func _draw() -> void:
	if is_dragging:
		var pull_vector: Vector2 = (drag_start_pos - drag_current_pos).limit_length(max_drag_dist)
		draw_line(Vector2.ZERO, pull_vector.rotated(-rotation), Color.WHITE, 4.0)

func on_body_entered(body: Node):
	if is_dead:
		return
	if body.is_in_group("Hazards") and can_take_damage:
		if cracks_level  >= max_cracks:
			die()
		else:
			change_crack_level(1)
			trigger_camera_shake(15.0)
			can_take_damage = false
			await get_tree().create_timer(0.4)
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

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	# Proximity magnetic field for RMagnet (repel) and BMagnet (attract)
	var current_tilemap = get_parent().get_node_or_null("TileMapLayer")
	if current_tilemap is TileMapLayer:
		var player_cell: Vector2i = current_tilemap.local_to_map(current_tilemap.to_local(global_position))
		# Check a 7x7 tile grid around the player
		for x in range(-3, 4):
			for y in range(-3, 4):
				var check_cell: Vector2i = player_cell + Vector2i(x, y)
				var data: TileData = current_tilemap.get_cell_tile_data(check_cell)
				if data:
					var b_type: String = str(data.get_custom_data("Block_type")).to_lower()
					if b_type == "rmagnet" or b_type == "bmagnet":
						var cell_world_pos: Vector2 = current_tilemap.to_global(current_tilemap.map_to_local(check_cell))
						var dist: float = global_position.distance_to(cell_world_pos)
						if dist < magnet_radius and dist > 2.0:
							var away_dir: Vector2 = (global_position - cell_world_pos).normalized()
							# Stronger pull/push the closer you get to the magnet
							var falloff: float = 1.0 - (dist / magnet_radius)
							var force_dir: Vector2 = away_dir if b_type == "rmagnet" else -away_dir
							apply_central_force(force_dir * magnet_force * (0.5 + falloff))

	var impact_speed: float = state.linear_velocity.length()
	if state.get_contact_count() > 0:
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
			var tile_data: TileData = collider.get_cell_tile_data(tile_coords)
			
			if tile_data:
				var block_type: String = str(tile_data.get_custom_data("Block_type")).to_lower()
				print("Hit tile at ", tile_coords, " Type: ", block_type)
				_apply_tile_effect(state, block_type, collider, tile_coords, impact_speed)

func _apply_tile_effect(state: PhysicsDirectBodyState2D, block_type: String, tilemap: TileMapLayer, coords: Vector2i, speed: float) -> void:
	match block_type:
		"breakable":
			if speed >= 500.0:
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
	
	#  hhelp help why is ts so hard
	collision_shape.set_deferred("disabled", true)
	z_index = -1
	

	var tile_center: Vector2 = tilemap.to_global(tilemap.map_to_local(coords))
	global_position = tile_center
	linear_velocity = Vector2.ZERO
	freeze = true
	
	await get_tree().create_timer(0.15).timeout
	
	
	freeze = false
	trigger_camera_shake(14.0)
	bounce_particles.global_position = global_position
	bounce_particles.restart()
	apply_central_impulse(fire_dir * 1800.0)
	
	await get_tree().create_timer(0.08).timeout
	collision_shape.set_deferred("disabled", false)
	z_index = 0
	
	await get_tree().create_timer(0.15).timeout
	is_in_cannon = false

func die() -> void:
	if is_dead:
		return
	is_dead = true
	is_dragging = false
	Engine.time_scale = 1.0
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
