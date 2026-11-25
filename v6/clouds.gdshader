shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, fog_disabled, shadows_disabled;
uniform vec3 sun_direction = vec3(-0.6,0.6,0.5);
uniform float detail_quality : hint_range(0.0,1.0) = 0.65;
varying vec3 sky_position;
void vertex(){
	sky_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
float hash21(vec2 p){
	p=fract(p*vec2(123.34,456.21));
	p+=dot(p,p+45.32);
	return fract(p.x*p.y);
}
float noise2(vec2 p){
	vec2 i=floor(p), f=fract(p);
	f=f*f*(3.0-2.0*f);
	return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y);
}
float cloud_field(vec2 p){
	float a=noise2(p)*0.54+noise2(p*2.03+8.0)*0.27+noise2(p*4.1-13.0)*0.13;
	if(detail_quality>0.1){a+=noise2(p*8.2+2.0)*0.06;}
	else{a+=0.03;}
	if(detail_quality>0.9){a+=noise2(p*15.5)*0.025-0.0125;}
	return a;
}
void fragment(){
	vec3 d=normalize(sky_position-CAMERA_POSITION_WORLD);
	float altitude=max(d.y,0.0);
	vec2 p=d.xz/(altitude+0.19)*2.25+vec2(TIME*0.011,-TIME*0.004);
	float n=cloud_field(p);
	float wisps=noise2(p*0.52+vec2(31.0,12.0));
	float density=smoothstep(0.48,0.72,n+0.08*wisps);
	float horizon=smoothstep(0.015,0.16,altitude);
	float sun_dot=max(dot(d,normalize(sun_direction)),0.0);
	float edge=cloud_field(p+vec2(0.10,-0.07))-n;
	float bright=clamp(0.6+edge*3.0+0.20*pow(sun_dot,9.0),0.0,1.0);
	vec3 shaded=mix(vec3(0.53,0.62,0.72),vec3(1.0,0.97,0.91),bright);
	float cloud_alpha=density*horizon*0.92;
	float halo=pow(sun_dot,35.0)*0.14+pow(sun_dot,220.0)*0.23;
	vec3 axis=normalize(cross(normalize(sun_direction),vec3(0,1,0)));
	vec3 axis2=cross(normalize(sun_direction),axis);
	float angle=atan(dot(d,axis2),dot(d,axis)+0.00001);
	float rays=pow(abs(cos(angle*4.0+0.32)),18.0)*pow(sun_dot,75.0)*0.035;
	float glare=(halo+rays)*(1.0-cloud_alpha*0.83)*horizon;
	float opacity=cloud_alpha+glare*(1.0-cloud_alpha);
	ALBEDO=mix(vec3(1.0,0.88,0.64),shaded,cloud_alpha/max(opacity,0.001));
	ALPHA=clamp(opacity,0.0,1.0);
}
