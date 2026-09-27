class_name PinballBall
extends RigidBody3D

signal hit_gadget(gadget: Node)

const VISUAL_PATH := "res://assets/models/ball.glb"

var _pending_velocity := Vector3.ZERO
var _has_pending_velocity := false

## Anti-balance nudge: a perfectly still ball above the flippers (outside the
## plunger lane) is balancing on an unstable point, e.g. exactly on top of a
## rounded slingshot corner. After STILL_TIME it gets a tiny random push, like
## the vibration of a real table. Real pockets (stable rest spots) would still
## trap the ball and are caught by the rest tests.
const STILL_SPEED := 0.01
const STILL_TIME := 0.8
const NUDGE_SPEED := 0.06
var _still := 0.0
var _nudge_max_z := INF
var _lane_x := INF
var _playfield: Node3D


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
	_playfield = get_parent() as Node3D
	var world := _playfield.get_parent() if _playfield else null
	if world is PinballWorld:
		_nudge_max_z = world.marker_position("Marker_FlipperLeft").z - 0.06
		_lane_x = world.table_info("lane_wall_x", 0.245)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _has_pending_velocity:
		state.linear_velocity = _pending_velocity
		state.angular_velocity = Vector3.ZERO
		_has_pending_velocity = false
	var velocity := state.linear_velocity
	var speed := velocity.length()
	if speed > PinballData.BALL_MAX_SPEED:
		state.linear_velocity = velocity * (PinballData.BALL_MAX_SPEED / speed)
	_check_balance(state, speed)


func _check_balance(state: PhysicsDirectBodyState3D, speed: float) -> void:
	if _playfield == null or speed > STILL_SPEED:
		_still = 0.0
		return
	var local := _playfield.to_local(state.transform.origin)
	if local.z > _nudge_max_z or local.x > _lane_x:
		_still = 0.0
		return
	_still += state.step
	if _still >= STILL_TIME:
		_still = 0.0
		var a := randf() * TAU
		state.linear_velocity += _playfield.global_basis * Vector3(cos(a), 0.0, sin(a)) * NUDGE_SPEED


func _on_body_entered(body: Node) -> void:
	if body != null and body.has_method("on_ball_hit"):
		body.on_ball_hit(self)
		hit_gadget.emit(body)
