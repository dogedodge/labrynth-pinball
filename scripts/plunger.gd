class_name PinballPlunger
extends Node3D

signal charge_changed(ratio: float)
signal launched(power: float)

const VISUAL_PATH := "res://assets/models/plunger.glb"
const MAX_PULL := 0.078
const CHARGE_SPEED := 0.14
const RELEASE_TIME := 0.05

@export var input_action: StringName = &"plunger"

var rest_z := 0.0
var charge := 0.0
var _releasing := false
var _playfield: Node3D
var _ball: PinballBall


func setup(playfield: Node3D, marker_z: float) -> void:
	_playfield = playfield
	rest_z = marker_z
	position.z = rest_z


func _ready() -> void:
	var visual: Node3D = ModelUtil.instantiate_glb(VISUAL_PATH)
	add_child(visual)


func bind_ball(ball: PinballBall) -> void:
	_ball = ball


func _physics_process(delta: float) -> void:
	if _releasing:
		var step := MAX_PULL / maxf(RELEASE_TIME, 0.008) * delta
		charge = move_toward(charge, 0.0, step)
		position.z = rest_z + charge
		charge_changed.emit(charge / MAX_PULL)
		if is_zero_approx(charge):
			_releasing = false
		return

	if Input.is_action_pressed(input_action):
		_unfreeze_ball()
		charge = minf(charge + CHARGE_SPEED * delta, MAX_PULL)
		position.z = rest_z + charge
		charge_changed.emit(charge / MAX_PULL)
	elif charge > 0.001:
		var power := maxf(charge / MAX_PULL, 0.32)
		_kick_ball(power)
		launched.emit(power)
		_releasing = true


func _unfreeze_ball() -> void:
	if _ball == null or not is_instance_valid(_ball):
		return
	if _ball.freeze:
		_ball.freeze = false
		_ball.sleeping = false


func _kick_ball(power: float) -> void:
	if _ball == null or not is_instance_valid(_ball) or _playfield == null:
		return
	_unfreeze_ball()
	if power < 0.05:
		return
	var dir := -_playfield.global_transform.basis.z
	var speed := lerpf(3.2, 7.8, clampf(power, 0.0, 1.0))
	_ball.launch(dir * speed)
