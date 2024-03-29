extends MultiMeshInstance
# warning-ignore-all:return_value_discarded

onready var rand := RandomNumberGenerator.new()
onready var Curry = preload("res://scenes/Curry.tscn")

enum Mountain {GOING_UP, GOING_DOWN}
enum Slope {STEEP, SHALLOW}
var mountain : int = Mountain.GOING_UP
var slope : int = Slope.STEEP

var curries : Array
var current : Array
var next : Array
var initial_mountain_index : int

# Cannot have min=0 here as != 0 tells the shader to do the mountain
const MOUNTAIN_LIMITS := Vector2(0.1, 1.0)
const EXTENT : int = 50
const MORPH_TIME : float = 1.0

func mountain_range(var x : float) -> float:
	var s : float
	match slope:
		Slope.STEEP:
			s = rand.randf_range(-0.20, 0.30)
		Slope.SHALLOW:
			s = rand.randf_range(-0.1, 0.20)
	var r : float
	match mountain:
		Mountain.GOING_UP:
			r = x + s
		Mountain.GOING_DOWN:
			r = x - s
	if r >= MOUNTAIN_LIMITS.y:
		r = MOUNTAIN_LIMITS.y
		mountain = Mountain.GOING_DOWN
	elif r <= MOUNTAIN_LIMITS.x:
		r = MOUNTAIN_LIMITS.x
		mountain = Mountain.GOING_UP
	elif rand.randf() > 0.75:
		mountain = Mountain.GOING_UP if rand.randf() > 0.5 else Mountain.GOING_DOWN
		slope = Slope.STEEP if rand.randf() > 0.5 else Slope.SHALLOW
	return r

func update_mountain(var i : int, var c : Color):
	multimesh.set_instance_custom_data(i, c)

func _ready():
	rand.randomize()
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.color_format = MultiMesh.COLOR_NONE
	multimesh.custom_data_format = MultiMesh.CUSTOM_DATA_8BIT
	var grid_mesh_instance : MeshInstance = $"../Grid"
	var grid_mesh : Mesh = grid_mesh_instance.mesh.duplicate()
	var materials : Array = []
	materials.push_back( load("res://materials/grid_faces.tres").duplicate() )
	materials.push_back( load("res://materials/grid_edges.tres").duplicate() )
	for m in materials:
		m.set_shader_param("SPEED", 1.0)
		m.set_shader_param("SHAPE_SIZE", grid_mesh_instance.STEP_SIZE)
		m.set_shader_param("SHAPE_LENGTH", grid_mesh_instance.LENGTH)
		m.set_shader_param("MOUNTAIN_MAX_HEIGHT", 200.0)
		m.set_shader_param("MOUNTAIN_MAX_COLOUR", 0.25) # Fraction of height
		m.set_shader_param("MOUNTAIN_TOP_COLOUR", Color.magenta)
		m.set_shader_param("SCROLL", true)
	grid_mesh.surface_set_material(0, materials[0])
	grid_mesh.surface_set_material(1, materials[1])
	multimesh.mesh = grid_mesh
	# Done setup - cannot change anything else after increasing instance_count
	initial_mountain_index = -1
	multimesh.instance_count = EXTENT*EXTENT
	var count : int = -1
# warning-ignore-all:integer_division
	for x in range(-EXTENT/2, EXTENT/2):
		for z in range(-EXTENT/2, EXTENT/2):
			count += 1
			assert(count < multimesh.instance_count)
			if x == GlobalVars.LEVEL.MOUNTAINS and initial_mountain_index == -1:
				initial_mountain_index = count
			multimesh.set_instance_custom_data(count, Color())
			multimesh.set_instance_transform(count, Transform(Basis(),
			  Vector3(x * grid_mesh_instance.LENGTH, 0, z * grid_mesh_instance.LENGTH)))
	current = generate_mountain()
	for i in range(EXTENT):
		var curry_inst = Curry.instance()
		curry_inst.curry(self, "update_mountain", [initial_mountain_index + i])
		curry_inst.call_me(current[i])
		curries.push_back(curry_inst)
		add_child(curry_inst)
	# Set collison for floor
	var collision_box : BoxShape = $Area/CollisionShape.shape
	collision_box.extents = Vector3(EXTENT * grid_mesh_instance.LENGTH, 1.0, EXTENT * grid_mesh_instance.LENGTH)
	
func generate_mountain() -> Array:
	var array = []
	var previous_mountain : float = 0.1
	for _i in range(EXTENT):
		var custom := Color()
		custom.r = previous_mountain
		custom.g = mountain_range(custom.r)
		custom.b = mountain_range(custom.g)
		custom.a = mountain_range(custom.b)
		previous_mountain = custom.a
		array.push_back(custom)
	return array


func _on_Timer_timeout():
	current = next if !next.empty() else current
	next = generate_mountain()
	var tween : Tween = $Tween
	print("Update mountain")
	for i in range(EXTENT):
		tween.interpolate_method(curries[i], "call_me", current[i], next[i], 
		MORPH_TIME, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	tween.start()
