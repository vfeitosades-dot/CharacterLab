shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 sun_direction=vec3(0.5,0.6,0.5);
uniform float quality=1.0;
uniform float ripple_clock=0.0;
uniform vec4 ripple_0=vec4(0.0,0.0,-100.0,0.0);
uniform vec4 ripple_1=vec4(0.0,0.0,-100.0,0.0);
uniform vec4 ripple_2=vec4(0.0,0.0,-100.0,0.0);
uniform vec4 ripple_3=vec4(0.0,0.0,-100.0,0.0);
varying vec3 world_pos;
float ring(vec2 p,vec4 impulse){
	float age=max(0.0,ripple_clock-impulse.z);
	float d=length(p-impulse.xy);
	float front=d-age*0.95;
	return sin(front*31.0)*exp(-front*front*15.0)*exp(-age*1.35)*impulse.w*0.018;
}
float wave(vec2 p,float t){
	float a=sin(dot(p,vec2(4.1,1.7))+t*2.1)*0.009;
	a+=sin(dot(p,vec2(-2.6,5.7))-t*1.7)*0.006;
	a+=sin(dot(p,vec2(8.7,6.3))+t*2.9)*0.003;
	a+=sin(dot(p,vec2(13.4,-8.3))-t*3.1)*0.0015;
	a+=ring(p,ripple_0)+ring(p,ripple_1)+ring(p,ripple_2)+ring(p,ripple_3);
	return a;
}
void vertex(){
	vec3 p=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	float border=smoothstep(0.0,0.035,min(min(UV.x,1.0-UV.x),min(UV.y,1.0-UV.y)));
	VERTEX.y+=wave(p.xz,TIME)*border;
	world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
vec3 view_position(vec2 uv,mat4 inv_proj){
	float d=texture(depth_tex,uv).r;
	vec3 ndc;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		ndc=vec3(uv,d)*2.0-1.0;
	#else
		ndc=vec3(uv*2.0-1.0,d);
	#endif
	vec4 v=inv_proj*vec4(ndc,1.0);
	return v.xyz/v.w;
}
vec2 project_uv(vec3 p,mat4 projection){
	vec4 c=projection*vec4(p,1.0);
	return c.xy/c.w*0.5+0.5;
}
float inside(vec2 uv){
	return step(0.001,uv.x)*step(uv.x,0.999)*step(0.001,uv.y)*step(uv.y,0.999);
}
vec3 sky_color(vec3 r){
	float s=max(dot(r,normalize(sun_direction)),0.0);
	vec3 sky=mix(vec3(0.76,0.85,0.91),vec3(0.18,0.43,0.73),smoothstep(0.0,0.8,r.y));
	float clouds=sin(r.x*14.0+r.z*8.0+TIME*0.022)+sin(r.z*27.0-r.x*10.0+TIME*0.03);
	sky=mix(sky,vec3(0.87,0.92,0.97),smoothstep(1.1,1.8,clouds)*smoothstep(0.0,0.25,r.y)*0.45);
	return sky+vec3(1.0,0.87,0.66)*(pow(s,240.0)*2.2+pow(s,35.0)*0.075);
}
// March only a short ray in view space; fallback to sky for off-screen objects.
vec4 trace_reflection(vec3 origin,vec3 direction,mat4 projection,mat4 inv_proj,float q){
	vec4 found=vec4(0.0);
	float prev_t=0.06;
	int steps=12;
	if(q>1.5){steps=24;}
	for(int i=1;i<=24;i++){
		if(i>steps){break;}
		float t=0.06+float(i)*0.10+float(i*i)*0.013;
		vec3 p=origin+direction*t;
		if(p.z>=-0.06){break;}
		vec2 uv=project_uv(p,projection);
		if(inside(uv)<0.5){break;}
		float diff=view_position(uv,inv_proj).z-p.z;
		if(diff>=0.0 && diff<0.40){
			float lo=prev_t,hi=t;
			for(int j=0;j<3;j++){
				float mid=(lo+hi)*0.5;
				vec3 m=origin+direction*mid;
				vec2 mu=project_uv(m,projection);
				if(view_position(mu,inv_proj).z-m.z>=0.0){hi=mid;}else{lo=mid;}
			}
			vec2 hit=project_uv(origin+direction*hi,projection);
			float edge=min(min(hit.x,1.0-hit.x),min(hit.y,1.0-hit.y));
			found=vec4(texture(screen_tex,hit).rgb,smoothstep(0.0,0.09,edge)*(1.0-smoothstep(3.0,9.0,t)));
			break;
		}
		prev_t=t;
	}
	return found;
}
void fragment(){
	vec2 p=world_pos.xz;
	float h=wave(p,TIME);
	float dx=(wave(p+vec2(0.018,0.0),TIME)-h)/0.018;
	float dz=(wave(p+vec2(0.0,0.018),TIME)-h)/0.018;
	vec3 n=normalize(vec3(-dx,1.0,-dz));
	if(quality>0.5){
		n=normalize(n+vec3(sin(p.x*43.0+p.y*21.0+TIME*3.2)*0.014,0.0,cos(p.y*34.0-p.x*23.0-TIME*2.7)*0.014));
	}
	vec3 v=normalize(CAMERA_POSITION_WORLD-world_pos);
	float facing=clamp(dot(n,v),0.0,1.0);
	float fresnel=0.0204+0.9796*pow(1.0-facing,5.0);
	vec3 scene=view_position(SCREEN_UV,INV_PROJECTION_MATRIX);
	float depth=clamp(length(scene-VERTEX),0.0,4.0);
	vec3 nview=normalize((VIEW_MATRIX*vec4(n,0.0)).xyz);
	vec3 refracted_ray=refract(normalize(VERTEX),nview,0.7502);
	vec3 hit_est=VERTEX+refracted_ray*depth;
	vec2 uv=mix(SCREEN_UV,project_uv(hit_est,PROJECTION_MATRIX),0.56);
	uv=clamp(uv,vec2(0.002),vec2(0.998));
	if(view_position(uv,INV_PROJECTION_MATRIX).z>VERTEX.z-0.006){uv=SCREEN_UV;}
	vec3 source=texture(screen_tex,uv).rgb;
	vec3 transmission=exp(-vec3(1.25,0.24,0.12)*depth);
	vec3 through=source*transmission+vec3(0.018,0.27,0.30)*(1.0-transmission);
	vec3 reflection=sky_color(reflect(-v,n));
	if(quality>0.5){
		vec3 ray=reflect(normalize(VERTEX),nview);
		vec4 ssr=trace_reflection(VERTEX+nview*0.035,ray,PROJECTION_MATRIX,INV_PROJECTION_MATRIX,quality);
		reflection=mix(reflection,ssr.rgb,ssr.a);
	}
	float wall=min(min(UV.x,1.0-UV.x)*6.0,min(UV.y,1.0-UV.y)*4.0);
	float meniscus=exp(-wall*85.0)*0.15;
	ALBEDO=mix(through,reflection,clamp(fresnel+meniscus,0.0,1.0));
	ALPHA=1.0;
}
