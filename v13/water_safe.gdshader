shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never;
uniform vec3 sun_direction=vec3(0.5,0.6,0.5);
uniform float quality=0.0;
uniform float ripple_clock=0.0;
uniform vec4 ripple_0=vec4(0.0,0.0,-100.0,0.0);
uniform vec4 ripple_1=vec4(0.0,0.0,-100.0,0.0);
uniform vec4 ripple_2=vec4(0.0,0.0,-100.0,0.0);
uniform vec4 ripple_3=vec4(0.0,0.0,-100.0,0.0);
varying vec3 world_pos;
float ring(vec2 p,vec4 impulse){
	float age=max(0.0,ripple_clock-impulse.z);
	float front=length(p-impulse.xy)-age*0.95;
	return sin(front*31.0)*exp(-front*front*15.0-age*1.35)*impulse.w*0.012;
}
float wave(vec2 p){
	return sin(dot(p,vec2(4.1,1.7))+TIME*2.1)*0.008+
		sin(dot(p,vec2(-2.6,5.7))-TIME*1.7)*0.005+
		sin(dot(p,vec2(8.7,6.3))+TIME*2.9)*0.002+
		ring(p,ripple_0)+ring(p,ripple_1)+ring(p,ripple_2)+ring(p,ripple_3);
}
void vertex(){
	vec3 p=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	float edge=min(min(UV.x,1.0-UV.x),min(UV.y,1.0-UV.y));
	VERTEX.y+=wave(p.xz)*smoothstep(0.0,0.035,edge);
	world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment(){
	vec2 p=world_pos.xz;
	float h=wave(p);
	float dx=(wave(p+vec2(0.02,0.0))-h)/0.02;
	float dz=(wave(p+vec2(0.0,0.02))-h)/0.02;
	vec3 n=normalize(vec3(-dx,1.0,-dz));
	vec3 v=normalize(CAMERA_POSITION_WORLD-world_pos);
	float fresnel=0.0204+0.9796*pow(1.0-clamp(dot(n,v),0.0,1.0),5.0);
	vec3 r=reflect(-v,n);
	vec3 sky=mix(vec3(0.76,0.85,0.91),vec3(0.18,0.43,0.73),smoothstep(0.0,0.8,r.y));
	float sun=max(dot(r,normalize(sun_direction)),0.0);
	NORMAL=normalize((VIEW_MATRIX*vec4(n,0.0)).xyz);
	ALBEDO=mix(vec3(0.06,0.48,0.54),sky,fresnel);
	ROUGHNESS=0.17;
	SPECULAR=0.55;
	EMISSION=sky*fresnel*0.22+vec3(1.0,0.88,0.64)*pow(sun,160.0)*0.75;
	ALPHA=mix(0.25,0.94,fresnel);
}
