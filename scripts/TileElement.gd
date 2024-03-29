extends StaticBody
# warning-ignore-all:return_value_discarded

class_name TileElement

var id := 0

enum State {BUILT, SELECTED, BEING_DESTROYED, DESTROYED, DISABLED}
var state = State.BUILT
var selected_by : Array
var particles_instance : Particles

var paths : Dictionary # dict of all pathable neighbours. Key=neighbour, Value=connecting monorail
var neighbours : Array # Array of all neighbours (including immutible ones)

var tween : Tween
var camera_manager : Spatial 
var building_manager
var job_manager : JobManager 

var player : int # Who owns this floor
var building # What is built here

var monorail_cap_mm : MultiMesh
var monorail_cap_id : int
var monorail_cap_moved := false

var tile_mm : MultiMesh
var tile_mm_id : int

var claim_strength : int = 0
var pulse_count : int = 0
var updating_owner_emission := false

# Set to a vec3 if this tile is participating in the pathing. Note: in global coordinates
var pathing_centre = null

onready var HEIGHT : float = GlobalVars.FLOOR_HEIGHT + GlobalVars.TILE_OFFSET

const HOVER_COLOUR : Color = Color(0/255.0, 45/255.0, 227/255.0)
const SELECT_COLOUR : Color = Color(100/255.0, 200/255.0, 150/255.0) # Not used directly
const HOVER_REMOVE_COLOUR : Color = Color(160/255.0, 0/255.0, 56/255.0)
const OWNED_COLOUR : Array = [
	Color(1, 0, 0),
	Color(0, 0, 1),
	Color(1, 1, 0),
	Color(0, 1, 0),
]

const PULSE_TIME := 0.1 # Time in seconds to pulse for
const PULSE_DECAY := 0.001 # Amount to reduce pulse by per tile
const CAPTURE_TIME = 1.5 # Time in seconds to capture per enemy neighbour
const FADE_TIME : float = 5.0 # Time to allow revoke of destroy order

# Only have one countdown timer
var tween_active := false

func set_building(var b):
	assert(building == null)
	building = b
	b.location = self

func set_disabled():
	state = State.DISABLED
	
func set_destroyed():
	state = State.DESTROYED
	set_tile_mm_emission(0.0)
	transform.origin.y = -HEIGHT
	set_tile_mm_height(-HEIGHT)
	var pathing_manager = $"../../../PathingManager"
	# Note: We don't have access to the paths variable yet
	# as this is called also during the level setup
	for n in neighbours:
		if n.state == State.DESTROYED:
			pathing_manager.connect_tiles(GlobalVars.MAX_PLAYERS, self, n, true)
	
func get_state() -> int:
	return state
	
func set_id(var i: int):
	id = i
	
func get_id():
	return id
	
func links_to(var target : StaticBody, var mr, var my_child : bool):
	assert(neighbours.has(target))
	paths[target] = mr
	if my_child:
		mr.set_connections(self, target)
		target.links_to(self, mr, false) # Add reciprocal link
	
func add_neighbour(var n : StaticBody):
	if !neighbours.has(n):
		neighbours.append(n)

func can_be_destroyed() -> bool:
	for n in paths.keys():
		if n.state == State.DESTROYED and n.player != -1 and selected_by[ n.player ]:
			# My destruction was requested by someone who has a tile right nextdoor
			return true
	var pathing_manager = $"../../../PathingManager" 
	for n in paths.keys():
		if n.state != State.DESTROYED:
			continue
		for p in GlobalVars.MAX_PLAYERS:
			if selected_by[p]:
				# Get player's home base tile
				var myMCP = $"../../../../TileManager".tile_dictionary[ GlobalVars.LEVEL.MCP[p] ]
				if pathing_manager.are_tiles_connected(GlobalVars.MAX_PLAYERS, n, myMCP):
					# My destriction was requested by someone who has a theoretically navagable
					# path from a destroyed tile next to me back to their home-base
					return true 
	return false
	
func _ready():
	player = -1
	building = null
	for _p in GlobalVars.MAX_PLAYERS:
		selected_by.push_back(false)
	# See delayed_ready
	
func delayed_ready():
	if state >= State.DISABLED:
		return
	connect("mouse_entered", self, "_on_StaticBody_mouse_entered")
	connect("mouse_exited", self, "_on_StaticBody_mouse_exited")
	connect("input_event", self, "_on_StaticBody_input_event")
	tween = $"../../../Tween"
	camera_manager = $"../../../../CameraManager"
	job_manager = $"../../../../JobManager"
	building_manager = $"../../../../BuildingManager"

func update_HOVER_color(var is_hover : bool):
	if state >= State.SELECTED:
		return
	if tile_mm == null:
		return
	if is_hover:
		set_tile_mm_emission(1.0)
		set_tile_mm_color(HOVER_COLOUR)
	else:
		set_tile_mm_emission(0.0)

		
func update_selected(var player_selecting):
	if state >= State.BEING_DESTROYED:
		return
	if GlobalVars.SELECTING_MODE:
		state = State.SELECTED
		selected_by[player_selecting] = true
	else:
		selected_by[player_selecting] = false
		var n_selected = 0
		for p in GlobalVars.MAX_PLAYERS:
			if selected_by[p]:
				n_selected += 1
		state = State.SELECTED if n_selected > 0 else State.BUILT
	tween.remove(self)
	tween_active = false
	if state == State.SELECTED:
		if can_be_destroyed():
			do_deconstruct_start(FADE_TIME)
		else:
			set_tile_mm_color(SELECT_COLOUR)
	else:
		update_HOVER_color(true)
		
# Called when one of MY neighbors is destroyed. Check if I was queued for destruction
func a_neighbour_just_fell():
	if state == State.SELECTED and can_be_destroyed():
		do_deconstruct_start(FADE_TIME / 5.0)
		
func assign_monorail_jobs_on_demolish():
	# Check for monorail construction tasks
	# Call if I was just destroyed, and there is an owned tile next door
	# Here the owner of the neighbouring tile(s) sets who the jobs go to
	for n in paths.keys():
		if n.state != State.DESTROYED:
			continue # No - can only connect to destroyed tiles
		if n.player == -1:
			continue # No - can't setup jobs from unowned tiles to unowned tiles
		job_manager.add_job(n.player, job_manager.JobType.CONSTRUCT_MONORAIL, n, self)
			
func try_and_spread_monorail():
	# Check for monorail construction tasks
	# Call if a piece of monorail was just finished to/from me
	# Here my owner determins who the jobs go to
	if building != null:
		return
	for n in paths.keys():
		if n.state != State.DESTROYED:
			continue # No - can only connect to destroyed tiles
		var mr = paths[n]
		if mr.state == mr.State.INITIAL:
			# Spread 
			job_manager.add_job(player, job_manager.JobType.CONSTRUCT_MONORAIL, self, n)
			
func try_and_spread_capture():
	if building != null:
		return
	for n in paths.keys():
		if n.state != State.DESTROYED:
			continue # No - can only connect to destroyed tiles
		var mr = paths[n]
		if mr.state == mr.State.CONSTRUCTED:
			# Attack Check
			if player != -1 and n.player != -1 and player != n.player:
				if n.building != null:
					job_manager.add_job(player, job_manager.JobType.CLAIM_BUILDING, self, n)
				else:
					job_manager.add_job(player, job_manager.JobType.CLAIM_TILE, n, null)

func update_owner_emission():
	if player == -1:
		set_tile_mm_emission(0.0)
		return
	claim_strength = 1
	set_tile_mm_color(OWNED_COLOUR[player])
	for n in paths.keys():
		if n.player == player:
			claim_strength += 1
	tween.interpolate_method(self, "set_tile_mm_emission", get_tile_mm_emission(), claim_strength * 0.01, 0.5)
	tween.interpolate_callback(self, 0.5, "owner_emission_done")
	tween.start()
	updating_owner_emission = true
	
func owner_emission_done():
	updating_owner_emission = false

func get_tile_mm_height() -> float:
	return tile_mm.get_instance_transform(tile_mm_id).origin.y

func set_tile_mm_height(var value : float):
	var t : Transform = tile_mm.get_instance_transform(tile_mm_id)
	t.origin.y = value
	tile_mm.set_instance_transform(tile_mm_id, t)

func get_tile_mm_color() -> Color:
	var c = tile_mm.get_instance_color(tile_mm_id)
	return Color(c.r, c.g, c.b, 1.0)

func set_tile_mm_color(var value : Color):
	var c = tile_mm.get_instance_color(tile_mm_id)
	tile_mm.set_instance_color(tile_mm_id, Color(value.r, value.g, value.b, c.a))

func get_tile_mm_emission() -> float:
	return tile_mm.get_instance_color(tile_mm_id).a

func set_tile_mm_emission(var value : float):
	var c = tile_mm.get_instance_color(tile_mm_id)
	c.a = value
	tile_mm.set_instance_color(tile_mm_id, c)

func raise_cap_call(var value : float):
	var t : Transform = monorail_cap_mm.get_instance_transform(monorail_cap_id)
	t.origin.y = value
	monorail_cap_mm.set_instance_transform(monorail_cap_id, t)

func raise_cap(var time):
	if not monorail_cap_moved:
		tween.interpolate_method(self, "raise_cap_call", monorail_cap_mm.get_instance_transform(monorail_cap_id).origin.y, 0.0, time)
		tween.start()
		monorail_cap_moved = true

func do_deconstruct_start(var time : float):
	if tween_active:
		return
	tween.interpolate_method(self, "set_tile_mm_color",
		SELECT_COLOUR, HOVER_REMOVE_COLOUR, time,
		Tween.TRANS_CIRC, Tween.EASE_IN)
	tween.interpolate_callback(self, time, "do_deconstruct_a")
	tween.start()
	tween_active = true
	
func do_deconstruct_a():
	state = State.BEING_DESTROYED
	var thunk_distance : float = GlobalVars.rand.randf_range(0.05, 0.2)
	var thunk_time := thunk_distance * 2
	tween.interpolate_property(self, "translation:y",
		null, -HEIGHT * thunk_distance, thunk_time,
		Tween.TRANS_QUART, Tween.EASE_IN_OUT)
	tween.interpolate_method(self, "set_tile_mm_height",
		get_tile_mm_height(), -HEIGHT * thunk_distance, thunk_time,
		Tween.TRANS_QUART, Tween.EASE_IN_OUT)
	tween.interpolate_method(self, "set_tile_mm_emission",
		1.0, 0.0, thunk_time,
		Tween.TRANS_QUART, Tween.EASE_IN_OUT)
	tween.interpolate_callback(self, thunk_time, "do_deconstruct_b")
	tween.start()
	
func do_deconstruct_b():
	set_tile_mm_emission(0.0)
	var fall_time : float = GlobalVars.rand.randf_range(4.5, 5.5)
	camera_manager.slow_mo(true)
	camera_manager.add_trauma(0.20, to_global(Vector3.ZERO), fall_time)
	tween.interpolate_property(self, "translation:y",
		null, -HEIGHT, fall_time,
		Tween.TRANS_QUART, Tween.EASE_IN_OUT)
	tween.interpolate_method(self, "set_tile_mm_height",
		get_tile_mm_height(), -HEIGHT, fall_time,
		Tween.TRANS_QUART, Tween.EASE_IN_OUT)
	tween.interpolate_callback(self, fall_time, "done_deconstruct")
	tween.interpolate_callback(camera_manager, 0.25, "slow_mo", false)
	tween.start()
	particles_instance = $"../../../Particles".duplicate()
	self.add_child(particles_instance)
	particles_instance.emitting = true

func done_deconstruct():
	set_destroyed()
	for n in paths.keys():
		n.a_neighbour_just_fell()
	assign_monorail_jobs_on_demolish()
	particles_instance.queue_free()
	
func pulse_start(var pulse_e, var pulse_n):
	pulse_count = pulse_n
	if not updating_owner_emission:
		set_tile_mm_emission( get_tile_mm_emission() + pulse_e )
	tween.interpolate_callback(self, PULSE_TIME, "pulse_end", pulse_e, pulse_n, not updating_owner_emission)
		
func pulse_end(var pulse_e, var pulse_n, var i_pulsed):
	if i_pulsed:
		set_tile_mm_emission( get_tile_mm_emission() - pulse_e )
	pulse_e -= PULSE_DECAY
	if pulse_e <= 0:
		return
	for n in paths.keys():
		if n.state == State.DESTROYED and n.pulse_count < pulse_count and n.player == player:
			n.pulse_start(pulse_e, pulse_n)

func _on_StaticBody_mouse_entered():
	if building_manager.is_placing():
		return building_manager.update_blueprint(self)
	update_HOVER_color(true)
	GlobalVars.SELECTED_NODE = self
	if Input.is_mouse_button_pressed(1):
		update_selected(0)

func _on_StaticBody_mouse_exited():
	if building_manager.is_placing():
		return
	update_HOVER_color(false)
	
func start_capture(var by_whome):
	var time := CAPTURE_TIME * claim_strength
	tween.remove(self)
	tween.interpolate_method(self, "set_tile_mm_color", get_tile_mm_color(), OWNED_COLOUR[by_whome.player], time)
	tween.interpolate_property(by_whome, "rotation:y", null, by_whome.rotation.y+(4.0*PI*time), time)
	tween.interpolate_callback(self, time, "set_captured", by_whome)
	tween.start()
	
func abandon_capture(var by_whome):
	var time := CAPTURE_TIME
	tween.remove(by_whome)
	tween.remove(self)
	tween.interpolate_method(self, "set_tile_mm_color", get_tile_mm_color(), OWNED_COLOUR[player], time)
	tween.start()
	
func set_captured(var by_whome):
	player = by_whome.player
	update_owner_emission()
	try_and_spread_capture()
	for n in paths.keys(): # Give the enemy jobs to reclaim
		n.update_owner_emission()
		n.try_and_spread_capture()
	by_whome.job_finished(true)

# From one destroyed tile to another	
func get_access_tiles():
	var array : Array = []
	for n in paths.keys():
		if n.building == null and n.player == player:
			assert(n.state == State.DESTROYED)
			array.push_back(n)
	return array
	
# For a particular player to build a barrier
func get_access_tiles_wall(var for_player : int):
	var array : Array = []
	for n in paths.keys():
		if n.building == null and n.player == for_player:
			assert(n.state == State.DESTROYED)
			array.push_back(n)
	return array

func _on_StaticBody_input_event(_camera, event, _click_position, _click_normal, _shape_idx):
	if not event is InputEventMouseButton or not event.is_pressed() or not event.button_index == BUTTON_LEFT:
		return
	if building_manager.is_placing():
		return building_manager.place_blueprint(self)
#	print("Me ", get_id(), " " , self)
#	for n in neighbours:
#		print(" N ", n.get_id() , " " , n.state , " " , n)
#	for thePath in paths.keys():
#		print (" Path -> ", thePath.get_id())
	GlobalVars.SELECTING_MODE = (state == State.BUILT)
	update_selected(0) # Currently only user who can click things
