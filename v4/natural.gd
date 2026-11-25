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
	setup_motion_tree()
	if "--smoke-test" in OS.get_cmdline_user_args():
		await get_tree().process_frame
		motion_tree.advance(0.05)
		print("YBOT_V4_CLIPS=",library.get_animation_list())
		print("YBOT_V4_BLEND_STATE=",playback.get_current_node())
		get_tree().quit(0 if playback.get_current_node() == &"ground" else 1)
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
	var blend_speed := 1.0-exp(-12.0*dt)
	var w: float = smoothstep(0.04,V4_WALK,speed)
	var r: float = smoothstep(V4_WALK,3.9,speed)
	walk_weight = lerpf(walk_weight,w,blend_speed)
	run_weight = lerpf(run_weight,r,blend_speed)
	walk_rate = lerpf(walk_rate,clampf(speed/V4_WALK,0.42,1.38),1.0-exp(-9.0*dt))
	run_rate = lerpf(run_rate,clampf(speed/V4_RUN,0.58,1.13),1.0-exp(-9.0*dt))
	motion_tree.set("parameters/ground/idle_walk/blend_amount",walk_weight)
	motion_tree.set("parameters/ground/walk_run/blend_amount",run_weight)
	motion_tree.set("parameters/ground/walk_rate/scale",walk_rate)
	motion_tree.set("parameters/ground/run_rate/scale",run_rate)

func begin_v4_jump(speed: float) -> void:
	active_jump = "run_jump" if speed > 2.45 else "jump"
	jump_t0 = 0.04 if active_jump == "run_jump" else 0.22
	jump_t1 = 0.64 if active_jump == "run_jump" else 0.81
	jump_duration = library.get_animation(active_jump).length
	jump_phase = 1
	jump_clock = 0.0
	airborne_elapsed = 0.0
	recovery_elapsed = 0.0
	jump_buffer = 0.0
	playback.travel(StringName(active_jump))

func _physics_process(dt: float) -> void:
	if not ready_ok or motion_tree == null:
		return
	var x := float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A))
	var z := float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W))
	var stick := Vector3(x,0,z).limit_length(1.0).rotated(Vector3.UP,yaw)
	var moving := stick.length_squared()>0.01
	var sprint := moving and Input.is_physical_key_pressed(KEY_SHIFT)
	var target_speed := V4_RUN if sprint else V4_WALK
	var planar := horizontal_velocity()
	var grounded := body.is_on_floor()
	var pressed := Input.is_physical_key_pressed(KEY_SPACE)
	if pressed and not jump_was_pressed:
		jump_buffer = 0.15
	else:
		jump_buffer = maxf(0.0,jump_buffer-dt)
	jump_was_pressed = pressed
	if grounded and jump_phase == 0 and jump_buffer > 0.0:
		begin_v4_jump(planar.length())
	var target := stick*target_speed
	# Direction changes require real deceleration before reversing.
	var opposite := moving and planar.length()>0.25 and planar.normalized().dot(stick)<-0.25
	if opposite:
		target = Vector3.ZERO
	var accel_limit := 4.3 if sprint else 5.2
	if not moving or opposite:
		accel_limit = 7.4
	elif moving and planar.length()>target_speed:
		accel_limit = 6.2
	if jump_phase == 1 and active_jump == "jump":
		target = Vector3.ZERO
		accel_limit = 10.0
	elif jump_phase == 2 or not grounded:
		target = planar.lerp(stick*minf(takeoff_speed,target_speed),0.20) if moving else planar
		accel_limit = 1.1
	elif jump_phase == 3:
		var recovery: float = smoothstep(0.0,0.22,recovery_elapsed)
		target *= lerpf(0.38,1.0,recovery)
		accel_limit = 5.0
	var desired_accel := (target-planar)/maxf(dt,0.001)
	desired_accel = desired_accel.limit_length(accel_limit)
	accel_vector = accel_vector.move_toward(desired_accel,35.0*dt)
	var step := accel_vector*dt
	if step.dot(target-planar)>0.0 and step.length()>planar.distance_to(target):
		planar = target
		accel_vector = Vector3.ZERO
	else:
		planar += step
	if not moving and grounded and planar.length()<0.045:
		planar = Vector3.ZERO
		accel_vector = Vector3.ZERO
	body.velocity.x = planar.x
	body.velocity.z = planar.z
	# Fast turns have lower angular speed, and orientation follows actual travel.
	var face := planar if planar.length()>0.14 else stick
	if face.length_squared()>0.01:
		var goal := atan2(face.x,face.z)
		var error := wrapf(goal-pivot.rotation.y,-PI,PI)
		var max_turn := lerpf(7.0,3.8,clampf(planar.length()/V4_RUN,0.0,1.0))
		if not grounded: max_turn = 2.8
		var goal_rate := clampf(error*8.0,-max_turn,max_turn)
		visual_turn_rate = move_toward(visual_turn_rate,goal_rate,26.0*dt)
		pivot.rotation.y += clampf(visual_turn_rate*dt,minf(0.0,error),maxf(0.0,error))
	else:
		visual_turn_rate = move_toward(visual_turn_rate,0.0,26.0*dt)
	var launched := false
	if jump_phase == 1:
		jump_clock += dt
		if jump_clock >= jump_t0:
			jump_phase = 2
			takeoff_speed = planar.length()
			body.velocity.y = V4_G*(jump_t1-jump_t0)*0.5
			launched = true
	elif jump_phase == 2:
		airborne_elapsed += dt
	elif jump_phase == 3:
		recovery_elapsed += dt
		var recover_time := clampf(jump_duration-jump_t1-0.10,0.18,0.50)
		if recovery_elapsed >= recover_time:
			jump_phase = 0
			playback.travel(&"ground")
	if not grounded and not launched:
		body.velocity.y -= V4_G*dt
	elif grounded and not launched and body.velocity.y<0.0:
		body.velocity.y = 0.0
	body.move_and_slide()
	if jump_phase == 2 and not launched and body.is_on_floor() and body.velocity.y<=0.0:
		jump_phase = 3
		recovery_elapsed = 0.0
	update_weights(horizontal_velocity().length(),dt)
	motion_tree.advance(dt)
	if body.position.y < -8.0:
		body.position = Vector3(0,0.05,0)
		body.velocity = Vector3.ZERO
		accel_vector = Vector3.ZERO
		jump_phase = 0
		playback.start(&"ground")
		camera_ready = false

func _process(dt: float) -> void:
	if camera == null: return
	var desired_focus := body.global_position+Vector3(0,1.28,0)
	if not camera_ready:
		camera_focus = desired_focus
		camera_ready = true
	camera_focus = camera_focus.lerp(desired_focus,1.0-exp(-16.0*dt))
	var speed := horizontal_velocity().length()
	var distance := lerpf(4.4,4.8,clampf(speed/V4_RUN,0.0,1.0))
	var offset := Vector3(0,0,distance).rotated(Vector3.RIGHT,pitch).rotated(Vector3.UP,yaw)
	camera.global_position = camera.global_position.lerp(camera_focus+offset,1.0-exp(-11.0*dt))
	camera.look_at(camera_focus,Vector3.UP)
