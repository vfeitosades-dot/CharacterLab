extends "res://pool.gd"

var high_renderer := false
var pool_probe: ReflectionProbe

func make_world() -> void:
	high_renderer = RenderingServer.get_current_rendering_method()=="forward_plus"
	super.make_world()
	if cinematic_environment==null: return
	if high_renderer:
		pool_probe=ReflectionProbe.new()
		pool_probe.name="PoolEnvironmentReflection"
		pool_probe.size=Vector3(13,7,11)
		pool_probe.origin_offset=Vector3(0,0,0)
		pool_probe.intensity=0.8
		pool_probe.enable_shadows=true
		pool_probe.update_mode=ReflectionProbe.UPDATE_ONCE
		add_child(pool_probe)
		pool_probe.position=POOL_CENTER+Vector3(0,2.0,0)
	apply_graphics_quality()

func apply_graphics_quality() -> void:
	super.apply_graphics_quality()
	if cinematic_environment==null or cinematic_sun==null: return
	var high := graphics_quality==2
	var medium := graphics_quality==1
	var advanced := high_renderer and graphics_quality>0
	var ultra := high_renderer and high
	var env := cinematic_environment
	# Keep a fixed afternoon with neutral highlights and blue fill.
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure=1.0
	env.tonemap_white=4.0
	env.adjustment_saturation=1.02
	env.adjustment_contrast=1.04
	env.ambient_light_color=Color(0.74,0.83,1.0)
	env.ambient_light_energy=0.46 if advanced else 0.63
	env.ambient_light_sky_contribution=0.65
	env.fog_density=0.0012
	env.glow_enabled=graphics_quality>0
	env.glow_intensity=0.16
	env.glow_hdr_threshold=1.35
	cinematic_sun.light_energy=1.85
	cinematic_sun.light_color=Color(1.0,0.93,0.81)
	cinematic_sun.shadow_bias=0.018
	cinematic_sun.shadow_normal_bias=0.24
	cinematic_sun.directional_shadow_max_distance=20.0 if not medium and not high else 42.0
	cinematic_sun.directional_shadow_split_1=0.09
	cinematic_sun.directional_shadow_split_2=0.25
	cinematic_sun.directional_shadow_split_3=0.50
	cinematic_sun.directional_shadow_blend_splits=true
	cinematic_sun.light_angular_distance=0.53 if advanced else 0.0
	cinematic_sun.shadow_blur=1.15 if graphics_quality>0 else 0.8
	if high_renderer:
		env.ssao_enabled=advanced
		env.ssao_radius=0.55
		env.ssao_intensity=1.25
		env.ssil_enabled=ultra
		env.ssil_radius=1.6
		env.ssil_intensity=0.85
		env.ssr_enabled=ultra
		env.ssr_max_steps=48
		env.sdfgi_enabled=ultra
		env.sdfgi_use_occlusion=true
		env.sdfgi_read_sky_light=true
		env.sdfgi_min_cell_size=0.30
		env.volumetric_fog_enabled=ultra
		env.volumetric_fog_density=0.003
		env.volumetric_fog_albedo=Color(0.89,0.92,0.97)
		get_viewport().use_taa=advanced
		get_viewport().msaa_3d=Viewport.MSAA_DISABLED
		get_viewport().scaling_3d_scale=0.75 if graphics_quality==0 else (0.85 if medium else 1.0)
	if contact_shadow!=null:
		contact_shadow.visible=true
	if graphics_label!=null:
		graphics_label.text="Esc Configuracoes | "+("Forward+ / GI avancada" if high_renderer else "Compatibilidade / leve")+" | "+["Leve","Equilibrado","Alto"][graphics_quality]
