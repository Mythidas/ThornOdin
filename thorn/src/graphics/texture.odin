package graphics

import "core:log"
import "core:strings"
import "vendor:sdl3"
import stbi "vendor:stb/image"

Texture_Error :: enum {
	NONE,
	TEXTURE_IMAGE_LOAD,
	TEXTURE_COPY_CMD,
	TEXTURE_CREATE,
}

Texture_Handle :: distinct int

Texture_Slot :: struct {
	page: ^sdl3.GPUTexture,
	rect: [4]f32,
	size: [2]int,
}

@(private)
textures: struct {
	slots:   [dynamic]Texture_Slot,
	by_path: map[string]Texture_Handle,
}

texture_load :: proc {
	texture_load_from_path,
	texture_load_from_slot,
}

texture_load_from_path :: proc(path: string) -> (th: Texture_Handle, err: Texture_Error) {
	if h, ok := textures.by_path[path]; ok do return h, nil

	slot := texture_create_from_path(path) or_return

	append(&textures.slots, slot)
	th = Texture_Handle(len(textures.slots) - 1)
	textures.by_path[strings.clone(path)] = th
	return th, nil
}

texture_load_from_slot :: proc(slot: Texture_Slot) -> Texture_Handle {
	append(&textures.slots, slot)
	return Texture_Handle(len(textures.slots) - 1)
}

texture_destroy :: proc() {
	for &ts in textures.slots {
		sdl3.ReleaseGPUTexture(state.device, ts.page)
	}

	delete(textures.slots)
	delete(textures.by_path)
}

@(private)
texture_create_from_path :: proc(path: string) -> (s: Texture_Slot, err: Texture_Error) {
	w, h, n: i32
	bytes := stbi.load(strings.clone_to_cstring(path), &w, &h, &n, 4)

	if bytes == nil do return {}, .TEXTURE_IMAGE_LOAD
	defer stbi.image_free(bytes)

	return texture_create_from_pixels(bytes, int(w), int(h))
}

@(private)
texture_create_from_pixels :: proc(
	pixels: [^]u8,
	w, h: int,
) -> (
	s: Texture_Slot,
	err: Texture_Error,
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
	tex := sdl3.CreateGPUTexture(state.device, tex_info)
	if tex == nil {
		log.errorf("GPU Create Texture failed: %s", sdl3.GetError())
		return {}, .TEXTURE_CREATE
	}

	byte_size := u32(w * h * 4)
	transfer := sdl3.CreateGPUTransferBuffer(
		state.device,
		sdl3.GPUTransferBufferCreateInfo{usage = .UPLOAD, size = byte_size},
	)
	if transfer == nil {
		log.errorf("GPU Create Transfer Buffer failed: %s", sdl3.GetError())
		return {}, .TEXTURE_CREATE
	}

	mapped := ([^]u8)(sdl3.MapGPUTransferBuffer(state.device, transfer, false))
	copy(mapped[:byte_size], pixels[:byte_size])
	sdl3.UnmapGPUTransferBuffer(state.device, transfer)

	cmd := sdl3.AcquireGPUCommandBuffer(state.device)
	copy_pass := sdl3.BeginGPUCopyPass(cmd)

	src := sdl3.GPUTextureTransferInfo {
		transfer_buffer = transfer,
		offset          = 0,
	}
	dst := sdl3.GPUTextureRegion {
		texture = tex,
		w       = u32(w),
		h       = u32(h),
		d       = 1,
	}
	sdl3.UploadToGPUTexture(copy_pass, src, dst, false)

	sdl3.EndGPUCopyPass(copy_pass)
	if !sdl3.SubmitGPUCommandBuffer(cmd) {
		log.errorf("GPU submit failed: %s", sdl3.GetError())
		sdl3.ReleaseGPUTransferBuffer(state.device, transfer)
		return {}, .TEXTURE_COPY_CMD
	}

	sdl3.ReleaseGPUTransferBuffer(state.device, transfer)
	return Texture_Slot{page = tex, size = {w, h}, rect = {0, 0, 1, 1}}, nil
}
