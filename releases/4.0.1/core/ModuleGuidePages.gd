extends Reference

func for_tool(key):
	var instructions = {
		"tab:0":["Game controls","Choose a playback or practice control. Gameplay actions retain their original local-level restrictions.","Open a local level, pause, then advance one frame to inspect movement."],
		"tab:1":["Macro Bot","1. Open a local level and start Macro Bot.\n2. Play; place checkpoints to keep good sections.\n3. Save to a slot, then use Play Macro.","To extend a saved run: Continue From End. To branch earlier: Edit Timeline → Continue From Here. Save into a different slot to keep both versions."],
		"tab:2":["Autoplay","Open a local practice level, select the route-learning controls and start an attempt. Review progress before keeping a learned route.","Try a short level first. Stop learning before changing levels; public-match execution is not enabled."],
		"replays":["Replay library","Select a saved replay, inspect its details and use the existing playback or export controls. Level Council is separate public-match analysis.","Choose one recording and open its timeline. Scrub before pressing play."],
		"council":["Level Council","1. Press Start recording explicitly.\n2. Choose a saved game, then its map.\n3. Expand the viewer; drag the timeline or press Space to play/pause.","Filter by map and compare several completed races. DNF means unfilled qualification slots, not every eliminated player. Stop after winner finishes the active match before stopping."],
		"maps":["Match maps","Join a public match. This page displays map information already received by the client for that match.","Look for the 32P, 16P, 8P and elimination entries. Ratings browsing now lives in Top rated levels."],
		"rated":["Top rated levels","Select All time, Today, Week or Month. The existing ratings query and cache populate the level list.","Compare the weekly list with All time. These are level ratings, not the current match's selected maps."],
		"accounts":["Accounts","Use Add account to save a login, then select an existing account to switch. Read confirmations before removing a saved account.","Check the displayed identity before switching. Never share session or credential files; Windows protection does not protect against malware running as you."],
		"game":["Game tools","Choose the existing tool you need. Editor and specialized utilities may open separate working windows where more space is useful.","Open Editor+ from a local level and use its ? guide for editing examples."],
		"social":["Friends & party","Use the existing friends controls to find players and the party controls to manage invitations. Availability still depends on game services.","Review the recipient before sending an invitation. This cleanup does not change party membership or send invitations automatically."],
		"loadouts":["Looks","Save an outfit as a loadout, then select it to restore that combination using the existing cosmetic controls.","Save your current look before experimenting with another combination."],
		"themes":["Editor themes","Choose a menu background here; choose level themes in the native editor theme picker.","Preview a theme in the editor before saving your level."],
		"wins":["Wins leaderboard","Choose the period, refresh or import a snapshot, then select a player for details.","Compare weekly and all-time totals. Period results depend on available snapshots, not a complete history of every match."]
	}
	var data = instructions.get(key,["Tool","Hover controls for their function.","Use the existing controls; no actions run when opening this guide."])
	return [{"title":data[0],"section":"","picture":"tool_flow","caption":"Your current tool view — captured locally when opening this guide.","steps":data[1],"example":data[2],"tip":"Hover controls for details. Ctrl + wheel zooms; Ctrl + 0 resets the view. Recording guests occupy real player slots."}]
