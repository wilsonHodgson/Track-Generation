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

# Spring the body back to center based on speed
var speed_body_spring_ratio = 0.1
var body_spring_max = 0.4


func _ready():
	find_node("Camera").activate_camera()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if not Input.is_action_pressed("bike_rotate_left") and not Input.is_action_pressed("bike_rotate_right"):
		if front_wheel.angular_damp < 1:
			var percent_damped = min(float(OS.get_ticks_msec() - _turning_damp_start) / turning_damp_time, 1)
			front_wheel.angular_damp = -1.0 + sin(percent_damped * PI * 0.5) * 2.0

func _physics_process(delta):
	if Input.is_action_just_pressed("bike_move_forward"):
		front_wheel.add_force(front_wheel.transform.basis.z * 1000 * delta, Vector3(0,0,0))
			
	if Input.is_action_just_pressed("bike_hop"):
		bike_body.add_force(bike_body.transform.basis.y * 1000 * delta, Vector3())
		front_wheel.add_force(bike_body.transform.basis.y * 2000 * delta, Vector3())
		
	if Input.is_action_just_pressed("bike_rotate_left") or Input.is_action_just_pressed("bike_rotate_right"):
		front_wheel.angular_damp = -1
		
	if Input.is_action_pressed("bike_rotate_left"):
		front_wheel.add_torque(Vector3(0, 2 * delta, 0))
	elif Input.is_action_pressed("bike_rotate_right"):
		front_wheel.add_torque(Vector3(0, -2 * delta, 0))
	elif Input.is_action_just_released("bike_rotate_left") or Input.is_action_just_released("bike_rotate_right"):
		_turning_damp_start = OS.get_ticks_msec()
	
	# Is a dot product really necessary to determine if the bike is going forward or not?
	var direction = sign(front_wheel.transform.basis.z.dot(front_wheel.linear_velocity.normalized()))
	current_speed = front_wheel.linear_velocity.length() * direction
	
	if current_speed > 0:
		# This might not be the right away to keep the body straight
		wheel_joint.set_param_y(
			Generic6DOFJoint.PARAM_ANGULAR_SPRING_STIFFNESS, 
			min(current_speed * speed_body_spring_ratio, body_spring_max))
		wheel_joint.set_param_y(
			Generic6DOFJoint.PARAM_ANGULAR_SPRING_DAMPING, 
			min(current_speed * speed_body_spring_ratio * 0.05, body_spring_max))
		
	var wheel_friction = friction_low + (_percent_velocity_sideways(front_wheel) * friction_high)
	front_wheel.physics_material_override.friction = wheel_friction
	
	var body_friction = friction_low + (_percent_velocity_sideways(bike_body) * friction_high)
	bike_body.physics_material_override.friction = body_friction
	

func _percent_velocity_sideways(body):
	if body.linear_velocity.length() < 0.01:
		return 0
	else:
		# Calculate the dot product of the forward vector and the velocity vector
		var dot_prod = body.transform.basis.z.normalized().dot(body.linear_velocity.normalized()) 
		return sin((dot_prod - 1) * -0.5 * PI)
