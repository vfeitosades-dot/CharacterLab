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
const NX := 64
const NZ := 44
var wave_now := PackedFloat32Array()
var wave_old := PackedFloat32Array()
var wave_next := PackedFloat32Array()
var height_image: Image
var height_texture: ImageTexture
var reflection_view: SubViewport
var reflection_camera: Camera3D
var reflection_tick := 0.0
var previous_pool_pos := Vector2(1000,1000)
var was_in_water := false
var water_tick := 0.0
var water_test := false

func init_water_simulation() -> void:
	wave_now.resize(NX*NZ)
	wave_old.resize(NX*NZ)
	wave_next.resize(NX*NZ)
	height_image=Image.create(NX,NZ,false,Image.FORMAT_RF)
	height_image.fill(Color(0.5,0,0,1))
	height_texture=ImageTexture.create_from_image(height_image)
	water_mat.set_shader_parameter("height_field",height_texture)

func disturb_water(p: Vector2, strength: float) -> void:
	var u := (p.x-POOL_CENTER.x+3.0)/6.0
	var v := (p.y-POOL_CENTER.z+2.0)/4.0
	var cx := clampi(roundi(u*float(NX-1)),2,NX-3)
	var cz := clampi(roundi(v*float(NZ-1)),2,NZ-3)
	for z in range(cz-2,cz+3):
		for x in range(cx-2,cx+3):
			var d := Vector2(x-cx,z-cz).length_squared()
			wave_now[z*NX+x]+=strength*exp(-d*0.38)

func step_water() -> void:
	# Damped finite-difference shallow-surface wave equation, reflective boundaries.
	for z in range(1,NZ-1):
		for x in range(1,NX-1):
			var i := z*NX+x
			var c := wave_now[i]
			var lap := wave_now[i-1]+wave_now[i+1]+wave_now[i-NX]+wave_now[i+NX]-4.0*c
			wave_next[i]=clampf((2.0*c-wave_old[i]+0.12*lap)*0.986,-0.045,0.045)
	for z in range(1,NZ-1):
		wave_next[z*NX]=wave_next[z*NX+1]*0.96
		wave_next[z*NX+NX-1]=wave_next[z*NX+NX-2]*0.96
	for x in range(NX):
		wave_next[x]=wave_next[NX+x]*0.96
		wave_next[(NZ-1)*NX+x]=wave_next[(NZ-2)*NX+x]*0.96
	var temp := wave_old
	wave_old=wave_now
	wave_now=wave_next
	wave_next=temp

func upload_water() -> void:
	for z in range(NZ):
		for x in range(NX):
			height_image.set_pixel(x,z,Color(0.5+wave_now[z*NX+x]*8.0,0,0,1))
	height_texture.update(height_image)

func hide_from_reflection(node: Node) -> void:
	if node is VisualInstance3D:
		node.layers=2
	for child in node.get_children():
		hide_from_reflection(child)

func setup_reflection() -> void:
	reflection_view=SubViewport.new()
	reflection_view.name="PlanarReflection"
	reflection_view.own_world_3d=false
	reflection_view.world_3d=get_viewport().world_3d
	reflection_view.size=Vector2i(480,270)
	reflection_view.render_target_update_mode=SubViewport.UPDATE_DISABLED
	add_child(reflection_view)
	reflection_camera=Camera3D.new()
	reflection_camera.cull_mask=1
	reflection_camera.near=0.05
	reflection_camera.far=900.0
	reflection_view.add_child(reflection_camera)
	reflection_camera.current=true
	water_mat.set_shader_parameter("planar_reflection",reflection_view.get_texture())

func refresh_reflection(dt: float) -> void:
	if reflection_view==null or camera==null: return
	var near_pool := camera.global_position.distance_to(POOL_CENTER)<25.0
	if not near_pool:
		reflection_view.render_target_update_mode=SubViewport.UPDATE_DISABLED
		water_mat.set_shader_parameter("reflection_available",false)
		return
	reflection_tick+=dt
	if reflection_tick<0.05 and not water_test: return
	reflection_tick=0.0
	var sz := get_viewport().get_visible_rect().size
	var width := 384 if graphics_quality==0 else (640 if graphics_quality==1 else 960)
	var desired := Vector2i(width,maxi(1,roundi(float(width)*sz.y/maxf(sz.x,1.0))))
	if reflection_view.size!=desired: reflection_view.size=desired
	var pos := camera.global_position
	pos.y=2.0*WATER_HEIGHT-pos.y
	var direction := -camera.global_basis.z
	direction.y=-direction.y
	var up := camera.global_basis.y
	up.y=-up.y
	reflection_camera.global_position=pos
	reflection_camera.look_at(pos+direction,-up)
	reflection_camera.fov=camera.fov
	reflection_camera.keep_aspect=camera.keep_aspect
	reflection_view.render_target_update_mode=SubViewport.UPDATE_ONCE
	water_mat.set_shader_parameter("reflection_available",true)
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
	water_mat.shader=preload("res://visual/water_liquid.gdshader")
	water_mat.set_shader_parameter("sun_direction",cinematic_sun.global_basis.z.normalized())
	water_surface.material_override=water_mat
	pool.add_child(water_surface)
	water_mat.render_priority=2
	init_water_simulation()
	var sign_label := Label3D.new()
	sign_label.text="WATER LAB"
	sign_label.font_size=50
	sign_label.pixel_size=0.006
	sign_label.position=Vector3(0,0.65,2.35)
	sign_label.rotation_degrees.y=180
	pool.add_child(sign_label)
	hide_from_reflection(pool)
	for child in get_children():
		if child is StaticBody3D: hide_from_reflection(child)
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
	contact_shadow.layers=2
	setup_reflection()
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
		refresh_reflection(dt)
		var water_point := Vector2(pos.x,pos.z)
		var wet := in_pool and pos.y<WATER_HEIGHT+0.1
		if wet and (not was_in_water or water_point.distance_to(previous_pool_pos)>0.23):
			disturb_water(water_point,0.018 if not was_in_water else 0.008)
			previous_pool_pos=water_point
		was_in_water=wet
		water_tick+=minf(dt,0.05)
		var steps := 0
		while water_tick>=1.0/60.0 and steps<3:
			step_water()
			water_tick-=1.0/60.0
			steps+=1
		if steps>0: upload_water()
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
		water_test=true
		body.position=POOL_CENTER+Vector3(0,0,3.0)
		body.reset_physics_interpolation()
		camera_ready=false
		yaw=0.0
		pitch=-0.35
		disturb_water(Vector2(POOL_CENTER.x,POOL_CENTER.z),0.02)
		for i in range(45):
			await get_tree().process_frame
		var ok := is_instance_valid(camera) and is_instance_valid(water_surface) and is_instance_valid(reflection_camera) and ready_ok
		print("LIQUID_WAVE_TEST=",wave_now.size()," REFLECTION_VIEW=",reflection_view.size)
		var shot := get_viewport().get_texture().get_image()
		if not shot.is_empty(): shot.save_png("user://water-preview.png")
		print("WINDOW_STARTUP_OK=",ok," RENDERER=",RenderingServer.get_current_rendering_method())
		get_tree().quit(0 if ok else 1)

func load_settings() -> void:
	super.load_settings()
	# Start conservatively each launch; user can raise quality from ESC.
	graphics_quality=0
