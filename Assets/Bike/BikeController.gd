extends Spatial

signal started_accelerating

onready var front_wheel = get_parent().find_node("BikeFrontWheel")
onready var front_wheel_mesh = front_wheel.get_node("Mesh")
onready var front_wheel_shape = front_wheel.get_node("CollisionShape")
onready var front_fork = find_node("FrontFork")
onready var bike_body = get_parent().find_node("BikeBody")
onready var wheel_joint = get_parent().find_node("FrontWheelJoint")

var current_speed = 0
# Speed in units forward per second
var max_speed = 6
var max_turn_force = 15

var friction_high = 3.0
var friction_low = 0.01

# Time to fully dampen turning after releasing the turn key in msec
var turning_damp_time = 150 
var _turning_damp_start

# Distance that must be traveled for the body to centre itself
var centre_body_travel = 1.5
var base_joint_angle = (30.0 / 180.0) * PI
var percent_centered = 0
var _target_joint_angle = base_joint_angle

var in_contact = false
var accelerating = false
var turning = false

func _ready():
	find_node("Camera").activate_camera()

func _physics_process(delta):
	# Find the dot between the forward vector and the velocity vector to determine direction
	var direction = sign(front_wheel.global_transform.basis.z.dot(front_wheel.linear_velocity.normalized()))
	# Project the velocity vector onto the forward vector at the same magnitude to determine the forward velocity
	var forward_velocity = front_wheel.linear_velocity.project(front_wheel.global_transform.basis.z)
	current_speed = forward_velocity.length() * direction
	
	_process_movement_input(delta)
	_update_fork_basis()
	_update_front_wheel_basis()
	_update_bike_friction()
	_update_bike_body_centering(delta)
	_update_bike_roll(delta)
	
	

func _process_movement_input(delta):
	if Input.is_action_pressed("bike_move_forward"):
		if Input.is_action_just_pressed("bike_move_forward"):
			accelerating = true
			emit_signal("started_accelerating")
		if current_speed < max_speed and in_contact:
			# Apply force towards the forward vector at max speed
			var force_direction = ((bike_body.global_transform.basis.z * max_speed) - bike_body.linear_velocity).normalized()
			bike_body.add_force(force_direction * 150 * delta, Vector3())
		elif not in_contact:
			# If accelerating but not in contact with the ground, continue to apply force to correct the forward direction
			var force_direction = ((bike_body.global_transform.basis.z * current_speed) - bike_body.linear_velocity).normalized()
			bike_body.add_force(force_direction * 150 * delta, Vector3())
	else:
		if Input.is_action_just_released("bike_move_forward"):
			accelerating = false
			
	if Input.is_action_just_pressed("bike_hop") and in_contact:
		bike_body.add_force(bike_body.transform.basis.y * 1000 * delta, Vector3())
		front_wheel.add_force(bike_body.transform.basis.y * 2000 * delta, Vector3())
		
	if Input.is_action_just_pressed("bike_rotate_left") or Input.is_action_just_pressed("bike_rotate_right"):
		turning = true
		front_wheel.angular_damp = -1
		
	if Input.is_action_pressed("bike_rotate_left"):
		front_wheel.add_torque(Vector3(0, 2 * delta, 0))
		bike_body.add_force(bike_body.transform.basis.x * (current_speed * max_turn_force) * delta, Vector3())
		front_wheel.add_force(front_wheel.transform.basis.x * (current_speed * max_turn_force) * delta, Vector3())
	elif Input.is_action_pressed("bike_rotate_right"):
		front_wheel.add_torque(Vector3(0, -2 * delta, 0))
		bike_body.add_force(bike_body.transform.basis.x * (current_speed * -max_turn_force) * delta, Vector3())
		front_wheel.add_force(front_wheel.transform.basis.x * (current_speed * -max_turn_force) * delta, Vector3())
	else:
		if Input.is_action_just_released("bike_rotate_left") or Input.is_action_just_released("bike_rotate_right"):
			turning = false
			_turning_damp_start = OS.get_ticks_msec()
		# Climb to fully dampened turning on a sine wave when no turning is pressed
		if front_wheel.angular_damp < 1:
			var percent_damped = min(float(OS.get_ticks_msec() - _turning_damp_start) / turning_damp_time, 1)
			front_wheel.angular_damp = -1.0 + sin(percent_damped * PI * 0.5) * 2.0

func _update_fork_basis():
	front_fork.global_transform.basis = Basis(
		front_wheel.global_transform.basis.x,
		bike_body.global_transform.basis.y,
		front_wheel.global_transform.basis.z)
		
func _update_front_wheel_basis():
	var mesh_scale = front_wheel_mesh.global_transform.basis.get_scale()
	var new_basis = Basis(
		bike_body.global_transform.basis.y.normalized() * -0.1,
		#front_wheel_mesh.global_transform.basis.y,
		front_wheel_mesh.global_transform.basis.y,
		front_wheel_mesh.global_transform.basis.z)
	#front_wheel_mesh.global_transform.basis = new_basis
	print("\nScale -- Old -- New\n%s" % [mesh_scale])
	_print_basis_xyz(front_wheel_mesh.global_transform.basis)
	_print_basis_xyz(new_basis)
		
#	var shape_scale = front_wheel_shape.global_transform.basis.get_scale()
	front_wheel_mesh.global_transform.basis = new_basis
#	front_wheel_shape.global_transform.basis.scaled(shape_scale)

func _print_basis_xyz(basis):
	print("(%s, %s, %s)" % [basis.x, basis.y, basis.z])

func _update_bike_friction():
	var wheel_friction = friction_low + (_percent_velocity_sideways(front_wheel) * friction_high)
	front_wheel.physics_material_override.friction = wheel_friction
	
	var body_friction = friction_low + (_percent_velocity_sideways(bike_body) * friction_high)
	bike_body.physics_material_override.friction = body_friction
		
func _update_bike_body_centering(delta):
	if accelerating:
		_target_joint_angle = (0.0 / 180.0) * PI
	elif turning:
		_target_joint_angle = base_joint_angle
	
	var cur_joint_angle = stepify(wheel_joint.get_param_y(Generic6DOFJoint.PARAM_ANGULAR_UPPER_LIMIT), 0.001)
	percent_centered = max(1 - (cur_joint_angle / base_joint_angle), 0)
	if cur_joint_angle > _target_joint_angle:
		# Gradually step the angle down if the current angle is greater than the target (i.e 30 -> 0deg)
		# Percent of centre_body_travel traveled in this tick * the total angle to traverse
		var distance_traveled_in_frame = max(current_speed * delta, 0)
		var angle_change = (distance_traveled_in_frame / centre_body_travel) * (base_joint_angle - _target_joint_angle)
		var new_angle = max(cur_joint_angle - angle_change, 0)
		wheel_joint.set_param_y(Generic6DOFJoint.PARAM_ANGULAR_UPPER_LIMIT, new_angle)
		wheel_joint.set_param_y(Generic6DOFJoint.PARAM_ANGULAR_LOWER_LIMIT, new_angle * -1)
	elif cur_joint_angle < _target_joint_angle:
		# Set the angle in one step if the current angle is less than the target (i.e 0 -> 30deg)
		wheel_joint.set_param_y(Generic6DOFJoint.PARAM_ANGULAR_UPPER_LIMIT, _target_joint_angle)
		wheel_joint.set_param_y(Generic6DOFJoint.PARAM_ANGULAR_LOWER_LIMIT, _target_joint_angle * -1)
		
func _update_bike_roll(delta):
	var forward_velocity_normal = bike_body.transform.basis.z.cross(bike_body.linear_velocity).y
	var roll = min(abs(forward_velocity_normal), 2) * sign(forward_velocity_normal) * (current_speed / max_speed) * -1
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
