class_name PinballSlingshot
extends StaticBody3D

const LEFT_PATH := "res://assets/models/slingshot_left.glb"
const RIGHT_PATH := "res://assets/models/slingshot_right.glb"
const KICK := 0.28
const COOLDOWN := 0.16

var is_left := true
var kick_local := Vector3.ZERO
## Rubber kicking face (two end points, playfield-local XZ). Like a real slingshot
## (switches behind the rubber), only hits on this face kick; the other two edges
## (along the inlane / above the flipper) are passive.
var face_local: Array[Vector2] = []
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
	# exact hulls: simplification could flatten the rounded rubber ends into a ledge
	ModelUtil.add_convex_collision(self, visual, false)


func _physics_process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(_cooldown - delta, 0.0)


func on_ball_hit(ball: PinballBall) -> void:
	if _cooldown > 0.0:
		return
	if not _hit_on_face(ball):
		return
	_cooldown = COOLDOWN
	var dir := kick_local
	if _playfield:
		dir = (_playfield.global_transform.basis * kick_local).normalized()
	ball.apply_central_impulse(dir * KICK)
	var game := get_tree().get_first_node_in_group("pinball_game")
	if game and game.has_method("add_score"):
		game.add_score(PinballData.SCORE_SLINGSHOT)


func _hit_on_face(ball: PinballBall) -> bool:
	if face_local.size() != 2 or _playfield == null:
		return true
	var p3 := _playfield.to_local(ball.global_position)
	var p := Vector2(p3.x, p3.z)
	var a := face_local[0]
	var b := face_local[1]
	var n := Vector2(kick_local.x, kick_local.z).normalized()
	var t := (p - a).dot(b - a) / (b - a).length_squared()
	var d := (p - a).dot(n)
	return d > 0.0 and t > -0.05 and t < 1.05
