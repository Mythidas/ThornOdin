package graphics

import "core:log"
import "thorn:core"
import "vendor:sdl3"

Page_Handle :: core.Handle(Page_Slot)
Texture_Handle :: core.Handle(Texture_Slot)

@(private)
Texture_Slot :: struct {
	size: core.IVec2,
	rect: core.Rect,
	page: Page_Handle,
}

@(private)
Page_Slot :: struct {
	tex:  ^sdl3.GPUTexture,
	size: core.IVec2,
}

@(private = "file")
textures: struct {
	pages:    core.Handle_Store(Page_Slot),
	textures: core.Handle_Store(Texture_Slot),
}

page_create :: proc(pixels: []u8, w, h: int) -> (ph: Page_Handle, err: Graphics_Error) {
	ensure(w > 0 && h > 0, "Page size must be positive")
	ensure(len(pixels) >= w * h * 4, "Pixels buffer smaller than w * h * 4")

	gpu := texture_create_from_pixels(raw_data(pixels), w, h) or_return

	handle, data := core.handles_slot_acquire(&textures.pages)
	data.tex = gpu
	data.size = core.IVec2{w, h}

	log.debugf("Page created: index=%d gen=%d size=%dx%d", handle.idx, handle.gen, w, h)
	return handle, nil
}

page_destroy :: proc(handle: Page_Handle) {
	ensure(handle.idx != 0, "Cannot destroy the default page")

	data, ok := core.handles_slot_get(&textures.pages, handle)
	if !ok {
		log.warnf("Stale or invalid handle: %v", handle)
		return
	}

	for &t, i in textures.textures.data {
		if t.data.page == handle {
			core.handles_slot_release(&textures.textures, Texture_Handle{u32(i), t.gen})
		}
	}

	sdl3.ReleaseGPUTexture(state.device, data.tex)
	core.handles_slot_release(&textures.pages, handle)
}

texture_create :: proc(
	page_handle: Page_Handle,
	x, y, w, h: int,
) -> (
	th: Texture_Handle,
	err: Graphics_Error,
) {
	page, ok := core.handles_slot_get(&textures.pages, page_handle)
	if !ok {
		log.errorf("Invalid page handle %v", page_handle)
		return {}, .INVALID_HANDLE
	}

	ensure(w > 0 && h > 0, "Region size must be positive")
	ensure(
		x >= 0 && y >= 0 && x + w <= page.size.x && y + h <= page.size.y,
		"Region outside page bounds",
	)

	handle, data := core.handles_slot_acquire(&textures.textures)
	data.page = page_handle
	data.size = {w, h}
	data.rect = {
		f32(x) / f32(page.size.x),
		f32(y) / f32(page.size.y),
		f32(x + w) / f32(page.size.x),
		f32(y + h) / f32(page.size.y),
	}

	return handle, nil
}

texture_destroy :: proc(handle: Texture_Handle) {
	ensure(handle.idx != 0, "Cannot destroy the default texture")

	_, ok := core.handles_slot_get(&textures.textures, handle)
	if !ok {
		log.warnf("Stale or invalid handle %v", handle)
		return
	}

	core.handles_slot_release(&textures.textures, handle)
}

@(private)
texture_initialize :: proc() -> (err: Graphics_Error) {
	defer if err != nil {
		log.errorf("Failed to initialize textures")
		texture_terminate()
	}

	textures.pages = core.handles_store_create(Page_Slot)
	textures.textures = core.handles_store_create(Texture_Slot)

	dtex_pixels := []u8{255, 0, 255, 255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 0, 255, 255}
	default_tex := texture_create_from_pixels(raw_data(dtex_pixels), 2, 2) or_return

	handle, page := core.handles_slot_acquire(&textures.pages)
	page^ = {
		tex  = default_tex,
		size = {2, 2},
	}

	_, tex := core.handles_slot_acquire(&textures.textures)
	tex^ = {
		page = handle,
		size = {2, 2},
		rect = {0, 0, 1, 1},
	}
	return nil
}

@(private)
texture_terminate :: proc() {
	for &v in textures.pages.data {
		if v.data.tex == nil do continue
		sdl3.ReleaseGPUTexture(state.device, v.data.tex)
	}

	core.handles_store_destroy(&textures.pages)
	core.handles_store_destroy(&textures.textures)
	textures = {}
}

@(private)
texture_find :: proc(handle: Texture_Handle) -> ^Texture_Slot {
	return core.handles_slot_get_or_default(&textures.textures, handle)
}

@(private)
texture_find_page :: proc(handle: Page_Handle) -> ^Page_Slot {
	return core.handles_slot_get_or_default(&textures.pages, handle)
}

@(private = "file")
texture_create_from_pixels :: proc(
	pixels: [^]u8,
	w, h: int,
) -> (
	tex: ^sdl3.GPUTexture,
	err: Graphics_Error,
) {
	tex_info := sdl3.GPUTextureCreateInfo {
		type                 = .D2,
		format               = .R8G8B8A8_UNORM_SRGB,
		usage                = sdl3.GPUTextureUsageFlags{.SAMPLER},
		width                = u32(w),
		height               = u32(h),
		layer_count_or_depth = 1,
		num_levels           = 1,
	}
	gputex := sdl3.CreateGPUTexture(state.device, tex_info)
	if gputex == nil {
		log.errorf("GPU Create Texture failed: %s", sdl3.GetError())
		return {}, .GPU_TEXTURE
	}
	defer if err != nil do sdl3.ReleaseGPUTexture(state.device, gputex)

	byte_size := u32(w * h * 4)
	transfer := sdl3.CreateGPUTransferBuffer(
		state.device,
		sdl3.GPUTransferBufferCreateInfo{usage = .UPLOAD, size = byte_size},
	)
	if transfer == nil {
		log.errorf("GPU Create Transfer Buffer failed: %s", sdl3.GetError())
		return {}, .GPU_TEXTURE
	}
	defer sdl3.ReleaseGPUTransferBuffer(state.device, transfer)

	mapped := ([^]u8)(sdl3.MapGPUTransferBuffer(state.device, transfer, false))
	if mapped == nil {
		log.errorf("Failed to map transfer buffer: %s", sdl3.GetError())
		return {}, .GPU_TEXTURE
	}

	copy(mapped[:byte_size], pixels[:byte_size])
	sdl3.UnmapGPUTransferBuffer(state.device, transfer)

	cmd := sdl3.AcquireGPUCommandBuffer(state.device)
	if cmd == nil {
		log.errorf("Failed to acquire cmd buffer: %s", sdl3.GetError())
		return {}, .GPU_TEXTURE
	}

	copy_pass := sdl3.BeginGPUCopyPass(cmd)

	src := sdl3.GPUTextureTransferInfo {
		transfer_buffer = transfer,
		offset          = 0,
	}
	dst := sdl3.GPUTextureRegion {
		texture = gputex,
		w       = u32(w),
		h       = u32(h),
		d       = 1,
	}
	sdl3.UploadToGPUTexture(copy_pass, src, dst, false)

	sdl3.EndGPUCopyPass(copy_pass)
	if !sdl3.SubmitGPUCommandBuffer(cmd) {
		log.errorf("GPU submit failed: %s", sdl3.GetError())
		return {}, .GPU_TEXTURE
	}

	return gputex, nil
}
