extends Reference

# Moves Goobplayability's saved data from the old spots in the game's user folder
# into user://goobplayability/ (list in ModPaths.MOVED_DATA). Runs at start-up; each
# item moves once. If the new spot already exists the old one is left alone.
# Accounts (user://goobplayability/accounts) and game files are never touched.

const ModPaths = preload("user://mod/core/ModPaths.gd")

static func run() -> Array:
	var moved = []
	var directory = Directory.new()
	directory.make_dir_recursive(ModPaths.DATA_DIR)
	for pair in ModPaths.MOVED_DATA:
		var old_path: String = pair[0]
		var new_path: String = pair[1]
		var is_file = directory.file_exists(old_path)
		if not is_file and not directory.dir_exists(old_path):
			continue
		if directory.file_exists(new_path) or directory.dir_exists(new_path):
			continue
		if directory.rename(old_path, new_path) == OK:
			moved.append(old_path.get_file())
	return moved
