class_name PinballDrain
extends Area3D

signal ball_drained

const VISUAL_PATH := "res://assets/models/drain.glb"


func _ready() -> void:
	collision_layer = PinballData.LAYER_DRAIN
	collision_mask = PinballData.LAYER_BALL
	monitorable = false
	monitoring = true

	var visual: Node3D = ModelUtil.instantiate_glb(VISUAL_PATH)
	add_child(visual)

	var box := BoxShape3D.new()
	box.size = Vector3(0.16, 0.04, 0.07)
	var cs := CollisionShape3D.new()
	cs.shape = box
	cs.position = Vector3(0.0, 0.02, 0.01)
	add_child(cs)

	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if body is PinballBall:
		ball_drained.emit()
