extends Spatial

signal started_accelerating

onready var front_wheel = get_parent().find_node("BikeFrontWheel")
onready var bike_body = get_parent().find_node("BikeBody")
onready var wheel_joint = get_parent().find_node("FrontWheelJoint")

var current_speed = 0
var max_speed = 5
var _wheel_velocity_norm = Vector3()

var friction_high = 3.0
var friction_low = 0

# Time to fully dampen turning after releasing the turn key in msec
var turning_damp_time = 150 
var _turning_damp_start

# Time for the body to be full centered on the front wheel when accelerating
var body_center_time = 0.5
var base_joint_angle = (30.0 / 180.0) * PI
var _target_joint_angle = base_joint_angle

var in_contact = false
var accelerating = false
var turning = false

func _ready():
	find_node("Camera").activate_camera()

func _physics_process(delta):
	_wheel_velocity_norm = front_wheel.linear_velocity.normalized()
	# Find the dot between the forward vector and the velocity vector to determine direction
	var direction = sign(front_wheel.global_transform.basis.z.dot(_wheel_velocity_norm))
	# Project the velocity vector onto the forward vector at the same magnitude to determine the forward velocity
	var forward_velocity = front_wheel.linear_velocity.project(front_wheel.global_transform.basis.z)
	current_speed = forward_velocity.length() * direction
	
	_process_movement_input(delta)	
	_update_bike_friction()
	_update_bike_body_centering(delta)

func _process_movement_input(delta):
	if Input.is_action_pressed("bike_move_forward"):
		if Input.is_action_just_pressed("bike_move_forward"):
			accelerating = true
			emit_signal("started_accelerating")
		if current_speed < max_speed:
			# Apply force towards the forward vector at max speed
			var force_direction = ((bike_body.global_transform.basis.z * max_speed) - bike_body.linear_velocity).normalized()
			bike_body.add_force(force_direction * 150 * delta, Vector3())
	else:
		if Input.is_action_just_released("bike_move_forward"):
			accelerating = false
			
	if Input.is_action_just_pressed("bike_hop") and in_contact:
		print("jump")
		bike_body.add_force(bike_body.transform.basis.y * 1000 * delta, Vector3())
		front_wheel.add_force(bike_body.transform.basis.y * 2000 * delta, Vector3())
		
	if Input.is_action_just_pressed("bike_rotate_left") or Input.is_action_just_pressed("bike_rotate_right"):
		turning = true
		front_wheel.angular_damp = -1
		
	if Input.is_action_pressed("bike_rotate_left"):
		front_wheel.add_torque(Vector3(0, 2 * delta, 0))
		bike_body.add_force(bike_body.transform.basis.x * (current_speed * 10) * delta, Vector3())
		front_wheel.add_force(front_wheel.transform.basis.x * (current_speed * 10) * delta, Vector3())
	elif Input.is_action_pressed("bike_rotate_right"):
		front_wheel.add_torque(Vector3(0, -2 * delta, 0))
		bike_body.add_force(bike_body.transform.basis.x * (current_speed * -10) * delta, Vector3())
		front_wheel.add_force(front_wheel.transform.basis.x * (current_speed * -10) * delta, Vector3())
	else:
		if Input.is_action_just_released("bike_rotate_left") or Input.is_action_just_released("bike_rotate_right"):
			turning = false
			_turning_damp_start = OS.get_ticks_msec()
		# Climb to fully dampened turning on a sine wave when no turning is pressed
		if front_wheel.angular_damp < 1:
			var percent_damped = min(float(OS.get_ticks_msec() - _turning_damp_start) / turning_damp_time, 1)
			front_wheel.angular_damp = -1.0 + sin(percent_damped * PI * 0.5) * 2.0

func _update_bike_friction():
	var wheel_friction = friction_low + (_percent_velocity_sideways(front_wheel) * friction_high)
	front_wheel.physics_material_override.friction = wheel_friction
	
	var body_friction = friction_low + (_percent_velocity_sideways(bike_body) * friction_high)
	bike_body.physics_material_override.friction = body_friction
		
func _update_bike_body_centering(delta):
	if accelerating:
		_target_joint_angle = 0.0
	elif turning:
		# 30 degrees in radians, rounded
		_target_joint_angle = stepify((30.0 / 180.0) * PI, 0.001)
	
	var cur_joint_angle = stepify(wheel_joint.get_param_y(Generic6DOFJoint.PARAM_ANGULAR_UPPER_LIMIT), 0.001)
	if cur_joint_angle > _target_joint_angle:
		# Gradually step the angle down if the current angle is greater than the target (i.e 30 -> 0deg)
		# Percent of center_time elapsed in this tick * the total amount of change
		var angle_change = (delta / body_center_time) * (base_joint_angle - _target_joint_angle)
		var new_angle = max(cur_joint_angle - angle_change, 0)
		wheel_joint.set_param_y(Generic6DOFJoint.PARAM_ANGULAR_UPPER_LIMIT, new_angle)
		wheel_joint.set_param_y(Generic6DOFJoint.PARAM_ANGULAR_LOWER_LIMIT, new_angle * -1)
	elif cur_joint_angle < _target_joint_angle:
		# Set the angle in one step if the current angle is less than the target (i.e 0 -> 30deg)
		wheel_joint.set_param_y(Generic6DOFJoint.PARAM_ANGULAR_UPPER_LIMIT, _target_joint_angle)
		wheel_joint.set_param_y(Generic6DOFJoint.PARAM_ANGULAR_LOWER_LIMIT, _target_joint_angle * -1)
	
func _percent_velocity_sideways(body):
	# Calculate the dot product of the forward vector and the velocity vector
	var dot_prod = body.transform.basis.z.normalized().dot(body.linear_velocity.normalized()) 
	return sin((dot_prod - 1) * -0.5 * PI)

func _on_BikeFrontWheel_body_entered(body):
	in_contact = true

func _on_BikeFrontWheel_body_exited(body):
	in_contact = false
