extends Camera

var camera_direction_delay = 2000
var _activated = false
var _sample_start_time = OS.get_ticks_msec()
var _camera_dir_samples = []
onready var _base_distance = Vector3(transform.origin.x, 0, transform.origin.z).length()
onready var _base_height = transform.origin.y
onready var _bike_wheel = get_parent().find_node("BikeFrontWheel")
onready var _bike_body = get_parent().find_node("BikeBody")

# Activate the camera in this function call instead of on ready so we can choose to do it after BikeController is ready
func activate_camera():
	current = true
	_activated = true

func _process(delta):
	if _activated == false:
		return
	_update_look_at()

func _update_look_at():
	var body_gtransform = _bike_body.global_transform
	var wheel_gtransform = _bike_wheel.global_transform
	
	if OS.get_ticks_msec() - _sample_start_time > camera_direction_delay:
		_camera_dir_samples.pop_back()
	_camera_dir_samples.insert(0, wheel_gtransform.basis.z)
	
	var look_at_target = wheel_gtransform.origin + (_average_vec_array(_camera_dir_samples) * 1)
		
	var look_at_position = Vector3(
		wheel_gtransform.origin.x - _base_distance * wheel_gtransform.basis.z.x,
		body_gtransform.origin.y + _base_height,
		wheel_gtransform.origin.z - _base_distance * wheel_gtransform.basis.z.z)
	look_at_from_position(look_at_position, look_at_target, Vector3(0, 1, 0))
	
func _average_vec_array(a):
	var array_sum = Vector3()
	for item in a:
		array_sum = item + array_sum
	return array_sum / a.size()
	
#func _on_Bike_started_accelerating():
#	_acceleration_dir_samples = []
#	_acceleration_start_time = OS.get_ticks_msec()
