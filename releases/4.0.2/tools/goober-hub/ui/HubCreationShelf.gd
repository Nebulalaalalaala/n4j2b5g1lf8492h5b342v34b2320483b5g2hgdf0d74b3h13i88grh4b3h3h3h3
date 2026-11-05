extends "user://mod/tools/goober-hub/ui/HubPage.gd"
const FILTERS = ["Outfits","Stamps","Replays","Levels"]
const KINDS = {"Outfits":"outfit","Stamps":"stamp","Replays":"macro"}
var filter = "Outfits"
var owner = ""
var picker
var local = []
var selected = 0
var upload_open = false
var ready_upload = {}
var code_field
var confirm_remove = ""

func build(parent, user_id) -> bool:
	if owner != user_id:
		owner = user_id
		upload_open = false
		ready_upload = {}
		confirm_remove = ""
	var choices = FILTERS if hub.shared_creations.can_macros() else ["Outfits","Stamps","Levels"]
	if not filter in choices: filter = "Outfits"
	ui.choice(parent,choices,filter,self,"_filter")
	if filter == "Levels": return false
	var service = hub.shared_creations
	var which = KINDS[filter]
	service.fetch(owner,which,service.offset if service.profile_owner==owner and service.kind==which else 0)
	var head_card = ui.surface(parent,ui.PANEL,20)
	var col = ui.box(head_card,true,12)
	var heading = ui.section(col,filter,"palette" if which=="outfit" else "hammer" if which=="stamp" else "play","",_color())
	if owner == hub.store.account:
		ui.action(heading,"Add creation",self,"_add",null,"accent","plus",_color())
	ui.action(heading,"Refresh",self,"_refresh",null,"quiet","sparkle",_color())
	if owner == hub.store.account:
		ui.wrap(col,"Only items you publish appear here. Your other saved work stays private.",17,ui.DIM)
	if upload_open and owner==hub.store.account: _publisher(col,which)
	var code_row = ui.box(col,false,10)
	code_field = ui.field(code_row,"Paste sharing code","",50)
	ui.action(code_row,"Open code",self,"_code",null,"quiet","eye",ui.SKY)
	if not service.pending_item.empty(): _preview(parent,service.pending_item)
	if service.status == "missing":
		ui.empty(parent,"Creations setup needed","Run GOOBER_HUB_CREATIONS.sql in Supabase to enable public sharing.","hammer",ui.GOLD)
		return true
	if service.rows.empty():
		ui.empty(parent,"Loading creations…" if service.status=="loading" else "Couldn't load creations" if service.status=="error" else "No shared "+filter.to_lower(),"Saved items appear here after publishing." if owner==hub.store.account else "This player hasn't shared any yet.","palette" if which=="outfit" else "hammer" if which=="stamp" else "play",_color())
	else:
		var grid = GridContainer.new()
		grid.columns = 2
		grid.add_constant_override("hseparation",18)
		grid.add_constant_override("vseparation",18)
		ui.grow(grid)
		parent.add_child(grid)
		for row in service.rows: _card(grid,row)
	var navigation = ui.box(parent,false,12)
	ui.action(navigation,"Previous",self,"_page",-24,"quiet","back").disabled = service.offset==0
	ui.spacer(navigation)
	ui.text(navigation,"Page %d" % (service.offset/24+1),17,ui.DIM)
	ui.spacer(navigation)
	ui.action(navigation,"Next",self,"_page",24,"quiet","chevron_right").disabled = service.rows.size()<24
	return true

func _color(): return ui.HUB_PINK if filter=="Outfits" else ui.SKY if filter=="Stamps" else ui.MINT
func _filter(value):
	filter = value
	upload_open = false
	ready_upload = {}
	hub.shared_creations.pending_item = {}
	hub.shared_creations.offset = 0
	screen.render()
func _refresh():
	hub.shared_creations.fetch(owner,KINDS[filter],hub.shared_creations.offset,true)
	screen.render()
func _page(delta):
	hub.shared_creations.fetch(owner,KINDS[filter],max(0,hub.shared_creations.offset+delta),true)
	screen.scroll.scroll_vertical = 0
	screen.render()
func _add():
	upload_open = not upload_open
	selected = 0
	ready_upload = {}
	screen.render()

func _publisher(parent, which):
	var well = ui.inset(parent,18)
	var col = ui.box(well,true,12)
	local = hub.shared_creations.local_items(which)
	ui.text(col,"Choose a saved "+("outfit" if which=="outfit" else "stamp" if which=="stamp" else "macro"),18,ui.SOFT)
	if local.empty():
		ui.text(col,"Save one in the original tool first.",17,ui.DIM)
		return
	selected = int(clamp(selected,0,local.size()-1))
	picker = OptionButton.new()
	picker.align = Button.ALIGN_CENTER
	picker.add_font_override("font",ui.font("text",20))
	picker.add_stylebox_override("normal",ui.flat(ui.BASE,14,14,0,ui.BASE,false))
	picker.add_color_override("font_color",ui.WHITE)
	picker.get_popup().add_font_override("font",ui.font("text",20))
	picker.clip_text = true
	picker.rect_min_size.y = 48
	ui.grow(picker)
	col.add_child(picker)
	for item in local: picker.add_item(str(item.name))
	picker.select(selected)
	picker.connect("item_selected",self,"_select_local")
	var row = ui.box(col,false,12)
	ui.action(row,"Prepare",self,"_prepare",null,"secondary","check",_color())
	var publish = ui.action(row,"Publish to profile",self,"_publish",null,"accent","plus",_color())
	publish.disabled = ready_upload.empty() or not hub.identity.signed_in()
	ui.wrap(col,"Public to other Goobplayability users. You can remove it later; copies already saved by others remain theirs.",16,ui.DIM)
	if not ready_upload.empty(): ui.text(col,"Ready: "+ready_upload.name,18,ui.MINT)

func _select_local(index):
	selected = index
	ready_upload = {}
	screen.render()
func _prepare():
	if selected<0 or selected>=local.size(): return
	ready_upload = hub.shared_creations.prepare(KINDS[filter],local[selected])
	if ready_upload.empty(): screen.show_notice("This item is unsupported or too large to share. Original item unchanged.")
	screen.render()
func _publish():
	if ready_upload.empty(): return
	hub.shared_creations.publish(ready_upload)
	upload_open = false
	ready_upload = {}
	screen.render()
func _code(): hub.shared_creations.lookup_code(code_field.text)

func _card(parent, row):
	if not row is Dictionary or not row.get("kind") in KINDS.values(): return
	var card = ui.surface(parent,ui.PANEL,20)
	ui.grow(card)
	var content = ui.box(card,false,18) if row.kind=="outfit" else card
	var col = ui.box(content,true,12)
	col.alignment = BoxContainer.ALIGN_CENTER
	ui.grow(col)
	var top = ui.box(col,false,12)
	ui.tile_icon(top,"palette" if row.kind=="outfit" else "hammer" if row.kind=="stamp" else "play",_color(),64)
	var title = ui.wrap(top,str(row.get("title","Untitled")),24,ui.WHITE)
	title.add_font_override("font",ui.font("display",24))
	ui.text(col,"Outfit" if row.kind=="outfit" else "Editor stamp" if row.kind=="stamp" else "TAS replay / macro",16,ui.DIM)
	var details = load(ModPaths.path("HubCreationDetails.gd")).caption(row)
	if not details.empty(): ui.wrap(col,details,17,ui.SOFT)
	var actions = ui.box(col,false,8)
	var save_button = ui.action(actions,"Save",hub.shared_creations,"download",row,"secondary","",_color())
	_save_feedback(save_button,row)
	if row.kind=="outfit":
		var button = ui.action(actions,"Equip",self,"_equip",row,"accent","",ui.HUB_PINK)
		button.hint_tooltip = "Saves a new Look and equips it in Avatar Studio. Does not grant GooberDash cosmetic ownership."
	ui.action(actions,"Copy code",self,"_copy",row,"quiet","",ui.SKY)
	if row.get("owner")==hub.store.account:
		ui.action(col,"Confirm removal" if confirm_remove==row.id else "Remove from profile",self,"_remove",row,"danger")
	if row.kind=="outfit":
		var preview = load(ModPaths.path("HubOutfitPreview.gd")).new()
		preview.service = hub.shared_creations
		preview.row = row
		preview.studio = hub.shared_creations.studio()
		preview.font = ui.font("text",16)
		preview.rect_min_size = Vector2(240,230)
		ui.grow(preview,true,true)
		content.add_child(preview)

func _copy(row):
	OS.clipboard = hub.shared_creations.code(row)
	screen.show_notice("Sharing code copied.")

func _save_feedback(button, item):
	var feedback = load(ModPaths.path("HubSaveFeedback.gd")).new()
	button.add_child(feedback)
	feedback.configure(button,hub.shared_creations,hub.shared_creations.code(item))
func _equip(row): hub.shared_creations.download(row,true)
func _remove(row):
	if confirm_remove!=row.id:
		confirm_remove=row.id
		screen.render()
		return
	confirm_remove = ""
	hub.shared_creations.unpublish(row)

func _preview(parent, item):
	var card = ui.surface(parent,ui.PANEL,20)
	var col = ui.box(card,true,12)
	ui.section(col,str(item.get("title","Shared creation")),"eye","",ui.LILAC)
	if item.kind=="outfit":
		var studio = hub.shared_creations.studio()
		if studio != null:
			var preview = load(ModPaths.path("HubOutfitPreview.gd")).new()
			preview.studio = studio
			preview.payload = item.payload
			preview.rect_min_size = Vector2(0,250)
			col.add_child(preview)
	ui.text(col,"Editor stamp" if item.kind=="stamp" else "TAS replay / macro" if item.kind=="macro" else "Avatar Studio outfit",18,ui.SOFT)
	var details = load(ModPaths.path("HubCreationDetails.gd")).caption(item)
	if not details.empty(): ui.wrap(col,details,18,ui.SOFT)
	var actions = ui.box(col,false,10)
	var save_button = ui.action(actions,"Save to tool",self,"_save_pending",false,"secondary","check",ui.MINT)
	_save_feedback(save_button,item)
	if item.kind=="outfit": ui.action(actions,"Equip outfit",self,"_save_pending",true,"accent","palette",ui.HUB_PINK)
	ui.action(actions,"Close preview",self,"_close_preview",null,"quiet","close")
func _save_pending(equip):
	if hub.shared_creations.pending_item.empty(): return
	screen.show_notice(hub.shared_creations.save_item(hub.shared_creations.pending_item,equip))
func _close_preview():
	hub.shared_creations.pending_item={}
	screen.render()
