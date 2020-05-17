tool
extends Spatial
class_name CairoTilesetGen

onready var base_material : SpatialMaterial = preload("res://materials/aluminium.tres")
onready var outline_material : ShaderMaterial = preload("res://materials/grid_edges.tres")
onready var disabled_material : ShaderMaterial = preload("res://materials/grid_faces.tres")
onready var cairo = $Cairo
onready var tiles : Node = $Tiles
onready var monorail = preload("res://scenes/Monorail.tscn")

var rand := RandomNumberGenerator.new()

onready var tile_script = preload("res://scripts/TileElement.gd")
var tile_id : int = 0

func populate(var physics_body_instance : StaticBody):
	var mesh_instance = MeshInstance.new()
	mesh_instance.set_script(tile_script)
	if not Engine.editor_hint: mesh_instance.set_id(tile_id)
	var mat : Material
	if tile_id in GlobalVars.LEVEL.IMMUTABLE or not physics_body_instance.visible:
		physics_body_instance.visible = true # Note: was being used as a flag
		mat = disabled_material
		if not Engine.editor_hint: mesh_instance.set_disabled()
		physics_body_instance.add_to_group("disabled")
	elif tile_id in GlobalVars.LEVEL.INVISIBLE:
		mesh_instance.visible = false
		if not Engine.editor_hint: mesh_instance.set_disabled()
		physics_body_instance.add_to_group("invisible")
	else:
		mat = base_material.duplicate()
		physics_body_instance.add_to_group("interactive")
	tile_id += 1
	mesh_instance.use_in_baked_light = true
	mesh_instance.set_mesh(cairo.cairo_mesh)
	mesh_instance.set_surface_material(0, mat)
	mesh_instance.set_surface_material(1, outline_material)
	physics_body_instance.add_child(mesh_instance)
	var cs = CollisionShape.new()
	cs.set_shape(cairo.cairo_mesh_shape)
	physics_body_instance.add_child(cs)
	var ray := RayCast.new()
	ray.translate(Vector3(cairo.UNIT/2.0, cairo.HEIGHT/2.0, cairo.UNIT/2.0))
	ray.cast_to = Vector3(50.0, 0, 0)
	physics_body_instance.add_child(ray)
	physics_body_instance.add_to_group("tiles")
	
func check_disabled(var physics_body_instance : StaticBody) -> bool:
	var t_local : Vector3 = physics_body_instance.translation
	var t : Vector3 = physics_body_instance.to_global(t_local)
	var distance_v := Vector2()
	var max_outer : float = GlobalVars.LEVEL.TRIPLETS*3*cairo.UNIT*2
	if t.z < 0 or t.x < 0:
		distance_v.x = -min(t.x, t.z)
	if t.z > max_outer or t.x > max_outer:
		distance_v.y = max(t.x, t.z) - max_outer
	var distance = max(distance_v.x, distance_v.y)
	if distance > 0:
		physics_body_instance.visible = false # Used to communicate w below
		if distance > cairo.UNIT*4 and distance > rand.randf_range(0.0, cairo.UNIT*8):
			return true
	return false

func add_cluster(var xOff : int, var yOff : int):
	var spatial : Spatial = Spatial.new()
	var yMod : float = cairo.RIGHT_POINT__UP * xOff
	var xMod : float = cairo.RIGHT_POINT__UP * yOff
	spatial.translate(Vector3(yMod + yOff*(cairo.TOP_POINT__RIGHT + cairo.TOP_POINT__UP), 
		0, xOff*(cairo.UNIT + cairo.RIGHT_POINT__RIGHT) - xMod))
	var physics_body_a := StaticBody.new() # TL
	var physics_body_b := StaticBody.new() # BL
	var physics_body_c := StaticBody.new() # BR
	var physics_body_d := StaticBody.new() # TR
	physics_body_a.translate(Vector3(cairo.UNIT, -GlobalVars.TILE_OFFSET, 0))
	physics_body_b.translate(Vector3(cairo.UNIT, -GlobalVars.TILE_OFFSET, 0))
	physics_body_c.translate(Vector3(cairo.UNIT + cairo.RIGHT_POINT__UP,
		-GlobalVars.TILE_OFFSET, cairo.UNIT + cairo.RIGHT_POINT__RIGHT))
	physics_body_d.translate(Vector3(cairo.UNIT + cairo.RIGHT_POINT__UP,
		-GlobalVars.TILE_OFFSET, cairo.UNIT + cairo.RIGHT_POINT__RIGHT))
	physics_body_b.rotate_y(deg2rad(-90.0))
	physics_body_c.rotate_y(deg2rad(180.0))
	physics_body_d.rotate_y(deg2rad(90.0))
	spatial.add_child(physics_body_a)
	spatial.add_child(physics_body_b)
	spatial.add_child(physics_body_c)
	spatial.add_child(physics_body_d)
	tiles.add_child(spatial)
	physics_body_a.queue_free() if check_disabled(physics_body_a) else populate(physics_body_a)
	physics_body_b.queue_free() if check_disabled(physics_body_b) else populate(physics_body_b)
	physics_body_c.queue_free() if check_disabled(physics_body_c) else populate(physics_body_c)
	physics_body_d.queue_free() if check_disabled(physics_body_d) else populate(physics_body_d)

func _generate():
	tile_id = 0
	rand.set_seed(GlobalVars.LEVEL.SEED)
	for i in range(0, tiles.get_child_count()):
		tiles.get_child(i).queue_free()
	var floor_v := Vector2()
	var border : int = GlobalVars.LEVEL.BORDER_TRIPLETS*3
	var arena : int = GlobalVars.LEVEL.TRIPLETS*3
	for x in range(-border, (arena*2) + border):
		for y in range(-border - arena, arena + border):
			floor_v = Vector2(floor(x/3.0), floor(y/3.0))
			if (y+border < 0 - floor_v.x  ||  y-border > arena - floor_v.x): continue
			if (x+border < 0 + floor_v.y  ||  x-border > arena + floor_v.y): continue
			add_cluster(x, y)

# Called when the node enters the scene tree for the first time.
func _ready():
	_generate()

func _physics_process(var _delta):
	set_physics_process(false)
	print("Phys once")
	if Engine.editor_hint:
		return
	set_neighbours()
	disabled_tiles_to_multimesh() # Broken
	apply_loaded_level()
	add_monorail()

func set_neighbours():
	for tile in get_tree().get_nodes_in_group("tiles"):
		var ray : RayCast = tile.get_child(2)
		for _a in range(10):
			ray.force_raycast_update()
			var c = ray.get_collider()
			if c != null and c.get_child(0).has_method("add_neighbour"):
				c.get_child(0).add_neighbour( tile.get_child(0) )
				tile.get_child(0).add_neighbour( c.get_child(0) )
			ray.rotate_object_local(Vector3.UP, 2.0*PI / 10.0)
		ray.queue_free()

func apply_loaded_level():
	for tile in get_tree().get_nodes_in_group("tiles"):
		var mesh : MeshInstance = tile.get_child(0)
		if mesh.get_id() in GlobalVars.LEVEL.DESTROYED:
			mesh.set_destroyed()
			tile.translation.y = -cairo.HEIGHT
		if mesh.get_id() == GlobalVars.LEVEL.MCP_0:
			var mcp_0 = $"..//Buildings/MCP".duplicate()
			mcp_0.transform = tile.get_global_transform()
			add_child(mcp_0)
			tile.translation.y = -cairo.HEIGHT
			mesh.set_destroyed()
		if mesh.get_id() == GlobalVars.LEVEL.MCP_1:
			var mcp_1 = $"../Buildings/MCP".duplicate()
			add_child(mcp_1)
			mcp_1.transform = tile.get_global_transform()
			tile.translation.y = -cairo.HEIGHT
			mesh.set_destroyed()

func add_monorail():
	for tile in get_tree().get_nodes_in_group("interactive"):
		var m : MeshInstance = tile.get_child(0)
		var mr = monorail.instance()
		mr.transform = m.get_transform()
		mr.transform.origin.y = cairo.HEIGHT
		mr.transform.origin.z += 6.333
		mr.transform.origin.x += 6.333
		m.add_child(mr)
		
#		var mr2 = monorail.instance()
#		mr2.transform = m.get_transform()
#		mr2.transform.origin.y = cairo.HEIGHT
#		mr2.transform.origin.z += 6.333
#		mr2.transform.origin.x += 6.333
#		mr2.rotate_y(deg2rad(60))
#		m.add_child(mr2)
#
#		var mr3 = monorail.instance()
#		mr3.transform = m.get_transform()
#		mr3.transform.origin.y = cairo.HEIGHT
#		mr3.transform.origin.z += 6.333
#		mr3.transform.origin.x += 6.333
#		mr3.rotate_y(deg2rad(120))
#		m.add_child(mr3)
			
func disabled_tiles_to_multimesh():
	var disabled := get_tree().get_nodes_in_group("disabled")
	var disabled_mm : MultiMeshInstance = $DisabledTiles
	disabled_mm.set_multimesh(MultiMesh.new())
	disabled_mm.get_multimesh().transform_format = MultiMesh.TRANSFORM_3D
	#
	var mesh_instance = MeshInstance.new()
	mesh_instance.set_mesh(cairo.cairo_mesh)
	mesh_instance.set_surface_material(0, disabled_material)
	mesh_instance.set_surface_material(1, outline_material)
	#
	disabled_mm.get_multimesh().mesh = mesh_instance
	disabled_mm.get_multimesh().instance_count = disabled.size()
	# Broken
	for i in range(disabled.size()):
		disabled_mm.get_multimesh().set_instance_transform(i, disabled[i].get_global_transform())
		disabled_mm.get_multimesh().set_instance_transform(i, Transform(Basis(), Vector3(-70,10,-70)))
		#print(disabled[i].get_global_transform())
		#disabled[i].get_child(0).queue_free()
	print(disabled_mm.get_multimesh())
