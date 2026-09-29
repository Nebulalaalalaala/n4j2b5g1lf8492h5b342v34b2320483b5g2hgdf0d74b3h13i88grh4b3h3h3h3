extends Reference

func for_tool(key):
	var instructions = {
		"tab:0":["Game controls","Choose a playback or practice control. Gameplay actions retain their original local-level restrictions.","Open a local level, pause, then advance one frame to inspect movement."],
		"tab:1":["Macro Bot","Choose a slot, record a run, then stop and save it. Play Macro replays the saved inputs; the timeline editor lets you inspect or edit them.","Record a short jump on a local level. Stop, reset the level, then play the same slot."],
		"tab:2":["Autoplay","Open a local practice level, select the route-learning controls and start an attempt. Review progress before keeping a learned route.","Try a short level first. Stop learning before changing levels; public-match execution is not enabled."],
		"replays":["Replay library","Select a saved replay, inspect its details and use the existing playback or export controls. Level Council is separate public-match analysis.","Choose one recording and open its timeline. Scrub before pressing play."],
		"council":["Level Council","Enable Record public matches. Search a map or creator, choose a dated recording and scrub the timeline. Hover players for names and available stats.","Filter to 8P, sort by observed DNF and compare multiple recordings. Full-qualification timing excludes unfilled rounds. The guest occupies a real slot."],
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
	return [{"title":data[0],"section":"","picture":"tool_flow","caption":"Choose → inspect → act","steps":data[1],"example":data[2],"tip":"Ctrl + wheel zooms around the cursor. Ctrl + 0 resets navigation zoom. Disabled modules can be restored in Settings."}]
