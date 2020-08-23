extends Path2D


# Declare member variables here. Examples:
# var a = 2
# var b = "text"

##DRAWS A TRACK FROM A WELL DEFINED CURVE
func drawRoad():
	print(self.curve.get_baked_length())
		# avoid using interpolate_baked, see results
	var num_samples = 120
	var num_points = self.curve.get_point_count()
	var num_subsamples = float(num_samples)/num_points
	var starting_line = {}
	for i in num_points+1:
		for j in num_subsamples+1:
			if j != 0:
				print(i+(1/num_subsamples*j))
			else:
				print(i)
			var point_on_curve = self.curve.interpolate(i, 0)*scale.x
			var next_point_on_curve = self.curve.interpolate(i, 0.00001)*scale.y
			
			if (i == 0 and j == 0):
				starting_line["left"] = _2Dto3D(point_on_curve)
				starting_line["right"] = _2Dto3D(next_point_on_curve)
				
			#if (i == num_points and j == num_samples):
			#	next_point_on_curve == self.curve.interpolate(i, -0.00001)*scale.y
			
			if (j > 0) :
				point_on_curve = self.curve.interpolate(i, 1/num_subsamples*j)*scale.x
				next_point_on_curve = self.curve.interpolate(i, (1/num_subsamples*j)+0.00001)*scale.y
		
			var point_on_3Dcurve = _2Dto3D(point_on_curve)
			var next_point_on_3Dcurve = _2Dto3D(next_point_on_curve)
			
			var slope_of_curve = point_on_3Dcurve - next_point_on_3Dcurve
			var perp_slope_of_curve = Vector3(0,1,0).cross(slope_of_curve.normalized())
			#if (j == num_samples and i == num_points):
			#	perp_slope_of_curve = (starting_line["left"] - starting_line["right"]).normalized()
			#	$ImmediateGeometry.add_vertex(starting_line["left"] + 1*perp_slope_of_curve)
			#	$ImmediateGeometry.add_vertex(starting_line["right"] + -1*perp_slope_of_curve)
			#else:
			$ImmediateGeometry.add_vertex(point_on_3Dcurve + 1*perp_slope_of_curve)
			$ImmediateGeometry.add_vertex(point_on_3Dcurve + -1*perp_slope_of_curve)
			
# Called when the node enters the scene tree for the first time.

func _2Dto3D(var input : Vector2 = Vector2(0, 0)):
	return Vector3(input.x, 0, input.y)

func _ready():
		# Called when the node is added to the scene for the first time.
	# Initialization here
	$ImmediateGeometry.begin(PrimitiveMesh.PRIMITIVE_TRIANGLE_STRIP)
	$ImmediateGeometry.set_color(Color (0, 0, 0))
	$ImmediateGeometry.set_normal(Vector3 (0, 1, 0))
	
	var samples = 200.0
	drawRoad()
	
	$ImmediateGeometry.end()
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
