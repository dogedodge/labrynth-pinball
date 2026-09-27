class_name PinballSlingshot
extends StaticBody3D

const LEFT_PATH := "res://assets/models/slingshot_left.glb"
const RIGHT_PATH := "res://assets/models/slingshot_right.glb"
const KICK := 0.28
const COOLDOWN := 0.16

var is_left := true
var kick_local := Vector3.ZERO
var _cooldown := 0.0
var _playfield: Node3D


func _ready() -> void:
	_playfield = get_parent() as Node3D
	# kick_local is set by world.gd from layout.json ("slingshots" -> kick_dir):
	# perpendicular to the rubber kicking face, pointing into the playfield.
	if kick_local.length_squared() < 0.0001:
		kick_local = Vector3(0.82 if is_left else -0.82, 0.0, -0.57)
	kick_local = kick_local.normalized()
	collision_layer = PinballData.LAYER_GADGET
	collision_mask = PinballData.LAYER_BALL
	physics_material_override = ModelUtil.physics_material(0.08, 0.2)
	var visual: Node3D = ModelUtil.instantiate_glb(LEFT_PATH if is_left else RIGHT_PATH)
	add_child(visual)
	ModelUtil.add_convex_collision(self, visual)


func _physics_process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(_cooldown - delta, 0.0)


func on_ball_hit(ball: PinballBall) -> void:
	if _cooldown > 0.0:
		return
	_cooldown = COOLDOWN
	var dir := kick_local
	if _playfield:
		dir = (_playfield.global_transform.basis * kick_local).normalized()
	ball.apply_central_impulse(dir * KICK)
	var game := get_tree().get_first_node_in_group("pinball_game")
	if game and game.has_method("add_score"):
		game.add_score(PinballData.SCORE_SLINGSHOT)
