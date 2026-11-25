shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
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
	// Geometry: millimetre-scale ripples. Shorter waves affect shading only.
	return sin(dot(p,vec2(7.2,3.8))+TIME*5.2)*0.0023
	+sin(dot(p,vec2(-5.7,12.4))-TIME*6.4)*0.0016
	+sin(dot(p,vec2(15.9,8.3))+TIME*8.0)*0.00085;
}
vec2 slope_band(vec2 p,vec2 k,float amplitude,float phase){
	return k*amplitude*cos(dot(p,k)+phase);
}
vec2 micro_slope(vec2 p,float distance_to_eye){
	// Independent capillary-like bands; fade subpixel frequencies at distance.
	vec2 slow=vec2(sin(p.y*1.65+TIME*0.39),cos(p.x*1.9-TIME*0.33))*0.045;
	vec2 q=p+slow;
	vec2 slope=slope_band(q,vec2(26.7,12.4),0.00095,TIME*10.0);
	slope+=slope_band(q,vec2(-17.1,35.3),0.00075,-TIME*12.7+1.2);
	slope+=slope_band(q,vec2(42.5,-21.2),0.00052,TIME*16.3+2.9);
	if(quality>0.5){
		slope+=slope_band(q,vec2(-53.3,-29.8),0.00036,-TIME*20.4+0.5)*(1.0-smoothstep(8.0,18.0,distance_to_eye));
		slope+=slope_band(q,vec2(76.4,45.2),0.00022,TIME*24.1)*(1.0-smoothstep(5.0,12.0,distance_to_eye));
	}
	return slope*(1.0-smoothstep(14.0,28.0,distance_to_eye));
}
float view_depth(vec2 uv,mat4 inv_proj){
	float d=texture(depth_tex,uv).r;
	vec4 q=inv_proj*vec4(uv*2.0-1.0,d*2.0-1.0,1.0);
	return -q.z/q.w;
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
	vec2 micro=micro_slope(p,length(CAMERA_POSITION_WORLD-world_pos));
	vec3 n=normalize(vec3(-dx-micro.x,1.0,-dz-micro.y));
	vec3 v=normalize(CAMERA_POSITION_WORLD-world_pos);
	float cos_theta=clamp(dot(n,v),0.0,1.0);
	float fresnel=0.02037+0.97963*pow(1.0-cos_theta,5.0);
	vec3 reflected=reflect(-v,n);
	vec3 sky=mix(vec3(0.73,0.84,0.91),vec3(0.19,0.43,0.73),smoothstep(0.0,0.85,reflected.y));
	vec3 nview=normalize((VIEW_MATRIX*vec4(n,0.0)).xyz);
	vec2 distortion=nview.xy-(VIEW_MATRIX*vec4(0,1,0,0)).xy;
	float surface_depth=-VERTEX.z;
	float behind=max(0.0,view_depth(SCREEN_UV,INV_PROJECTION_MATRIX)-surface_depth);
	vec2 refract_uv=clamp(SCREEN_UV+distortion*0.045*clamp(behind*2.0,0.0,1.0),vec2(0.003),vec2(0.997));
	if(view_depth(refract_uv,INV_PROJECTION_MATRIX)<surface_depth+0.005){refract_uv=SCREEN_UV;}
	vec3 refracted=texture(screen_tex,refract_uv).rgb;
	float path=clamp(behind,0.0,0.26/max(0.24,cos_theta));
	vec3 extinction=exp(-vec3(0.49,0.09,0.035)*path);
	vec3 through=refracted*extinction+vec3(0.018,0.20,0.24)*(1.0-extinction);
	vec3 reflection=sky;
	if(reflection_available){
		vec2 mirror_uv=vec2(SCREEN_UV.x,1.0-SCREEN_UV.y)+vec2(distortion.x,-distortion.y)*0.10;
		float fade=smoothstep(0.0,0.07,min(min(mirror_uv.x,1.0-mirror_uv.x),min(mirror_uv.y,1.0-mirror_uv.y)));
		reflection=mix(sky,texture(planar_reflection,clamp(mirror_uv,vec2(0.001),vec2(0.999))).rgb,fade);
	}
	float light_dot=max(dot(reflected,normalize(sun_direction)),0.0);
	float glint=pow(light_dot,300.0)*1.15+pow(light_dot,75.0)*0.11;
	float border=min(min(pool_uv.x,1.0-pool_uv.x)*6.0,min(pool_uv.y,1.0-pool_uv.y)*4.0);
	float meniscus=exp(-max(border,0.0)*95.0)*0.10;
	ALBEDO=mix(through,reflection,clamp(fresnel+meniscus,0.0,1.0))+vec3(1.0,0.91,0.73)*glint;
	ALPHA=1.0;
}
