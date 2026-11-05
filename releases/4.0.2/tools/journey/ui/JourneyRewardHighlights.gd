extends Reference
# Account-scoped, presentation-only unlock bookkeeping. The first observation
# quietly establishes a baseline; nothing changes XP, claims or notifications.
var account = ""
var recent = {}

func observe(model, store):
	if model.get("preview",false) or not model.get("signed_in",false) or not store.writable or not store.test.empty(): return
	if account != store.account_id:
		account = store.account_id
		recent.clear()
	var keys = []
	var cosmetics = model.get("cosmetics",{})
	if cosmetics is Dictionary:
		for group in ["themes","finishes"]:
			for reward in cosmetics.get(group,[]):
				if str(reward.get("state","locked"))!="locked": keys.append(group+":"+str(reward.key))
	var achievements = model.get("achievements")
	if achievements!=null:
		for collection in achievements.collections:
			for tier in range(1,int(collection.tier)+1): keys.append("badge:%s:%d" % [collection.key,tier])
	if not store.seen.has("rewards"): store.seen.rewards = {}
	var seen = store.seen.rewards
	var initial = not seen.has("_baseline")
	var changed = initial
	seen["_baseline"] = true
	for key in keys:
		if seen.has(key): continue
		seen[key] = true
		changed = true
		if not initial: recent[key] = OS.get_ticks_msec()+300000
	if changed: store.save()

func decorate(card, key, color):
	if int(recent.get(key,0))<OS.get_ticks_msec():
		recent.erase(key)
		return
	var halo = RewardHalo.new()
	halo.registry = self
	halo.key = key
	halo.color = color
	card.add_child(halo)

class RewardHalo extends Node:
	var registry
	var key = ""
	var color = Color.white
	var elapsed = 0.0
	var started = false
	var previous_tooltip = ""
	var border = StyleBoxFlat.new()
	func _ready():
		border.bg_color = Color.transparent
		border.set_border_width_all(3)
		border.set_corner_radius_all(32)
		border.corner_detail = 16
		border.anti_aliasing = true
		previous_tooltip = get_parent().hint_tooltip
		get_parent().hint_tooltip = "Recently unlocked" if previous_tooltip.empty() else previous_tooltip+" · Recently unlocked"
		get_parent().connect("draw",self,"_draw")
	func _process(delta):
		if not _visible_card(): return
		if not started:
			# One automatic highlight, not one per re-render or per click.
			if not registry.recent.has(key):
				queue_free()
				return
			registry.recent.erase(key)
			started = true
		elapsed += delta
		if elapsed>=8.0:
			get_parent().hint_tooltip = previous_tooltip
			queue_free()
			return
		get_parent().update()
	func _visible_card():
		if not get_parent().is_visible_in_tree(): return false
		var clipped = get_parent().get_global_rect()
		var node = get_parent()
		while node is Control:
			if node is ScrollContainer: clipped = clipped.clip(node.get_global_rect())
			node = node.get_parent()
		return clipped.size.x>1 and clipped.size.y>1
	func _draw():
		border.border_color = Color(color.r,color.g,color.b,.65*min(1.0,8.0-elapsed))
		get_parent().draw_style_box(border,Rect2(Vector2(1,1),get_parent().rect_size-Vector2(2,2)))
	func _exit_tree():
		get_parent().hint_tooltip = previous_tooltip
		get_parent().update()
