extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Archive only catalog data already delivered by the normal shop. Expired
# offers stay browsable; this cannot extend a server-side purchase window.
const CACHE = ModPaths.SEASON_DEALS_CACHE
var catalog = {}
var panels = []

func _font(size: int) -> DynamicFont:
	var font = DynamicFont.new()
	font.font_data = load("res://goodoh/fonts/ttf/Baloo2-ExtraBold.ttf")
	font.size = size
	return font

func _ready() -> void:
	var file = File.new()
	if file.open(CACHE, File.READ) == OK:
		if file.get_len() < 2097152:
			var parsed = JSON.parse(file.get_as_text())
			if parsed.error == OK and parsed.result is Dictionary:
				for id in parsed.result:
					if parsed.result[id] is Dictionary and catalog.size() < 300:
						catalog[id] = parsed.result[id]
		file.close()
	Moonlight.shop.connect("products_loaded", self, "_refresh")
	Moonlight.shop.connect("product_purchase_complete", self, "_purchased")
	get_tree().connect("node_added", self, "_consider")
	_scan(get_tree().root)
	_refresh()

func _scan(node: Node) -> void:
	_consider(node)
	for child in node.get_children():
		_scan(child)

func _consider(node: Node) -> void:
	if node is Shop_DealsPanel:
		call_deferred("_attach", node)

func _attach(panel) -> void:
	if not is_instance_valid(panel) or panel.has_meta("season_archive") or Moonlight.discord_api.discord_platform_is_mobile():
		return
	panel.set_meta("season_archive", true)
	var archive = VBoxContainer.new()
	archive.name = "SeasonArchive"
	archive.rect_min_size.x = 700
	panel.deal_nodes_parent.add_child(archive)
	panels.append([panel, archive, 0, 0])
	_render(panels.back())

func _purchased(_sku) -> void:
	call_deferred("_refresh")

func _refresh() -> void:
	for id in Moonlight.shop.products:
		var product = Moonlight.shop.products[id]
		if not product.is_deal or product.hidden or product.deal_start > OS.get_unix_time():
			continue
		if catalog.size() < 300 or catalog.has(id):
			catalog[id] = {"data": product.product_data.duplicate(true), "price": product.product_price}
	var file = File.new()
	if file.open(CACHE, File.WRITE) == OK:
		file.store_string(JSON.print(catalog))
		file.close()
	for state in panels.duplicate():
		if not is_instance_valid(state[0]) or not is_instance_valid(state[1]):
			panels.erase(state)
		else:
			call_deferred("_render", state)

func _owned(product) -> bool:
	var cosmetics = Moonlight_Storage.nested_get("data.cosmetics", product.product_data, [])
	if not cosmetics is Array or cosmetics.empty():
		return false
	var cards = Moonlight.storage.storage_get("player.profile.cards", {})
	for id in cosmetics:
		if not bool(cards.get(id, {}).get("unlocked", false)):
			return false
	return true

func _products(filter: int) -> Array:
	var result = []
	var seen = {}
	var ids = catalog.keys()
	ids.sort()
	for id in ids:
		var entry = catalog[id]
		if not entry.get("data", null) is Dictionary:
			continue
		var product = Moonlight.shop.products.get(id)
		if product == null:
			product = Moonlight_ShopProduct.new(str(id), entry.data)
			product.product_price = str(entry.get("price", ""))
		if product.hidden or product.deal_start > OS.get_unix_time():
			continue
		var active = product.is_active_deal() and Moonlight.shop.products.has(id)
		var owned = _owned(product)
		if (filter == 0 and active) or (filter == 1 and not owned):
			continue
		var cosmetics = Moonlight_Storage.nested_get("data.cosmetics", product.product_data, []).duplicate()
		cosmetics.sort()
		var signature = JSON.print(cosmetics) if not cosmetics.empty() else str(id)
		if seen.has(signature):
			continue
		seen[signature] = true
		result.append(product)
	return result

func _render(state: Array) -> void:
	if not is_instance_valid(state[0]) or not is_instance_valid(state[1]):
		return
	var archive = state[1]
	for child in archive.get_children():
		archive.remove_child(child)
		child.queue_free()
	var header = Label.new()
	header.text = "SEASON DEALS · ARCHIVE"
	header.add_font_override("font", _font(28))
	archive.add_child(header)
	var bar = HBoxContainer.new()
	archive.add_child(bar)
	for entry in [["Past seasons", 0], ["Owned cosmetics", 1]]:
		var button = Button.new()
		button.text = entry[0]
		button.add_font_override("font", _font(22))
		button.connect("pressed", self, "_filter", [state, entry[1]])
		bar.add_child(button)
	var products = _products(state[2])
	state[3] = clamp(state[3], 0, max(0, int(ceil(products.size() / 3.0)) - 1))
	var hint = Label.new()
	hint.autowrap = true
	hint.add_font_override("font", _font(20))
	hint.rect_min_size = Vector2(700, 48)
	hint.text = "Previously received offers · archived prices may be outdated.\nExpired offers cannot be reactivated by this client."
	archive.add_child(hint)
	if products.empty():
		var empty = Label.new()
		empty.text = "No past offers in the received catalog yet."
		empty.add_font_override("font", _font(22))
		archive.add_child(empty)
	for index in range(state[3] * 3, min(products.size(), state[3] * 3 + 3)):
		var product = products[index]
		var active = product.is_active_deal() and Moonlight.shop.products.has(product.product_id)
		var availability = Label.new()
		availability.add_font_override("font", _font(20))
		availability.text = ("Cosmetics owned · " if _owned(product) else "") + ("Current offer" if active else "Archived · unavailable to purchase")
		archive.add_child(availability)
		var card = load("res://project_specific/ui/shop/Shop_DealButton.tscn").instance()
		archive.add_child(card)
		card.shop_purchase_on_press = false
		card.render_product(product)
		card.has_seconds_left = false
		card.time_panel.hide()
		card.button.disabled = not active
		if active:
			card.connect("button_pressed", self, "_buy", [state[0], product.product_id])
	if products.size() > 3:
		for entry in [["Previous", -1], ["Next", 1]]:
			var button = Button.new()
			button.text = entry[0]
			button.add_font_override("font", _font(22))
			button.connect("pressed", self, "_page", [state, entry[1]])
			bar.add_child(button)
	state[0].show()

func _filter(state: Array, value: int) -> void:
	state[2] = value
	state[3] = 0
	_render(state)

func _page(state: Array, delta: int) -> void:
	state[3] += delta
	_render(state)

func _buy(panel, id: String) -> void:
	var product = Moonlight.shop.products.get(id)
	if product != null and product.is_active_deal() and is_instance_valid(panel):
		panel.on_deal_button_pressed(product)
