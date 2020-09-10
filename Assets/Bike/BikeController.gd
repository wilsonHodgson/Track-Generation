extends RigidBody

var front_wheel
var front_wheel_mesh
var front_wheel_shape
var front_wheel_joint

# Upright force applied when the angle is outside of the upright range
var upright_torque_force = 30
# Additional force applied based on how far outside of the range the angle is
var upright_torque_spring_force = 5
# The angular velocity limit at which force stops being applied
var upright_torque_force_limit = 2.5
# The strength of the dampening force inside the upright_range
var upright_torque_dampen = 0.3
# The angular velocity required to trigger the dampening force
var upright_torque_dampen_trigger = 0.15
# The range in radians that the angle is to be kept within
var upright_range = 0.1

# Called when the node enters the scene tree for the first time.
func _ready():
	front_wheel = get_parent().find_node("BikeFrontWheel")
	front_wheel_mesh = front_wheel.find_node("FrontWheelMesh")
	front_wheel_shape = front_wheel.find_node("FrontWheelShape")
	front_wheel_joint = get_parent().find_node("FrontWheelJoint")

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func _physics_process(delta):
	if Input.is_action_just_pressed("bike_move_forward"):
		front_wheel.add_force(front_wheel_mesh.transform.basis.z * 10000 * delta, Vector3(0,0,0))
		add_torque(Vector3(0, relative_front_wheel_yaw() * delta, 0))
			
	if Input.is_action_just_pressed("bike_hop"):
		add_force(transform.basis.y * 1000 * delta, Vector3(0,0,0))
		front_wheel.add_force(transform.basis.y * 2000 * delta, Vector3(0,0,0))
	if Input.is_action_pressed("bike_rotate_left"):
		if relative_front_wheel_yaw() > -0.5:
			front_wheel_mesh.rotation.y = front_wheel_mesh.rotation.y + (1 * delta)
			front_wheel_shape.rotation.y = front_wheel_shape.rotation.y + (1 * delta)
	elif Input.is_action_pressed("bike_rotate_right"):
		if relative_front_wheel_yaw() < 0.5:
			front_wheel_mesh.rotation.y = front_wheel_mesh.rotation.y - (1 * delta)
			front_wheel_shape.rotation.y = front_wheel_shape.rotation.y - (1 * delta)
			
	apply_upright_torque(delta)

func apply_upright_torque(delta):
	print("angle %s\tvel %s" % [rotation.z, angular_velocity.z])
	if rotation.z > upright_range:
		# Apply negative upright torque
		if angular_velocity.z > upright_torque_force_limit * -1:
			var torque = (upright_torque_force * -1) - (rotation.z * upright_torque_spring_force)
			add_torque(Vector3(0, 0, torque * delta))
		else:
			print("limit")
	elif rotation.z < upright_range * -1:
		# Apply positive upright torque
		if angular_velocity.z < upright_torque_force_limit:
			var torque = upright_torque_force - (rotation.z * upright_torque_spring_force)
			add_torque(Vector3(0, 0, torque * delta))
		else:
			print("limit")
	else:
		# Dampen any torque
		if abs(angular_velocity.z) > upright_torque_dampen_trigger:
			print("dampen")
			add_torque(Vector3(0, 0, angular_velocity.z * -upright_torque_dampen))

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
	var result = degree_diff(rotation.y, front_wheel_mesh.rotation.y)
	return result
	
func degree_diff(deg_a, deg_b):
	deg_a = to_bound_degrees(deg_a)
	deg_b = to_bound_degrees(deg_b)
	
	var raw_diff = deg_a - deg_b
	if abs(raw_diff) > PI / 2:
		return raw_diff - PI
	return raw_diff
	
func to_bound_degrees(degrees):
	if degrees >= -PI / 2 and degrees <= PI / 2:
		return degrees
	
	if int(degrees / (PI / 2)) % 2 != 0:
		return -(PI / 2) + fmod(degrees, PI / 2)
	else:
		return fmod(degrees, PI / 2)
