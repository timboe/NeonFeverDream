extends StaticBody

class_name Monorail

const CONSTRUCT_TIME := 1.0

enum State {INITIAL, UNDER_CONSTRUCTION, CONSTRUCTED}
enum Pathing {BIDIRECTIONAL, OWNER_TO_TARGET, TARGET_TO_OWNER, NONE}

var state : int = State.INITIAL
var pathing : Array

var tile_owner : TileElement
var tile_target : TileElement

func _ready():
	for _i in range(GlobalVars.MAX_PLAYERS):
		pathing.push_back( Pathing.BIDIRECTIONAL )

func set_connections(var o : TileElement, var t : TileElement):
	tile_owner = o
	tile_target = t
	
func start_construction(var by_whome):
	assert(state == State.INITIAL)
	state = State.UNDER_CONSTRUCTION
	var tween : Tween = $"../../Tween"
	tween.remove(self)
	tween.interpolate_property(self, "translation:y", null, 0.0, CONSTRUCT_TIME)
	tween.interpolate_callback(self, CONSTRUCT_TIME, "set_constructed", by_whome, false)
	tween.start()
	tile_owner.raise_cap(CONSTRUCT_TIME)
	tile_target.raise_cap(CONSTRUCT_TIME)
	
func abandon_construction():
	assert(state == State.UNDER_CONSTRUCTION)
	var tween : Tween = $"../../Tween"
	tween.remove(self)
	tween.interpolate_property(self, "translation:y", null, -0.5, CONSTRUCT_TIME)
	tween.interpolate_callback(self, CONSTRUCT_TIME, "set_initial")
	tween.start()	

func set_initial():
	assert(state == State.UNDER_CONSTRUCTION)
	state = State.INITIAL

func set_constructed(var by_whome, var instant : bool):
	if not instant:
		assert(state == State.UNDER_CONSTRUCTION)
	state = State.CONSTRUCTED
	if tile_owner.player == -1:
		tile_owner.player = by_whome.player
	if tile_target.player == -1:
		tile_target.player = by_whome.player
	if tile_owner.building != null or tile_target.building != null:
		update_building_passable()
	else:
		update_pathing()
	tile_owner.update_owner_emission()
	tile_target.update_owner_emission()
	# Can we connect these out further?
	tile_owner.try_and_spread_monorail()
	tile_target.try_and_spread_monorail()
	# Or start a fight?
	tile_owner.try_and_spread_capture()
	tile_target.try_and_spread_capture()
	transform.origin.y = 0
	if not instant:
		by_whome.job_finished(true)

func update_building_passable():
	if (state != State.CONSTRUCTED):
		return
	var owner_accessible = (tile_owner.building == null) 
	var target_accessible = (tile_target.building == null)
	var state : int =  Pathing.NONE
	if owner_accessible and target_accessible:
		state = Pathing.BIDIRECTIONAL
	elif owner_accessible and not target_accessible:
		state = Pathing.TARGET_TO_OWNER
	elif not owner_accessible and target_accessible:
		state = Pathing.OWNER_TO_TARGET
	set_passable_for_all(state)

func set_passable_for_all(var passable_state):
	for p in range(GlobalVars.MAX_PLAYERS):
		pathing[p] = passable_state
	update_pathing()

func set_passable(var player : int, var passable_state):
	pathing[player] = passable_state
	update_pathing()

func get_passable(var player : int, var from : TileElement, var to : TileElement):
	if (state != State.CONSTRUCTED):
		return false
	assert(from == tile_owner or from == tile_target)
	assert(to == tile_owner or to == tile_target)
	assert(from != to)
	match pathing[player]:
		Pathing.BIDIRECTIONAL:
			return true
		Pathing.NONE:
			return false
		Pathing.OWNER_TO_TARGET:
			return true if from == tile_owner and to == tile_target else false
		Pathing.TARGET_TO_OWNER:
			return true if from == tile_target and to == tile_owner else false

func update_pathing():
	if state != State.CONSTRUCTED:
		return
	var pm = $"../../PathingManager"
	for p in range(GlobalVars.MAX_PLAYERS):
		pm.disconnect_tiles(p, tile_owner, tile_target)
		match pathing[p]:
			Pathing.BIDIRECTIONAL:
				pm.connect_tiles(p, tile_owner, tile_target, true)
			Pathing.OWNER_TO_TARGET:
				pm.connect_tiles(p, tile_owner, tile_target, false)
			Pathing.TARGET_TO_OWNER:
				pm.connect_tiles(p, tile_target, tile_owner, false)
			Pathing.NONE:
				pass

