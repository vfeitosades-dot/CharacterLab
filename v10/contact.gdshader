shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float strength=0.24;
void fragment(){
	vec2 p=(UV-vec2(0.5))*2.0;
	float d=dot(p,p);
	ALBEDO=vec3(0.035,0.045,0.06);
	ALPHA=exp(-d*5.0)*(1.0-smoothstep(0.50,1.0,d))*strength;
}
