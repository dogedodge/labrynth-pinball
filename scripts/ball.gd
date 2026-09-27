class_name PinballBall
extends RigidBody3D

signal hit_gadget(gadget: Node)

const VISUAL_PATH := "res://assets/models/ball.glb"

var _pending_velocity := Vector3.ZERO
var _has_pending_velocity := false


func launch(velocity: Vector3) -> void:
	freeze = false
	sleeping = false
	_pending_velocity = velocity
	_has_pending_velocity = true


func _ready() -> void:
	mass = PinballData.BALL_MASS
	continuous_cd = true
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 12
	collision_layer = PinballData.LAYER_BALL
	collision_mask = (
		PinballData.LAYER_WORLD
		| PinballData.LAYER_FLIPPER
		| PinballData.LAYER_GADGET
		| PinballData.LAYER_PLUNGER
	)
	physics_material_override = ModelUtil.physics_material(0.18, 0.32)
	linear_damp = 0.28
	angular_damp = 0.9
	gravity_scale = 1.0

	var sphere := SphereShape3D.new()
	sphere.radius = PinballData.BALL_RADIUS - 0.0008
	var cs := CollisionShape3D.new()
	cs.shape = sphere
	add_child(cs)

	var visual: Node3D = ModelUtil.instantiate_glb(VISUAL_PATH)
	add_child(visual)
	body_entered.connect(_on_body_entered)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _has_pending_velocity:
		state.linear_velocity = _pending_velocity
		state.angular_velocity = Vector3.ZERO
		_has_pending_velocity = false
	var velocity := state.linear_velocity
	var speed := velocity.length()
	if speed > PinballData.BALL_MAX_SPEED:
		state.linear_velocity = velocity * (PinballData.BALL_MAX_SPEED / speed)


func _on_body_entered(body: Node) -> void:
	if body != null and body.has_method("on_ball_hit"):
		body.on_ball_hit(self)
		hit_gadget.emit(body)
