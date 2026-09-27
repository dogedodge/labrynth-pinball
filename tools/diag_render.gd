extends SceneTree
## Diagnostic renders of the lower playfield (needs a display / xvfb, not --headless):
##   godot --path . -s tools/diag_render.gd -- --mode=top   --out=/tmp/top.png
##   godot --path . -s tools/diag_render.gd -- --mode=close --out=/tmp/close.png  [--side=right]
## Slingshot rubber faces are recoloured magenta, kick vectors are drawn as cyan
## arrows from the middle of each kicking face, UI is hidden.

var main: Node
var frames := 0
var args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 3:
		_setup()
	if frames == 12:
		var img := root.get_texture().get_image()
		var out := String(args.get("out", "/tmp/diag.png"))
		img.save_png(out)
		print("DIAG SAVED ", out)
		quit()
	return false


func _setup() -> void:
	var world: Node3D = main.get_node("World")
	main.get_node("UI").visible = false
	if world.ball:
		world.ball.freeze = true
		world.ball.visible = false
	var pf: Node3D = world.playfield
	var magenta := StandardMaterial3D.new()
	magenta.albedo_color = Color(1, 0, 1)
	magenta.emission_enabled = true
	magenta.emission = Color(1, 0, 1)
	magenta.emission_energy_multiplier = 0.6
	for sling_name in ["SlingshotLeft", "SlingshotRight"]:
		var sling: Node3D = pf.get_node(sling_name)
		for mi in _meshes(sling):
			if String(mi.name).ends_with("Kicker"):
				mi.material_override = magenta
		# kick arrow from the middle of the kicking face (layout "face")
		var sl: Dictionary = world.get_layout().get("slingshots", {}).get("Marker_" + sling_name, {})
		var face: Array = sl.get("face", [])
		var start := sling.position + Vector3(0, 0.04, 0)
		if face.size() == 2:
			start = Vector3((face[0][0] + face[1][0]) * 0.5, 0.04, (face[0][1] + face[1][1]) * 0.5)
		_arrow(pf, start, sling.kick_local.normalized() * 0.09, Color(0, 1, 1))
	var cam := Camera3D.new()
	pf.add_child(cam)
	var mode := String(args.get("mode", "top"))
	if mode == "top":
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 0.62  # vertical extent (m)
		cam.position = Vector3(float(args.get("cx", "-0.0245")), 2.0, float(args.get("cz", "0.2")))
		cam.rotation_degrees = Vector3(-90, 0, 0)
	else:
		var side := String(args.get("side", "left"))
		var sling: Node3D = pf.get_node("SlingshotLeft" if side == "left" else "SlingshotRight")
		cam.fov = 20.0
		var target := sling.position
		cam.position = target + Vector3(0.0, 0.42, 0.38)
		cam.look_at(pf.to_global(target), pf.global_transform.basis.y)
	cam.current = true


func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


func _arrow(parent: Node3D, start: Vector3, vec: Vector3, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.003
	cyl.bottom_radius = 0.003
	cyl.height = vec.length()
	shaft.mesh = cyl
	shaft.material_override = mat
	parent.add_child(shaft)
	var dir := vec.normalized()
	shaft.position = start + vec * 0.5
	shaft.basis = Basis(Quaternion(Vector3.UP, dir))
	var head := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.009
	cone.height = 0.02
	head.mesh = cone
	head.material_override = mat
	parent.add_child(head)
	head.position = start + vec + dir * 0.01
	head.basis = Basis(Quaternion(Vector3.UP, dir))
