package graphics

import "vendor:sdl3"

Texture :: struct {
	handle: ^sdl3.GPUTexture,
	size:   [2]f32,
}

create_texture :: proc {
	create_texture_from_pixels,
}

destroy_texture :: proc(device: ^sdl3.GPUDevice, texture: ^Texture) {
	if texture == nil || device == nil do return
	sdl3.ReleaseGPUTexture(device, texture.handle)
	texture^ = {}
}

create_texture_from_pixels :: proc(
	device: ^sdl3.GPUDevice,
	pixels: [^]u8,
	w, h: i32,
) -> (
	res: Texture,
) {
	tex_info := sdl3.GPUTextureCreateInfo {
		type                 = .D2,
		format               = .R8G8B8A8_UNORM,
		usage                = sdl3.GPUTextureUsageFlags{.SAMPLER},
		width                = u32(w),
		height               = u32(h),
		layer_count_or_depth = 1,
		num_levels           = 1,
	}
	tex := sdl3.CreateGPUTexture(device, tex_info)

	byte_size := u32(w * h * 4)
	transfer := sdl3.CreateGPUTransferBuffer(
		device,
		sdl3.GPUTransferBufferCreateInfo{usage = .UPLOAD, size = byte_size},
	)

	mapped := ([^]u8)(sdl3.MapGPUTransferBuffer(device, transfer, false))
	copy(mapped[:byte_size], pixels[:byte_size])
	sdl3.UnmapGPUTransferBuffer(device, transfer)

	cmd := sdl3.AcquireGPUCommandBuffer(device)
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
	assert(sdl3.SubmitGPUCommandBuffer(cmd))

	sdl3.ReleaseGPUTransferBuffer(device, transfer)
	return Texture{handle = tex, size = {f32(w), f32(h)}}
}
