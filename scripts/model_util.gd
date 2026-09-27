class_name ModelUtil
extends Object


static func instantiate_glb(path: String) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("Failed to load model: " + path)
		return Node3D.new()
	return packed.instantiate() as Node3D


static func find_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_find_meshes_into(node, out)
	return out


static func _find_meshes_into(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_find_meshes_into(child, out)


static func find_named(node: Node, node_name: String) -> Node:
	if node.name == node_name:
		return node
	return node.find_child(node_name, true, false)


static func physics_material(friction: float, bounce: float) -> PhysicsMaterial:
	var mat := PhysicsMaterial.new()
	mat.friction = friction
	mat.bounce = bounce
	return mat


static func duplicate_surface_material(mesh_instance: MeshInstance3D) -> Material:
	var mat := mesh_instance.get_active_material(0)
	if mat == null:
		return null
	var dup := mat.duplicate()
	mesh_instance.set_surface_override_material(0, dup)
	return dup


static func add_convex_collision(body: CollisionObject3D, visual_root: Node, simplify := true) -> void:
	for mesh_instance in find_meshes(visual_root):
		if mesh_instance.mesh == null:
			continue
		var cs := CollisionShape3D.new()
		cs.name = mesh_instance.name + "Shape"
		cs.shape = mesh_instance.mesh.create_convex_shape(true, simplify)
		body.add_child(cs)
		cs.global_transform = mesh_instance.global_transform


static func add_trimesh_collision(mesh_instance: MeshInstance3D, phys_mat: PhysicsMaterial) -> StaticBody3D:
	mesh_instance.create_trimesh_collision()
	for child in mesh_instance.get_children():
		if child is StaticBody3D:
			var body := child as StaticBody3D
			body.physics_material_override = phys_mat
			body.collision_layer = PinballData.LAYER_WORLD
			body.collision_mask = PinballData.LAYER_BALL
			return body
	return null
