extends Node3D

const MODEL = preload("res://assets/character.glb")
var player: CharacterBody3D
var visual: Node3D
var pivot: Node3D
var camera: Camera3D
var anim: AnimationPlayer
var yaw := 0.0
var pitch := -0.16
var current := ""
var hud: Label
var zoom := 4.5
var was_grounded := false
var land_time := 0.0
var jump_was_down := false

func _ready() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("718eac")
	sky_mat.sky_horizon_color = Color("dce3e7")
	sky_mat.ground_bottom_color = Color("757d86")
	sky_mat.ground_horizon_color = Color("dce3e7")
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d7e5f3")
	env.ambient_light_energy = 0.75
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 35.0
	add_child(sun)
	var ground := StaticBody3D.new()
	ground.position.y = -0.15
	add_child(ground)
	var slab := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(100, 0.3, 100)
	slab.mesh = box
	var mat := ShaderMaterial.new()
	mat.shader = load("res://grid.gdshader")
	slab.material_override = mat
	ground.add_child(slab)
	var ground_col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	ground_col.shape = shape
	ground.add_child(ground_col)
	player = CharacterBody3D.new()
	player.floor_snap_length = 0.25
	player.position = Vector3(0, 0.03, 0)
	add_child(player)
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = 0.29
	var col := CollisionShape3D.new()
	col.shape = capsule
	col.position.y = 0.9
	player.add_child(col)
	visual = Node3D.new()
	player.add_child(visual)
	var model := MODEL.instantiate()
	visual.add_child(model)
	anim = find_anim(model)
	if anim:
		for a in anim.get_animation_list():
			if String(a).get_file() in ["Idle", "Walk", "Run", "Fall"]:
				anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		set_anim("Idle", 1.0)
	pivot = Node3D.new()
	add_child(pivot)
	pivot.position = player.position + Vector3(0, 1.45, 0)
	camera = Camera3D.new()
	camera.fov = 62
	camera.position = Vector3(0, 0, zoom)
	pivot.add_child(camera)
	camera.current = true
	var ui := CanvasLayer.new()
	add_child(ui)
	hud = Label.new()
	hud.position = Vector2(24, 20)
	hud.add_theme_font_size_override("font_size", 19)
	hud.add_theme_color_override("font_shadow_color", Color(0,0,0,0.8))
	hud.add_theme_constant_override("shadow_offset_x", 1)
	hud.add_theme_constant_override("shadow_offset_y", 2)
	ui.add_child(hud)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := find_anim(child)
		if found:
			return found
	return null

func set_anim(state: String, speed: float) -> void:
	if not anim:
		return
	if current != state:
		for a in anim.get_animation_list():
			if String(a).get_file() == state:
				anim.speed_scale = speed
				anim.play(a, 0.17, 1.0)
				current = state
				return
	else:
		anim.speed_scale = speed

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * 0.003
		pitch = clampf(pitch - event.relative.y * 0.003, -0.8, 0.35)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
		if event.keycode == KEY_R:
			player.position = Vector3(0, 0.1, 0)
			player.velocity = Vector3.ZERO
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = maxf(2.2, zoom - 0.4)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = minf(7.0, zoom + 0.4)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		input.x = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		input.y = float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	input = input.limit_length()
	var direction := Vector3(input.x, 0, input.y).rotated(Vector3.UP, yaw)
	var sprint := Input.is_physical_key_pressed(KEY_SHIFT)
	var jump_down := Input.is_physical_key_pressed(KEY_SPACE) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var jump_pressed := jump_down and not jump_was_down
	jump_was_down = jump_down
	var speed := 4.4 if sprint else 1.8
	var target := direction * speed
	var accel := 14.0 if direction.length() > 0.01 else 19.0
	player.velocity.x = move_toward(player.velocity.x, target.x, accel * delta)
	player.velocity.z = move_toward(player.velocity.z, target.z, accel * delta)
	if player.is_on_floor():
		if jump_pressed:
			player.velocity.y = 4.4
		else:
			player.velocity.y = -0.1
	else:
		player.velocity.y -= 14.0 * delta
	player.move_and_slide()
	if direction.length() > 0.02:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-direction.x, -direction.z), 1.0 - exp(-12.0 * delta))
	var planar := Vector2(player.velocity.x, player.velocity.z).length()
	var grounded := player.is_on_floor()
	if grounded and not was_grounded:
		land_time = 0.22
	was_grounded = grounded
	land_time = maxf(0.0, land_time - delta)
	if not grounded:
		land_time = 0.0
		set_anim("Jump" if player.velocity.y > 0.0 else "Fall", 1.0)
	elif land_time > 0.0:
		set_anim("Land", 1.0)
	elif planar < 0.15:
		set_anim("Idle", 1.0)
	elif planar > 2.45:
		set_anim("Run", clampf(planar / 4.4, 0.65, 1.2))
	else:
		set_anim("Walk", clampf(planar / 1.8, 0.45, 1.35))
	pivot.position = pivot.position.lerp(player.position + Vector3(0, 1.45, 0), 1.0 - exp(-16.0 * delta))
	pivot.rotation = Vector3(pitch, yaw, 0)
	camera.position.z = lerpf(camera.position.z, zoom, 1.0 - exp(-10.0 * delta))
	if player.position.y < -8:
		player.position = Vector3(0, 0.1, 0)
		player.velocity = Vector3.ZERO
	hud.text = "CHARACTER LAB  |  %s  |  %d FPS\nWASD mover   SHIFT correr   ESPACO pular\nMouse camera   Scroll zoom   R reiniciar   ESC cursor" % [current, Engine.get_frames_per_second()]
