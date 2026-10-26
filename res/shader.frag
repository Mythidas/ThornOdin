#version 450

layout(location = 0) in  vec2 in_uv;
layout(location = 1) in  vec4 in_color;
layout(location = 0) out vec4 out_color;

layout(set = 2, binding = 0) uniform sampler2D tex0;

void main() {
	vec4 tex_color = texture(tex0, in_uv);
	out_color = tex_color * in_color;
}
