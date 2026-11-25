extends "res://movement.gd"

var cinematic_environment: Environment
var cinematic_sun: DirectionalLight3D
var cloud_material: ShaderMaterial
var concrete_material: ShaderMaterial
var graphics_label: Label
var graphics_quality := 1
var pause_layer: CanvasLayer
var pause_panel: Control
var sensitivity := 1.0
var camera_fov := 73.0
var fps_display := true
var fps_label: Label
var quality_option: OptionButton
var fps_option: OptionButton
var menu_open := false
var fps_cap := 60
var menu_path := "user://settings.cfg"

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
	load_settings()
	camera.fov = camera_fov
	var overlay := CanvasLayer.new()
	add_child(overlay)
	graphics_label = Label.new()
	graphics_label.position = Vector2(14,36)
	graphics_label.add_theme_font_size_override("font_size",13)
	graphics_label.add_theme_color_override("font_shadow_color",Color(0.06,0.08,0.11,0.85))
	graphics_label.add_theme_constant_override("shadow_offset_x",1)
	graphics_label.add_theme_constant_override("shadow_offset_y",1)
	overlay.add_child(graphics_label)
	fps_label = Label.new()
	fps_label.position = Vector2(14,58)
	overlay.add_child(fps_label)
	build_settings_menu()
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
		graphics_label.text = "Esc  Configuracoes | F6  Graficos: "+["Leve","Equilibrado","Alto"][graphics_quality]+"  |  Sol fixo / nuvens animadas"

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(menu_path)==OK:
		graphics_quality = clampi(int(config.get_value("graphics","quality",1)),0,2)
		sensitivity = clampf(float(config.get_value("controls","sensitivity",1.0)),0.25,2.5)
		camera_fov = clampf(float(config.get_value("camera","fov",73.0)),55.0,95.0)
		fps_display = bool(config.get_value("graphics","fps_display",true))
		fps_cap = int(config.get_value("graphics","fps_cap",60))
	Engine.max_fps = fps_cap

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("graphics","quality",graphics_quality)
	config.set_value("graphics","fps_display",fps_display)
	config.set_value("graphics","fps_cap",fps_cap)
	config.set_value("controls","sensitivity",sensitivity)
	config.set_value("camera","fov",camera_fov)
	config.save(menu_path)

func menu_button(text_value: String, parent: Control) -> Button:
	var btn := Button.new()
	btn.text = text_value
	btn.custom_minimum_size.y = 42
	parent.add_child(btn)
	return btn

func menu_label(text_value: String, parent: Control) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size",15)
	parent.add_child(label)
	return label

func build_settings_menu() -> void:
	pause_layer = CanvasLayer.new()
	pause_layer.layer = 50
	add_child(pause_layer)
	pause_panel = Control.new()
	pause_layer.add_child(pause_panel)
	pause_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.025,0.035,0.05,0.88)
	pause_panel.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	pause_panel.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(460,0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055,0.075,0.095,1.0)
	style.border_color = Color(0.20,0.32,0.40)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	card.add_theme_stylebox_override("panel",style)
	center.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",9)
	card.add_child(column)
	var header := menu_label("Y BOT  /  CONFIGURACOES",column)
	header.add_theme_font_size_override("font_size",25)
	menu_label("Jogo pausado  •  ESC para voltar",column)
	menu_label("QUALIDADE GRAFICA",column)
	quality_option = OptionButton.new()
	for preset in ["Leve","Equilibrado","Alto"]: quality_option.add_item(preset)
	column.add_child(quality_option)
	quality_option.select(graphics_quality)
	quality_option.item_selected.connect(func(index: int): graphics_quality=index; apply_graphics_quality(); save_settings())
	menu_label("LIMITE DE FPS",column)
	fps_option = OptionButton.new()
	for cap in [30,45,60,120,0]: fps_option.add_item("Sem limite" if cap==0 else str(cap)+" FPS",cap)
	column.add_child(fps_option)
	fps_option.select(maxi(0,fps_option.get_item_index(fps_cap)))
	fps_option.item_selected.connect(func(index: int): fps_cap=fps_option.get_item_id(index); Engine.max_fps=fps_cap; save_settings())
	var sens_label := menu_label("SENSIBILIDADE DO MOUSE  "+str(snappedf(sensitivity,0.05)),column)
	var sens := HSlider.new()
	sens.min_value=0.25
	sens.max_value=2.5
	sens.step=0.05
	sens.value=sensitivity
	column.add_child(sens)
	sens.value_changed.connect(func(value: float): sensitivity=value; sens_label.text="SENSIBILIDADE DO MOUSE  "+str(value); save_settings())
	var fov_label := menu_label("CAMPO DE VISAO  "+str(int(camera_fov)),column)
	var fov_slider := HSlider.new()
	fov_slider.min_value=55
	fov_slider.max_value=95
	fov_slider.step=1
	fov_slider.value=camera_fov
	column.add_child(fov_slider)
	fov_slider.value_changed.connect(func(value: float): camera_fov=value; camera.fov=value; fov_label.text="CAMPO DE VISAO  "+str(int(value)); save_settings())
	var fps_check := CheckButton.new()
	fps_check.text="Mostrar contador de FPS"
	fps_check.button_pressed=fps_display
	column.add_child(fps_check)
	fps_check.toggled.connect(func(value: bool): fps_display=value; save_settings())
	var resume := menu_button("Continuar jogo",column)
	resume.pressed.connect(func(): toggle_menu(false))
	var quit := menu_button("Sair do jogo",column)
	quit.pressed.connect(func(): save_settings(); get_tree().quit())
	pause_panel.hide()

func toggle_menu(open: bool) -> void:
	if pause_panel == null: return
	menu_open = open
	v7_paused = open
	pause_panel.visible = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	if open:
		quality_option.grab_focus()
	else:
		jump_buffer = 0.0
		jump_was_pressed = Input.is_physical_key_pressed(KEY_SPACE)
	save_settings()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
		toggle_menu(not menu_open)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if menu_open: return
	if event is InputEventMouseMotion and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x*0.003*sensitivity
		pitch = clampf(pitch-event.relative.y*0.003*sensitivity,-1.05,0.30)
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F6:
		graphics_quality = (graphics_quality+1)%3
		apply_graphics_quality()
		if quality_option != null: quality_option.select(graphics_quality)
		save_settings()
		return
	super._unhandled_input(event)

func _process(dt: float) -> void:
	super._process(dt)
	if fps_label != null:
		fps_label.visible = fps_display
		fps_label.text = str(Engine.get_frames_per_second())+" FPS"
