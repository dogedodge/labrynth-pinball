extends Node

enum State { WAIT_LAUNCH, PLAYING, BALL_LOST, GAME_OVER }

@onready var world: PinballWorld = $World
@onready var hud: PinballHUD = $UI/HUD
@onready var touch: TouchControls = $UI/TouchControls
@onready var overlays: GameOverlays = $UI/Overlays

var score := 0
var balls_left := PinballData.BALLS_PER_GAME
var state: State = State.WAIT_LAUNCH
var _drain_lock := false
var _user_args: PackedStringArray = []
var _game_id := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("pinball_game")
	_user_args = OS.get_cmdline_user_args()
	world.ball_drained.connect(_on_ball_drained)
	world.plunger_charge_changed.connect(_on_plunger_charge)
	_new_game()
	if _has_arg("--smoke-test"):
		_run_smoke_test()
	elif _has_arg("--screenshot"):
		_run_screenshot()


func _new_game() -> void:
	_game_id += 1
	score = 0
	balls_left = PinballData.BALLS_PER_GAME
	_drain_lock = false
	get_tree().paused = false
	overlays.hide_all()
	_update_hud()
	_serve_ball()


func _serve_ball() -> void:
	state = State.WAIT_LAUNCH
	_drain_lock = false
	world.spawn_ball()
	_update_hud()


func add_score(points: int) -> void:
	if state == State.GAME_OVER:
		return
	score += points
	_update_hud()


func _update_hud() -> void:
	hud.set_status(score, balls_left, state == State.GAME_OVER)


func _on_plunger_charge(ratio: float) -> void:
	touch.set_launch_charge(ratio)
	if state == State.WAIT_LAUNCH and ratio > 0.0:
		state = State.PLAYING


func _on_ball_drained() -> void:
	if _drain_lock or state == State.GAME_OVER or state == State.BALL_LOST:
		return
	_drain_lock = true
	state = State.BALL_LOST
	_lose_ball()


func _lose_ball() -> void:
	var id := _game_id
	balls_left = max(balls_left - 1, 0)
	_update_hud()
	await get_tree().create_timer(0.85).timeout
	if not is_inside_tree() or id != _game_id:
		return
	world.clear_ball()
	if balls_left <= 0:
		state = State.GAME_OVER
		overlays.show_game_over(score)
		_update_hud()
	else:
		_serve_ball()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"pause") and state != State.GAME_OVER:
		_toggle_pause()
	if Input.is_action_just_pressed(&"restart"):
		_new_game()
	_check_out_of_bounds()


func _toggle_pause() -> void:
	if state == State.GAME_OVER:
		return
	var paused := not get_tree().paused
	get_tree().paused = paused
	if paused:
		overlays.show_paused()
	else:
		overlays.hide_all()


func _check_out_of_bounds() -> void:
	if state == State.GAME_OVER or state == State.BALL_LOST:
		return
	if world.ball == null or not is_instance_valid(world.ball):
		return
	var local := world.ball_playfield_position()
	if local.y < -0.25 or local.z > 0.62:
		_on_ball_drained()


func _has_arg(flag: String) -> bool:
	for arg in _user_args:
		if arg == flag or arg.begins_with(flag + "="):
			return true
	return false


func _arg_value(flag: String, default_value: String) -> String:
	for arg in _user_args:
		if arg.begins_with(flag + "="):
			return arg.substr(flag.length() + 1)
	return default_value


func _run_smoke_test() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	var report := {}
	var failures: PackedStringArray = []

	if world.ball == null:
		failures.append("ball was not spawned")
	var start := world.ball_playfield_position()
	report["spawn"] = [start.x, start.y, start.z]
	await get_tree().create_timer(0.35).timeout
	var parked := world.ball_playfield_position()
	report["parked"] = [parked.x, parked.y, parked.z]
	if parked.x < 0.22:
		failures.append("ball left the plunger lane before launch")

	Input.action_press(&"plunger")
	await get_tree().create_timer(0.55).timeout
	report["plunger_charge"] = world.plunger.charge
	report["ball_frozen"] = world.ball.freeze
	report["ball_before_release"] = [
		world.ball_playfield_position().x,
		world.ball_playfield_position().y,
		world.ball_playfield_position().z,
	]
	Input.action_release(&"plunger")
	await get_tree().create_timer(0.4).timeout

	var launched := world.ball_playfield_position()
	report["after_launch"] = [launched.x, launched.y, launched.z]
	report["ball_velocity"] = [
		world.ball.linear_velocity.x,
		world.ball.linear_velocity.y,
		world.ball.linear_velocity.z,
	]
	var moved_up := launched.z < start.z - 0.20
	report["moved_up_lane"] = moved_up
	if not moved_up:
		failures.append(
			"ball did not move up the lane (spawn z=%.3f after z=%.3f)" % [start.z, launched.z]
		)

	if world.left_flipper == null or world.right_flipper == null:
		failures.append("flippers missing")
	else:
		if absf(world.left_flipper.position.z - 0.42) > 0.05:
			failures.append("left flipper not at player-end marker (z=%.3f)" % world.left_flipper.position.z)
		var left_rest := world.left_flipper.rotation.y
		Input.action_press(&"flipper_left")
		await get_tree().create_timer(0.12).timeout
		var left_active := world.left_flipper.rotation.y
		Input.action_release(&"flipper_left")
		var left_ok := absf(rad_to_deg(left_active) - PinballData.FLIPPER_LEFT_ACTIVE_DEG) < 12.0
		report["left_flipper_rest_deg"] = rad_to_deg(left_rest)
		report["left_flipper_active_deg"] = rad_to_deg(left_active)
		report["left_flipper_ok"] = left_ok
		if not left_ok:
			failures.append("left flipper did not rotate to active angle")

		Input.action_press(&"flipper_right")
		await get_tree().create_timer(0.12).timeout
		var right_active := world.right_flipper.rotation.y
		Input.action_release(&"flipper_right")
		var right_ok := absf(rad_to_deg(right_active) - PinballData.FLIPPER_RIGHT_ACTIVE_DEG) < 12.0
		report["right_flipper_active_deg"] = rad_to_deg(right_active)
		report["right_flipper_ok"] = right_ok
		if not right_ok:
			failures.append("right flipper did not rotate to active angle")

	_check_inlane_collision(report, failures)
	await _check_inlane_ball_block(report, failures)

	if failures.is_empty():
		print("SMOKE TEST PASSED")
		print(JSON.stringify(report))
		get_tree().quit(0)
	else:
		printerr("SMOKE TEST FAILED: ", ", ".join(failures))
		print(JSON.stringify(report))
		get_tree().quit(1)


func _playfield_ray(from_local: Vector3, to_local: Vector3) -> Dictionary:
	var space := world.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		world.playfield.to_global(from_local),
		world.playfield.to_global(to_local)
	)
	query.collision_mask = PinballData.LAYER_WORLD
	query.collide_with_areas = false
	return space.intersect_ray(query)


func _check_inlane_collision(report: Dictionary, failures: PackedStringArray) -> void:
	# Rays through the visible yellow rails, on the outer third where the old
	# inverted colliders did not sit.
	var blockers := [
		["left_inlane", Vector3(-0.18, 0.02, 0.318), Vector3(-0.30, 0.02, 0.318)],
		["right_inlane", Vector3(0.12, 0.02, 0.318), Vector3(0.26, 0.02, 0.318)],
		["left_apron", Vector3(-0.04, 0.02, 0.48), Vector3(-0.20, 0.02, 0.48)],
		["right_apron", Vector3(-0.01, 0.02, 0.48), Vector3(0.14, 0.02, 0.48)],
	]
	for spec in blockers:
		var from_pos: Vector3 = spec[1]
		var to_pos: Vector3 = spec[2]
		var hit: Dictionary = _playfield_ray(from_pos, to_pos)
		report[String(spec[0]) + "_hit"] = not hit.is_empty()
		if hit.is_empty():
			failures.append("%s not blocking a playfield ray" % spec[0])
	# Inlane feed to the flippers must stay open.
	var feeds := [
		["left_feed", Vector3(-0.06, 0.02, 0.34), Vector3(-0.09, 0.02, 0.45)],
		["right_feed", Vector3(0.01, 0.02, 0.34), Vector3(0.04, 0.02, 0.45)],
	]
	for spec in feeds:
		var from_pos: Vector3 = spec[1]
		var to_pos: Vector3 = spec[2]
		var hit: Dictionary = _playfield_ray(from_pos, to_pos)
		report[String(spec[0]) + "_clear"] = hit.is_empty()
		if not hit.is_empty():
			failures.append("%s path to flipper is blocked" % spec[0])


func _check_inlane_ball_block(report: Dictionary, failures: PackedStringArray) -> void:
	if world.ball == null or not is_instance_valid(world.ball):
		failures.append("no ball for inlane impact test")
		return
	world.plunger.bind_ball(null)
	world.ball.position = Vector3(-0.14, PinballData.BALL_RADIUS, 0.28)
	world.ball.launch(world.playfield.global_transform.basis * Vector3(-3.2, 0.0, 2.4))
	await get_tree().create_timer(0.35).timeout
	if world.ball == null or not is_instance_valid(world.ball):
		failures.append("ball disappeared during inlane impact test")
		return
	var pos := world.ball_playfield_position()
	report["inlane_impact"] = [pos.x, pos.y, pos.z]
	var in_left_pocket := pos.x < -0.20 and pos.z > 0.31 and pos.z < 0.55
	report["inlane_impact_in_pocket"] = in_left_pocket
	if in_left_pocket:
		failures.append(
			"ball passed through left inlane into the side pocket (x=%.3f z=%.3f)" % [pos.x, pos.z]
		)
	if pos.y < -0.05 or pos.x < -0.32:
		failures.append("ball left the table during inlane impact test")


func _run_screenshot() -> void:
	var path := _arg_value("--screenshot", "docs/gameplay.png")
	if not path.begins_with("/") and not path.begins_with("res://") and not path.begins_with("user://"):
		path = ProjectSettings.globalize_path("res://").path_join(path)
	# Launch so the table is in play, then capture.
	await get_tree().create_timer(0.3).timeout
	Input.action_press(&"plunger")
	await get_tree().create_timer(0.5).timeout
	Input.action_release(&"plunger")
	Input.action_press(&"flipper_left")
	Input.action_press(&"flipper_right")
	await get_tree().create_timer(0.55).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	Input.action_release(&"flipper_left")
	Input.action_release(&"flipper_right")
	if err != OK:
		printerr("Failed to save screenshot to ", path, " err=", err)
		get_tree().quit(1)
		return
	print("SCREENSHOT SAVED ", path)
	get_tree().quit(0)
