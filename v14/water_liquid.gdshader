shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D height_field : filter_linear, repeat_disable;
uniform sampler2D planar_reflection : filter_linear, repeat_disable;
uniform bool reflection_available=false;
uniform vec3 sun_direction=vec3(0.5,0.6,0.5);
uniform float quality=0.0;
uniform float ripple_clock=0.0;
uniform vec4 ripple_0=vec4(0.0);
uniform vec4 ripple_1=vec4(0.0);
uniform vec4 ripple_2=vec4(0.0);
uniform vec4 ripple_3=vec4(0.0);
varying vec3 world_pos;
float sim_height(vec2 uv){
	return (texture(height_field,clamp(uv,vec2(0.001),vec2(0.999))).r-0.5)/8.0;
}
float wind_wave(vec2 p){
	return sin(dot(p,vec2(4.1,1.7))+TIME*2.1)*0.006
	+sin(dot(p,vec2(-2.6,5.7))-TIME*1.7)*0.004
	+sin(dot(p,vec2(9.7,6.3))+TIME*2.9)*0.0018
	+sin(dot(p,vec2(17.1,-12.7))-TIME*4.0)*0.0008;
}
float surface_height(vec2 p,vec2 uv){
	return sim_height(uv)+wind_wave(p);
}
void vertex(){
	vec3 p=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	vec2 pool_uv=(p.xz-vec2(5.0,-10.0))/vec2(6.0,4.0);
	float edge=min(min(pool_uv.x,1.0-pool_uv.x),min(pool_uv.y,1.0-pool_uv.y));
	VERTEX.y+=surface_height(p.xz,pool_uv)*smoothstep(0.0,0.025,edge);
	world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment(){
	vec2 p=world_pos.xz;
	vec2 pool_uv=(p-vec2(5.0,-10.0))/vec2(6.0,4.0);
	float e=0.023;
	float dx=(surface_height(p+vec2(e,0),pool_uv+vec2(e/6.0,0))-surface_height(p-vec2(e,0),pool_uv-vec2(e/6.0,0)))/(2.0*e);
	float dz=(surface_height(p+vec2(0,e),pool_uv+vec2(0,e/4.0))-surface_height(p-vec2(0,e),pool_uv-vec2(0,e/4.0)))/(2.0*e);
	vec3 n=normalize(vec3(-dx,1.0,-dz));
	vec3 v=normalize(CAMERA_POSITION_WORLD-world_pos);
	float cos_theta=clamp(dot(n,v),0.0,1.0);
	float fresnel=0.02037+0.97963*pow(1.0-cos_theta,5.0);
	vec3 reflected=reflect(-v,n);
	vec3 sky=mix(vec3(0.73,0.84,0.91),vec3(0.19,0.43,0.73),smoothstep(0.0,0.85,reflected.y));
	vec3 nview=normalize((VIEW_MATRIX*vec4(n,0.0)).xyz);
	vec2 distortion=nview.xy-(VIEW_MATRIX*vec4(0,1,0,0)).xy;
	vec2 refract_uv=clamp(SCREEN_UV+distortion*0.050,vec2(0.003),vec2(0.997));
	vec3 refracted=texture(screen_tex,refract_uv).rgb;
	float path=0.26/max(0.35,cos_theta);
	vec3 extinction=exp(-vec3(0.72,0.14,0.07)*path);
	vec3 through=refracted*extinction+vec3(0.035,0.29,0.32)*(1.0-extinction);
	vec3 reflection=sky;
	if(reflection_available){
		vec2 mirror_uv=vec2(SCREEN_UV.x,1.0-SCREEN_UV.y)+vec2(distortion.x,-distortion.y)*0.10;
		float fade=smoothstep(0.0,0.07,min(min(mirror_uv.x,1.0-mirror_uv.x),min(mirror_uv.y,1.0-mirror_uv.y)));
		reflection=mix(sky,texture(planar_reflection,clamp(mirror_uv,vec2(0.001),vec2(0.999))).rgb,fade);
	}
	float light_dot=max(dot(reflected,normalize(sun_direction)),0.0);
	float glint=pow(light_dot,190.0)*1.35+pow(light_dot,34.0)*0.065;
	float border=min(min(pool_uv.x,1.0-pool_uv.x)*6.0,min(pool_uv.y,1.0-pool_uv.y)*4.0);
	float meniscus=exp(-max(border,0.0)*95.0)*0.10;
	ALBEDO=mix(through,reflection,clamp(fresnel+meniscus,0.0,1.0))+vec3(1.0,0.91,0.73)*glint;
	ALPHA=1.0;
}
