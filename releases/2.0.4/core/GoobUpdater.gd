extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")

signal status_changed(status, detail)
signal latest_version_changed(version)
signal update_available(manifest)
signal update_installed(version)
signal rollback_changed(available)

const MANIFEST_URL := "https://raw.githubusercontent.com/Nebulalaalalaala/n4j2b5g1lf8492h5b342v34b2320483b5g2hgdf0d74b3h13i88grh4b3h3h3h3/main/manifest.json"
const RELEASE_ROOT := "https://raw.githubusercontent.com/Nebulalaalalaala/n4j2b5g1lf8492h5b342v34b2320483b5g2hgdf0d74b3h13i88grh4b3h3h3h3/main/releases/"
const GAME_COMPATIBILITY := "goober-dash-2026-08-04-godot-3.5.1"
const MANIFEST_SCHEMA := 2
const UPDATE_ROOT := ModPaths.UPDATES_DIR
const STAGING_ROOT := UPDATE_ROOT + "/staging"
const BACKUP_ROOT := UPDATE_ROOT + "/backups"
const ROLLBACK_META_PATH := UPDATE_ROOT + "/last_rollback.dat"
const INSTALLED_RECORD := ModPaths.ROOT + "installed.json"
const MAX_MANIFEST_BYTES := 1048576
const MAX_FILE_BYTES := 16777216
const MAX_FILES := 2000
# Files are mod-relative paths ("core/GoobUpdater.gd"); anything else is refused.
const ALLOWED_EXTENSIONS := ["gd", "js", "json", "png", "jpg", "ttf", "otf", "wav", "ogg", "ps1", "bat", "pck"]
const NEVER_UPDATED := ["tools/level-council/", "installed.json"]
const PATH_CHARACTERS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./ "

var current_version := "0.0.0"
var latest_version := "--"
var automatic_checks := false
var busy := false
var available_manifest := {}
var last_check_manual := false

var _request: HTTPRequest
var _request_mode := ""
var _download_queue := []
var _download_index := 0
var _staging_dir := ""
var _active_file := {}


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	_request = HTTPRequest.new()
	_request.name = "GoobplayabilityUpdateRequest"
	_request.pause_mode = Node.PAUSE_MODE_PROCESS
	_request.body_size_limit = MAX_FILE_BYTES
	_request.connect("request_completed", self, "_on_request_completed")
	add_child(_request)
	emit_signal("rollback_changed", has_rollback())


func configure(installed_version: String, check_automatically: bool) -> void:
	current_version = installed_version
	automatic_checks = check_automatically
	if automatic_checks:
		call_deferred("check_now", false)


func set_automatic_checks(value: bool) -> void:
	automatic_checks = value


func check_now(manual := true) -> void:
	if busy:
		_emit_status("BUSY", "An update operation is already running.")
		return
	busy = true
	last_check_manual = manual
	_request_mode = "manifest"
	_request.download_file = ""
	_request.body_size_limit = MAX_MANIFEST_BYTES
	_emit_status("CHECKING", "Checking for updates…")
	var error := _request.request(MANIFEST_URL, PoolStringArray(["Accept: application/json", "Cache-Control: no-cache"]), true, HTTPClient.METHOD_GET)
	if error != OK:
		_fail("Could not start the update check (error %d)." % error)


func install_available_update() -> void:
	if busy:
		return
	if available_manifest.empty():
		_emit_status("NO UPDATE", "Check for updates first.")
		return
	busy = true
	# Only files of the tools this install has (installed.json); a full install takes everything.
	var tools := _installed_tools()
	_download_queue = []
	for entry in available_manifest["files"]:
		if (tools.empty() or str(entry.get("module", "core")) in tools) and not _already_installed(entry):
			_download_queue.append(entry.duplicate(true))
	_download_index = 0
	_staging_dir = STAGING_ROOT + "/" + str(available_manifest["version"])
	_ensure_dir(_staging_dir)
	_emit_status("DOWNLOADING", "Downloading update files…")
	_download_next_file()


# Images, sounds and fonts that are already exactly this version (same size and
# SHA-256) are not downloaded again, so unchanged art costs nothing on later
# updates. Code is always downloaded (small, and TASTool parts get relinked).
func _already_installed(entry) -> bool:
	if not str(entry.get("path", "")).get_extension().to_lower() in ["png", "jpg", "wav", "ogg", "ttf", "otf"]:
		return false
	var path := ModPaths.ROOT + str(entry.get("path", ""))
	var file := File.new()
	if not file.file_exists(path) or file.open(path, File.READ) != OK:
		return false
	var size := file.get_len()
	file.close()
	return size == int(entry.get("size", -1)) and _sha256_file(path) == str(entry.get("sha256", "")).to_lower()


func has_rollback() -> bool:
	var file := File.new()
	return file.file_exists(ROLLBACK_META_PATH)


func rollback_last_update() -> bool:
	if busy or not has_rollback():
		return false
	var meta_file := File.new()
	if meta_file.open(ROLLBACK_META_PATH, File.READ) != OK:
		_emit_status("ROLLBACK FAILED", "The rollback record could not be opened.")
		return false
	var meta = meta_file.get_var()
	meta_file.close()
	if typeof(meta) != TYPE_DICTIONARY or typeof(meta.get("files", [])) != TYPE_ARRAY:
		_emit_status("ROLLBACK FAILED", "The rollback record is invalid.")
		return false
	busy = true
	var directory := Directory.new()
	for entry in meta["files"]:
		if typeof(entry) != TYPE_DICTIONARY:
			busy = false
			_emit_status("ROLLBACK FAILED", "The rollback record contains an invalid file.")
			return false
		var relative := str(entry.get("path", ""))
		if not _valid_path(relative):
			busy = false
			_emit_status("ROLLBACK FAILED", "Rollback refused an invalid path.")
			return false
		var destination := ModPaths.ROOT + relative
		if bool(entry.get("had_original", false)):
			var backup_path := str(entry.get("backup", ""))
			if not backup_path.begins_with(BACKUP_ROOT + "/") or directory.copy(backup_path, destination) != OK:
				busy = false
				_emit_status("ROLLBACK FAILED", "Could not restore %s." % relative)
				return false
		else:
			if directory.file_exists(destination):
				directory.remove(destination)
	directory.remove(ROLLBACK_META_PATH)
	busy = false
	emit_signal("rollback_changed", false)
	_emit_status("ROLLED BACK", "The previous version was restored. Restart Goober Dash to apply it.")
	return true


func _on_request_completed(result: int, response_code: int, _headers: PoolStringArray, body: PoolByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_fail("HTTPS request failed (result %d, HTTP %d)." % [result, response_code])
		return
	if _request_mode == "manifest":
		_handle_manifest(body)
	elif _request_mode == "file":
		_handle_downloaded_file()


func _handle_manifest(body: PoolByteArray) -> void:
	if body.size() <= 0 or body.size() > MAX_MANIFEST_BYTES:
		_fail("The release manifest has an invalid size.")
		return
	var parsed := JSON.parse(body.get_string_from_utf8())
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		_fail("The release manifest is not valid JSON.")
		return
	var validation_error := _validate_manifest(parsed.result)
	if not validation_error.empty():
		_fail("Manifest rejected: " + validation_error)
		return
	latest_version = str(parsed.result["version"])
	emit_signal("latest_version_changed", latest_version)
	available_manifest = parsed.result.duplicate(true)
	busy = false
	if _compare_versions(latest_version, current_version) > 0:
		_emit_status("UPDATE AVAILABLE", "Goobplayability %s is available." % latest_version)
		emit_signal("update_available", available_manifest.duplicate(true))
	else:
		available_manifest.clear()
		_emit_status("UP TO DATE", "Goobplayability %s is the latest release." % current_version)


func _validate_manifest(manifest: Dictionary) -> String:
	if int(manifest.get("schema", 0)) != MANIFEST_SCHEMA:
		return "unsupported schema"
	var version := str(manifest.get("version", ""))
	if not _valid_version(version):
		return "invalid version"
	if str(manifest.get("game_compatibility", "")) != GAME_COMPATIBILITY:
		return "release is for a different Goober Dash build"
	var files = manifest.get("files", null)
	if typeof(files) != TYPE_ARRAY or files.empty() or files.size() > MAX_FILES:
		return "invalid file list"
	var seen := {}
	for entry in files:
		if typeof(entry) != TYPE_DICTIONARY:
			return "invalid file entry"
		var path := str(entry.get("path", ""))
		var url := str(entry.get("url", ""))
		var sha256 := str(entry.get("sha256", "")).to_lower()
		var size := int(entry.get("size", 0))
		if not _valid_path(path) or seen.has(path):
			return "invalid or duplicate path"
		seen[path] = true
		if typeof(entry.get("module", "")) != TYPE_STRING or str(entry.get("module", "")).empty():
			return "missing tool for %s" % path
		if url != RELEASE_ROOT + version + "/" + path.replace(" ", "%20"):
			return "download URL is outside the pinned release location"
		if not _valid_sha256(sha256):
			return "invalid SHA-256 for %s" % path
		if size <= 0 or size > MAX_FILE_BYTES:
			return "invalid size for %s" % path
	if not seen.has("TASTool.gd") or not seen.has("core/GoobUpdater.gd"):
		return "release is missing core files"
	return ""


func _valid_path(path: String) -> bool:
	if path.empty() or path.length() > 200 or path.begins_with("/") or path.begins_with(".") or path.find("..") >= 0 or path.find("//") >= 0:
		return false
	for blocked in NEVER_UPDATED:
		if path.begins_with(blocked):
			return false
	if not path.get_extension().to_lower() in ALLOWED_EXTENSIONS:
		return false
	for index in range(path.length()):
		if PATH_CHARACTERS.find(path[index]) < 0:
			return false
	return true


func _installed_tools() -> Array:
	var file := File.new()
	if file.open(INSTALLED_RECORD, File.READ) != OK:
		return []
	var parsed := JSON.parse(file.get_as_text())
	file.close()
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY or typeof(parsed.result.get("tools", null)) != TYPE_ARRAY:
		return []
	var tools: Array = parsed.result["tools"].duplicate()
	if not "core" in tools:
		tools.append("core")
	return tools


func _download_next_file() -> void:
	if _download_index >= _download_queue.size():
		_install_staged_files()
		return
	_active_file = _download_queue[_download_index]
	var relative := str(_active_file["path"])
	var temp_path := _staging_dir + "/" + relative + ".download"
	_ensure_dir(temp_path.get_base_dir())
	var directory := Directory.new()
	if directory.file_exists(temp_path):
		directory.remove(temp_path)
	_request_mode = "file"
	_request.download_file = temp_path
	_request.body_size_limit = min(MAX_FILE_BYTES, int(_active_file["size"]) + 1)
	var error := _request.request(str(_active_file["url"]), PoolStringArray(["Accept: application/octet-stream", "Cache-Control: no-cache"]), true, HTTPClient.METHOD_GET)
	if error != OK:
		_fail("Could not start downloading %s (error %d)." % [relative, error])


func _handle_downloaded_file() -> void:
	var relative := str(_active_file["path"])
	var temp_path := _staging_dir + "/" + relative + ".download"
	var file := File.new()
	if not file.file_exists(temp_path) or file.open(temp_path, File.READ) != OK:
		_fail("The download for %s was not written." % relative)
		return
	var downloaded_size := file.get_len()
	file.close()
	if downloaded_size != int(_active_file["size"]):
		_fail("Size verification failed for %s." % relative)
		return
	var actual_hash := _sha256_file(temp_path)
	if actual_hash != str(_active_file["sha256"]).to_lower():
		_fail("SHA-256 verification failed for %s." % relative)
		return
	_download_index += 1
	_emit_status("DOWNLOADING", "Verified %d/%d files…" % [_download_index, _download_queue.size()])
	_download_next_file()


func _install_staged_files() -> void:
	if not _installed_tools().empty():
		_relink_staged_tastool()
	var backup_dir := BACKUP_ROOT + "/" + current_version + "-" + str(OS.get_unix_time())
	_ensure_dir(backup_dir)
	var directory := Directory.new()
	var rollback_files := []
	for entry in _download_queue:
		var relative := str(entry["path"])
		var source := ModPaths.ROOT + relative
		var backup := backup_dir + "/" + relative
		var had_original := directory.file_exists(source)
		_ensure_dir(backup.get_base_dir())
		if had_original and directory.copy(source, backup) != OK:
			_fail("Could not back up %s; nothing was installed." % relative)
			return
		rollback_files.append({"path": relative, "backup": backup, "had_original": had_original})
	var installed := []
	for entry in _download_queue:
		var relative := str(entry["path"])
		var staged := _staging_dir + "/" + relative + ".download"
		var destination := ModPaths.ROOT + relative
		_ensure_dir(destination.get_base_dir())
		if directory.copy(staged, destination) != OK:
			_restore_install_failure(rollback_files, installed)
			_fail("Installing %s failed; already-written files were restored." % relative)
			return
		installed.append(relative)
	var meta := {"from_version": current_version, "to_version": str(available_manifest["version"]), "backup_dir": backup_dir, "files": rollback_files}
	var meta_file := File.new()
	if meta_file.open(ROLLBACK_META_PATH, File.WRITE) != OK:
		_restore_install_failure(rollback_files, installed)
		_fail("Could not write rollback metadata; the update was restored.")
		return
	meta_file.store_var(meta)
	meta_file.close()
	var installed_version := str(available_manifest["version"])
	_record_version(installed_version)
	busy = false
	available_manifest.clear()
	emit_signal("rollback_changed", true)
	emit_signal("update_installed", installed_version)
	_emit_status("INSTALLED", "Goobplayability %s was installed. Restart the game to use it." % installed_version)


# TASTool is split over numbered files (NN_name.gd) that each extend the previous one.
# With some tools left out, the staged parts are re-linked in number order, like the installer does.
func _relink_staged_tastool() -> void:
	var parts := []
	for entry in _download_queue:
		var relative := str(entry["path"])
		if relative.get_base_dir().get_file() == "TASTool" and relative.get_extension() == "gd":
			parts.append(relative)
	parts.sort_custom(self, "_part_before")
	var links := {}
	for index in range(1, parts.size()):
		links[parts[index]] = parts[index - 1]
	if not parts.empty():
		links["TASTool.gd"] = parts[parts.size() - 1]
	for relative in links:
		var staged: String = _staging_dir + "/" + relative + ".download"
		var file := File.new()
		if file.open(staged, File.READ) != OK:
			continue
		var text := file.get_as_text()
		file.close()
		var first_end := text.find("\n")
		if first_end < 0 or not text.begins_with("extends "):
			continue
		if file.open(staged, File.WRITE) == OK:
			file.store_string("extends \"user://mod/%s\"" % links[relative] + text.substr(first_end))
			file.close()


func _part_before(a: String, b: String) -> bool:
	return int(a.get_file().split("_")[0]) < int(b.get_file().split("_")[0])


func _record_version(version: String) -> void:
	var file := File.new()
	if file.open(INSTALLED_RECORD, File.READ) != OK:
		return
	var parsed := JSON.parse(file.get_as_text())
	file.close()
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		return
	parsed.result["version"] = version
	if file.open(INSTALLED_RECORD, File.WRITE) == OK:
		file.store_string(to_json(parsed.result))
		file.close()


func _restore_install_failure(rollback_files: Array, installed: Array) -> void:
	var directory := Directory.new()
	for entry in rollback_files:
		var relative := str(entry["path"])
		if not relative in installed:
			continue
		var destination := ModPaths.ROOT + relative
		if bool(entry["had_original"]):
			directory.copy(str(entry["backup"]), destination)
		elif directory.file_exists(destination):
			directory.remove(destination)


func _sha256_file(path: String) -> String:
	var file := File.new()
	if file.open(path, File.READ) != OK:
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	while file.get_position() < file.get_len():
		context.update(file.get_buffer(min(65536, file.get_len() - file.get_position())))
	file.close()
	return context.finish().hex_encode()


func _valid_version(version: String) -> bool:
	var parts := version.split(".")
	if parts.size() != 3:
		return false
	for part in parts:
		var part_string := str(part)
		if part_string.empty():
			return false
		for index in range(part_string.length()):
			var code: int = part_string.ord_at(index)
			if code < 48 or code > 57:
				return false
	return true


func _valid_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in range(value.length()):
		var code: int = value.ord_at(index)
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102):
			return false
	return true


func _compare_versions(left: String, right: String) -> int:
	var a := left.split(".")
	var b := right.split(".")
	for index in range(3):
		var av := int(a[index]) if index < a.size() else 0
		var bv := int(b[index]) if index < b.size() else 0
		if av != bv:
			return 1 if av > bv else -1
	return 0


func _ensure_dir(path: String) -> void:
	var directory := Directory.new()
	if not directory.dir_exists(path):
		directory.make_dir_recursive(path)


func _fail(detail: String) -> void:
	busy = false
	_request.download_file = ""
	_emit_status("UPDATE FAILED", detail)


func _emit_status(status: String, detail: String) -> void:
	emit_signal("status_changed", status, detail)
