extends MeshInstance

class_name TileElement

var id := 0

enum State {BUILT, SELECTED, BEING_DESTROYED, DESTROYED, DISABLED}
var state = State.BUILT 
var particles_instance : Particles

onready var mat : SpatialMaterial = get_surface_material(0)
onready var parent_physics_body : StaticBody = get_parent()
onready var tween : Tween = $"../../../Tween"
onready var camera_manager : Node = $"/root/World/CameraManager"
onready var HEIGHT : float = $"../../../../CairoTilesetGen".HEIGHT

const DISABLE_COLOUR : Color = Color(0/255.0, 0/255.0, 0/255.0)
const HOVER_COLOUR : Color = Color(0/255.0, 45/255.0, 227/255.0)
const SELECT_COLOUR : Color = Color(125/255.0, 125/255.0, 0/255.0) # Not used directly
const HOVER_SELECT_COLOUR := HOVER_COLOUR + SELECT_COLOUR
const HOVER_REMOVE_COLOUR : Color = Color(160/255.0, 0/255.0, 56/255.0)

func set_disabled():
	state = State.DISABLED
 
func set_id(var i: int):
	id = i
	
func _ready():
	if state == State.DISABLED:
		return
	parent_physics_body.connect("mouse_entered", self, "_on_StaticBody_mouse_entered")
	parent_physics_body.connect("mouse_exited", self, "_on_StaticBody_mouse_exited")
	parent_physics_body.connect("input_event", self, "_on_StaticBody_input_event")
	mat.emission_energy = 1.0 
	mat.emission_enabled = false

func update_HOVER_color(var is_hover : bool):
	if state >= State.SELECTED:
		return
	if is_hover:
		mat.emission = HOVER_COLOUR
		mat.emission_enabled = true
	else:
		mat.emission_enabled = false
		
func update_selected():
	if state >= State.BEING_DESTROYED:
		return
	var fade_time : float = 5.0
	state = State.SELECTED if GlobalVars.SELECTING_MODE else State.BUILT
	tween.remove(self.mat)
	tween.remove(self)
	if state == State.SELECTED:
		print("Do Tween")
		tween.interpolate_property(self.mat, "emission",
			HOVER_SELECT_COLOUR, HOVER_REMOVE_COLOUR, fade_time,
			Tween.TRANS_CIRC, Tween.EASE_IN)
		tween.interpolate_callback(self, fade_time, "do_deconstruct_a")
		tween.start()
	else:
		update_HOVER_color(true)

func do_deconstruct_a():
	print("Remove " + str(id))
	state = State.BEING_DESTROYED
	var thunk_distance : float = GlobalVars.rand.randf_range(0.05, 0.2)
	var thunk_time := thunk_distance * 2
	tween.interpolate_property(parent_physics_body, "translation:y",
		null, -HEIGHT * thunk_distance, thunk_time,
		Tween.TRANS_QUART, Tween.EASE_IN_OUT)
	tween.interpolate_property(self.mat, "emission_energy",
		1.0, 0.0, thunk_time,
		Tween.TRANS_QUART, Tween.EASE_IN_OUT)
	tween.interpolate_callback(self, thunk_time, "do_deconstruct_b")
	tween.start()
	
func do_deconstruct_b():
	mat.emission_enabled = false
	var fall_time : float = GlobalVars.rand.randf_range(4.5, 5.5)
	camera_manager.chroma(false)
	camera_manager.slow_mo(true)
	camera_manager.add_trauma(0.20, to_global(Vector3.ZERO), fall_time)
	tween.interpolate_property(parent_physics_body, "translation:y",
		null, -HEIGHT, fall_time,
		Tween.TRANS_QUART, Tween.EASE_IN_OUT)
	tween.interpolate_callback(self, fall_time, "done_deconstruct")
	tween.interpolate_callback(camera_manager, 0.25, "slow_mo", false)
	tween.start()
	particles_instance = $"../../../Particles".duplicate()
	parent_physics_body.add_child(particles_instance)
	particles_instance.emitting = true

	
func done_deconstruct():
	print("Removed " + str(id))
	state = State.DESTROYED
	particles_instance.queue_free()
	camera_manager.chroma(true)

func _on_StaticBody_mouse_entered():
	update_HOVER_color(true)
	GlobalVars.SELECTED_NODE = self
	if Input.is_mouse_button_pressed(1):
		update_selected()

func _on_StaticBody_mouse_exited():
	update_HOVER_color(false)

func _on_StaticBody_input_event(_camera, event, _click_position, _click_normal, _shape_idx):
	if event is InputEventMouseButton:
		if event.is_pressed() and event.button_index == BUTTON_LEFT:
			GlobalVars.SELECTING_MODE = (state == State.BUILT)
			update_selected()

func get_state() -> int:
	return state
