extends Node


# Declare member variables here. Examples:
# var a = 2
# var b = "text"
var _time = 0
var _time_now = 0
var _elapsed = 0
var _timer_started = false

# Called when the node enters the scene tree for the first time.
func _ready():
	_time_now = OS.get_unix_time()
	_time = OS.get_unix_time()
	start()

func start():
	_timer_started = true
	
func stop():
	_timer_started = false
	
func read():
	return _elapsed
	
func _count():
	_time_now = OS.get_unix_time()
	if (_timer_started):
		_elapsed += _time_now - _time
		
	_time = _time_now
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	_count()
