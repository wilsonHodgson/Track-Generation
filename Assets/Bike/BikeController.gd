extends Spatial

onready var front_wheel = get_parent().find_node("BikeFrontWheel")
onready var bike_body = get_parent().find_node("BikeBody")
onready var wheel_joint = get_parent().find_node("FrontWheelJoint")

var current_speed = 0
var max_speed = 5

var friction_high = 1.5
var friction_low = 0

# Time to fully dampen turning after releasing the turn key in msec
var turning_damp_time = 150 
var _turning_damp_start

var body_center_time = 500
var base_joint_angle = (30.0 / 180.0) * PI
var _target_joint_angle = base_joint_angle

var in_contact = false
var accelerating = false
var turning = false

func _ready():
	find_node("Camera").activate_camera()

func _physics_process(delta):
	var direction = sign(front_wheel.transform.basis.z.dot(front_wheel.linear_velocity.normalized()))
	current_speed = (front_wheel.linear_velocity.length() * direction)
	
	_process_movement_input(delta)	
	_update_bike_friction()
	_update_bike_body_centering(delta)

func _process_movement_input(delta):
	accelerating = false
	if Input.is_action_pressed("bike_move_forward"):
		if current_speed < max_speed:
			bike_body.add_force(bike_body.transform.basis.z * 150 * delta, Vector3(0,0,0))
		if current_speed > 0:
			accelerating = true
			
	if Input.is_action_just_pressed("bike_hop") and in_contact:
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
	print(body_friction)
		
func _update_bike_body_centering(delta):
	if accelerating and not turning:
		_target_joint_angle = 0.0
	else:
		_target_joint_angle = stepify((30.0 / 180.0) * PI, 0.001)
	
	var cur_joint_angle = stepify(wheel_joint.get_param_y(Generic6DOFJoint.PARAM_ANGULAR_UPPER_LIMIT), 0.001)
	if cur_joint_angle > _target_joint_angle:
		# Percent of center_time elapsed in this tick * the total amount of change
		var angle_change = (delta / (body_center_time / 1000.0)) * (base_joint_angle - _target_joint_angle)
		var new_angle = max(cur_joint_angle - angle_change, 0)
		wheel_joint.set_param_y(Generic6DOFJoint.PARAM_ANGULAR_UPPER_LIMIT, new_angle)
		wheel_joint.set_param_y(Generic6DOFJoint.PARAM_ANGULAR_LOWER_LIMIT, new_angle * -1)
	elif cur_joint_angle < _target_joint_angle:
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
