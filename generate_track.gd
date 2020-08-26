extends Path2D


# Declare member variables here. Examples:
# var a = 2
# var b = "text"

##DRAWS A TRACK FROM A WELL DEFINED CURVE
func drawRoad():
	print(self.curve.get_baked_length())
		# avoid using interpolate_baked, see results
	var num_samples = 140
	var num_points = self.curve.get_point_count()
	var num_subsamples = float(num_samples)/num_points
	var starting_line = {}
	
	for i in num_points+1:
		for j in num_subsamples+1:
			if j != 0:
				print(i+(1/num_subsamples*j))
			else:
				print(i)
			var point_on_curve = self.curve.interpolate(i, 0)*scale+position
			var next_point_on_curve = self.curve.interpolate(i, 0.00001)*scale+position
				
			if (j > 0) :
				point_on_curve = self.curve.interpolate(i, 1/num_subsamples*j)*scale+position
				next_point_on_curve = self.curve.interpolate(i, (1/num_subsamples*j)+0.00001)*scale+position
		
			var point_on_3Dcurve = _2Dto3D(point_on_curve)
			var next_point_on_3Dcurve = _2Dto3D(next_point_on_curve)
			
			var slope_of_curve = point_on_3Dcurve - next_point_on_3Dcurve
			var perp_slope_of_curve = Vector3(0,1,0).cross(slope_of_curve.normalized())

			$ImmediateGeometry.add_vertex(point_on_3Dcurve + 1*perp_slope_of_curve)
			$ImmediateGeometry.add_vertex(point_on_3Dcurve + -1*perp_slope_of_curve)
			
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
