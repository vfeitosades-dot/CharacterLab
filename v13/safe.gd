extends "res://cinematic.gd"

const POOL_CENTER := Vector3(8.0,0,-8.0)
const WATER_HEIGHT := 0.29
var water_surface: MeshInstance3D
var water_mat: ShaderMaterial
var contact_shadow: MeshInstance3D
var contact_mat: ShaderMaterial
var ripple_origin := Vector2.ZERO
var ripple_age := 10.0
var last_ripple := Vector2(1000,1000)
var ripple_clock := 0.0
var ripple_cursor := 0
var ripple_slots: Array[Vector4] = [Vector4(0,0,-100,0),Vector4(0,0,-100,0),Vector4(0,0,-100,0),Vector4(0,0,-100,0)]

func make_world() -> void:
	super.make_world()
	build_pool()

func pool_box(parent: Node3D, label_text: String, pos: Vector3, dimensions: Vector3, mat: Material, solid: bool) -> void:
	var mesh := BoxMesh.new()
	mesh.size=dimensions
	var visual_mesh := MeshInstance3D.new()
	visual_mesh.name=label_text
	visual_mesh.mesh=mesh
	visual_mesh.material_override=mat
	if solid:
		var wall := StaticBody3D.new()
		parent.add_child(wall)
		wall.position=pos
		wall.add_child(visual_mesh)
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size=dimensions
		collider.shape=shape
		wall.add_child(collider)
	else:
		parent.add_child(visual_mesh)
		visual_mesh.position=pos

func pool_material(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color=color
	mat.roughness=roughness
	return mat

func build_pool() -> void:
	var pool := Node3D.new()
	pool.name="WaterTestPool"
	add_child(pool)
	pool.position=POOL_CENTER
	var tiles := ShaderMaterial.new()
	tiles.shader=preload("res://visual/pool_tiles.gdshader")
	tiles.set_shader_parameter("sun_direction",cinematic_sun.global_basis.z.normalized())
	var coping := pool_material(Color(0.76,0.72,0.64),0.76)
	var outer := pool_material(Color(0.47,0.52,0.54),0.87)
	# A shallow raised test basin leaves the original baseplate collision intact.
	pool_box(pool,"TiledFloor",Vector3(0,0.017,0),Vector3(6.0,0.034,4.0),tiles,false)
	for side in [-1.0,1.0]:
		pool_box(pool,"LongWall",Vector3(0,0.19,side*2.14),Vector3(6.56,0.38,0.28),tiles,true)
		pool_box(pool,"ShortWall",Vector3(side*3.14,0.19,0),Vector3(0.28,0.38,4.0),tiles,true)
		pool_box(pool,"LongCoping",Vector3(0,0.39,side*2.14),Vector3(6.64,0.045,0.38),coping,false)
		pool_box(pool,"ShortCoping",Vector3(side*3.14,0.39,0),Vector3(0.38,0.045,4.0),coping,false)
	pool_box(pool,"AccessStep",Vector3(0,0.07,2.62),Vector3(2.2,0.14,0.66),outer,true)
	var plane := PlaneMesh.new()
	plane.size=Vector2(6.0,4.0)
	plane.subdivide_width=96
	plane.subdivide_depth=64
	water_surface=MeshInstance3D.new()
	water_surface.name="InteractiveWater"
	water_surface.mesh=plane
	water_surface.position.y=WATER_HEIGHT
	water_surface.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water_mat=ShaderMaterial.new()
	water_mat.shader=preload("res://visual/water_safe.gdshader")
	water_mat.set_shader_parameter("sun_direction",cinematic_sun.global_basis.z.normalized())
	water_surface.material_override=water_mat
	pool.add_child(water_surface)
	var sign_label := Label3D.new()
	sign_label.text="WATER LAB"
	sign_label.font_size=50
	sign_label.pixel_size=0.006
	sign_label.position=Vector3(0,0.65,2.35)
	sign_label.rotation_degrees.y=180
	pool.add_child(sign_label)
	apply_graphics_quality()

func make_player() -> void:
	super.make_player()
	var plane := PlaneMesh.new()
	plane.size=Vector2(1.3,1.3)
	contact_shadow=MeshInstance3D.new()
	contact_shadow.name="SoftContactShadow"
	contact_shadow.mesh=plane
	contact_shadow.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	contact_mat=ShaderMaterial.new()
	contact_mat.shader=preload("res://visual/contact.gdshader")
	contact_shadow.material_override=contact_mat
	add_child(contact_shadow)
	apply_graphics_quality()

func apply_graphics_quality() -> void:
	super.apply_graphics_quality()
	if cinematic_sun!=null:
		cinematic_sun.shadow_bias=0.025
		cinematic_sun.shadow_normal_bias=0.38
		cinematic_sun.shadow_blur=0.85 if graphics_quality==0 else 1.15
		cinematic_sun.directional_shadow_max_distance=24.0 if graphics_quality==0 else 36.0
		cinematic_sun.directional_shadow_split_1=0.12
		cinematic_sun.directional_shadow_split_2=0.30
		cinematic_sun.directional_shadow_split_3=0.60
		# PCSS is available only in Forward+; keep the existing renderer.
		cinematic_sun.light_angular_distance=0.0
	if water_mat!=null:
		water_mat.set_shader_parameter("quality",float(graphics_quality))
	if graphics_label!=null:
		graphics_label.text += " | Piscina: frente-direita"

func _process(dt: float) -> void:
	super._process(dt)
	if body==null or v7_paused: return
	var pos := body.get_global_transform_interpolated().origin
	var in_pool := absf(pos.x-POOL_CENTER.x)<2.95 and absf(pos.z-POOL_CENTER.z)<1.95
	if contact_shadow!=null:
		contact_shadow.visible=not in_pool and absf(pos.x)<49.5 and absf(pos.z)<49.5
		contact_shadow.global_position=Vector3(pos.x,0.012,pos.z)
		var height := maxf(0.0,pos.y)
		contact_mat.set_shader_parameter("strength",0.24*exp(-height*4.5))
		contact_shadow.scale=Vector3.ONE*(1.0+height*0.45)
	if water_mat!=null:
		ripple_age+=dt
		ripple_clock+=dt
		var point := Vector2(pos.x,pos.z)
		if in_pool and pos.y<WATER_HEIGHT+0.15 and (point.distance_to(last_ripple)>0.32 or ripple_age>0.65 and horizontal_velocity().length()>0.2):
			ripple_origin=point
			ripple_age=0.0
			last_ripple=point
			ripple_slots[ripple_cursor]=Vector4(point.x,point.y,ripple_clock,clampf(horizontal_velocity().length()*0.23+0.45,0.45,1.0))
			ripple_cursor=(ripple_cursor+1)%4
		water_mat.set_shader_parameter("ripple_clock",ripple_clock)
		for i in range(4):
			water_mat.set_shader_parameter("ripple_"+str(i),ripple_slots[i])

func _ready() -> void:
	super._ready()
	if "--smoke-test" in OS.get_cmdline_user_args(): return
	if "--startup-test" in OS.get_cmdline_user_args():
		for i in range(40):
			await get_tree().process_frame
		var ok := is_instance_valid(camera) and is_instance_valid(water_surface) and ready_ok
		print("WINDOW_STARTUP_OK=",ok," RENDERER=",RenderingServer.get_current_rendering_method())
		get_tree().quit(0 if ok else 1)

func load_settings() -> void:
	super.load_settings()
	# Start conservatively each launch; user can raise quality from ESC.
	graphics_quality=0
