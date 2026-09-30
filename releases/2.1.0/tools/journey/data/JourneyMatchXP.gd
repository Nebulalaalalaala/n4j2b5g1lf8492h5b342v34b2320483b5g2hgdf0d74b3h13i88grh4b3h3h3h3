extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Read-only observation of the local player's real game. No RPCs or native XP writes.
var controller
var policy
var game = null
var account_id = ""
var match_id = ""
var rounds = {}
var current = 0
var last_position = null
var elapsed = 0.0
var queued = []
var receipt = []
var xp_before = -1
var terminal = false
var terminal_age = 0.0
var winner = false
var poisoned = false
var trial_baseline = null
var trial_checked = false
var retry_after = 0
var saw_over = false
var bonus_revision = -1

func _ready():
	policy = load(ModPaths.path("JourneyMatchRewards.gd")).new()
	policy.rewards = load(ModPaths.path("JourneyDefinitions.gd")).REWARDS

func _process(delta):
	elapsed += delta
	if elapsed<0.1:
		return
	var step = min(elapsed,0.25)
	elapsed = 0.0
	var service = controller.profile_service
	if service==null or service.store==null:
		return
	var account = str(service.store.account_id)
	if account!=account_id:
		_disconnect()
		account_id = account
		bonus_revision = -1
		queued = []
		receipt = []
		xp_before = -1
	var next = service.game if is_instance_valid(service.game) else null
	if next!=game:
		# Left a public match before it ended: that breaks a win streak, as in the game.
		if not match_id.empty() and not saw_over and not poisoned:
			set_streak(account_id, 0)
		saw_over = false
		_commit()
		_disconnect()
		game = next
		rounds = {}
		current = 0
		match_id = ""
		bonus_revision = -1
		terminal = false
		winner = false
		poisoned = false
		trial_baseline = null
		trial_checked = false
		last_position = null
		if game!=null:
			for pair in [["player_hit_finish_line","_finish"],["player_eliminated","_eliminated"],["game_over","_over"]]:
				game.connect(pair[0],self,pair[1])
	if is_instance_valid(game):
		if service._synthetic():
			poisoned = true
			queued = []
		if _eligible():
			_sample(step)
		elif not poisoned:
			_world_record()
		if terminal or not game.is_in_regular_play():
			_commit()
		if terminal:
			terminal_age += step
	else:
		_commit()
	if not receipt.empty() and (not is_instance_valid(game) or (terminal and terminal_age>=1.0)):
		_present()

func _eligible():
	if not is_instance_valid(game) or account_id.empty() or poisoned or game.is_server() or game.is_custom_game:
		return false
	var d = game.wp_game_data
	var player = game.get_local_player()
	return player!=null and str(player.uuid)==account_id and not (d.is_time_trial or d.is_replay or d.is_level_editor or d.is_tutorial) and not game.is_in_lobby() and game.level.loaded_level!=null

func _sample(delta):
	var player = game.get_local_player()
	if player==null or player.type!=NetworkPlayer.REAL:
		return
	var number = int(game.wp_game_data.gameplay_round_counter)
	if number<=0:
		return
	# Do not bind a new round to the previous/lobby level during a transition.
	# Finish callbacks still sample the already observed round after regular play.
	if number!=current and not game.is_in_regular_play():
		return
	var observed_id = str(game.wp_game_data.match_id)
	# Public games report the placeholder "match_id not set"; treat it as empty
	# so every match gets its own award ids.
	if observed_id.empty() or observed_id=="match_id not set":
		# Server random seed is replicated and stable across reconnects.
		var seed_id = int(game.wp_game_data.random_int)
		if seed_id==0:
			return
		observed_id = "seed-"+str(seed_id)
	if observed_id!=match_id:
		match_id = observed_id
		bonus_revision = -1
		rounds = {}
		current = 0
		terminal = false
		terminal_age = 0.0
	if number!=current:
		_queue_round()
		current = number
		last_position = null
	if not rounds.has(number):
		var level = game.level.loaded_level
		rounds[number] = {"number":number,"eligible":true,"map_id":str(level.level_id),
			"race":level.level_type==LevelUtils.LevelType.RACE,"active":0.0,"distance":0.0,"rank":0}
	# A finish signal can arrive before this observer connects, or be missed
	# during a frame stall. The replicated rank is authoritative too. Only use
	# it in active race play: transition resets and elimination ranks differ.
	if game.is_in_regular_play() and rounds[number].race and not player.eliminated:
		var replicated_rank = int(player.rank)
		if replicated_rank>0 and int(rounds[number].rank)==0:
			rounds[number].rank = replicated_rank
			_queue_round()
	if game.is_in_regular_play() and player.alive and not player.eliminated:
		var inputs = game.local_client_continuous_input
		var moving = inputs.size()>0 and inputs[0]!=null and abs(float(inputs[0]))>0
		var jumping = inputs.size()>1 and bool(inputs[1])
		if last_position!=null and (moving or jumping):
			var distance = player.position.distance_to(last_position)
			if distance>0.1 and distance<200:
				rounds[number].active += delta
				rounds[number].distance += distance
		last_position = player.position
	else:
		_queue_round()

func _finish(id,rank,_out_of,_line,_position):
	if not _eligible() or not game.is_local_player(id):
		return
	_sample(0.0)
	if rounds.has(current) and int(rounds[current].rank)==0:
		rounds[current].rank = int(rank)
	_queue_round()

func _eliminated(id):
	if _eligible() and game.is_local_player(id):
		_queue_round()
		terminal = true
		terminal_age = 0.0

func _over(id):
	if not _eligible():
		return
	# Catch a final race finish whose result signal precedes our callback.
	var player = game.get_local_player()
	if rounds.has(current) and int(game.wp_game_data.gameplay_round_counter)==current and rounds[current].race and not player.eliminated and int(player.rank)>0:
		rounds[current].rank = int(player.rank)
	_queue_round()
	winner = game.is_local_player(id)
	var now = OS.get_unix_time()
	var day = str(int(floor(float(now+int(OS.get_time_zone_info().get("bias",0))*60)/86400.0)))
	queued.append_array(policy.match_awards(account_id,match_id,rounds,winner,now,day))
	if not saw_over:
		saw_over = true
		var streak = streak_of(account_id)+1 if winner else 0
		set_streak(account_id,streak)
		queued.append_array(policy.streak_award(account_id,match_id,streak,now))
	terminal = true
	terminal_age = 0.0

func _queue_round():
	if not rounds.has(current) or poisoned:
		return
	var ledger = controller.ledger
	for entry in policy.round_awards(account_id,match_id,rounds[current],OS.get_unix_time()):
		if not ledger.ids.has(entry.id):
			var found = false
			for pending in queued:
				found = found or pending.id==entry.id
			if not found:
				queued.append(entry)

func _commit():
	if account_id.empty() or OS.get_ticks_msec()<retry_after:
		return
	controller._sync_account()
	var ledger = controller.ledger
	if ledger.account_id!=account_id:
		return
	if queued.empty() and (not terminal or bonus_revision==ledger.revision):
		return
	if terminal and not poisoned and not match_id.empty():
		var now = OS.get_unix_time()
		var day = str(int(floor(float(now+int(OS.get_time_zone_info().get("bias",0))*60)/86400.0)))
		queued.append_array(policy.daily_awards(account_id,match_id,ledger.entries,queued,now,day))
	if queued.empty():
		bonus_revision = ledger.revision
		return
	var fresh = []
	for entry in queued:
		if not ledger.ids.has(entry.id):
			fresh.append(entry)
	var before = ledger.total_xp
	if ledger.award_batch(fresh)<0:
		retry_after = OS.get_ticks_msec()+5000
		push_warning("Journey match XP not saved yet: "+str(ledger.error))
		return
	queued = []
	bonus_revision = ledger.revision if terminal else -1
	if not fresh.empty():
		if xp_before<0:
			xp_before = before
		receipt.append_array(fresh)

func _present():
	# A compact card over the game's own result screen (see JourneyMatchCard);
	# the full Journey menu only opens from its Details button.
	var hud_node = null
	if is_instance_valid(game):
		var scene = get_tree().current_scene
		hud_node = scene.find_node("GameHUD",true,false) if scene!=null else null
		if hud_node==null:
			return
	if is_instance_valid(controller.screen) and controller.screen.design_preview:
		return
	var parent = get_tree().current_scene if get_tree().current_scene!=null else get_tree().root
	var old = parent.get_node_or_null("JourneyMatchCard")
	if old!=null:
		# Same screen, more XP (e.g. eliminated, then the match ended): one card.
		receipt = old.receipt+receipt
		xp_before = old.xp_before
		parent.remove_child(old)
		old.queue_free()
	var card = load(ModPaths.path("JourneyMatchCard.gd")).new()
	card.name = "JourneyMatchCard"
	card.setup(controller,receipt,xp_before,hud_node)
	parent.add_child(card)
	receipt = []
	xp_before = -1

func _disconnect():
	if is_instance_valid(game):
		for pair in [["player_hit_finish_line","_finish"],["player_eliminated","_eliminated"],["game_over","_over"]]:
			if game.is_connected(pair[0],self,pair[1]):
				game.disconnect(pair[0],self,pair[1])
	game = null

func _world_record():
	# Observe the native post-upload leaderboard refresh. Never submit, fetch or
	# infer a world record from a local PB / finish time alone.
	if trial_checked or account_id.empty() or not game.wp_game_data.is_time_trial or game.wp_game_data.is_replay or game.wp_game_data.is_level_editor or game.wp_game_data.is_tutorial:
		return
	var scene = get_tree().current_scene
	if not scene is TimeTrialGameplayScene or scene.game!=game or scene.parameters==null:
		return
	var p = scene.parameters
	if p.mode!=TimeTrialSceneParameters.TimeTrialSceneMode.TimeTrial or p.local_user_id!=account_id:
		return
	var records = p.leaderboard_data.get("records",[])
	if game.time_trial_finish_time<=0:
		if not records.empty() and not p.leaderboard_data.has("error"):
			trial_baseline = float(records[0].get("score",0))
		return
	if trial_baseline==null or records.empty() or p.leaderboard_data.has("error"):
		return
	var top = records[0]
	var score = float(top.get("score",0))
	if str(top.get("owner_id",""))!=account_id or score<=0 or score>=float(trial_baseline) or abs(score-game.time_trial_finish_time*100000.0)>1.0:
		return
	trial_checked = true
	var certified = load(ModPaths.path("JourneyCertified.gd")).load_cache()
	var eligible = false
	for level in certified.get("levels",[]):
		eligible = eligible or str(level.id)==p.level_id
	if not eligible:
		return
	queued.append_array(policy.world_record_awards(account_id,p.level_id,trial_baseline,records,game.time_trial_finish_time,eligible,OS.get_unix_time()))
	terminal = true
	terminal_age = 0.0

# Current win streak per account, counted from observed public matches and
# re-synced from the account's GooberDash stats whenever Journey reads them.
static func streak_of(owner:String) -> int:
	var config = ConfigFile.new()
	if owner.empty() or config.load("user://goobplayability/journey".plus_file(owner.sha256_text()+".streak.cfg"))!=OK:
		return 0
	return int(config.get_value("streak","current",0))

static func set_streak(owner:String,value:int) -> void:
	if owner.empty():
		return
	var config = ConfigFile.new()
	config.set_value("streak","current",max(0,value))
	Directory.new().make_dir_recursive("user://goobplayability/journey")
	config.save("user://goobplayability/journey".plus_file(owner.sha256_text()+".streak.cfg"))
