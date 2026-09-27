class_name PinballFlipper
extends AnimatableBody3D

const VISUAL_PATH := "res://assets/models/flipper.glb"

@export var input_action: StringName = &"flipper_left"
@export var rest_angle_deg := PinballData.FLIPPER_LEFT_REST_DEG
@export var active_angle_deg := PinballData.FLIPPER_LEFT_ACTIVE_DEG
@export var flip_time := 0.026
@export var return_time := 0.075

var _pressed := false


func _ready() -> void:
	sync_to_physics = true
	collision_layer = PinballData.LAYER_FLIPPER
	collision_mask = PinballData.LAYER_BALL
	physics_material_override = ModelUtil.physics_material(0.45, 0.12)

	rotation.y = deg_to_rad(rest_angle_deg)
	var visual: Node3D = ModelUtil.instantiate_glb(VISUAL_PATH)
	add_child(visual)
	ModelUtil.add_convex_collision(self, visual)


func _physics_process(delta: float) -> void:
	_pressed = Input.is_action_pressed(input_action)
	var target := deg_to_rad(active_angle_deg if _pressed else rest_angle_deg)
	var travel := absf(deg_to_rad(active_angle_deg - rest_angle_deg))
	var duration := flip_time if _pressed else return_time
	var step := (travel / maxf(duration, 0.008)) * delta
	rotation.y = rotate_toward(rotation.y, target, step)


func is_at_active() -> bool:
	return absf(rad_to_deg(rotation.y) - active_angle_deg) < 8.0
