extends Spatial

signal started_accelerating

class TurnFlick:
	var distance = 0
	var time_msec = 0
	
	func msec_since():
		return OS.get_ticks_msec() - time_msec

onready var front_wheel = get_parent().find_node("BikeFrontWheel")
onready var front_wheel_mesh = front_wheel.get_node("Mesh")
onready var front_wheel_shape = front_wheel.get_node("CollisionShape")
onready var front_fork = find_node("FrontFork")
onready var bike_body = get_parent().find_node("BikeBody")
onready var wheel_joint = get_parent().find_node("FrontWheelJoint")

var using_joypad = false
var joypad_device = 0
var turning_deadzone = 0.025

var forward_speed = 0
var body_speed = 0
# Speed in units forward per second
var max_speed = 6
var acceleration_force = 100
var correction_force = 50
var max_turn_force = 15

var friction_high_normal = 1.5
var friction_high_drifting = 0.75
var friction_high = friction_high_normal
var friction_low = 0.1

# Time to fully dampen turning after releasing the turn key in msec
var turning_damp_time = 150 
var _turning_damp_start

# Distance that must be traveled for the body to centre itself
var centre_body_travel = 1.5
var base_joint_angle = (30.0 / 180.0) * PI
var percent_centered = 0
var _target_joint_angle = base_joint_angle
var _last_joint_upper_angle = base_joint_angle
var _last_joint_lower_angle = -base_joint_angle
var _joint_percent_transitioned = 0.0
var _lock_joint_over_seconds = null
var _lock_joint_over_distance = null
var _joint_locked_to_angle = false

var front_wheel_unlock_speed = 2.0

var in_contact = false
var accelerating = false
var turning = false

enum DriftStage {READY, STARTING, SLIDING, STOPPED}
var drift = DriftStage.READY
var drift_early_flick_allowance = 500
var drift_late_flick_allowance = 100
var drift_start_force = 24
# The slide force that will be multiplied by the body speed to create the slide power
var drift_slide_force_mult = 18
# The amount of drift slide power lost each second
var drift_slide_power_loss = 70
var _drift_slide_power
var _drift_stage_switch_time

var turn_flick = TurnFlick.new()
var flick_min_turn_per_sec = 7
var _turn_flicking = false
var _last_turn_input = 0
var _last_held_turn_input = 0
var _turn_input_started = false

func _ready():
	find_node("Camera").activate_camera()
	_get_joypad()
	
func _get_joypad():
	var joypads = Input.get_connected_joypads()
	if joypads.size() > 0:
		using_joypad = true
		joypad_device = joypads[0]

func _physics_process(delta):
	# Find the dot between the forward vector and the velocity vector to determine direction
	var direction = sign(front_wheel.global_transform.basis.z.dot(front_wheel.linear_velocity.normalized()))
	# Project the velocity vector onto the forward vector at the same magnitude to determine the forward velocity
	var forward_velocity = front_wheel.linear_velocity.project(front_wheel.global_transform.basis.z)
	forward_speed = forward_velocity.length() * direction
	body_speed = front_wheel.linear_velocity.length()
	
	if is_front_wheel_locked():
		if is_drifting() or forward_speed <= front_wheel_unlock_speed:
			unlock_front_wheel()
	
	# Movement updates
	_process_movement_input(delta)
	_update_bike_friction()
	_update_bike_body_centering(delta)
	
	# Visual updates
	_update_bike_roll(delta)
	_update_fork_basis()
	_update_front_wheel_basis()
	
func is_drifting():
	return drift == DriftStage.STARTING or drift == DriftStage.SLIDING

func _process_movement_input(delta):
	if Input.is_action_pressed("bike_move_forward") and not is_drifting():
		if Input.is_action_just_pressed("bike_move_forward"):
			accelerating = true
			lock_front_wheel_over_distance(0, centre_body_travel)
			emit_signal("started_accelerating")
		if forward_speed < max_speed and in_contact:
			# Apply force towards the forward vector at max speed
			var force_direction = ((bike_body.global_transform.basis.z * max_speed) - bike_body.linear_velocity).normalized()
			var force_magnitude = correction_force + acceleration_force
			bike_body.add_force(force_direction * force_magnitude * delta, Vector3())
	else:
		if Input.is_action_just_released("bike_move_forward"):
			accelerating = false	
		if is_front_wheel_locked():
			var force_direction = ((bike_body.global_transform.basis.z * forward_speed) - bike_body.linear_velocity).normalized()
			bike_body.add_force(force_direction * correction_force * delta, Vector3())
	
			
	if Input.is_action_just_pressed("bike_hop") and in_contact:
		bike_body.add_force(bike_body.transform.basis.y * 1000 * delta, Vector3())
		front_wheel.add_force(bike_body.transform.basis.y * 2000 * delta, Vector3())
		
	var turn_input = _get_turn_input()
	var turn_delta = abs(turn_input - _last_turn_input) / delta
	
	if not _turn_input_started:
		if turn_input != 0 and turn_delta == 0:
			_turn_input_started = true
	else:
		if turn_input == 0 and turn_delta == 0:
			_turn_input_started = false
	
	if turn_delta < flick_min_turn_per_sec:
		if _turn_flicking:
			# Don't count releasing input as a flick or the initial turn input 
			if turn_input != 0:
				turn_flick.distance = turn_input - _last_held_turn_input
				turn_flick.time_msec = OS.get_ticks_msec()
				print(turn_flick.distance)
			_turn_flicking = false
		_last_held_turn_input = turn_input
	else:
		if _turn_input_started:
			_turn_flicking = true
	_last_turn_input = turn_input
	
	if Input.is_action_pressed("bike_drift"):
		if drift == DriftStage.READY:
				_drift_stage_switch_time = OS.get_ticks_msec()
				drift = DriftStage.STARTING
		elif drift == DriftStage.STARTING:
			# Give the player an extra 100msec to flick the turn input
			if OS.get_ticks_msec() - _drift_stage_switch_time > drift_late_flick_allowance:
				var total_allowance = drift_early_flick_allowance + drift_late_flick_allowance
				if turn_flick.msec_since() > total_allowance:
					print("Too slow (%s)" % turn_flick.msec_since())
					drift = DriftStage.STOPPED
				else:
					_drift_slide_power = body_speed * drift_slide_force_mult * sign(-turn_flick.distance)
					# Set the joint angle to a percentage of the normal front wheel range of rotation based on the intensity of the flick
					bike_body.add_force(bike_body.transform.basis.x * drift_start_force * -turn_flick.distance, Vector3())
					lock_front_wheel_over_seconds(clamp(turn_flick.distance, -1, 1) * base_joint_angle, 1)
					friction_high = friction_high_drifting
					drift = DriftStage.SLIDING
		elif drift == DriftStage.SLIDING:
			bike_body.add_force(bike_body.transform.basis.x * _drift_slide_power * delta, Vector3())
			front_wheel.add_force(front_wheel.transform.basis.x * _drift_slide_power * 0.8 * delta, Vector3())
			var power_loss = drift_slide_power_loss * delta * sign(_drift_slide_power)
			_drift_slide_power = _drift_slide_power - power_loss
			print(_drift_slide_power)
			if body_speed < 0 or abs(power_loss) > abs(_drift_slide_power):
				print("Drift stopped")
				unlock_front_wheel()
				friction_high = friction_high_normal
				drift = DriftStage.STOPPED
	else:
		if drift != DriftStage.READY:
			if drift == DriftStage.SLIDING:
				friction_high = friction_high_normal
			unlock_front_wheel()
			drift = DriftStage.READY
		
		if turn_input != 0:
			if !turning:
				turning = true
				front_wheel.angular_damp = -1
			
			if !is_front_wheel_locked():
				front_wheel.add_torque(Vector3(0, 2 * turn_input * delta, 0))
				
			bike_body.add_force(bike_body.transform.basis.x * (forward_speed * max_turn_force * turn_input) * delta, Vector3())
			front_wheel.add_force(front_wheel.transform.basis.x * (forward_speed * max_turn_force * turn_input) * delta, Vector3())
		else:
			if turning:
				turning = false
				_turning_damp_start = OS.get_ticks_msec()
			# Climb to fully dampened turning on a sine wave when no turning is pressed
			# This gently stops the front wheel front rotating
			if front_wheel.angular_damp < 1:
				var percent_damped = min(float(OS.get_ticks_msec() - _turning_damp_start) / turning_damp_time, 1)
				front_wheel.angular_damp = -1.0 + sin(percent_damped * PI * 0.5) * 2.0
	
	if Input.is_action_pressed("test_button"):
		friction_high = friction_high_drifting
		bike_body.add_force(bike_body.transform.basis.x * 90 * delta, Vector3())
		front_wheel.add_force(front_wheel.transform.basis.x * 90 * 0.8 * delta, Vector3())
	elif Input.is_action_just_released("test_button"):
		friction_high = friction_high_normal
			
func _get_turn_input():
	if Input.is_action_pressed("bike_rotate_left"):
		return 1
	elif Input.is_action_pressed("bike_rotate_right"):
		return -1
	elif using_joypad:
		var axis_input = Input.get_joy_axis(joypad_device, JOY_ANALOG_LX) * -1
		if axis_input > -turning_deadzone and axis_input < turning_deadzone:
			axis_input = 0
		return axis_input
	else:
		return 0 

func _update_fork_basis():
	front_fork.global_transform.basis = Basis(
		front_wheel.global_transform.basis.x,
		bike_body.global_transform.basis.y,
		front_wheel.global_transform.basis.z)
		
func _update_front_wheel_basis():
	var mesh_scale = front_wheel_mesh.global_transform.basis.get_scale()
	var new_basis = Basis(
		bike_body.global_transform.basis.y * -0.1,
		front_wheel_mesh.global_transform.basis.y,
		front_wheel_mesh.global_transform.basis.z)		
	front_wheel_mesh.global_transform.basis = new_basis

func _print_basis_xyz(basis):
	print("(%s, %s, %s)" % [basis.x, basis.y, basis.z])

func _update_bike_friction():
	var wheel_friction = friction_low + (_percent_velocity_sideways(front_wheel) * friction_high)
	front_wheel.physics_material_override.friction = wheel_friction
	
	var body_friction = friction_low + (_percent_velocity_sideways(bike_body) * friction_high)
	bike_body.physics_material_override.friction = body_friction
	
func get_front_wheel_angle():
	var body_vector = Vector2(
		bike_body.global_transform.basis.z.x,
		bike_body.global_transform.basis.z.z)
	var wheel_vector = Vector2(
		front_wheel.global_transform.basis.z.x,
		front_wheel.global_transform.basis.z.z)
	return body_vector.angle_to(wheel_vector)
	
func set_front_wheel_locked(value):
	if value == true:
		lock_front_wheel_over_seconds(get_front_wheel_angle(), 0)
	else:
		unlock_front_wheel()
	
func is_front_wheel_locked():
	var cur_joint_angle = stepify(wheel_joint.get_param_y(Generic6DOFJoint.PARAM_ANGULAR_UPPER_LIMIT), 0.001)
	if cur_joint_angle == _target_joint_angle and _joint_locked_to_angle:
		return true
	return false
	
func lock_front_wheel_over_seconds(locked_radians, seconds):
	_joint_locked_to_angle = true
	_last_joint_upper_angle = stepify(wheel_joint.get_param_y(Generic6DOFJoint.PARAM_ANGULAR_UPPER_LIMIT), 0.001)
	_last_joint_lower_angle = stepify(wheel_joint.get_param_y(Generic6DOFJoint.PARAM_ANGULAR_LOWER_LIMIT), 0.001)
	_joint_percent_transitioned = 0.0
	_target_joint_angle = locked_radians
	_lock_joint_over_seconds = seconds
	_lock_joint_over_distance = null
	
func lock_front_wheel_over_distance(locked_radians, distance):
	_joint_locked_to_angle = true
	_last_joint_upper_angle = stepify(wheel_joint.get_param_y(Generic6DOFJoint.PARAM_ANGULAR_UPPER_LIMIT), 0.001)
	_last_joint_lower_angle = stepify(wheel_joint.get_param_y(Generic6DOFJoint.PARAM_ANGULAR_LOWER_LIMIT), 0.001)
	_joint_percent_transitioned = 0.0
	_target_joint_angle = locked_radians
	_lock_joint_over_seconds = null
	_lock_joint_over_distance = distance
	
func unlock_front_wheel():
	_joint_locked_to_angle = false
	_target_joint_angle = base_joint_angle
	_lock_joint_over_seconds = null
	_lock_joint_over_distance = null
		
func _update_bike_body_centering(delta):
	# Because the angle limits are always linked, we can just check against one of the limits
	var upper_limit_angle = stepify(wheel_joint.get_param_y(Generic6DOFJoint.PARAM_ANGULAR_UPPER_LIMIT), 0.001)
	if _joint_locked_to_angle and upper_limit_angle - _target_joint_angle != 0:
		# By default set the joint angle to the target instantly
		assert((_lock_joint_over_seconds != null and _lock_joint_over_distance != null) == false, 
			"The joint should not be locked both over seconds and over distance.")
			
		if _lock_joint_over_seconds != null and _lock_joint_over_distance == null:
			# Percent change over seconds
			_joint_percent_transitioned = min(_joint_percent_transitioned + (delta / _lock_joint_over_seconds), 1.0)
		elif _lock_joint_over_seconds == null and _lock_joint_over_distance != null:
			# Percent change over distance
			var distance_traveled_in_frame = max(forward_speed * delta, 0)
			_joint_percent_transitioned = min(_joint_percent_transitioned + (distance_traveled_in_frame / _lock_joint_over_distance), 1.0)
		
		var new_upper_angle = _last_joint_upper_angle - (_joint_percent_transitioned * (_last_joint_upper_angle - _target_joint_angle))
		wheel_joint.set_param_y(Generic6DOFJoint.PARAM_ANGULAR_UPPER_LIMIT, new_upper_angle)
		
		var new_lower_angle = _last_joint_lower_angle - (_joint_percent_transitioned * (_last_joint_lower_angle - _target_joint_angle))
		wheel_joint.set_param_y(Generic6DOFJoint.PARAM_ANGULAR_LOWER_LIMIT, new_lower_angle)
	elif not _joint_locked_to_angle and upper_limit_angle != _target_joint_angle:
		# When the joint is not locked, the target angle specifies the range of the joint
		wheel_joint.set_param_y(Generic6DOFJoint.PARAM_ANGULAR_UPPER_LIMIT, _target_joint_angle)
		wheel_joint.set_param_y(Generic6DOFJoint.PARAM_ANGULAR_LOWER_LIMIT, _target_joint_angle * -1)
		
func _update_bike_roll(delta):
	var forward_velocity_normal = bike_body.transform.basis.z.cross(bike_body.linear_velocity).y
	var roll = min(abs(forward_velocity_normal), 1.5) * sign(forward_velocity_normal) * (forward_speed / max_speed) * -1
	wheel_joint.set_param_z(Generic6DOFJoint.PARAM_ANGULAR_UPPER_LIMIT, roll)
	wheel_joint.set_param_z(Generic6DOFJoint.PARAM_ANGULAR_LOWER_LIMIT, roll)
	
func _percent_velocity_sideways(body):
	# Calculate the dot product of the forward vector and the velocity vector
	var dot_prod = body.transform.basis.z.normalized().dot(body.linear_velocity.normalized()) 
	return sin((dot_prod - 1) * -0.5 * PI)

func _on_BikeFrontWheel_body_entered(body):
	in_contact = true

func _on_BikeFrontWheel_body_exited(body):
	in_contact = false
