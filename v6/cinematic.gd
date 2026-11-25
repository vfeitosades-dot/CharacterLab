extends "res://movement.gd"

var cinematic_environment: Environment
var cinematic_sun: DirectionalLight3D
var cloud_material: ShaderMaterial
var concrete_material: ShaderMaterial
var graphics_label: Label
var graphics_quality := 1

func make_world() -> void:
	super.make_world()
	for child in get_children():
		if child is WorldEnvironment:
			cinematic_environment = child.environment
		elif child is DirectionalLight3D:
			cinematic_sun = child
		elif child is StaticBody3D:
			for surface in child.get_children():
				if surface is MeshInstance3D:
					concrete_material = ShaderMaterial.new()
					concrete_material.shader = preload("res://visual/concrete.gdshader")
					surface.material_override = concrete_material
	if cinematic_environment == null or cinematic_sun == null:
		push_error("Visual environment missing")
		return
	var sky := Sky.new()
	var atmosphere := ProceduralSkyMaterial.new()
	atmosphere.sky_top_color = Color(0.18,0.43,0.73)
	atmosphere.sky_horizon_color = Color(0.78,0.87,0.94)
	atmosphere.sky_curve = 0.22
	atmosphere.ground_bottom_color = Color(0.37,0.43,0.47)
	atmosphere.ground_horizon_color = Color(0.78,0.87,0.94)
	atmosphere.ground_curve = 0.16
	atmosphere.sun_angle_max = 13.0
	atmosphere.sun_curve = 0.12
	sky.sky_material = atmosphere
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	cinematic_environment.background_mode = Environment.BG_SKY
	cinematic_environment.sky = sky
	cinematic_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	cinematic_environment.ambient_light_color = Color(0.68,0.80,1.0)
	cinematic_environment.ambient_light_energy = 0.66
	cinematic_environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	cinematic_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	cinematic_environment.tonemap_exposure = 1.05
	cinematic_environment.tonemap_white = 4.0
	cinematic_environment.adjustment_enabled = true
	cinematic_environment.adjustment_saturation = 1.05
	cinematic_environment.adjustment_contrast = 1.03
	cinematic_environment.fog_enabled = true
	cinematic_environment.fog_light_color = Color(0.77,0.85,0.93)
	cinematic_environment.fog_density = 0.002
	cinematic_environment.fog_sun_scatter = 0.18
	cinematic_environment.fog_sky_affect = 0.0
	cinematic_sun.rotation_degrees = Vector3(-37,-48,0)
	cinematic_sun.light_color = Color(1.0,0.89,0.73)
	cinematic_sun.light_energy = 1.65
	cinematic_sun.shadow_enabled = true
	cinematic_sun.shadow_bias = 0.035
	cinematic_sun.shadow_normal_bias = 0.8
	cinematic_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	cinematic_sun.directional_shadow_max_distance = 45.0
	cinematic_sun.directional_shadow_split_1 = 0.08
	cinematic_sun.directional_shadow_split_2 = 0.22
	cinematic_sun.directional_shadow_split_3 = 0.48
	cinematic_sun.directional_shadow_blend_splits = true
	cinematic_sun.shadow_blur = 1.25
	var cloud_dome := MeshInstance3D.new()
	cloud_dome.name = "MovingCloudsAndSunHalo"
	var sphere := SphereMesh.new()
	sphere.radius = 350.0
	sphere.height = 700.0
	sphere.radial_segments = 48
	sphere.rings = 24
	cloud_dome.mesh = sphere
	cloud_dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cloud_material = ShaderMaterial.new()
	cloud_material.shader = preload("res://visual/clouds.gdshader")
	cloud_material.set_shader_parameter("sun_direction",cinematic_sun.global_basis.z.normalized())
	cloud_dome.material_override = cloud_material
	add_child(cloud_dome)
	apply_graphics_quality()

func make_player() -> void:
	super.make_player()
	camera.far = 1100.0
	camera.fov = 73.0
	var overlay := CanvasLayer.new()
	add_child(overlay)
	graphics_label = Label.new()
	graphics_label.position = Vector2(14,36)
	graphics_label.add_theme_font_size_override("font_size",13)
	graphics_label.add_theme_color_override("font_shadow_color",Color(0.06,0.08,0.11,0.85))
	graphics_label.add_theme_constant_override("shadow_offset_x",1)
	graphics_label.add_theme_constant_override("shadow_offset_y",1)
	overlay.add_child(graphics_label)
	apply_graphics_quality()

func apply_graphics_quality() -> void:
	if cinematic_environment == null or cinematic_sun == null: return
	var high := graphics_quality == 2
	var low := graphics_quality == 0
	cinematic_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if low else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	cinematic_sun.directional_shadow_max_distance = 24.0 if low else (65.0 if high else 45.0)
	cinematic_environment.glow_enabled = not low
	cinematic_environment.glow_intensity = 0.23
	cinematic_environment.glow_hdr_threshold = 1.2
	get_viewport().msaa_3d = Viewport.MSAA_2X if high else Viewport.MSAA_DISABLED
	if cloud_material != null:
		cloud_material.set_shader_parameter("detail_quality",0.0 if low else (1.0 if high else 0.65))
	if concrete_material != null:
		concrete_material.set_shader_parameter("detail_quality",0.0 if low else 1.0)
	if graphics_label != null:
		graphics_label.text = "F6  Graficos: "+["Leve","Equilibrado","Alto"][graphics_quality]+"  |  Sol fixo / nuvens animadas"

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F6:
		graphics_quality = (graphics_quality+1)%3
		apply_graphics_quality()
		return
	super._unhandled_input(event)
