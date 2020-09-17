extends RigidBody

var front_wheel
var friction_high = 1
var friction_low = 0.05

# Called when the node enters the scene tree for the first time.
func _ready():
	front_wheel = get_parent().find_node("BikeFrontWheel")

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func _physics_process(delta):
	if Input.is_action_just_pressed("bike_move_forward"):
		front_wheel.add_force(front_wheel.transform.basis.z * 1000 * delta, Vector3(0,0,0))
		#add_torque(Vector3(0, relative_front_wheel_yaw() * 10 * delta, 0))
			
	if Input.is_action_just_pressed("bike_hop"):
		add_force(transform.basis.y * 1000 * delta, Vector3())
		front_wheel.add_force(transform.basis.y * 2000 * delta, Vector3())
		
	if Input.is_action_pressed("bike_rotate_left"):
		front_wheel.add_torque(Vector3(0, 4 * delta, 0))
	elif Input.is_action_pressed("bike_rotate_right"):
		front_wheel.add_torque(Vector3(0, -4 * delta, 0))
		
	if Input.is_key_pressed(KEY_LEFT):
		add_force(transform.basis.x * 100 * delta, Vector3())
		front_wheel.add_force(front_wheel.transform.basis.x * 100 * delta, Vector3())
	if Input.is_key_pressed(KEY_RIGHT):
		add_force(transform.basis.x * -100 * delta, Vector3())
		front_wheel.add_force(front_wheel.transform.basis.x * 100 * delta, Vector3())
	if Input.is_key_pressed(KEY_DOWN):
		add_force(transform.basis.z * -100 * delta, Vector3())
		front_wheel.add_force(front_wheel.transform.basis.z * -100 * delta, Vector3())
		
	var wheel_friction = friction_low + (percent_velocity_sideways(front_wheel) * friction_high)
	front_wheel.physics_material_override.friction = wheel_friction
	
	var body_friction = friction_low + (percent_velocity_sideways(self) * friction_high)
	physics_material_override.friction = body_friction
	
	#print("wheel: %s\tbody: %s" % [wheel_friction, body_friction])

func percent_velocity_sideways(body):
	if body.linear_velocity.length() < 0.01:
		return 0
	else:
		# Calculate the dot product of the forward vector and the velocity vector
		var dot_prod = body.transform.basis.z.normalized().dot(body.linear_velocity.normalized()) 
		return sin((dot_prod - 1) * -0.5 * PI)
	
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
