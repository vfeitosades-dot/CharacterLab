shader_type spatial;
render_mode diffuse_burley;
varying vec3 world_position;
void vertex(){ world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment(){
 vec2 p = world_position.xz;
 vec2 fw = max(fwidth(p), vec2(0.001));
 vec2 g = abs(fract(p-0.5)-0.5) / fw;
 float line = 1.0-min(min(g.x,g.y),1.0);
 vec2 h = abs(fract(p/5.0-0.5)-0.5) / (fw/5.0);
 float major = 1.0-min(min(h.x,h.y),1.0);
 ALBEDO = mix(vec3(0.37,0.40,0.43),vec3(0.26,0.29,0.32),max(line*0.55,major*0.8));
 ROUGHNESS = 0.94;
}
