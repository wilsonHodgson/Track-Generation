extends Spatial

signal started_accelerating

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

enum DriftState {READY, SLIDING_LEFT, SLIDING_RIGHT, STOPPED}
var drift = DriftState.READY
var drift_speed_mult = 1.5
var drift_kick_force = 16
# The slide force that will be multiplied by the body speed to create the slide power
var drift_slide_force = 40
# The amount of drift slide power lost each second after the hold time
var drift_slide_power_loss = 80
var drift_slide_max_hold = 1.75
var _drift_slide_start
var _drift_slide_power
var _max_drift_input

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
		if forward_speed <= front_wheel_unlock_speed:
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
	return drift == DriftState.SLIDING_LEFT or drift == DriftState.SLIDING_RIGHT

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
		
	var drift_input = _get_drift_input()
	
	if drift == DriftState.READY:
		if drift_input != 0:
			if drift_input > 0:
				drift = DriftState.SLIDING_LEFT
			elif drift_input < 0:
				drift = DriftState.SLIDING_RIGHT
			_max_drift_input = 0
			_drift_slide_power = 0
			_drift_slide_start = OS.get_ticks_msec()
			unlock_front_wheel()
	elif drift != DriftState.STOPPED:
		if drift_input == 0:
			drift = DriftState.STOPPED
		else:
			var new_drift_input = 0
			if abs(drift_input) > _max_drift_input:
				new_drift_input = drift_input - _max_drift_input * sign(drift_input)
				_max_drift_input = abs(drift_input)
				
			var kick_force = new_drift_input * drift_kick_force * (drift_speed_mult * (forward_speed / max_speed))
			bike_body.add_force(bike_body.transform.basis.x * kick_force, Vector3())
			
			var added_slide_force = new_drift_input * drift_slide_force * (drift_speed_mult * (body_speed / max_speed))
			_drift_slide_power += added_slide_force
			
			if OS.get_ticks_msec() > _drift_slide_start + (drift_slide_max_hold * 1000):
				var slide_power_loss = drift_slide_power_loss * delta * sign(drift_input)
				if abs(_drift_slide_power) < abs(slide_power_loss):
					_drift_slide_power = 0
					drift = DriftState.STOPPED
				else:
					_drift_slide_power -= slide_power_loss
			
			bike_body.add_force(bike_body.transform.basis.x * _drift_slide_power * delta, Vector3())
			front_wheel.add_force(front_wheel.transform.basis.x * _drift_slide_power * 0.8 * delta, Vector3())
	elif drift == DriftState.STOPPED and drift_input == 0:
		drift = DriftState.READY
			
#	front_wheel.add_force(front_wheel.transform.basis.x * _drift_slide_power * 0.8 * delta, Vector3())
#	var power_loss = drift_slide_power_loss * delta * sign(_drift_slide_power)
#	_drift_slide_power = _drift_slide_power - power_loss
	
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
		
func _get_drift_input():
	var left_input
	if using_joypad:
		left_input = Input.get_joy_axis(joypad_device, JOY_ANALOG_L2)
	else: 
		left_input = int(Input.is_action_pressed("bike_rotate_left") and Input.is_action_pressed("bike_drift"))
		
	var right_input
	if using_joypad:
		right_input = Input.get_joy_axis(joypad_device, JOY_ANALOG_R2) * -1
	else: 
		right_input = int(Input.is_action_pressed("bike_rotate_right") and Input.is_action_pressed("bike_drift")) * -1
	
	if drift == DriftState.READY or drift == DriftState.STOPPED:
		if left_input > abs(right_input):
			return left_input
		return right_input 
	elif drift == DriftState.SLIDING_LEFT:
		return left_input
	elif drift == DriftState.SLIDING_RIGHT:
		return right_input

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
