extends "res://main.gd"
const MAP = {"spine":"Spine1","spine1":"Spine2","spine2":"Chest","neck":"Neck2","leftupleg":"LeftLeg","leftleg":"LeftShin","rightupleg":"RightLeg","rightleg":"RightShin"}
var clips: Array[String] = []
var panel: PanelContainer
var chooser: OptionButton
var preview := false
var crouch := false
var crawl := false
var action_left := 0.0
var speeds := {}

func _ready() -> void:
	make_world()
	make_player()
	if skeleton == null:
		get_tree().quit(1)
		return
	if ResourceLoader.exists("res://assets/idle.fbx"):
		import_clip(load("res://assets/idle.fbx") as PackedScene,"standard_idle",true)
	for item in FileAccess.get_file_as_string("res://assets/motion/index.txt").split("\n",false):
		var clip_name: String = item.strip_edges()
		if load_motion(clip_name):
			clips.append(clip_name)
	ready_ok = clips.size() == 45
	print("MOTIFECT_COUNT=",clips.size())
	if "--smoke-test" in OS.get_cmdline_user_args():
		get_tree().quit(0 if ready_ok else 1)
		return
	if not ready_ok:
		push_error("Expected all 45 Motifect clips")
		return
	make_menu()
	play_clip("idle_neutral",0.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func load_motion(clip_name: String) -> bool:
	var path := "res://assets/motion/" + clip_name + ".bvh"
	if not FileAccess.file_exists(path): return false
	var names: Array[String] = []
	var parents: Array[int] = []
	var starts: Array[int] = []
	var counts: Array[int] = []
	var stack: Array[int] = []
	var pending := -1
	var columns := 0
	var frames: Array[PackedFloat32Array] = []
	var dt := 1.0/30.0
	var in_motion := false
	for raw in FileAccess.get_file_as_string(path).split("\n",false):
		var line: String = raw.strip_edges()
		if line.begins_with("ROOT ") or line.begins_with("JOINT "):
			pending = names.size()
			names.append(line.get_slice(" ",1))
			parents.append(int(stack.back()) if not stack.is_empty() else -1)
			starts.append(0)
			counts.append(0)
		elif line == "End Site": pending = -1
		elif line == "{": stack.append(pending)
		elif line == "}":
			if not stack.is_empty(): stack.pop_back()
		elif line.begins_with("CHANNELS ") and not stack.is_empty() and int(stack.back()) >= 0:
			var idx: int = stack.back()
			var count := int(line.get_slice(" ",1))
			starts[idx] = columns
			counts[idx] = count
			columns += count
		elif line.begins_with("Frame Time:"):
			dt = float(line.get_slice(":",1))
			in_motion = true
		elif in_motion and not line.is_empty():
			var f := line.split_floats(" ",false)
			if f.size() == columns: frames.append(f)
	if names.is_empty() or frames.size() < 2 or dt <= 0: return false
	var clip := Animation.new()
	clip.length = (frames.size()-1)*dt
	var loop := clip_name.begins_with("idle_") or clip_name.begins_with("walk_") or clip_name.begins_with("run_") or clip_name.begins_with("crawl_") or clip_name == "army_crawl" or clip_name == "crouch_idle" or clip_name.begins_with("crouch_walk") or clip_name == "tiptoe_walk" or clip_name.begins_with("climb_stairs")
	clip.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var n := skeleton.get_bone_count()
	var indices: Array[int] = []
	var tracks: Array[int] = []
	var rests: Array[Quaternion] = []
	var globals: Array[Quaternion] = []
	var sp := str(model.get_path_to(skeleton))
	var hip := -1
	var foot := -1
	for i in range(n):
		var bone := str(skeleton.get_bone_name(i))
		var key := bone.to_lower().replace("mixamorig","").replace(":","").replace("_","")
		var src := -1
		if MAP.has(key): src = names.find(str(MAP[key]))
		else:
			for j in range(names.size()):
				if names[j].to_lower() == key:
					src = j
					break
		indices.append(src)
		if key == "hips": hip = i
		if key == "leftfoot": foot = i
		rests.append(skeleton.get_bone_global_rest(i).basis.orthonormalized().get_rotation_quaternion())
		globals.append(Quaternion.IDENTITY)
		var track := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(track,NodePath(sp+":"+bone))
		tracks.append(track)
	if hip < 0 or foot < 0: return false
	var h := absf(skeleton.get_bone_global_rest(hip).origin.y-skeleton.get_bone_global_rest(foot).origin.y)
	var rest_pos := skeleton.get_bone_rest(hip).origin
	var pt := clip.add_track(Animation.TYPE_POSITION_3D)
	clip.track_set_path(pt,NodePath(sp+":"+str(skeleton.get_bone_name(hip))))
	var source_globals: Array[Quaternion] = []
	source_globals.resize(names.size())
	speeds[clip_name] = maxf(0.1,Vector2(frames[-1][0]-frames[0][0],frames[-1][2]-frames[0][2]).length()*0.01/clip.length)
	for k in range(0,frames.size(),2):
		var f := frames[k]
		for j in range(names.size()):
			var off := starts[j]+(3 if counts[j] == 6 else 0)
			var q := Quaternion.IDENTITY
			if counts[j] >= 3:
				q = Quaternion(Vector3.BACK,deg_to_rad(f[off]))*Quaternion(Vector3.UP,deg_to_rad(f[off+1]))*Quaternion(Vector3.RIGHT,deg_to_rad(f[off+2]))
			source_globals[j] = q if parents[j] < 0 else source_globals[parents[j]]*q
		for i in range(n):
			var par := skeleton.get_bone_parent(i)
			var local := skeleton.get_bone_rest(i).basis.orthonormalized().get_rotation_quaternion()
			var src := indices[i]
			if src >= 0:
				globals[i] = (source_globals[src]*rests[i]).normalized()
				local = globals[i] if par < 0 else (globals[par].inverse()*globals[i]).normalized()
			else: globals[i] = local if par < 0 else globals[par]*local
			clip.rotation_track_insert_key(tracks[i],k*dt,local)
		var lift := (f[1]-100.0)*h/90.0
		if clip_name.begins_with("jump_"): lift = minf(lift,0.06*h)
		var offset := Vector3(0,lift,0)
		var hip_parent := skeleton.get_bone_parent(hip)
		if hip_parent >= 0: offset = skeleton.get_bone_global_rest(hip_parent).basis.inverse()*offset
		clip.position_track_insert_key(pt,k*dt,rest_pos+offset)
	return library.add_animation(clip_name,clip)==OK

func make_menu() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var hint := Label.new()
	hint.text = "C Agachar | X Rastejar | Alt Ponta dos pes | Q Rolar | F1 Animacoes"
	hint.position = Vector2(14,35)
	layer.add_child(hint)
	panel = PanelContainer.new()
	panel.position = Vector2(20,65)
	panel.custom_minimum_size = Vector2(320,0)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	chooser = OptionButton.new()
	box.add_child(chooser)
	for clip_name in clips: chooser.add_item(clip_name)
	if library.has_animation("standard_idle"): chooser.add_item("standard_idle")
	chooser.select(0)
	chooser.item_selected.connect(func(i: int): show_motion(chooser.get_item_text(i)))
	var replay := Button.new()
	replay.text = "Reproduzir novamente"
	box.add_child(replay)
	replay.pressed.connect(func(): show_motion(chooser.get_item_text(chooser.selected)))
	panel.hide()

func show_motion(clip_name: String) -> void:
	current = clip_name
	animator.speed_scale = 1.0
	animator.stop()
	animator.play(clip_name,0.15)

func play_clip(clip_name: String,blend: float = 0.16) -> void:
	if current != clip_name and library.has_animation(clip_name):
		current = clip_name
		animator.play(clip_name,blend)

func _unhandled_input(event: InputEvent) -> void:
	if not ready_ok: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			preview = not preview
			panel.visible = preview
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if preview else Input.MOUSE_MODE_CAPTURED
			body.velocity = Vector3.ZERO
			if preview: show_motion(chooser.get_item_text(chooser.selected))
			else: current = ""
			return
		if not preview and event.keycode == KEY_C:
			crouch = not crouch
			crawl = false
		if not preview and event.keycode == KEY_X:
			crawl = not crawl
			crouch = false
		if not preview and event.keycode == KEY_Q and body.is_on_floor() and action_left <= 0:
			play_clip("roll_forward",0.12)
			animator.speed_scale = 2.5
			action_left = 1.6
	if not preview: super._unhandled_input(event)

func _physics_process(delta: float) -> void:
	if not ready_ok or preview: return
	var x := float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A))
	var z := float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W))
	var input_dir := Vector3(x,0,z).limit_length(1.0)
	var moving := input_dir.length_squared()>0.01
	var run := Input.is_physical_key_pressed(KEY_SHIFT) and not crouch and not crawl
	var clip_name := "idle_neutral"
	if crawl: clip_name = "crawl_forward" if moving else "crouch_idle"
	elif crouch: clip_name = ("crouch_walk_backward" if z>0 else "crouch_walk_forward") if moving else "crouch_idle"
	elif moving:
		if Input.is_physical_key_pressed(KEY_ALT): clip_name = "tiptoe_walk"
		elif absf(x)>absf(z): clip_name = ("run_" if run else "walk_")+("strafe_left" if x<0 else "strafe_right")
		elif z>0: clip_name = "run_backward" if run else "walk_backward"
		else: clip_name = "run_sprint" if run else "walk_forward"
	var speed := clampf(float(speeds.get(clip_name,1.3)),0.35,3.8)
	var ground := body.is_on_floor()
	var target := input_dir.rotated(Vector3.UP,yaw)*speed
	var planar := Vector3(body.velocity.x,0,body.velocity.z)
	var pressed := Input.is_physical_key_pressed(KEY_SPACE)
	if ground and pressed and not jump_was_pressed and action_left<=0 and not crouch and not crawl:
		body.velocity.y = 3.4
		play_clip("jump_running" if run else "jump_standing",0.12)
		animator.speed_scale = 3.5
		action_left = 0.75
	jump_was_pressed = pressed
	if action_left>0:
		action_left = maxf(0,action_left-delta)
		if current == "roll_forward": target = Vector3(0,0,1).rotated(Vector3.UP,pivot.rotation.y)*1.7
	elif ground:
		play_clip(clip_name,0.18)
		animator.speed_scale = clampf(planar.length()/speed,0.65,1.2) if moving else 1.0
	planar = planar.move_toward(target,(7.0 if ground else 1.5)*delta)
	body.velocity.x = planar.x
	body.velocity.z = planar.z
	if moving: pivot.rotation.y = lerp_angle(pivot.rotation.y,yaw+PI,1.0-exp(-9.0*delta))
	if not ground: body.velocity.y -= 9.81*delta
	body.move_and_slide()
	if body.position.y < -8.0:
		body.position = Vector3(0,0.05,0)
		body.velocity = Vector3.ZERO
		action_left = 0.0
