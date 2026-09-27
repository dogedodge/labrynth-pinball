class_name PinballTarget
extends StaticBody3D

const VISUAL_PATH := "res://assets/models/target.glb"
const COOLDOWN := 0.25

var _cooldown := 0.0
var _visual: Node3D


func _ready() -> void:
	collision_layer = PinballData.LAYER_GADGET
	collision_mask = PinballData.LAYER_BALL
	physics_material_override = ModelUtil.physics_material(0.4, 0.15)

	_visual = ModelUtil.instantiate_glb(VISUAL_PATH)
	add_child(_visual)

	var box := BoxShape3D.new()
	box.size = Vector3(0.032, 0.034, 0.012)
	var cs := CollisionShape3D.new()
	cs.shape = box
	cs.position = Vector3(0.0, 0.017, 0.0)
	add_child(cs)


func _physics_process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(_cooldown - delta, 0.0)
		if _visual:
			_visual.scale.z = lerpf(1.0, 0.45, _cooldown / COOLDOWN)


func on_ball_hit(_ball: PinballBall) -> void:
	if _cooldown > 0.0:
		return
	_cooldown = COOLDOWN
	var game := get_tree().get_first_node_in_group("pinball_game")
	if game and game.has_method("add_score"):
		game.add_score(PinballData.SCORE_TARGET)
