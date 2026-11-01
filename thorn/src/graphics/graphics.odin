package graphics

/*
	Graphics renderer.
	Images:
		- Image: Physical Representation on Disk
		- Texture: Physical Representation on GPU
		- Sprite: Logical view of Texture
*/

import "core:log"
import "thorn:core"
import "thorn:window"
import "vendor:sdl3"

MAX_QUADS :: 10_000
MAX_INDICES :: MAX_QUADS * 6
MAX_VERTICES :: MAX_QUADS * 4

Graphics_Error :: enum {
	NONE,
	CLAIM_WINDOW,
	INVALID_WINDOW,
	GRAPHICS_PIPELINE,
	GPU_BUFFER,
	GPU_SHADER,
	GPU_DEVICE,
	GPU_TEXTURE,
}

Vertex :: struct {
	pos:   core.Vec3,
	color: core.Color,
	uv:    core.Vec2,
}

Camera_Uniform :: struct {
	mvp: core.Mat4,
}

Draw_Call :: struct {
	texture:     ^sdl3.GPUTexture,
	index_count: u32,
	index_off:   u32,
}

@(private)
state: struct {
	init:             bool,
	window:           ^sdl3.Window,
	device:           ^sdl3.GPUDevice,
	pipeline:         ^sdl3.GPUGraphicsPipeline,
	vbo:              GPU_Buffer,
	ibo:              GPU_Buffer,
	vbo_txb:          ^sdl3.GPUTransferBuffer,
	sampler:          ^sdl3.GPUSampler,
	calls:            [dynamic]Draw_Call,

	// CPU buffer
	vertices:         []Vertex,
	vertex_count:     u32,
	index_count:      u32,

	// Runtime
	camera:           Camera,
	camera_transform: core.Transform,
}

initialize :: proc() -> (err: Graphics_Error) {
	ensure(state.init == false, "Graphics.initialize() already called")

	state.window = window.get_native()
	if state.window == nil do return .INVALID_WINDOW

	state.device = sdl3.CreateGPUDevice({.SPIRV}, true, nil)
	if state.device == nil {
		log.errorf("Failed to create GPUDevice: %s", sdl3.GetError())
		return .GPU_DEVICE
	}
	defer if err != nil do sdl3.DestroyGPUDevice(state.device)

	if res := sdl3.ClaimWindowForGPUDevice(state.device, state.window); !res {
		log.errorf("Failed to claim window for GPU: %s", sdl3.GetError())
		return .CLAIM_WINDOW
	}
	defer if err != nil do sdl3.ReleaseWindowFromGPUDevice(state.device, state.window)

	state.pipeline = graphics_pipeline_create() or_return
	defer if err != nil do sdl3.ReleaseGPUGraphicsPipeline(state.device, state.pipeline)

	state.sampler = sdl3.CreateGPUSampler(
		state.device,
		sdl3.GPUSamplerCreateInfo {
			min_filter = .NEAREST,
			mag_filter = .NEAREST,
			mipmap_mode = .NEAREST,
			address_mode_u = .CLAMP_TO_EDGE,
			address_mode_v = .CLAMP_TO_EDGE,
			address_mode_w = .CLAMP_TO_EDGE,
		},
	)
	defer if err != nil do sdl3.ReleaseGPUSampler(state.device, state.sampler)

	texture_initialize() or_return
	defer if err != nil do texture_terminate()

	state.vertices = make([]Vertex, MAX_VERTICES)
	defer if err != nil do delete(state.vertices)

	state.vbo = buffer_create(
		{usage = sdl3.GPUBufferUsageFlags{.VERTEX}, size = size_of(Vertex) * MAX_VERTICES},
	) or_return
	defer if err != nil do buffer_destroy(&state.vbo)

	state.vbo_txb = sdl3.CreateGPUTransferBuffer(
		state.device,
		sdl3.GPUTransferBufferCreateInfo{usage = .UPLOAD, size = state.vbo.size},
	)
	if state.vbo_txb == nil {
		log.errorf("Failed to create transfer buffer: %s", sdl3.GetError())
		return .GPU_BUFFER
	}
	defer if err != nil do sdl3.ReleaseGPUTransferBuffer(state.device, state.vbo_txb)

	state.ibo = buffer_create(
		{usage = sdl3.GPUBufferUsageFlags{.INDEX}, size = size_of(u32) * MAX_INDICES},
	) or_return
	defer if err != nil do buffer_destroy(&state.ibo)

	index: u32 = 0
	indices := [MAX_INDICES]u32{}
	for i := 0; i < MAX_INDICES; i += 6 {
		indices[i + 0] = index + 0
		indices[i + 1] = index + 1
		indices[i + 2] = index + 2
		indices[i + 3] = index + 2
		indices[i + 4] = index + 3
		indices[i + 5] = index + 0

		index += 4
	}

	buffer_upload(&state.ibo, indices[:]) or_return

	log.info("Graphics Initialized")
	state.init = true
	return nil
}

terminate :: proc() {
	ensure(state.init, "Graphics.initialize() needs to be called")

	delete(state.calls)
	delete(state.vertices)
	texture_terminate()

	sdl3.ReleaseGPUSampler(state.device, state.sampler)
	buffer_destroy(&state.vbo)
	buffer_destroy(&state.ibo)
	sdl3.ReleaseGPUTransferBuffer(state.device, state.vbo_txb)
	sdl3.ReleaseGPUGraphicsPipeline(state.device, state.pipeline)
	sdl3.ReleaseWindowFromGPUDevice(state.device, state.window)
	sdl3.DestroyGPUDevice(state.device)

	state.init = false
	state = {}

	log.info("Graphics Terminated")
}

begin_frame :: proc(cam: Camera, cam_transform: core.Transform) {
	state.vertex_count = 0
	state.index_count = 0
	state.camera = cam
	state.camera_transform = cam_transform

	clear(&state.calls)
}

end_frame :: proc() {
	if state.vertex_count > 0 {
		buffer_upload(&state.vbo, state.vertices[:state.vertex_count], state.vbo_txb)
	}

	cmd := sdl3.AcquireGPUCommandBuffer(state.device)

	swap_tex: ^sdl3.GPUTexture
	swap_tex_w: u32 = 0
	swap_tex_h: u32 = 0
	if !sdl3.WaitAndAcquireGPUSwapchainTexture(
		cmd,
		state.window,
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
		clear_color = sdl3.FColor(state.camera.clear_color),
		store_op    = .STORE,
	}

	pass := sdl3.BeginGPURenderPass(cmd, &color_target, 1, nil)
	sdl3.BindGPUGraphicsPipeline(pass, state.pipeline)

	vbuf_binding := sdl3.GPUBufferBinding {
		buffer = state.vbo.handle,
		offset = 0,
	}
	sdl3.BindGPUVertexBuffers(pass, 0, &vbuf_binding, 1)

	ibuf_binding := sdl3.GPUBufferBinding {
		buffer = state.ibo.handle,
		offset = 0,
	}
	sdl3.BindGPUIndexBuffer(pass, ibuf_binding, ._32BIT)

	vert_u := Camera_Uniform {
		mvp = camera_calculate_matrix(
			state.camera,
			state.camera_transform,
			f32(swap_tex_w),
			f32(swap_tex_h),
		),
	}
	sdl3.PushGPUVertexUniformData(cmd, 0, &vert_u, size_of(vert_u))

	for &call in state.calls {
		binding := sdl3.GPUTextureSamplerBinding {
			texture = call.texture,
			sampler = state.sampler,
		}
		sdl3.BindGPUFragmentSamplers(pass, 0, &binding, 1)

		sdl3.DrawGPUIndexedPrimitives(pass, call.index_count, 1, call.index_off, 0, 0)
	}

	sdl3.EndGPURenderPass(pass)
	if !sdl3.SubmitGPUCommandBuffer(cmd) {
		log.errorf("GPU Submit Command failed: %s", sdl3.GetError())
	}
}

draw_sprite :: proc(
	transform: core.Transform,
	color: core.Color = {1, 1, 1, 1},
	sprite: Sprite_View,
) {
	uvs := [4]core.Vec2 {
		{sprite.uvs.x_min, sprite.uvs.y_min},
		{sprite.uvs.x_max, sprite.uvs.y_min},
		{sprite.uvs.x_max, sprite.uvs.y_max},
		{sprite.uvs.x_min, sprite.uvs.y_max},
	}

	draw_quad(transform, color, uvs, sprite.texture)
}

draw_quad :: proc(
	transform: core.Transform,
	color: core.Color = {1, 1, 1, 1},
	uvs: [4]core.Vec2 = {{0, 0}, {1, 0}, {1, 1}, {0, 1}},
	texture: Texture_Handle = 0,
) {
	if state.vertex_count + 4 > MAX_VERTICES {
		log.warn("Graphics quad limit reached, dropped draw")
		return
	}

	tex := texture_find(texture)
	corners := [4]core.Vec2{{-0.5, -0.5}, {0.5, -0.5}, {0.5, 0.5}, {-0.5, 0.5}}

	model := core.transform_matrix(transform)

	for i in 0 ..< 4 {
		local := core.Vec4{corners[i].x, corners[i].y, 0, 1}
		world := model * local

		tex_uv := core.Vec2 {
			tex.rect.x_min + uvs[i].x * (tex.rect.x_max - tex.rect.x_min),
			tex.rect.y_min + uvs[i].y * (tex.rect.y_max - tex.rect.y_min),
		}

		state.vertices[int(state.vertex_count) + i] = Vertex {
			color = color,
			pos   = world.xyz,
			uv    = tex_uv,
		}
	}

	state.vertex_count += 4
	state.index_count += 6

	push_call(texture)
}

@(private = "file")
push_call :: proc(tex_h: Texture_Handle) {
	n := len(state.calls)
	tex := texture_find_page(texture_find(tex_h).page).tex

	if n > 0 {
		last := &state.calls[n - 1]
		if last.texture == tex {
			last.index_count += 6
			return
		}
	}

	append(
		&state.calls,
		Draw_Call{texture = tex, index_off = state.index_count - 6, index_count = 6},
	)
}

