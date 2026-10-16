package graphics

import "core:log"
import "core:math/linalg"
import "core:os"
import "vendor:sdl3"

MAX_QUADS :: 10_000
MAX_INDICES :: MAX_QUADS * 6
MAX_VERTICES :: MAX_QUADS * 4

Vertex :: struct {
	color: [4]f32,
	pos:   [3]f32,
	uv:    [2]f32,
}

CameraProjection :: enum {
	ORTHOGRAPHIC,
	PERSPECTIVE,
}

Camera :: struct {
	fov:         f32,
	zoom:        f32,
	near, far:   f32,
	clear_color: [4]f32,
	mode:        CameraProjection,
}

CameraUniform :: struct {
	mvp: matrix[4, 4]f32,
}

Renderer :: struct {
	window:          ^sdl3.Window,
	device:          ^sdl3.GPUDevice,
	pipeline:        ^sdl3.GPUGraphicsPipeline,
	vbo:             ^sdl3.GPUBuffer,
	ibo:             ^sdl3.GPUBuffer,
	default_texture: Texture,
	sampler:         ^sdl3.GPUSampler,

	// CPU buffer
	vertices:        [dynamic]Vertex,
	index_count:     u32,
	vertex_count:    u32,

	// Runtime
	camera:          Camera,
	camera_pos:      [3]f32,
	camera_rot:      [3]f32,
}

calc_camera_matrix :: proc(cam: Camera, pos: [3]f32, rot: [3]f32, w, h: f32) -> matrix[4, 4]f32 {
	aspect: f32 = w / h

	mat := linalg.MATRIX4F32_IDENTITY
	if cam.mode == .PERSPECTIVE {
		mat = linalg.matrix4_perspective(linalg.to_radians(cam.fov), aspect, cam.near, cam.far)
	} else {
		half_h: f32 = cam.zoom * 0.5
		half_w: f32 = half_h * aspect
		mat = linalg.matrix_ortho3d(-half_w, half_w, -half_h, half_h, cam.near, cam.far)
	}

	return(
		mat *
		linalg.matrix4_translate(pos) *
		linalg.matrix4_rotate(linalg.to_radians(rot.x), [3]f32{1, 0, 0}) *
		linalg.matrix4_rotate(linalg.to_radians(rot.y), [3]f32{0, 1, 0}) *
		linalg.matrix4_rotate(linalg.to_radians(rot.z), [3]f32{0, 0, 1}) \
	)
}

load_shader :: proc(
	renderer: ^Renderer,
	path: string,
	stage: sdl3.GPUShaderStage,
	num_samplers, num_uniforms: u32,
) -> (
	^sdl3.GPUShader,
	Error,
) {
	code, err := os.read_entire_file(path, context.allocator)
	if err != nil do return nil, .INVALID_FILE
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

	shader := sdl3.CreateGPUShader(renderer.device, info)
	if shader == nil {
		log.errorf("Failed to create GPU shader: %s", sdl3.GetError())
		return nil, .CREATE_GPU_SHADER
	}

	return shader, nil
}

buffer_upload :: proc(renderer: ^Renderer, buff: ^sdl3.GPUBuffer, data: []$T) {
	if len(data) == 0 {return}

	size := len(data) * size_of(T)

	transfer := sdl3.CreateGPUTransferBuffer(
		renderer.device,
		sdl3.GPUTransferBufferCreateInfo{usage = .UPLOAD, size = u32(size)},
	)
	mapped := ([^]T)(sdl3.MapGPUTransferBuffer(renderer.device, transfer, false))
	copy(mapped[:len(data)], data[:])
	sdl3.UnmapGPUTransferBuffer(renderer.device, transfer)

	cmd := sdl3.AcquireGPUCommandBuffer(renderer.device)
	copy_pass := sdl3.BeginGPUCopyPass(cmd)
	src := sdl3.GPUTransferBufferLocation {
		transfer_buffer = transfer,
		offset          = 0,
	}
	dst := sdl3.GPUBufferRegion {
		buffer = buff,
		offset = 0,
		size   = u32(size),
	}

	sdl3.UploadToGPUBuffer(copy_pass, src, dst, false)
	sdl3.EndGPUCopyPass(copy_pass)
	assert(sdl3.SubmitGPUCommandBuffer(cmd))

	sdl3.ReleaseGPUTransferBuffer(renderer.device, transfer)
}

create_graphics_pipeline :: proc(renderer: ^Renderer) -> (err: Error) {
	vert_shader := load_shader(renderer, "res/shader.vert.spv", .VERTEX, 0, 1) or_return
	frag_shader := load_shader(renderer, "res/shader.frag.spv", .FRAGMENT, 1, 0) or_return

	vert_attrs := []sdl3.GPUVertexAttribute {
		{location = 0, buffer_slot = 0, format = .FLOAT4, offset = u32(offset_of(Vertex, color))},
		{location = 1, buffer_slot = 0, format = .FLOAT3, offset = u32(offset_of(Vertex, pos))},
		{location = 2, buffer_slot = 0, format = .FLOAT2, offset = u32(offset_of(Vertex, uv))},
	}

	vert_buffers := []sdl3.GPUVertexBufferDescription {
		{slot = 0, pitch = u32(size_of(Vertex)), input_rate = .VERTEX, instance_step_rate = 0},
	}

	color_target := sdl3.GPUColorTargetDescription {
		format = sdl3.GetGPUSwapchainTextureFormat(renderer.device, renderer.window),
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

	renderer.pipeline = sdl3.CreateGPUGraphicsPipeline(renderer.device, pipeline_info)
	if renderer.pipeline == nil {
		log.errorf("Failed to create GPU Graphic Pipeline: %s", sdl3.GetError())
		return .CREATE_GRAPHICS_PIPELINE
	}

	sdl3.ReleaseGPUShader(renderer.device, vert_shader)
	sdl3.ReleaseGPUShader(renderer.device, frag_shader)

	return nil
}

create_renderer :: proc(renderer: ^Renderer, window: ^sdl3.Window) -> (err: Error) {
	ensure(window != nil)

	renderer.window = window
	defer if err != nil do destroy_renderer(renderer)

	renderer.device = sdl3.CreateGPUDevice({.SPIRV}, true, nil)
	if renderer.device == nil {
		log.errorf("Failed to create GPUDevice: %s", sdl3.GetError())
		return .CREATE_GPU_DEVICE
	}

	if res := sdl3.ClaimWindowForGPUDevice(renderer.device, renderer.window); !res {
		log.errorf("Failed to claim window for GPU: %s", sdl3.GetError())
		return .CLAIM_WINDOW
	}

	create_graphics_pipeline(renderer) or_return

	renderer.sampler = sdl3.CreateGPUSampler(
		renderer.device,
		sdl3.GPUSamplerCreateInfo {
			min_filter = .NEAREST,
			mag_filter = .NEAREST,
			mipmap_mode = .NEAREST,
			address_mode_u = .CLAMP_TO_EDGE,
			address_mode_v = .CLAMP_TO_EDGE,
			address_mode_w = .CLAMP_TO_EDGE,
		},
	)

	white_pixel := [4]u8{255, 255, 255, 255}
	renderer.default_texture = create_texture(renderer.device, raw_data(white_pixel[:]), 1, 1)

	renderer.vertices = make([dynamic]Vertex, MAX_VERTICES)
	renderer.vbo = sdl3.CreateGPUBuffer(
		renderer.device,
		sdl3.GPUBufferCreateInfo {
			usage = sdl3.GPUBufferUsageFlags{.VERTEX},
			size = size_of(Vertex) * MAX_VERTICES,
		},
	)

	renderer.ibo = sdl3.CreateGPUBuffer(
		renderer.device,
		sdl3.GPUBufferCreateInfo {
			usage = sdl3.GPUBufferUsageFlags{.INDEX},
			size = size_of(u16) * MAX_INDICES,
		},
	)

	index: u16 = 0
	indices := [MAX_INDICES]u16{}
	for i := 0; i < MAX_INDICES; i += 6 {
		indices[i + 0] = index + 0
		indices[i + 1] = index + 1
		indices[i + 2] = index + 2
		indices[i + 3] = index + 2
		indices[i + 4] = index + 3
		indices[i + 5] = index + 0

		index += 4
	}

	buffer_upload(renderer, renderer.ibo, indices[:])

	return nil
}

destroy_renderer :: proc(renderer: ^Renderer) {
	if renderer == nil do return

	delete(renderer.vertices)
	destroy_texture(renderer.device, &renderer.default_texture)

	sdl3.ReleaseGPUSampler(renderer.device, renderer.sampler)
	sdl3.ReleaseGPUBuffer(renderer.device, renderer.vbo)
	sdl3.ReleaseGPUBuffer(renderer.device, renderer.ibo)
	sdl3.ReleaseGPUGraphicsPipeline(renderer.device, renderer.pipeline)
	sdl3.ReleaseWindowFromGPUDevice(renderer.device, renderer.window)
	sdl3.DestroyGPUDevice(renderer.device)

	renderer^ = {}
}

renderer_begin_frame :: proc(renderer: ^Renderer, cam: Camera, cam_pos: [3]f32, cam_rot: [3]f32) {
	renderer.vertex_count = 0
	renderer.index_count = 0
	renderer.camera = cam
	renderer.camera_pos = cam_pos
	renderer.camera_rot = cam_rot
}

renderer_end_frame :: proc(renderer: ^Renderer) {
	vbytes := renderer.vertex_count * size_of(Vertex)

	if renderer.vertex_count > 0 {
		buffer_upload(renderer, renderer.vbo, renderer.vertices[:renderer.vertex_count])
	}

	cmd := sdl3.AcquireGPUCommandBuffer(renderer.device)

	swap_tex: ^sdl3.GPUTexture
	swap_tex_w: u32 = 0
	swap_tex_h: u32 = 0
	if !sdl3.WaitAndAcquireGPUSwapchainTexture(
		cmd,
		renderer.window,
		&swap_tex,
		&swap_tex_w,
		&swap_tex_h,
	) {
		log.errorf("Swapchain image acquire failed: %s", sdl3.GetError())
		assert(sdl3.SubmitGPUCommandBuffer(cmd))
		return
	}

	if swap_tex == nil {
		log.error("No swapchain image found")
		assert(sdl3.SubmitGPUCommandBuffer(cmd))
		return
	}

	color_target := sdl3.GPUColorTargetInfo {
		texture     = swap_tex,
		load_op     = .CLEAR,
		clear_color = sdl3.FColor(renderer.camera.clear_color),
		store_op    = .STORE,
	}

	pass := sdl3.BeginGPURenderPass(cmd, &color_target, 1, nil)
	sdl3.BindGPUGraphicsPipeline(pass, renderer.pipeline)

	vbuf_binding := sdl3.GPUBufferBinding {
		buffer = renderer.vbo,
		offset = 0,
	}
	sdl3.BindGPUVertexBuffers(pass, 0, &vbuf_binding, 1)

	ibuf_binding := sdl3.GPUBufferBinding {
		buffer = renderer.ibo,
		offset = 0,
	}
	sdl3.BindGPUIndexBuffer(pass, ibuf_binding, ._16BIT)

	vert_u := CameraUniform {
		mvp = calc_camera_matrix(
			renderer.camera,
			renderer.camera_pos,
			renderer.camera_rot,
			f32(swap_tex_w),
			f32(swap_tex_h),
		),
	}
	sdl3.PushGPUVertexUniformData(cmd, 0, &vert_u, size_of(vert_u))

	binding := sdl3.GPUTextureSamplerBinding {
		texture = renderer.default_texture.handle,
		sampler = renderer.sampler,
	}
	sdl3.BindGPUFragmentSamplers(pass, 0, &binding, 1)
	sdl3.DrawGPUIndexedPrimitives(pass, renderer.index_count, 1, 0, 0, 0)

	sdl3.EndGPURenderPass(pass)
	assert(sdl3.SubmitGPUCommandBuffer(cmd))
}

draw_quad :: proc(
	renderer: ^Renderer,
	pos: [3]f32 = {0, 0, 0},
	rot: [3]f32 = {0, 0, 0},
	scale: [3]f32 = {1, 1, 1},
	color: [4]f32 = {1, 1, 1, 1},
) {
	corners := [4][2]f32{{-0.5, -0.5}, {0.5, -0.5}, {0.5, 0.5}, {-0.5, 0.5}}
	uvs := [4][2]f32{{0, 0}, {1, 0}, {1, 1}, {0, 1}}

	make_model :: proc(pos: [3]f32, rot: [3]f32, scale: [3]f32) -> matrix[4, 4]f32 {
		return(
			linalg.matrix4_translate(pos) *
			linalg.matrix4_rotate(linalg.to_radians(rot.x), [3]f32{1, 0, 0}) *
			linalg.matrix4_rotate(linalg.to_radians(rot.y), [3]f32{0, 1, 0}) *
			linalg.matrix4_rotate(linalg.to_radians(rot.z), [3]f32{0, 0, 1}) *
			linalg.matrix4_scale(scale) \
		)
	}

	model := make_model(pos, rot, scale)

	for i in 0 ..< 4 {
		local := [4]f32{corners[i].x, corners[i].y, 0, 1}
		world := model * local

		renderer.vertices[int(renderer.vertex_count) + i] = Vertex {
			color = color,
			pos   = world.xyz,
			uv    = uvs[i],
		}
	}

	renderer.vertex_count += 4
	renderer.index_count += 6
}
