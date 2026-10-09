extends Node

# Large Journey artwork (map thumbnails, theme layers) loaded off the main
# thread and shrunk to the size Journey shows it. Textures stay cached for the
# game session, so reopening Journey or a tab doesn't load them again.
# request() calls target.method(texture, binds...) at once when cached,
# otherwise once ready; with a watch control, loading waits until that
# control is near the screen. A freed target or watch is skipped.

const SHARED = "journey_textures"
const MARGIN = 1.0 # screens of look-ahead below and above the view
const PER_FRAME = 4

var _thread = null
var _mutex = Mutex.new()
var _semaphore = Semaphore.new()
var _queue = []
var _done = []
var _working = false
var _quit = false
var _waiting = {}
var _watched = []

static func cache() -> Dictionary:
	var tree = Engine.get_main_loop()
	if not tree.has_meta(SHARED):
		tree.set_meta(SHARED, {})
	return tree.get_meta(SHARED)

# cover: the image is shrunk until it would just cover a box of this size.
func request(path: String, cover: Vector2, target: Object, method: String, binds = [], watch = null) -> void:
	var key = "%s@%dx%d" % [path, cover.x, cover.y]
	var shared = cache()
	if shared.has(key):
		if shared[key] != null:
			target.callv(method, [shared[key]] + binds)
		return
	var waiter = [weakref(target), method, binds]
	if _waiting.has(key):
		_waiting[key].append(waiter)
	else:
		_waiting[key] = [waiter]
	if watch == null:
		_send(key, path, cover)
	else:
		_watched.append([key, path, cover, weakref(watch)])
	set_process(true)

func _send(key, path, cover):
	for i in range(_watched.size() - 1, -1, -1):
		if _watched[i][0] == key:
			_watched.remove(i)
	_mutex.lock()
	for job in _queue:
		if job[0] == key:
			_mutex.unlock()
			return
	_queue.append([key, path, cover])
	_mutex.unlock()
	if _thread == null or not _thread.is_active():
		_quit = false
		_thread = Thread.new()
		_thread.start(self, "_work")
	_semaphore.post()

func _process(_delta):
	if not _watched.empty():
		var view = get_viewport().get_visible_rect()
		view = view.grow_individual(0, view.size.y * MARGIN, 0, view.size.y * MARGIN)
		for entry in _watched.duplicate():
			var watch = entry[3].get_ref()
			if watch == null or not watch.is_inside_tree():
				_watched.erase(entry)
			elif watch.is_visible_in_tree() and view.intersects(watch.get_global_rect()):
				_send(entry[0], entry[1], entry[2])
	_mutex.lock()
	var ready = _done.slice(0, min(PER_FRAME, _done.size()) - 1) if not _done.empty() else []
	for item in ready:
		_done.erase(item)
	# The worker removes a job from the queue before decoding it. Keep polling
	# while that final job is in flight, so its result isn't stranded in _done.
	var busy = _working or not _queue.empty() or not _done.empty()
	_mutex.unlock()
	for item in ready:
		var texture = null
		if item[1] != null:
			texture = ImageTexture.new()
			texture.create_from_image(item[1], Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
		cache()[item[0]] = texture
		for waiter in _waiting.get(item[0], []):
			var target = waiter[0].get_ref()
			if target != null and texture != null:
				target.callv(waiter[1], [texture] + waiter[2])
		_waiting.erase(item[0])
	if not busy and _watched.empty():
		set_process(false)

func _work(_arg):
	while true:
		_semaphore.wait()
		_mutex.lock()
		if _quit:
			_mutex.unlock()
			return
		var job = _queue.pop_front() if not _queue.empty() else null
		_working = job != null
		_mutex.unlock()
		if job == null:
			continue
		var image = _shrink(job[1], job[2])
		_mutex.lock()
		_done.append([job[0], image])
		_working = false
		_mutex.unlock()

static func _shrink(path, cover):
	var image = Image.new()
	if not File.new().file_exists(path) or image.load(path) != OK or image.is_empty():
		return null
	var size = image.get_size()
	var factor = min(1.0, max(cover.x / size.x, cover.y / size.y))
	if factor < 1.0:
		image.resize(max(1, int(size.x * factor)), max(1, int(size.y * factor)), Image.INTERPOLATE_BILINEAR)
	if image.detect_alpha() == Image.ALPHA_NONE:
		image.convert(Image.FORMAT_RGB8)
	image.generate_mipmaps()
	return image

func _exit_tree():
	if _thread != null and _thread.is_active():
		_mutex.lock()
		_quit = true
		_mutex.unlock()
		_semaphore.post()
		_thread.wait_to_finish()
	_thread = null
	_mutex.lock()
	_queue.clear()
	_done.clear()
	_working = false
	_mutex.unlock()
	_waiting.clear()
	_watched.clear()
