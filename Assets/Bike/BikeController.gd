extends RigidBody

var front_wheel
var front_wheel_mesh
var front_wheel_shape
var front_yaw_target = 0
var front_yaw = 0

# Called when the node enters the scene tree for the first time.
func _ready():
	front_wheel = get_parent().find_node("BikeFrontWheel")
	front_wheel_mesh = front_wheel.find_node("FrontWheelMesh")
	front_wheel_shape = front_wheel.find_node("FrontWheelShape")


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func _physics_process(delta):
	if Input.is_action_just_pressed("bike_move_forward"):
		front_wheel.add_force(front_wheel_mesh.transform.basis.z * 10000 * delta, Vector3(0,0,0))
		#add_torque(Vector3(0, relative_front_wheel_yaw() * delta, 0))
			
	if Input.is_action_just_pressed("bike_hop"):
		add_force(transform.basis.y * 1000 * delta, Vector3(0,0,0))
		front_wheel.add_force(transform.basis.y * 2000 * delta, Vector3(0,0,0))
	if Input.is_action_pressed("bike_rotate_left"):
		if relative_front_wheel_yaw() > -30:
			front_wheel_mesh.rotation.y = front_wheel_mesh.rotation.y + (1 * delta)
			front_wheel_shape.rotation.y = front_wheel_shape.rotation.y + (1 * delta)
	elif Input.is_action_pressed("bike_rotate_right"):
		if relative_front_wheel_yaw() < 30:
			front_wheel_mesh.rotation.y = front_wheel_mesh.rotation.y - (1 * delta)
			front_wheel_shape.rotation.y = front_wheel_shape.rotation.y - (1 * delta)

#func _input(event):
#	if event.is_action_pressed("bike_rotate_left"):
#		pass
#
#	if Input.is_action_pressed("bike_rotate_left") and not Input.is_action_pressed("bike_rotate_right"):
#		print("Left")
#		state.angular_velocity.x = PI * -0.1
#	elif not Input.is_action_pressed("bike_rotate_left") and Input.is_action_pressed("bike_rotate_right"):
#		state.angular_velocity.x = PI * 0.1

func relative_front_wheel_yaw():
	var result = degree_diff(rotation_degrees.y, front_wheel_mesh.rotation_degrees.y)
	return result
	
func degree_diff(deg_a, deg_b):
	deg_a = to_bound_degrees(deg_a)
	deg_b = to_bound_degrees(deg_b)
	
	var raw_diff = deg_a - deg_b
	if abs(raw_diff) > 180:
		return raw_diff - 360
	return raw_diff
	
func to_bound_degrees(degrees):
	if degrees >= -180 and degrees <= 180:
		return degrees
	
	if int(degrees / 180) % 2 != 0:
		return -180 + fmod(degrees, 180.0)
	else:
		return fmod(degrees, 180.0)
