extends Node
const Tracker = preload("user://mod/tools/clips/DashKillTracker.gd")
signal highlight(first_time,last_time,kills)
var service
var game
var tracker = Tracker.new()
var round_key = ""
var chain = []
var pending = []
var confirmed_kills = 0
var observed_ticks = 0
var stun_edges = 0
var death_edges = 0
var impact_candidates = 0
var last_round = {}
var selected_victims={}
var selected_chain=false

func configure(owner) -> void:
	service = owner
	pause_mode = Node.PAUSE_MODE_PROCESS

func attach(next_game) -> void:
	if not is_instance_valid(next_game): next_game = null
	if is_instance_valid(game) and next_game==game: return
	if game==null and next_game==null: return
	detach()
	game = next_game
	if is_instance_valid(game) and game.has_signal("tick_post_step"):
		game.connect("tick_post_step",self,"_tick")
		if game.has_signal("player_eliminated"): game.connect("player_eliminated",self,"_eliminated")

func detach() -> void:
	_remember_round()
	if is_instance_valid(game) and game.is_connected("tick_post_step",self,"_tick"):
		game.disconnect("tick_post_step",self,"_tick")
	if is_instance_valid(game) and game.is_connected("player_eliminated",self,"_eliminated"):
		game.disconnect("player_eliminated",self,"_eliminated")
	game = null
	round_key = ""
	confirmed_kills = 0
	_reset_counters()
	selected_victims.clear()
	tracker.reset()
	_close_chain()

func _tick(_rate: float,_tick_number: int) -> void:
	if not is_instance_valid(game) or not service.active() or not service.settings.highlights: return
	if game.is_resimulating(): return
	var data = game.wp_game_data
	if data.is_replay or data.is_replay_ghost or data.is_time_trial or data.is_tutorial or data.is_level_editor: return
	if not game.has_loaded_level or game.level.loaded_level==null: return
	var mode = int(game.level.loaded_level.level_type)
	var allowed = (mode==1 and service.settings.knockout) or (mode==0 and service.settings.race)
	if not allowed:
		tracker.reset()
		return
	var key = "%s:%s:%s" % [data.match_id,data.level_key,data.gameplay_round_counter]
	if key!=round_key:
		_remember_round()
		_close_chain()
		tracker.reset()
		selected_victims.clear()
		round_key = key
		confirmed_kills = 0
		_reset_counters()
	var finishing = data.gameplay_state==WPGameData.GameplayState_GAME_OVER
	if data.gameplay_state!=WPGameData.GameplayState_LEVEL_PLAY and not finishing:
		_close_chain()
		# Reliable elimination messages may arrive just after the replicated
		# round state. Keep recent hit claims for that confirmation; their TTL
		# still applies, and a new map/round resets them before observing it.
		return
	var local = game.get_local_player()
	if local==null or local.type==NetworkPlayer.SPECTATOR: return
	var players = []
	observed_ticks += 1
	for index in game.get_player_count():
		var player = game.get_player_at_index(index)
		if player==null or player.type==NetworkPlayer.SPECTATOR or not is_instance_valid(player.body): continue
		if player.alive and not player.eliminated: selected_victims.erase(player.object_id)
		var body = player.body
		var previous_player = tracker.previous.get(player.object_id,{})
		if not previous_player.empty():
			if player.stun_timer>float(previous_player.stun)+0.5: stun_edges += 1
			if previous_player.alive and (not player.alive or player.eliminated): death_edges += 1
		var jumped = previous_player.has("jump_flag") and bool(previous_player.jump_flag)!=bool(player.jump_renderer_flag)
		players.append({"id":player.object_id,"alive":player.alive and not player.eliminated,"stun":player.stun_timer,
			"dashing":player.dash_timer>0 and player.dash_timer<=data.player_dash_ticks-data.player_dash_charge_ticks,
			"jumping":jumped,"jump_flag":player.jump_renderer_flag,"grounded":body.is_on_floor(),"position":body.global_position,"velocity":body.linear_velocity,"direction":Vector2.RIGHT if player.dash_dir else Vector2.LEFT})
	var pairs = Tracker.impact_pairs(players,tracker.previous,float(data.player_dash_force_distance),float(data.player_dash_impulse),float(data.player_dash_stun_ticks),float(data.player_spring_force_stun_ticks))
	impact_candidates += pairs.size()
	var now = OS.get_ticks_msec()/1000.0
	for kill in tracker.observe(players,pairs,now,local.object_id,float(data.player_spring_force_stun_ticks),float(data.player_spring_force_distance),max(100.0,float(data.player_dash_impulse)*0.2)): add_kill(kill.at,kill.victim)
	if finishing:
		_close_chain()
		_remember_round()

func _eliminated(id: int) -> void:
	if not is_instance_valid(game) or not service.active() or not service.settings.highlights or not service.settings.knockout: return
	var data = game.wp_game_data
	if data.is_replay or data.is_replay_ghost or data.is_time_trial or data.is_tutorial or data.is_level_editor: return
	if game.level.loaded_level==null or int(game.level.loaded_level.level_type)!=1: return
	var key = "%s:%s:%s" % [data.match_id,data.level_key,data.gameplay_round_counter]
	if key!=round_key: return
	var local = game.get_local_player()
	if local==null: return
	var now = OS.get_ticks_msec()/1000.0
	if tracker.confirm_elimination(id,now,local.object_id): add_kill(now,id)

func add_kill(now: float,victim: int) -> void:
	if not chain.empty() and now-float(chain[0].at)>float(service.settings.kill_window): _close_chain()
	for kill in chain:
		if kill.victim==victim: return
	chain.append({"at":now,"victim":victim})
	confirmed_kills += 1
	if not selected_victims.has(victim) and _selected(victim):
		selected_victims[victim]=true
		selected_chain=true

func status_text() -> String:
	if service==null or not service.settings.highlights: return "Off · clip key only"
	if not service.active(): return "Waiting for the replay buffer"
	if not is_instance_valid(game): return "Waiting for a match"
	var data = game.wp_game_data
	if data.is_replay or data.is_replay_ghost or data.is_time_trial or data.is_tutorial or data.is_level_editor: return "Match highlights only"
	if not game.has_loaded_level or game.level.loaded_level==null: return "Waiting for the map"
	var mode = int(game.level.loaded_level.level_type)
	if mode==1 and not service.settings.knockout: return "Knockout highlights off"
	if mode==0 and not service.settings.race: return "Race highlights off"
	if not mode in [0,1]: return "Waiting for the round"
	if game.get_local_player()==null: return "Waiting for your player"
	if not pending.empty(): return "%d-kill clip pending" % int(pending[0].count)
	if not chain.empty(): return "%d dash kill%s · collecting streak" % [chain.size(),"" if chain.size()==1 else "s"]
	if data.gameplay_state!=WPGameData.GameplayState_LEVEL_PLAY: return "Round finished" if confirmed_kills>0 else "Waiting for round start"
	return "Watching %s · %d dash kills" % ["Knockout" if mode==1 else "Race",confirmed_kills]


func _reset_counters() -> void:
	observed_ticks = 0
	stun_edges = 0
	death_edges = 0
	impact_candidates = 0


# Small operational status alongside the recorder's status.json. No account
# identifiers, player names, frame trace or console spam; overwritten in place.
func diagnostics() -> Dictionary:
	return {"status":status_text(),"observed_ticks":observed_ticks,"stun_edges":stun_edges,"death_edges":death_edges,"impact_candidates":impact_candidates,"linked_pushes":tracker.linked_pushes,"active_claims":tracker.claims.size(),"confirmed_kills":confirmed_kills,"collecting_kills":chain.size(),"pending_clips":pending.size(),"last_round":last_round}


func _remember_round() -> void:
	if observed_ticks<=0 or (death_edges==0 and stun_edges==0): return
	last_round = {"observed_ticks":observed_ticks,"stun_edges":stun_edges,"death_edges":death_edges,"impact_candidates":impact_candidates,"linked_pushes":tracker.linked_pushes,"confirmed_kills":confirmed_kills,"recorded_at":OS.get_unix_time()}

func _close_chain() -> void:
	if chain.empty(): return
	var count = chain.size()
	var save = (count==1 and service.settings.single_kills) or (count==2 and service.settings.double_kills) or (count==3 and service.settings.triple_kills) or (count>=4 and service.settings.multi_kills)
	save=save or selected_chain
	selected_chain=false
	if save: pending.append({"first":chain[0].at,"last":chain.back().at,"count":count})
	chain.clear()

func _process(_delta: float) -> void:
	if service==null: return
	var now = OS.get_ticks_msec()/1000.0
	if not chain.empty() and (now-float(chain[0].at)>=float(service.settings.kill_window) or (selected_chain and now-float(chain.back().at)>=float(service.settings.postroll))): _close_chain()
	for group in pending.duplicate():
		if now<float(group.last)+float(service.settings.postroll): continue
		pending.erase(group)
		emit_signal("highlight",group.first,group.last,group.count)

func disable() -> void:
	detach()
	chain.clear()
	pending.clear()

func _exit_tree() -> void: detach()

func _selected(victim: int) -> bool:
	var who=load("user://mod/tools/clips/ClipPlayers.gd").identity(game,victim)
	if who.empty(): return false
	for row in service.settings.get("watched_players",[]):
		if str(row.id)==str(who.id): return true
	return false
