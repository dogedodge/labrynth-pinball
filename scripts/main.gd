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
	if local.y < -0.25 or local.z > world.table_info("inner_half_z", 0.488) + 0.08:
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
	if parked.x < world.table_info("lane_wall_x", 0.445):
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
	# Let the shot finish: it must leave the plunger lane onto the playfield.
	var entered := false
	for i in range(40):
		await get_tree().create_timer(0.05).timeout
		var p := world.ball_playfield_position()
		if p.x < world.table_info("lane_wall_x", 0.445) - 0.02:
			entered = true
			report["entered_playfield_at"] = [p.x, p.y, p.z]
			break
	report["entered_playfield"] = entered
	if not entered:
		failures.append("launched ball never left the plunger lane onto the playfield")
	report["moved_up_lane"] = moved_up
	if not moved_up:
		failures.append(
			"ball did not move up the lane (spawn z=%.3f after z=%.3f)" % [start.z, launched.z]
		)

	if world.left_flipper == null or world.right_flipper == null:
		failures.append("flippers missing")
	else:
		if absf(world.left_flipper.position.z - world.marker_position("Marker_FlipperLeft").z) > 0.01:
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
	# Rays crossing each visible rail / apron wall must hit a world collider, and
	# the inlane feeds to the flippers must stay open. Positions derive from the
	# layout so they follow the table geometry.
	var lf := world.marker_position("Marker_FlipperLeft")
	var rf := world.marker_position("Marker_FlipperRight")
	var ix := world.table_info("inner_half_x", 0.488)
	var lane_x := world.table_info("lane_wall_x", 0.445)
	var blockers := [
		# horizontal ray at a z halfway down the rail, from the playfield side outwards
		["left_inlane", Vector3(lf.x - 0.10, 0.02, 0.2), Vector3(-ix - 0.02, 0.02, 0.2)],
		["right_inlane", Vector3(rf.x + 0.10, 0.02, 0.2), Vector3(lane_x, 0.02, 0.2)],
		["left_apron", Vector3(lf.x + 0.04, 0.02, lf.z + 0.07), Vector3(lf.x - 0.08, 0.02, lf.z + 0.07)],
		["right_apron", Vector3(rf.x - 0.04, 0.02, rf.z + 0.07), Vector3(rf.x + 0.08, 0.02, rf.z + 0.07)],
		# outer walls, lane wall and top wall
		["left_wall", Vector3(-ix + 0.03, 0.02, -0.2), Vector3(-ix - 0.05, 0.02, -0.2)],
		["top_wall", Vector3(0.0, 0.02, -0.40), Vector3(0.0, 0.02, -0.55)],
		["lane_wall", Vector3(lane_x - 0.03, 0.02, 0.1), Vector3(lane_x + 0.02, 0.02, 0.1)],
	]
	for spec in blockers:
		var from_pos: Vector3 = spec[1]
		var to_pos: Vector3 = spec[2]
		var hit: Dictionary = _playfield_ray(from_pos, to_pos)
		report[String(spec[0]) + "_hit"] = not hit.is_empty()
		if hit.is_empty():
			failures.append("%s not blocking a playfield ray" % spec[0])
	var feeds := [
		["left_feed", Vector3(lf.x + 0.04, 0.02, lf.z - 0.05), Vector3(lf.x + 0.02, 0.02, lf.z + 0.04)],
		["right_feed", Vector3(rf.x - 0.04, 0.02, rf.z - 0.05), Vector3(rf.x - 0.02, 0.02, rf.z + 0.04)],
	]
	for spec in feeds:
		var from_pos: Vector3 = spec[1]
		var to_pos: Vector3 = spec[2]
		var hit: Dictionary = _playfield_ray(from_pos, to_pos)
		report[String(spec[0]) + "_clear"] = hit.is_empty()
		if not hit.is_empty():
			failures.append("%s path to flipper is blocked" % spec[0])


func _check_inlane_ball_block(report: Dictionary, failures: PackedStringArray) -> void:
	# Fire the ball at max speed into walls / rails and check it never ends up
	# behind them (anti-tunnelling). Each shot: start, velocity (table-local).
	if world.ball == null or not is_instance_valid(world.ball):
		failures.append("no ball for wall impact test")
		return
	world.plunger.bind_ball(null)
	var ix := world.table_info("inner_half_x", 0.488)
	var iz := world.table_info("inner_half_z", 0.488)
	var lane_x := world.table_info("lane_wall_x", 0.445)
	var r := PinballData.BALL_RADIUS
	var pockets: Array[PackedVector2Array] = []
	var col: Dictionary = world.get_layout().get("colliders", {})
	for raw in col.get("pockets", []):
		var poly := PackedVector2Array()
		for q in raw:
			poly.append(Vector2(float(q[0]), float(q[1])))
		pockets.append(poly)
	var shots := [
		["left_inlane", Vector3(-0.30, r, 0.05), Vector3(-6.0, 0.0, 8.0)],
		["right_inlane", Vector3(0.25, r, 0.05), Vector3(6.0, 0.0, 8.0)],
		["left_wall", Vector3(-0.30, r, -0.20), Vector3(-12.0, 0.0, 0.5)],
		["lane_wall", Vector3(0.30, r, 0.10), Vector3(12.0, 0.0, 0.5)],
		["top_wall", Vector3(-0.02, r, -0.30), Vector3(0.3, 0.0, -12.0)],
	]
	for shot in shots:
		world.ball.freeze = false
		world.ball.position = shot[1]
		world.ball.linear_velocity = Vector3.ZERO
		world.ball.launch(world.playfield.global_transform.basis * Vector3(shot[2]))
		var worst := Vector3.ZERO
		var escaped := false
		for i in range(12):
			await get_tree().physics_frame
			await get_tree().physics_frame
			if world.ball == null or not is_instance_valid(world.ball):
				failures.append("ball disappeared during %s impact test" % shot[0])
				return
			var pos := world.ball_playfield_position()
			var p2 := Vector2(pos.x, pos.z)
			var out := pos.x < -ix or pos.z < -iz or pos.z > iz or pos.y < -0.02
			for poly in pockets:
				out = out or Geometry2D.is_point_in_polygon(p2, poly)
			if shot[0] == "lane_wall":
				out = out or pos.x > lane_x
			if out:
				escaped = true
				worst = pos
				break
			worst = pos
		report[String(shot[0]) + "_impact"] = [worst.x, worst.y, worst.z]
		if escaped:
			failures.append("ball tunneled through %s (x=%.3f z=%.3f)" % [shot[0], worst.x, worst.z])


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
