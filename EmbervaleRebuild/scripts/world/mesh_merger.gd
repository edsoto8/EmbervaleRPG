class_name MeshMerger
extends RefCounted
## Bakes many static MeshInstance3Ds that use shared PropFactory materials into a few
## vertex-coloured chunks, cutting draw calls.
##
## Colours are stored as-is (not linearised): in the Compatibility renderer a vertex colour renders
## like the same value in the material's `albedo` uniform. Vertex alpha carries the wind weight as
## `1 - weight`; anchored meshes ramp the weight from their root (0) to their tip (weight).

static var _coloured := {}


## Merges every eligible mesh under `root` (skipping anything under a node in `keep`) into chunks of
## `chunk_size` metres. Returns the new chunk MeshInstance3Ds (children of `target`, default `root`).
## Options: "cast_shadow" (bool), "visibility_end" (float, fades small decor), "name" (String),
## "target" (Node3D), "material" (Material), "single" (bool: one mesh at the target's origin).
static func merge(root: Node3D, keep: Array = [], chunk_size: float = 24.0, options: Dictionary = {}) -> Array:
	var target: Node3D = options.get("target", root)
	var single: bool = options.get("single", false)
	var inv := target.global_transform.affine_inverse()
	var buckets := {}
	var sources: Array[MeshInstance3D] = []
	_collect(root, keep, sources)
	for mi in sources:
		var xf := inv * mi.global_transform
		var key := Vector2i.ZERO if single else Vector2i(floori(xf.origin.x / chunk_size), floori(xf.origin.z / chunk_size))
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append([mi, xf])
	var out: Array = []
	var material: Material = options.get("material", PropFactory.vertex_mat())
	var prefix: String = options.get("name", "Batch")
	for key in buckets:
		var centre := Vector3.ZERO if single else Vector3((key.x + 0.5) * chunk_size, 0.0, (key.y + 0.5) * chunk_size)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var offset := Transform3D(Basis.IDENTITY, -centre)
		for pair in buckets[key]:
			var mi: MeshInstance3D = pair[0]
			st.append_from(_coloured_mesh(mi), 0, offset * pair[1])
		var chunk := MeshInstance3D.new()
		chunk.name = "%s_%d_%d" % [prefix, key.x, key.y]
		chunk.mesh = st.commit()
		chunk.material_override = material
		chunk.position = centre
		chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if options.get("cast_shadow", true) \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if options.has("visibility_end"):
			chunk.visibility_range_end = options["visibility_end"]
			chunk.visibility_range_end_margin = 6.0
			chunk.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			chunk.set_meta("decor_chunk", true)
		target.add_child(chunk)
		out.append(chunk)
	for mi in sources:
		mi.get_parent().remove_child(mi)
		mi.free()
	return out


static func is_mergeable(mi: MeshInstance3D) -> bool:
	return mi.mesh != null and mi.visible and PropFactory.is_shared(mi.material_override)


static func _collect(node: Node, keep: Array, out: Array[MeshInstance3D]) -> void:
	if node in keep:
		return
	if node is MeshInstance3D and is_mergeable(node):
		out.append(node)
	for child in node.get_children():
		_collect(child, keep, out)


## A copy of the mesh's first surface carrying the material colour and wind weight per vertex.
static func _coloured_mesh(mi: MeshInstance3D) -> ArrayMesh:
	var m: Material = mi.material_override
	var color: Color = m.get_meta("pf_color")
	var sway: float = m.get_meta("pf_sway")
	var anchored: bool = mi.get_meta("pf_anchored", false)
	var key := "%d|%s|%.2f|%s" % [mi.mesh.get_instance_id(), color.to_html(false), sway, anchored]
	if _coloured.has(key):
		return _coloured[key]
	var arrays := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors := PackedColorArray()
	colors.resize(verts.size())
	var c := Color(color.r, color.g, color.b, 1.0 - sway)
	if anchored and sway > 0.0:
		var aabb := mi.mesh.get_aabb()
		var h := maxf(aabb.size.y, 0.001)
		for i in verts.size():
			var t := clampf((verts[i].y - aabb.position.y) / h, 0.0, 1.0)
			colors[i] = Color(color.r, color.g, color.b, 1.0 - sway * t)
	else:
		colors.fill(c)
	var clean := []
	clean.resize(Mesh.ARRAY_MAX)
	clean[Mesh.ARRAY_VERTEX] = verts
	clean[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]
	clean[Mesh.ARRAY_COLOR] = colors
	var indices: Variant = arrays[Mesh.ARRAY_INDEX]
	if indices == null or (indices as PackedInt32Array).is_empty():
		# Non-indexed meshes get an explicit index so they merge correctly with indexed ones.
		var seq := PackedInt32Array()
		seq.resize(verts.size())
		for i in verts.size():
			seq[i] = i
		indices = seq
	clean[Mesh.ARRAY_INDEX] = indices
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, clean)
	_coloured[key] = am
	return am
