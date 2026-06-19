extends CharacterBody3D

@export var min_speed := 10
@export var max_speed := 18

var _is_dying := false
var _target_velocity := Vector3.ZERO
var _highlight_ring: MeshInstance3D

func _ready() -> void:
	add_to_group("mobs")
	# Move mobs off layer 1 (player) onto their own layer (2).
	# Detect layer 3 (ground) so they can land, but not layer 1 (player).
	# Removing layer 2 from the mask means mobs never physically block
	# each other — no more pile-ups. Soft repulsion handles spacing.
	set_collision_layer_value(1, false)
	set_collision_layer_value(2, true)
	set_collision_mask_value(1, false)  # Don't detect layer 1 (player)
	set_collision_mask_value(2, false)  # Don't detect other mobs
	set_collision_mask_value(3, true)  # Detect layer 3 (ground)
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:position"))
	config.add_property(NodePath(".:rotation"))
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.replication_config = config
	add_child(sync)
	_setup_highlight()

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	_apply_separation()
	velocity.x = lerpf(velocity.x, _target_velocity.x, 5.0 * delta)
	velocity.z = lerpf(velocity.z, _target_velocity.z, 5.0 * delta)
	move_and_slide()

func _apply_separation() -> void:
	for mob in get_tree().get_nodes_in_group("mobs"):
		if mob == self or mob._is_dying:
			continue
		var diff: Vector3 = global_position - mob.global_position
		diff.y = 0.0
		var dist: float = diff.length()
		if dist < 2.5 and dist > 0.001:
			# Gentle push — stronger the closer they are, fades to zero at 2.5 units
			velocity += diff.normalized() * (2.5 - dist) * 6.0

func initialize(start_position: Vector3, player_position: Vector3, angle_offset: float, speed: int) -> void:
	look_at_from_position(start_position, player_position, Vector3.UP)
	rotate_y(angle_offset)
	velocity = Vector3.FORWARD * speed
	velocity = velocity.rotated(Vector3.UP, rotation.y)
	_target_velocity = velocity

func _on_visible_on_screen_notifier_3d_screen_exited() -> void:
	if is_multiplayer_authority() and not _is_dying:
		_die.rpc()

func _setup_highlight() -> void:
	_highlight_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.1
	torus.outer_radius = 1.4
	torus.rings = 32
	torus.ring_segments = 8
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.1)
	mat.emission_energy_multiplier = 4.0
	torus.material = mat
	_highlight_ring.mesh = torus
	_highlight_ring.position = Vector3(0, 0.15, 0)
	_highlight_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_highlight_ring.visible = false
	add_child(_highlight_ring)

func set_highlighted(on: bool) -> void:
	_highlight_ring.visible = on

@rpc("authority", "call_local", "reliable")
func _die() -> void:
	if _is_dying:
		return
	_is_dying = true
	set_highlighted(false)
	set_physics_process(false)
	$CollisionShape3D.disabled = true
	var sync := get_node_or_null("Sync")
	if sync:
		sync.queue_free()
	var tween := create_tween()
	tween.tween_property($Pivot, "scale", Vector3(1.5, 0.05, 1.5), 0.2).set_ease(Tween.EASE_OUT)
	tween.tween_callback(queue_free)
