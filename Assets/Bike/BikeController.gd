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

var fwheel_locked = false
var fwheel_unlock_speed = 2.0

var in_contact = false
var accelerating = false
var turning = false

enum DriftStage {READY, STARTING, SLIDING, STOPPED}
var drift = DriftStage.READY
var drift_early_flick_allowance = 500
var drift_late_flick_allowance = 100
var drift_start_force = 24
# The slide force that will be multiplied by the body speed to create the slide power
var drift_slide_force_mult = 3
# The amount of drift slide power lost each second
var drift_slide_power_loss = 2
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
	
	if fwheel_locked:
		if is_drifting() or body_speed <= fwheel_unlock_speed:
			fwheel_locked = false
	
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
			emit_signal("started_accelerating")
		if forward_speed < max_speed and in_contact:
			# Apply force towards the forward vector at max speed
			var force_direction = ((bike_body.global_transform.basis.z * max_speed) - bike_body.linear_velocity).normalized()
			var force_magnitude = correction_force + acceleration_force
			bike_body.add_force(force_direction * force_magnitude * delta, Vector3())
	else:
		if Input.is_action_just_released("bike_move_forward"):
			accelerating = false	
		if fwheel_locked:
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
					var drift_power = -turn_flick.distance
					print("Drift power: %s" % [drift_power])
					_drift_slide_power = body_speed * drift_slide_force_mult * sign(drift_power)
					bike_body.add_force(bike_body.transform.basis.x * (drift_start_force * drift_power), Vector3())
					friction_high = friction_high_drifting
					drift = DriftStage.SLIDING
		elif drift == DriftStage.SLIDING:
			bike_body.add_force(bike_body.transform.basis.x * _drift_slide_power * delta, Vector3())
			front_wheel.add_force(front_wheel.transform.basis.x * _drift_slide_power * delta, Vector3())
			var power_loss = drift_slide_power_loss * delta * sign(_drift_slide_power)
			_drift_slide_power = _drift_slide_power - power_loss
			print(_drift_slide_power)
			if body_speed < 1.0 or abs(power_loss) > abs(_drift_slide_power):
				print("Drift stopped")
				friction_high = friction_high_normal
				drift = DriftStage.STOPPED
	else:
		if drift != DriftStage.READY:
			if drift == DriftStage.SLIDING:
				friction_high = friction_high_normal
			drift = DriftStage.READY
		
		if turn_input != 0:
			if !turning:
				turning = true
				front_wheel.angular_damp = -1
			
			if !fwheel_locked:
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
		
func _update_bike_body_centering(delta):
	if accelerating or fwheel_locked:
		_target_joint_angle = 0.0
	elif !fwheel_locked:
		_target_joint_angle = base_joint_angle
	
	var cur_joint_angle = stepify(wheel_joint.get_param_y(Generic6DOFJoint.PARAM_ANGULAR_UPPER_LIMIT), 0.001)
	percent_centered = max(1 - (cur_joint_angle / base_joint_angle), 0)
	if cur_joint_angle > _target_joint_angle:
		# Gradually step the angle down if the current angle is greater than the target (i.e 30 -> 0deg)
		# Percent of centre_body_travel traveled in this tick * the total angle to traverse
		var distance_traveled_in_frame = max(forward_speed * delta, 0)
		var angle_change = (distance_traveled_in_frame / centre_body_travel) * (base_joint_angle - _target_joint_angle)
		var new_angle = max(cur_joint_angle - angle_change, 0)
		wheel_joint.set_param_y(Generic6DOFJoint.PARAM_ANGULAR_UPPER_LIMIT, new_angle)
		wheel_joint.set_param_y(Generic6DOFJoint.PARAM_ANGULAR_LOWER_LIMIT, new_angle * -1)
		
		if new_angle == 0:
			fwheel_locked = true
	elif cur_joint_angle < _target_joint_angle:
		# Set the angle in one step if the current angle is less than the target (i.e 0 -> 30deg)
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
