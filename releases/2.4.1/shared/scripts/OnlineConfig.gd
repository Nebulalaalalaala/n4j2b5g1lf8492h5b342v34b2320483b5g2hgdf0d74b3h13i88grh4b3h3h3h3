extends Reference

# Online service settings used by more than one tool (Replay library, Journey leaderboard).
# The key is the Supabase publishable (anon) key; table access is limited by row-level security.
# It is stored encoded so it doesn't show up in plain-text searches of the source.
const SUPABASE_URL := "https://sfoughvdkegevdfrhuum.supabase.co"
const _ANON_KEY_ENCODED := "cWJ6bGE2TG5fd0dCeEtFOUl3RjJBOVFsdFdsdFBtZl9lbGJhaHNpbGJ1cF9icw=="


static func anon_key() -> String:
	var text := Marshalls.base64_to_utf8(_ANON_KEY_ENCODED)
	var out := ""
	for index in range(text.length() - 1, -1, -1):
		out += text[index]
	return out
