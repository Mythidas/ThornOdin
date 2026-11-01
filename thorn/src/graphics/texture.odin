package graphics

import "core:log"
import "thorn:core"
import "vendor:sdl3"

Page_Handle :: distinct int
Texture_Handle :: distinct int

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
	pages: [dynamic]Page_Slot,
	slots: [dynamic]Texture_Slot,
}

page_create :: proc(pixels: [^]u8, w, h: int) -> (ph: Page_Handle, err: Graphics_Error) {
	tex := texture_create_from_pixels(pixels, w, h) or_return
	page := Page_Handle(len(textures.pages))
	append(&textures.pages, Page_Slot{tex = tex, size = {w, h}})

	return page, nil
}

texture_create :: proc(page_handle: Page_Handle, x, y, w, h: int) -> Texture_Handle {
	page := textures.pages[page_handle]

	tex := Texture_Handle(len(textures.slots))
	append(
		&textures.slots,
		Texture_Slot {
			page = page_handle,
			size = {w, h},
			rect = {
				f32(x) / f32(page.size.x),
				f32(y) / f32(page.size.y),
				f32(x + w) / f32(page.size.x),
				f32(y + h) / f32(page.size.y),
			},
		},
	)

	return tex
}

@(private)
texture_initialize :: proc() -> (err: Graphics_Error) {
	defer if err != nil {
		log.errorf("Failed to initialize textures")
		texture_terminate()
	}

	textures.pages = make([dynamic]Page_Slot)
	textures.slots = make([dynamic]Texture_Slot)

	dtex_pixels := []u8{255, 0, 255, 255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 0, 255, 255}
	default_tex := texture_create_from_pixels(raw_data(dtex_pixels), 2, 2) or_return

	append(&textures.pages, Page_Slot{tex = default_tex, size = {2, 2}})
	append(&textures.slots, Texture_Slot{page = 0, size = {2, 2}, rect = {0, 0, 1, 1}})
	return nil
}

@(private)
texture_terminate :: proc() {
	for &v in textures.pages {
		sdl3.ReleaseGPUTexture(state.device, v.tex)
	}

	delete(textures.pages)
	delete(textures.slots)
	textures = {}
}

@(private)
texture_find :: proc(handle: Texture_Handle) -> Texture_Slot {
	return textures.slots[handle]
}

@(private)
texture_find_page :: proc(handle: Page_Handle) -> Page_Slot {
	return textures.pages[handle]
}

@(private)
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
