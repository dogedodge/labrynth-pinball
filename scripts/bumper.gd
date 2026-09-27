class_name PinballBumper
extends StaticBody3D

const VISUAL_PATH := "res://assets/models/bumper.glb"
const KICK := 0.22
const COOLDOWN := 0.12

var _cooldown := 0.0
var _cap_mat: StandardMaterial3D
var _flash := 0.0


func _ready() -> void:
	collision_layer = PinballData.LAYER_GADGET
	collision_mask = PinballData.LAYER_BALL
	physics_material_override = ModelUtil.physics_material(0.05, 0.55)

	var visual: Node3D = ModelUtil.instantiate_glb(VISUAL_PATH)
	add_child(visual)

	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.025
	cylinder.height = 0.042
	var cs := CollisionShape3D.new()
	cs.shape = cylinder
	cs.position = Vector3(0.0, 0.021, 0.0)
	add_child(cs)

	for mesh_instance in ModelUtil.find_meshes(visual):
		if mesh_instance.name == "BumperCap":
			var mat := ModelUtil.duplicate_surface_material(mesh_instance)
			if mat is StandardMaterial3D:
				_cap_mat = mat


func _physics_process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(_cooldown - delta, 0.0)
	if _flash > 0.0 and _cap_mat != null:
		_flash = maxf(_flash - delta * 4.0, 0.0)
		_cap_mat.emission_energy_multiplier = 1.0 + _flash * 6.0


func on_ball_hit(ball: PinballBall) -> void:
	if _cooldown > 0.0:
		return
	_cooldown = COOLDOWN
	_flash = 1.0
	var playfield := get_parent() as Node3D
	var offset := ball.global_position - global_position
	if playfield:
		var up := playfield.global_transform.basis.y
		offset -= up * offset.dot(up)
	if offset.length_squared() < 0.000001:
		offset = -playfield.global_transform.basis.z if playfield else Vector3(0, 0, -1)
	var dir := offset.normalized()
	ball.apply_central_impulse(dir * KICK)
	var game := get_tree().get_first_node_in_group("pinball_game")
	if game and game.has_method("add_score"):
		game.add_score(PinballData.SCORE_BUMPER)
