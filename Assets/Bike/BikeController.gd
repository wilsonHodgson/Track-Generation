extends Spatial

onready var front_wheel = get_parent().find_node("BikeFrontWheel")
onready var bike_body = get_parent().find_node("BikeBody")
onready var wheel_joint = get_parent().find_node("FrontWheelJoint")

var current_speed

var friction_high = 1
var friction_low = 0

# Time to fully dampen turning after releasing the turn key in msec
var turning_damp_time = 150 
var _turning_damp_start

# Spring and dampen the body back to center based on speed
var speed_body_spring_ratio = 0.2
var body_spring_max = 0.35
var speed_body_dampen_ratio = 0.01
var body_dampen_max = 0.015

var in_contact = false

func _ready():
	find_node("Camera").activate_camera()

func _physics_process(delta):
	_process_movement_input(delta)
	
	var direction = sign(front_wheel.transform.basis.z.dot(front_wheel.linear_velocity.normalized()))
	current_speed = front_wheel.linear_velocity.length() * direction
		
	_update_bike_friction()
	_update_bike_body_centering()

func _process_movement_input(delta):
	if Input.is_action_just_pressed("bike_move_forward"):
		bike_body.add_force(bike_body.transform.basis.z * 1000 * delta, Vector3(0,0,0))
			
	if Input.is_action_just_pressed("bike_hop"):
		bike_body.add_force(bike_body.transform.basis.y * 1000 * delta, Vector3())
		front_wheel.add_force(bike_body.transform.basis.y * 2000 * delta, Vector3())
		
	if Input.is_action_just_pressed("bike_rotate_left") or Input.is_action_just_pressed("bike_rotate_right"):
		# Reset any turn dampening if we're starting to turn again
		front_wheel.angular_damp = -1
		
	if Input.is_action_pressed("bike_rotate_left"):
		front_wheel.add_torque(Vector3(0, 2 * delta, 0))
	elif Input.is_action_pressed("bike_rotate_right"):
		front_wheel.add_torque(Vector3(0, -2 * delta, 0))
	else:
		if Input.is_action_just_released("bike_rotate_left") or Input.is_action_just_released("bike_rotate_right"):
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
	
func _update_bike_body_centering():
	if current_speed > 0 and in_contact:
		# Re-enable the spring
		if not wheel_joint.get_flag_y(Generic6DOFJoint.FLAG_ENABLE_ANGULAR_SPRING):
			wheel_joint.set_flag_y(Generic6DOFJoint.FLAG_ENABLE_ANGULAR_SPRING, true)
			
		# Spring the body on the angular y axis
		var spring_power = min(current_speed * speed_body_spring_ratio, body_spring_max)
		wheel_joint.set_param_y(Generic6DOFJoint.PARAM_ANGULAR_SPRING_STIFFNESS, spring_power)
		
		# Dampen excess body movement on the angular y axis
		var dampen_power = min(current_speed * speed_body_dampen_ratio, body_dampen_max)
		wheel_joint.set_param_y(Generic6DOFJoint.PARAM_ANGULAR_SPRING_DAMPING, dampen_power)
	elif wheel_joint.get_flag_y(Generic6DOFJoint.FLAG_ENABLE_ANGULAR_SPRING):
		# Disable the spring if there's no forward speed or contact with other bodies
		wheel_joint.set_flag_y(Generic6DOFJoint.FLAG_ENABLE_ANGULAR_SPRING, false)

func _percent_velocity_sideways(body):
	if body.linear_velocity.length() < 0.01:
		return 0
	else:
		# Calculate the dot product of the forward vector and the velocity vector
		var dot_prod = body.transform.basis.z.normalized().dot(body.linear_velocity.normalized()) 
		return sin((dot_prod - 1) * -0.5 * PI)

func _on_BikeFrontWheel_body_entered(body):
	in_contact = true

func _on_BikeFrontWheel_body_exited(body):
	in_contact = false
