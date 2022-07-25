extends Path2D

var mesh = Array()
var num_points = self.curve.get_point_count()
var finish_line

##DRAWS A TRACK FROM A WELL DEFINED CURVE
func drawRoad():
		# avoid using interpolate_baked, see results
	var width = 5
	var num_samples = 120
	var num_subsamples = float(num_samples)/num_points
	var collision_box
	var node
	var endpoint
	var end_direction

	for i in num_points+1:
		for j in num_subsamples+1:
			var point = i
			var subPoint = 0
			var tangent = _interpolated_tangent_2D(point, subPoint)
				
			if (j > 0) :
				point = i
				subPoint = 1/num_subsamples*j
		
			var point_on_curve = curve.interpolate(point, subPoint)
			var point_on_3Dcurve = _2Dto3D(point_on_curve)

			var perp_slope_of_curve = _interpolated_tangent_3D(point, subPoint)

			$ImmediateGeometry.add_vertex(point_on_3Dcurve + width*1*perp_slope_of_curve)
			$ImmediateGeometry.add_vertex(point_on_3Dcurve + width*-1*perp_slope_of_curve)
			
			mesh.push_front(point_on_3Dcurve + width*1*perp_slope_of_curve)
			mesh.push_front(point_on_3Dcurve + width*1*perp_slope_of_curve + Vector3(0, -1, 0))
			mesh.push_front(point_on_3Dcurve + width*-1*perp_slope_of_curve)
			mesh.push_front(point_on_3Dcurve + width*-1*perp_slope_of_curve + Vector3(0, -1, 0))
			
			if (j%2 == 0 and j != 0):
				node = CollisionShape.new()
				collision_box = ConvexPolygonShape.new()
				node.shape = collision_box
				var owner = $StaticBody.create_shape_owner($StaticBody)
				collision_box.points = PoolVector3Array(mesh)
				$StaticBody.shape_owner_add_shape(owner, node)
				$StaticBody.add_child(node)

				mesh.resize(4)
				
			if (j == num_subsamples and i == num_points):
				endpoint = point_on_3Dcurve
				end_direction = _interpolated_slope_3D(point, subPoint)
				_build_road_end(endpoint, end_direction)
				

func _build_road_start(var point:Vector3, var direction:Vector3):
	pass
	
func _build_road_end(var point:Vector3, var direction:Vector3):
	$FinishLine.global_transform.origin = point
	$FinishLine.look_at(point + direction, Vector3(0, 1, 0))

func _build_road():
	var length = curve.get_point_count()
	var last_position = curve.get_point_position(length-1)
	self.curve.clear_points()
	
	var road_builder = Vector2()
	var to_finish_line = road_builder.direction_to(finish_line)
	var wander_angle = to_finish_line.angle()+90
	var point_set = Array()
	for i in 9:
		var wander_direction = _wander(wander_angle)
		var walk_direction = to_finish_line.normalized()*30 + wander_direction
		point_set.append(road_builder)
		#curve.add_point(road_builder, -(i%2) * wander_direction.normalized()*59, -((i+1)%2)*wander_direction.normalized()*59)
		var point = CSGBox.new()
		add_child(point)
		point.translate(_2Dto3D(road_builder*scale+position))
		road_builder = road_builder + walk_direction
	var j = 0
	while j < 5:
		if (j == 0):
			curve.add_point(point_set[j], Vector2(), point_set[j+1])
			curve.add_point(point_set[j+3], point_set[j+2], Vector2())
		else :
			curve.add_point(point_set[j], point_set[j-1], point_set[j+1])
			curve.add_point(point_set[j+3], point_set[j+2], point_set[j+4])
		j += 4

func _wander(var angle):
	var wanderRadius = 25
	var angleVariant = 30
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	angle += rng.randf_range(-angleVariant, angleVariant) + 180
	var wander = Vector2(cos(angle), sin(angle)) * wanderRadius
	return wander
	
func _2DPerp(var input : Vector2):
	return Vector2(input.y, -input.x)

func _2Dto3D(var input : Vector2 = Vector2(0, 0)):
	return Vector3(input.x, 0, input.y)
	
func _interpolated_slope_2D(var idx, var offset):
	var point_on_curve = curve.interpolate(idx, offset)#*scale+position
	var approaching_point = curve.interpolate(idx, offset + 0.00001)#*scale+position
	var slope = point_on_curve - approaching_point
	return slope
	
func _interpolated_slope_3D(var idx, var offset):
	var point_on_curve = curve.interpolate(idx, offset)#*scale+position
	var approaching_point = curve.interpolate(idx, offset + 0.00001)#*scale+position
	var slope = point_on_curve - approaching_point
	return _2Dto3D(slope)
	
func _interpolated_tangent_3D(var idx, var offset):
	var slope3D = _2Dto3D(_interpolated_slope_2D(idx, offset))
	return Vector3(0,1,0).cross(slope3D).normalized()
	
func _interpolated_tangent_2D(var idx, var offset):
	var slope = _interpolated_slope_2D(idx, offset)
	return slope.normalized()

func _spawnCar():
	var startingPoint = self.curve.interpolate(0, 0.5)#*scale#+position
	var player = $Car
	player.global_translate(_2Dto3D(startingPoint) + Vector3(0,10,0))
	player.look_at(player.global_transform.origin + _interpolated_slope_3D(0, 0.5), Vector3(0, 1, 0))

func _spawnTree():
	var treeAsset = load("res://Assets/Kenney/tree_oak.obj")
	var tree = MeshInstance.new()
	tree.mesh = treeAsset
	add_child(tree)
	return tree
	
func drawTrees(var numTrees):
	var rng = RandomNumberGenerator.new()
	for i in numTrees:
				
		rng.randomize()
		var tree = _spawnTree()
		var distance = rng.randf_range(0, num_points)
		
		var idx = floor(distance)
		var offset = distance - idx
		var treePos = curve.interpolate(idx, offset)#*scale#+position
		
		rng.randomize()
		var treeOffset = (rng.randi_range(0,1)*2-1)*10*_interpolated_tangent_3D(idx, offset)
		tree.global_translate(_2Dto3D(treePos) + treeOffset)
		tree.scale *= (rng.randf_range(4,8))
		
func _ready():

	$ImmediateGeometry.begin(PrimitiveMesh.PRIMITIVE_TRIANGLE_STRIP)
	$ImmediateGeometry.set_color(Color (0, 0, 0))
	$ImmediateGeometry.set_normal(Vector3 (0, 1, 0))

	#finish_line = $Finish.position

	var samples = 200.0
	#_build_road()
	drawRoad()
	drawTrees(100)

	$ImmediateGeometry.end()
	_spawnCar()

