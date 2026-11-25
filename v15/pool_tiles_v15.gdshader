shader_type spatial;
uniform vec3 sun_direction=vec3(0.5,0.6,0.5);
varying vec3 wp;
varying vec3 wn;
void vertex(){
	wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	wn=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
vec2 rand2(vec2 p){
	return fract(sin(vec2(dot(p,vec2(127.1,311.7)),dot(p,vec2(269.5,183.3))))*43758.5453);
}
float cell_light(vec2 p,float t){
	vec2 i=floor(p),f=fract(p);
	float first=10.0,second=10.0;
	for(int y=-1;y<=1;y++){
		for(int x=-1;x<=1;x++){
			vec2 g=vec2(float(x),float(y));
			vec2 offset=0.5+0.36*sin(t+6.2831853*rand2(i+g));
			float d=length(g+offset-f);
			if(d<first){second=first;first=d;}else if(d<second){second=d;}
		}
	}
	return 1.0-smoothstep(0.012,0.105,second-first);
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
		float depth=0.29-wp.y;
		vec2 q=(wp.xz+sun_direction.xz*depth/max(sun_direction.y,0.2))*5.4;
		q+=vec2(sin(q.y*0.64+TIME*0.52),cos(q.x*0.71-TIME*0.44))*0.52;
		float a=cell_light(q,TIME*0.62);
		float b=cell_light(q*1.36+vec2(15.7,8.3),-TIME*0.43);
		float focused=(a*0.78+b*0.22)*exp(-depth*1.2);
		EMISSION=vec3(0.62,0.91,0.90)*focused*0.24;
	}
}
