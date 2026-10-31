package graphics

import "core:log"
import "core:os"
import "vendor:sdl3"

@(private)
graphics_pipeline_create :: proc() -> (pipe: ^sdl3.GPUGraphicsPipeline, err: Graphics_Error) {
	vert_shader := load_shader("res/shader.vert.spv", .VERTEX, 0, 1) or_return
	defer sdl3.ReleaseGPUShader(state.device, vert_shader)

	frag_shader := load_shader("res/shader.frag.spv", .FRAGMENT, 1, 0) or_return
	defer sdl3.ReleaseGPUShader(state.device, frag_shader)

	vert_attrs := []sdl3.GPUVertexAttribute {
		{location = 0, buffer_slot = 0, format = .FLOAT4, offset = u32(offset_of(Vertex, color))},
		{location = 1, buffer_slot = 0, format = .FLOAT3, offset = u32(offset_of(Vertex, pos))},
		{location = 2, buffer_slot = 0, format = .FLOAT2, offset = u32(offset_of(Vertex, uv))},
	}

	vert_buffers := []sdl3.GPUVertexBufferDescription {
		{slot = 0, pitch = u32(size_of(Vertex)), input_rate = .VERTEX, instance_step_rate = 0},
	}

	color_target := sdl3.GPUColorTargetDescription {
		format = sdl3.GetGPUSwapchainTextureFormat(state.device, state.window),
		blend_state = sdl3.GPUColorTargetBlendState {
			enable_blend = true,
			src_color_blendfactor = .SRC_ALPHA,
			dst_color_blendfactor = .ONE_MINUS_SRC_ALPHA,
			color_blend_op = .ADD,
			src_alpha_blendfactor = .ONE,
			dst_alpha_blendfactor = .ONE_MINUS_SRC_ALPHA,
			alpha_blend_op = .ADD,
		},
	}

	pipeline_info := sdl3.GPUGraphicsPipelineCreateInfo {
		vertex_shader = vert_shader,
		fragment_shader = frag_shader,
		vertex_input_state = sdl3.GPUVertexInputState {
			vertex_buffer_descriptions = raw_data(vert_buffers),
			num_vertex_buffers = u32(len(vert_buffers)),
			vertex_attributes = raw_data(vert_attrs),
			num_vertex_attributes = u32(len(vert_attrs)),
		},
		primitive_type = .TRIANGLELIST,
		rasterizer_state = sdl3.GPURasterizerState{fill_mode = .FILL, cull_mode = .NONE},
		target_info = sdl3.GPUGraphicsPipelineTargetInfo {
			color_target_descriptions = &color_target,
			num_color_targets = 1,
		},
	}

	pipe = sdl3.CreateGPUGraphicsPipeline(state.device, pipeline_info)
	if pipe == nil {
		log.errorf("Failed to create GPU Graphic Pipeline: %s", sdl3.GetError())
		return nil, .GRAPHICS_PIPELINE
	}

	return pipe, nil
}

@(private = "file")
load_shader :: proc(
	path: string,
	stage: sdl3.GPUShaderStage,
	num_samplers, num_uniforms: u32,
) -> (
	^sdl3.GPUShader,
	Graphics_Error,
) {
	code, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		log.errorf("Failed to load shader file: %s", path)
		return nil, .GPU_SHADER
	}
	defer delete(code)

	info := sdl3.GPUShaderCreateInfo {
		code_size            = len(code),
		code                 = raw_data(code),
		entrypoint           = "main",
		format               = {.SPIRV},
		stage                = stage,
		num_samplers         = num_samplers,
		num_storage_textures = 0,
		num_storage_buffers  = 0,
		num_uniform_buffers  = num_uniforms,
	}

	shader := sdl3.CreateGPUShader(state.device, info)
	if shader == nil {
		log.errorf("Failed to create GPU shader: %s", sdl3.GetError())
		return nil, .GPU_SHADER
	}

	return shader, nil
}
