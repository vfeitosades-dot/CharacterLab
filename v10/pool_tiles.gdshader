shader_type spatial;
varying vec3 wp;
varying vec3 wn;
void vertex(){
	wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	wn=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
void fragment(){
	vec2 p=wp.xz;
	if(abs(wn.x)>0.5){p=wp.zy;}
	else if(abs(wn.z)>0.5){p=wp.xy;}
	vec2 uv=fract(p/0.20);
	float edge=min(min(uv.x,1.0-uv.x),min(uv.y,1.0-uv.y));
	float grout=1.0-smoothstep(0.025,0.055,edge);
	float tile=fract(sin(dot(floor(p/0.20),vec2(12.9898,78.233)))*43758.5453);
	vec3 base=mix(vec3(0.25,0.53,0.57),vec3(0.42,0.69,0.72),tile);
	ALBEDO=mix(base,vec3(0.72,0.78,0.76),grout);
	ROUGHNESS=0.48+grout*0.36;
	if(wp.y<0.29){
		vec2 q=wp.xz*5.8+vec2(sin(wp.z*4.0+TIME*0.7),cos(wp.x*3.0-TIME*0.5))*0.85;
		float a=abs(sin(q.x+sin(q.y*1.8+TIME*0.6)));
		float b=abs(sin(q.y*1.37+sin(q.x*1.4-TIME*0.8)));
		float caustic=pow(1.0-min(a,b),8.0)*0.16;
		EMISSION=vec3(0.57,0.88,0.91)*caustic;
	}
}
