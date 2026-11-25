extends "res://main.gd"

# Continuous speed blending and independent stride rates. No third-party BVH.
var motion_tree: AnimationTree
var playback: AnimationNodeStateMachinePlayback
var accel_vector := Vector3.ZERO
var camera_focus := Vector3.ZERO
var camera_ready := false
var walk_weight := 0.0
var run_weight := 0.0
var walk_rate := 1.0
var run_rate := 1.0
var visual_turn_rate := 0.0
var takeoff_speed := 0.0
var airborne_elapsed := 0.0
var recovery_elapsed := 0.0
var active_jump := ""
var jump_phase := 0
var jump_duration := 0.0
var jump_t0 := 0.0
var jump_t1 := 0.0
const V4_WALK := 1.60
const V4_RUN := 4.24
const V4_G := 9.81
const STAND_PREP := 0.17
const STAND_FLIGHT := 0.59
var sole_probes: Array[Dictionary] = []
var floor_lift := 0.0
var v7_testing := false
var v7_test_stick := Vector3.ZERO
var v7_test_run := false
var v7_test_jump := false
var v7_paused := false
var v7_jump_heading := 0.0
var v7_air_velocity := Vector3.ZERO
var v7_turn_sign := 1.0
var v7_turning := false
var v7_speed := 0.0
var walk_cycle_seconds := 1.0
var run_cycle_seconds := 0.7
var gait_rate := 1.0

# Locate a common stride landmark: maximum forward separation of the left foot.
func stride_anchor(clip_name: String) -> float:
	var left := -1
	var right := -1
	for i in range(skeleton.get_bone_count()):
		var n := str(skeleton.get_bone_name(i)).to_lower().replace("_","").replace(":","")
		if n.ends_with("leftfoot"): left=i
		if n.ends_with("rightfoot"): right=i
	if left<0 or right<0: return 0.0
	var clip := library.get_animation(clip_name)
	animator.play(clip_name)
	var best := -INF
	var anchor := 0.0
	for i in range(48):
		var t := clip.length*float(i)/48.0
		animator.seek(t,true)
		var l := skeleton.get_bone_global_pose(left).origin
		var r := skeleton.get_bone_global_pose(right).origin
		var separation := (skeleton.global_basis*(l-r)).dot(pivot.global_basis.z.normalized())
		if separation>best:
			best=separation
			anchor=t
	animator.stop()
	return anchor

# Resample skeletal tracks into equal one-second cycles in the same foot phase.
func synchronize_gait(clip_name: String, anchor: float) -> void:
	var original := library.get_animation(clip_name)
	var result := original.duplicate() as Animation
	var duration := original.length
	result.length=1.0
	for track in range(original.get_track_count()):
		var kind := original.track_get_type(track)
		if kind not in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D]:
			continue
		if original.track_get_key_count(track)==0: continue
		for key in range(result.track_get_key_count(track)-1,-1,-1):
			result.track_remove_key(track,key)
		for sample in range(61):
			var phase := float(sample)/60.0
			var t := fposmod(anchor+duration*phase,duration)
			var value: Variant
			match kind:
				Animation.TYPE_POSITION_3D: value=original.position_track_interpolate(track,t)
				Animation.TYPE_ROTATION_3D: value=original.rotation_track_interpolate(track,t)
				Animation.TYPE_SCALE_3D: value=original.scale_track_interpolate(track,t)
			result.track_insert_key(track,phase,value)
		result.track_set_interpolation_type(track,Animation.INTERPOLATION_LINEAR)
		result.track_set_interpolation_loop_wrap(track,true)
	result.loop_mode=Animation.LOOP_LINEAR
	library.remove_animation(clip_name)
	library.add_animation(clip_name,result)

func prepare_gait_cycles() -> void:
	walk_cycle_seconds=library.get_animation("walk").length
	run_cycle_seconds=library.get_animation("run").length
	var a := stride_anchor("walk")
	var b := stride_anchor("run")
	synchronize_gait("walk",a)
	synchronize_gait("run",b)
	print("GAIT_SYNC walk=",walk_cycle_seconds," run=",run_cycle_seconds," anchors=",a,",",b)

# Build heel, ball and toe contact points in each bone's rest space.
# The baseplate top is y=0 and the body's origin is at the sole plane.
func setup_sole_probes() -> void:
	sole_probes.clear()
	for side in ["left","right"]:
		var foot_id := -1
		var toe_id := -1
		for i in range(skeleton.get_bone_count()):
			var b := str(skeleton.get_bone_name(i)).to_lower().replace("_","").replace(":","")
			if b.ends_with(side+"foot"): foot_id = i
			elif b.ends_with(side+"toebase"): toe_id = i
		if foot_id < 0: continue
		var foot_rest := skeleton.global_transform * skeleton.get_bone_global_rest(foot_id)
		var toe_rest := foot_rest
		if toe_id >= 0:
			toe_rest = skeleton.global_transform * skeleton.get_bone_global_rest(toe_id)
		var forward := toe_rest.origin-foot_rest.origin
		forward.y = 0.0
		if forward.length() < 0.015:
			forward = pivot.global_basis.z
			forward.y = 0.0
		forward = forward.normalized()
		var sole_y := body.global_position.y
		var heel := foot_rest.origin-forward*0.038
		heel.y = sole_y
		var ball := toe_rest.origin
		ball.y = sole_y
		var tip := ball+forward*0.042
		tip.y = sole_y
		sole_probes.append({"bone":foot_id,"local":foot_rest.affine_inverse()*heel})
		if toe_id >= 0:
			sole_probes.append({"bone":toe_id,"local":toe_rest.affine_inverse()*ball})
			sole_probes.append({"bone":toe_id,"local":toe_rest.affine_inverse()*tip})
		else:
			sole_probes.append({"bone":foot_id,"local":foot_rest.affine_inverse()*tip})
	print("SOLE_PROBES=",sole_probes.size())

func lowest_sole() -> float:
	var low := INF
	for probe in sole_probes:
		var id: int = probe["bone"]
		var point: Vector3 = probe["local"]
		var world_point := skeleton.global_transform * (skeleton.get_bone_global_pose(id) * point)
		low = minf(low,world_point.y)
	return low

func maintain_floor_contact(dt: float) -> void:
	if sole_probes.is_empty(): return
	var on_plate := absf(body.global_position.x)<49.9 and absf(body.global_position.z)<49.9
	var required := 0.0
	if on_plate:
		var uncorrected := lowest_sole()-floor_lift
		required = maxf(0.0,0.008-uncorrected)
	# Rising correction is immediate; release is critically damped to avoid pops.
	floor_lift = maxf(required,lerpf(floor_lift,required,1.0-exp(-28.0*dt)))
	pivot.position.y = floor_lift

func shorten_standing_prep() -> void:
	var clip := library.get_animation("jump")
	for track in range(clip.get_track_count()):
		for key in range(clip.track_get_key_count(track)):
			var t := clip.track_get_key_time(track,key)
			var adjusted := t*STAND_PREP/0.22 if t<=0.22 else t-0.22+STAND_PREP
			clip.track_set_key_time(track,key,adjusted)
	clip.length -= 0.22-STAND_PREP

func verify_standing_jump() -> void:
	for i in range(12):
		await get_tree().physics_frame
	if not body.is_on_floor() or sole_probes.size()<4:
		push_error("Ground or foot probe initialization failed")
		get_tree().quit(1)
		return
	begin_v4_jump(0.0)
	var high := body.global_position.y
	var low := INF
	var airborne_seen := false
	for i in range(130):
		await get_tree().physics_frame
		high = maxf(high,body.global_position.y)
		low = minf(low,lowest_sole())
		airborne_seen = airborne_seen or not body.is_on_floor()
	var ok := airborne_seen and high>0.25 and high<0.85 and low>=-0.012 and jump_phase==0 and body.is_on_floor()
	print("STAND_JUMP_HEIGHT=",high," LOWEST_SOLE=",low," LANDED=",body.is_on_floor()," PASS=",ok)
	if not ok:
		get_tree().quit(1)
		return
	await verify_directional_movement()

func verify_directional_movement() -> void:
	v7_testing = true
	var ok := true
	var previous_direction := Vector3.ZERO
	for direction in [Vector3.FORWARD,Vector3.BACK,Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD]:
		v7_test_stick = direction
		var min_turn_speed := INF
		for tick in range(105):
			await get_tree().physics_frame
			min_turn_speed=minf(min_turn_speed,horizontal_velocity().length())
		if previous_direction.length()>0.5:
			ok=ok and min_turn_speed>0.65
			print("CONTINUOUS_TURN_MIN_SPEED=",min_turn_speed)
		previous_direction=direction
		var velocity := horizontal_velocity()
		var facing := Vector3(sin(pivot.rotation.y),0,cos(pivot.rotation.y))
		var aligned := velocity.dot(direction)>1.0 and facing.dot(direction)>0.95
		ok = ok and aligned
		print("DIRECTION_TEST=",direction," VELOCITY=",velocity," ALIGNED=",aligned)
		v7_test_run = true
		for tick in range(35):
			await get_tree().physics_frame
		v7_test_jump = true
		await get_tree().physics_frame
		await get_tree().physics_frame
		v7_test_jump = false
		var seen_air := false
		var low := INF
		for tick in range(125):
			await get_tree().physics_frame
			seen_air = seen_air or not body.is_on_floor()
			low = minf(low,lowest_sole())
		ok = ok and seen_air and body.is_on_floor() and jump_phase==0 and low>=-0.015
		print("DIRECTION_JUMP=",direction," AIR=",seen_air," LOW=",low)
		v7_test_run = false
	v7_test_stick = Vector3.ZERO
	print("V7_DIRECTION_AND_JUMP_PASS=",ok)
	get_tree().quit(0 if ok else 1)

func _ready() -> void:
	make_world()
	make_player()
	if skeleton != null:
		prepare_animations()
	ready_ok = true
	for name in ["idle","walk","run","jump","run_jump"]:
		if not library.has_animation(name):
			ready_ok = false
			push_error("Required clip missing: " + name)
	if not ready_ok:
		get_tree().quit(1)
		return
	shorten_standing_prep()
	setup_sole_probes()
	prepare_gait_cycles()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	body.reset_physics_interpolation()
	setup_motion_tree()
	if "--smoke-test" in OS.get_cmdline_user_args():
		await get_tree().process_frame
		motion_tree.advance(0.05)
		print("YBOT_V4_CLIPS=",library.get_animation_list())
		print("YBOT_V4_BLEND_STATE=",playback.get_current_node())
		if playback.get_current_node() != &"ground":
			get_tree().quit(1)
			return
		await verify_standing_jump()
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func animation_node(clip_name: String) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = StringName(clip_name)
	return n

func add_transition(machine: AnimationNodeStateMachine, from: StringName, to: StringName, seconds: float) -> void:
	var t := AnimationNodeStateMachineTransition.new()
	t.xfade_time = seconds
	t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	machine.add_transition(from,to,t)

func setup_motion_tree() -> void:
	animator.stop()
	animator.speed_scale = 1.0
	var ground := AnimationNodeBlendTree.new()
	ground.add_node("idle",animation_node("idle"),Vector2(0,0))
	ground.add_node("walk",animation_node("walk"),Vector2(0,150))
	ground.add_node("run",animation_node("run"),Vector2(0,300))
	ground.add_node("walk_rate",AnimationNodeTimeScale.new(),Vector2(230,150))
	ground.add_node("run_rate",AnimationNodeTimeScale.new(),Vector2(230,300))
	var idle_walk := AnimationNodeBlend2.new()
	idle_walk.sync = true
	var walk_run := AnimationNodeBlend2.new()
	walk_run.sync = true
	ground.add_node("idle_walk",idle_walk,Vector2(470,60))
	ground.add_node("walk_run",walk_run,Vector2(700,150))
	ground.connect_node("walk_rate",0,"walk")
	ground.connect_node("run_rate",0,"run")
	ground.connect_node("idle_walk",0,"idle")
	ground.connect_node("idle_walk",1,"walk_rate")
	ground.connect_node("walk_run",0,"idle_walk")
	ground.connect_node("walk_run",1,"run_rate")
	ground.connect_node("output",0,"walk_run")
	var machine := AnimationNodeStateMachine.new()
	machine.add_node("ground",ground,Vector2(250,100))
	machine.add_node("jump",animation_node("jump"),Vector2(500,20))
	machine.add_node("run_jump",animation_node("run_jump"),Vector2(500,220))
	add_transition(machine,&"ground",&"jump",0.10)
	add_transition(machine,&"ground",&"run_jump",0.10)
	add_transition(machine,&"jump",&"ground",0.20)
	add_transition(machine,&"run_jump",&"ground",0.19)
	motion_tree = AnimationTree.new()
	motion_tree.name = "ContinuousLocomotion"
	model.add_child(motion_tree)
	motion_tree.anim_player = motion_tree.get_path_to(animator)
	motion_tree.root_node = NodePath("..")
	motion_tree.tree_root = machine
	motion_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	motion_tree.active = true
	playback = motion_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	playback.start(&"ground")
	update_weights(0.0,1.0)
	motion_tree.advance(0.0)

func update_weights(speed: float, dt: float) -> void:
	var blend_speed := 1.0-exp(-15.0*dt)
	var w: float = smoothstep(0.025,1.25,speed)
	var r: float = smoothstep(1.65,3.80,speed)
	walk_weight = lerpf(walk_weight,w,blend_speed)
	run_weight = lerpf(run_weight,r,blend_speed)
	var natural_speed := lerpf(V4_WALK,V4_RUN,run_weight)
	var cycle := lerpf(walk_cycle_seconds,run_cycle_seconds,run_weight)
	var stride_scale := clampf(speed/natural_speed,0.45,1.18)
	var requested_rate := stride_scale/maxf(cycle,0.15)
	gait_rate=lerpf(gait_rate,requested_rate,1.0-exp(-12.0*dt))
	motion_tree.set("parameters/ground/idle_walk/blend_amount",walk_weight)
	motion_tree.set("parameters/ground/walk_run/blend_amount",run_weight)
	motion_tree.set("parameters/ground/walk_rate/scale",gait_rate)
	motion_tree.set("parameters/ground/run_rate/scale",gait_rate)

func begin_v4_jump(speed: float) -> void:
	v7_jump_heading = pivot.rotation.y
	v7_air_velocity = horizontal_velocity()
	active_jump = "run_jump" if speed > 2.45 else "jump"
	jump_t0 = 0.04 if active_jump == "run_jump" else STAND_PREP
	jump_t1 = 0.64 if active_jump == "run_jump" else STAND_PREP+STAND_FLIGHT
	jump_duration = library.get_animation(active_jump).length
	jump_phase = 1
	jump_clock = 0.0
	airborne_elapsed = 0.0
	recovery_elapsed = 0.0
	jump_buffer = 0.0
	playback.travel(StringName(active_jump))

func _physics_process(dt: float) -> void:
	if not ready_ok or motion_tree == null or v7_paused:
		return
	var x := float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A))
	var z := float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W))
	var stick := Vector3(x,0,z).limit_length(1.0).rotated(Vector3.UP,yaw)
	if v7_testing:
		stick = v7_test_stick
	var moving := stick.length_squared()>0.01
	var sprint := moving and (v7_test_run if v7_testing else Input.is_physical_key_pressed(KEY_SHIFT))
	var target_speed := V4_RUN if sprint else V4_WALK
	var planar := horizontal_velocity()
	var grounded := body.is_on_floor()
	var pressed := v7_test_jump if v7_testing else Input.is_physical_key_pressed(KEY_SPACE)
	if pressed and not jump_was_pressed:
		jump_buffer = 0.25
	else:
		jump_buffer = maxf(0.0,jump_buffer-dt)
	jump_was_pressed = pressed
	var launched := false
	var speed := planar.length()
	var heading := pivot.rotation.y
	var error := 0.0
	if moving:
		error = wrapf(atan2(stick.x,stick.z)-heading,-PI,PI)
		# An exact 180-degree turn must keep a stable direction, not alternate each tick.
		if absf(absf(error)-PI)<0.035:
			error = PI*v7_turn_sign
		elif absf(error)>0.035:
			v7_turn_sign = signf(error)
	if jump_phase == 0 and grounded:
		# Curve the velocity with the body rather than brake to idle.
		var corner := absf(error)/PI
		var corner_speed := target_speed*lerpf(1.0,0.56 if sprint else 0.82,smoothstep(0.10,1.0,corner))
		var desired_speed := corner_speed if moving else 0.0
		var rate := 4.8 if sprint else 5.8
		if desired_speed<speed: rate = 4.4 if moving else 8.0
		v7_speed = move_toward(speed,desired_speed,rate*dt)
		if moving:
			var max_turn := lerpf(8.0,4.9,clampf(speed/V4_RUN,0.0,1.0))
			var rate_goal := clampf(error*9.0,-max_turn,max_turn)
			visual_turn_rate = move_toward(visual_turn_rate,rate_goal,36.0*dt)
			var angular_step := clampf(visual_turn_rate*dt,minf(error,0.0),maxf(error,0.0))
			pivot.rotation.y = wrapf(heading+angular_step,-PI,PI)
		else:
			visual_turn_rate = move_toward(visual_turn_rate,0.0,36.0*dt)
		planar = Vector3(sin(pivot.rotation.y),0,cos(pivot.rotation.y))*v7_speed
		if not moving and v7_speed<0.03:
			planar = Vector3.ZERO
		if jump_buffer>0.0:
			body.velocity.x = planar.x
			body.velocity.z = planar.z
			begin_v4_jump(planar.length())
	elif jump_phase == 1:
		pivot.rotation.y = v7_jump_heading
		if active_jump == "jump":
			v7_air_velocity = v7_air_velocity.move_toward(Vector3.ZERO,10.0*dt)
		planar = v7_air_velocity
		jump_clock += dt
		if jump_clock>=jump_t0:
			jump_phase = 2
			takeoff_speed = planar.length()
			body.velocity.y = V4_G*maxf(dt,jump_t1-jump_t0-dt)*0.5
			launched = true
	elif jump_phase == 2 or not grounded:
		# No instant reversal in the air. Horizontal momentum stays aligned to takeoff.
		pivot.rotation.y = v7_jump_heading
		planar = v7_air_velocity
		airborne_elapsed += dt
	elif jump_phase == 3:
		pivot.rotation.y = v7_jump_heading
		var landing_target := Vector3.ZERO
		if moving and absf(error)<0.60:
			landing_target = Vector3(sin(v7_jump_heading),0,cos(v7_jump_heading))*minf(target_speed,takeoff_speed)
		planar = planar.move_toward(landing_target,6.0*dt)
		recovery_elapsed += dt
		var recover_time := clampf(jump_duration-jump_t1-0.10,0.18,0.50)
		if recovery_elapsed>=recover_time:
			jump_phase = 0
			v7_turning = false
			visual_turn_rate = 0.0
			playback.travel(&"ground")
	body.velocity.x = planar.x
	body.velocity.z = planar.z
	if not grounded and not launched:
		body.velocity.y -= V4_G*dt
	elif grounded and not launched and body.velocity.y<0.0:
		body.velocity.y = 0.0
	body.move_and_slide()
	if jump_phase == 2 and not launched and body.is_on_floor() and body.velocity.y<=0.0:
		jump_phase = 3
		recovery_elapsed = 0.0
	var blend_speed := horizontal_velocity().length()
	update_weights(blend_speed,dt)
	motion_tree.advance(dt)
	maintain_floor_contact(dt)
	if body.position.y < -8.0:
		body.position = Vector3(0,0.05,0)
		body.reset_physics_interpolation()
		body.velocity = Vector3.ZERO
		v7_air_velocity = Vector3.ZERO
		v7_speed = 0.0
		v7_turning = false
		jump_phase = 0
		playback.start(&"ground")
		camera_ready = false
		floor_lift = 0.0
		pivot.position.y = 0.0

func _process(dt: float) -> void:
	if camera == null or v7_paused: return
	var desired_focus := body.get_global_transform_interpolated().origin+Vector3(0,1.28,0)
	if not camera_ready:
		camera_focus = desired_focus
		camera_ready = true
	camera_focus = camera_focus.lerp(desired_focus,1.0-exp(-16.0*dt))
	var speed := horizontal_velocity().length()
	var distance := lerpf(4.4,4.8,clampf(speed/V4_RUN,0.0,1.0))
	var offset := Vector3(0,0,distance).rotated(Vector3.RIGHT,pitch).rotated(Vector3.UP,yaw)
	camera.global_position = camera.global_position.lerp(camera_focus+offset,1.0-exp(-11.0*dt))
	camera.look_at(camera_focus,Vector3.UP)
