extends Reference

# News: posts from the Supabase news_posts table (written from the Supabase
# dashboard), then the built-in changelog for this client.

const Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")
const Kit = preload("user://mod/core/workspace4/Kit.gd")
const Notices = preload("user://mod/core/workspace4/Notices.gd")
const Cloud = preload("user://mod/core/workspace4/Cloud.gd")
const PAGES = ["settings", "overlay", "effects", "clips", "workshop", "news", "tab:0", "tab:1", "sandbox", "game", "home", "maps", "replays", "themes", "wins", "accounts", "goober-hub"]

const RELEASES = [
	{
		"version": "4.0",
		"title": "Goobplayability 4.0",
		"summary": "Explore the new workspace, recording tools and creative studios.",
		"items": [
			[
				"A new workspace",
				"Galaxy dark/light themes, Arctic Fox branding, reorganized pages, shared shortcuts and reduced-motion options.",
				"settings"
			],
			[
				"Macro Bot modes",
				"Choose Checkpoints or Sections. Timeline remains available from the working run.",
				"tab:1"
			],
			[
				"Sections and alternate takes",
				"Record attempts, keep the fastest take, choose later stops and continue from the real end of the kept run.",
				"tab:1"
			],
			[
				"Editable route boxes",
				"Place and reorder stop boxes in freecam, or preview suggestions from a selected native leaderboard replay.",
				"tab:1"
			],
			[
				"Recovery and editor playback",
				"Working-run autosave and restart recovery; held macros can also play in the matching native Level Editor.",
				"tab:1"
			],
			[
				"Overlay Studio",
				"Arrange the same widgets used in game, with snapping, layers, undo/redo and named layout import/export.",
				"overlay"
			],
			[
				"Keyboard and level cards",
				"Show actual inputs with rising-key animation, keep FPS above menus and use real level-information cards.",
				"overlay"
			],
			[
				"Effects Editor",
				"Combine trails and emitters; edit gradients and lifetime curves, save presets and link effects to Avatar Studio Looks.",
				"effects"
			],
			[
				"Avatar Studio",
				"Share outfit codes, rotate saved Looks, preview themes and manage imported PNGs with thumbnails and recoverable storage.",
				"sandbox"
			],
			[
				"Clip Studio",
				"Record gameplay to MP4 with the optional Windows components and FFmpeg installed. Set the duration and game audio in Clip Studio.",
				"clips"
			],
			[
				"Automatic highlights",
				"Clip confirmed dash-caused kills and streaks, or add selected players using match and cached-name suggestions.",
				"clips"
			],
			[
				"Smaller, steadier captures",
				"Choose file-size presets and use the paced recorder with recovery from supported capture/device failures.",
				"clips"
			],
			[
				"Zoom and spectator tools",
				"Configure smooth wheel/shortcut zoom and a native-style living-player picker while spectating.",
				"game"
			],
			[
				"Native dash recharge",
				"Other-player recharge indicators reuse the actual game bar; nicknames stay private to your own client.",
				"game"
			],
			[
				"Maps, replay library and Wins",
				"Redesigned views preserve native map routes, replay actions and source-aware community statistics.",
				"maps"
			],
			[
				"Level themes",
				"Browse match looks and editor themes in one destination, with previews and remembered match selections.",
				"themes"
			],
			[
				"Workshop and notifications",
				"Exchange supported effect/layout files, find built-in update cards and keep one notification history.",
				"workshop"
			],
			[
				"Performance and control",
				"Hidden previews sleep, repeated native redraws are reduced, and session Unload restores normal presentation.",
				"settings"
			]
		]
	}
]


var menu
var cloud
var feed: VBoxContainer

func build(owner_menu, content: VBoxContainer) -> void:
	menu = owner_menu
	Notices.add("release-4.0.0", "Goobplayability 4.0", "See the new workspace, Sections and creative studios.", "news")
	var setup = Kit.row(content)
	Kit.action(menu, setup, "Windows component setup", "folder", self, "_open_windows_setup")
	feed = Kit.column(content, 12)
	cloud = Cloud.new()
	content.add_child(cloud)
	cloud.connect("finished", self, "_feed_loaded")
	cloud.get_rows("news", "news_posts?select=id,title,body,tag,link,published_at&published=eq.true&order=published_at.desc&limit=20")
	for release in RELEASES:
		var card = menu.card(content, "What's new in " + str(release.version), Galaxy.color("accent"))
		Kit.hint(menu, card, str(release.summary))
		for item in release["items"]:
			var line = Kit.row(card, 12)
			var words = Kit.column(line, 1)
			words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			words.add_child(menu.label(item[0], 16))
			Kit.hint(menu, words, item[1])
			Kit.action(menu, line, "Open", "chev-right", menu, "select", [item[2]])


func _feed_loaded(_tag: String, ok: bool, data) -> void:
	if not ok or typeof(data) != TYPE_ARRAY:
		return
	for row in data:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var tag = str(row.get("tag", "")).left(20)
		var card = menu.card(feed, str(row.get("title", "")).left(80), Galaxy.color("playback"))
		var when = str(row.get("published_at", "")).left(10)
		Kit.hint(menu, card, (tag.capitalize() + " · " if not tag.empty() else "") + when)
		var body = menu.label(str(row.get("body", "")).left(1200), 15, Galaxy.color("ink"))
		body.autowrap = true
		card.add_child(body)
		var link = str(row.get("link", ""))
		if link in PAGES:
			var open_row = Kit.row(card, 8)
			Kit.action(menu, open_row, "Open", "chev-right", menu, "select", [link])
		Notices.add("news-" + str(row.get("id", "")), str(row.get("title", "")).left(80), str(row.get("body", "")).left(140), "news")


func _open_windows_setup() -> void:
	OS.shell_open("https://github.com/Nebulalaalalaala/n4j2b5g1lf8492h5b342v34b2320483b5g2hgdf0d74b3h13i88grh4b3h3h3h3/tree/main/components/4.0.0")
