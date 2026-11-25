shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform float detail_quality : hint_range(0.0,1.0) = 1.0;
varying vec3 surface_world;
void vertex(){surface_world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
float hash21(vec2 p){
	p=fract(p*vec2(123.34,456.21));
	p+=dot(p,p+45.32);
	return fract(p.x*p.y);
}
float noise2(vec2 p){
	vec2 i=floor(p),f=fract(p);
	f=f*f*(3.0-2.0*f);
	return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y);
}
void fragment(){
	vec2 p=surface_world.xz;
	float dist=length(surface_world-CAMERA_POSITION_WORLD);
	float large=noise2(p*0.19);
	float medium=noise2(p*3.5);
	float micro=noise2(p*72.0);
	float near_detail=1.0-smoothstep(8.0,24.0,dist);
	vec3 base=mix(vec3(0.33,0.34,0.33),vec3(0.53,0.51,0.47),large);
	base+=(medium-0.5)*0.055+(micro-0.5)*0.035*near_detail;
	vec2 tiles=abs(fract(p/5.0+0.5)-0.5);
	float seam=smoothstep(0.495,0.499,max(tiles.x,tiles.y));
	float stain=smoothstep(0.72,0.92,noise2(p*0.44+2.0));
	ALBEDO=base*(1.0-0.22*seam-0.12*stain);
	ROUGHNESS=clamp(0.82+0.13*medium-0.12*stain,0.58,1.0);
	METALLIC=0.0;
	SPECULAR=0.35;
	if(detail_quality>0.1 && near_detail>0.01){
		float dx=noise2(p*72.0+vec2(0.12,0.0))-micro;
		float dy=noise2(p*72.0+vec2(0.0,0.12))-micro;
		NORMAL_MAP=normalize(vec3(-dx*0.22,-dy*0.22,1.0))*0.5+0.5;
		NORMAL_MAP_DEPTH=0.65*near_detail;
	}
}
