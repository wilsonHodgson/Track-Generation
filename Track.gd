extends Path

# class member variables go here, for example:
# var a = 2
# var b = "textvar"

func drawRoad():
	print(self.curve.get_baked_length())
		# avoid using interpolate_baked, see results
	var num_samples = 160
	var num_points = self.curve.get_point_count()
	var num_subsamples = float(num_samples)/num_points
	for i in num_points:
		for j in num_subsamples:
			if j != 0:
				print(i+(1/num_subsamples*j))
			else:
				print(i)
			var point_on_curve = self.curve.interpolate(i, 0)
			var next_point_on_curve = self.curve.interpolate(i, 0.00001)
			
			if (j > 0) :
				point_on_curve = self.curve.interpolate(i, 1/num_subsamples*j)
				next_point_on_curve = self.curve.interpolate(i, (1/num_subsamples*j)+0.00001)
		
			var slope_of_curve = point_on_curve - next_point_on_curve
			var perp_slope_of_curve = Vector3(0,1,0).cross(slope_of_curve.normalized())
			$ImmediateGeometry.add_vertex(point_on_curve + 1*perp_slope_of_curve)
			$ImmediateGeometry.add_vertex(point_on_curve + -1*perp_slope_of_curve)
		

func _ready():
	# Called when the node is added to the scene for the first time.
	# Initialization here
	$ImmediateGeometry.begin(PrimitiveMesh.PRIMITIVE_TRIANGLE_STRIP)
	$ImmediateGeometry.set_color(Color (0, 0, 0))
	$ImmediateGeometry.set_normal(Vector3 (0, 1, 0))
	
	var samples = 200.0
	drawRoad()
	
	$ImmediateGeometry.end()
	pass

func _process(delta):

#	# Called every frame. Delta is time since last frame.
#	# Update game logic here.


	pass
