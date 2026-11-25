shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 sun_direction=vec3(0.5,0.6,0.5);
uniform float quality=1.0;
uniform vec2 ripple_origin=vec2(0.0);
uniform float ripple_age=10.0;
varying vec3 world_pos;
float wave(vec2 p,float t){
	float a=sin(dot(p,vec2(3.2,1.1))+t*1.7)*0.013;
	a+=sin(dot(p,vec2(-1.5,4.7))-t*1.3)*0.009;
	a+=sin(dot(p,vec2(8.7,6.3))+t*2.2)*0.0035;
	float dist=length(p-ripple_origin);
	float band=exp(-pow((dist-ripple_age*0.8)*5.0,2.0));
	a+=sin(dist*24.0-ripple_age*16.0)*band*exp(-ripple_age*2.0)*0.016;
	return a;
}
void vertex(){
	vec3 p=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	float border=smoothstep(0.0,0.05,min(min(UV.x,1.0-UV.x),min(UV.y,1.0-UV.y)));
	VERTEX.y+=wave(p.xz,TIME)*border;
	world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
float scene_depth(vec2 uv,mat4 inv_proj){
	float d=texture(depth_tex,uv).r;
	vec3 ndc;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		ndc=vec3(uv,d)*2.0-1.0;
	#else
		ndc=vec3(uv*2.0-1.0,d);
	#endif
	vec4 v=inv_proj*vec4(ndc,1.0);
	return -v.z/max(abs(v.w),0.0001);
}
void fragment(){
	vec2 p=world_pos.xz;
	float h=wave(p,TIME);
	float dx=(wave(p+vec2(0.025,0.0),TIME)-h)/0.025;
	float dz=(wave(p+vec2(0.0,0.025),TIME)-h)/0.025;
	vec3 n=normalize(vec3(-dx,1.0,-dz));
	if(quality>0.5){
		n=normalize(n+vec3(sin(p.x*37.0+p.y*23.0+TIME*2.7)*0.019,0.0,cos(p.y*32.0-p.x*19.0-TIME*2.0)*0.019));
	}
	vec3 v=normalize(CAMERA_POSITION_WORLD-world_pos);
	float cos_angle=clamp(dot(n,v),0.0,1.0);
	float fresnel=0.0204+0.9796*pow(1.0-cos_angle,5.0);
	float current_depth=-VERTEX.z;
	float depth=max(0.0,scene_depth(SCREEN_UV,INV_PROJECTION_MATRIX)-current_depth);
	vec2 offset=vec2(dx,dz)*0.036*clamp(depth,0.0,0.7);
	vec2 uv=clamp(SCREEN_UV+offset,vec2(0.002),vec2(0.998));
	if(scene_depth(uv,INV_PROJECTION_MATRIX)<current_depth+0.015){uv=SCREEN_UV;}
	vec3 refracted=texture(screen_tex,uv).rgb;
	vec3 transmittance=exp(-vec3(1.5,0.32,0.15)*min(depth,4.0));
	vec3 water_color=refracted*transmittance+vec3(0.025,0.22,0.26)*(1.0-transmittance);
	vec3 r=reflect(-v,n);
	vec3 sky=mix(vec3(0.76,0.85,0.91),vec3(0.18,0.43,0.73),smoothstep(0.0,0.8,r.y));
	float glitter=pow(max(dot(r,normalize(sun_direction)),0.0),180.0);
	float wide_glint=pow(max(dot(r,normalize(sun_direction)),0.0),24.0)*0.07;
	sky+=vec3(1.0,0.86,0.61)*(glitter*1.6+wide_glint);
	vec3 result=mix(water_color,sky,fresnel);
	ALBEDO=result;
	ALPHA=1.0;
}
