package graphics

import "core:log"
import "core:strings"
import "vendor:sdl3"

@(private)
ATLAS_SIZE :: 2048

Texture_Handle :: distinct int

@(private)
Texture_Rect :: struct {
	u0, v0: f32,
	u1, v1: f32,
}

@(private)
Texture_Slot :: struct {
	page: ^sdl3.GPUTexture,
	size: [2]int,
	rect: Texture_Rect,
}

@(private = "file")
textures: struct {
	slots:     [dynamic]Texture_Slot,
	by_path:   map[string]Texture_Handle,
	asset_dir: string,
}

@(private)
texture_init :: proc(asset_dir: string) -> (err: Graphics_Error) {
	textures.asset_dir = strings.clone(asset_dir)

	dtex_pixels := []u8{255, 0, 255, 255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 0, 255, 255}
	default_tex := texture_create_from_pixels(raw_data(dtex_pixels), 2, 2) or_return
	defer if err != nil do sdl3.ReleaseGPUTexture(state.device, default_tex)

	append(&textures.slots, Texture_Slot{page = default_tex, size = {2, 2}, rect = {0, 0, 1, 1}})

	images := image_find_all(asset_dir)
	if len(images) == 0 do return nil
	defer image_destroy_all(images)

	image_slice := make([]Image, len(images))
	copy_slice(image_slice, images)
	defer delete(image_slice)

	dir_slash := asset_dir[len(asset_dir) - 1] != '/'
	for {
		atlas, unpacked := atlas_pack(ATLAS_SIZE, ATLAS_SIZE, image_slice)
		defer atlas_destroy(&atlas)
		defer delete(unpacked)

		if len(atlas.entries) == 0 {
			log.infof("Files to large to pack: %v", len(unpacked))
			break
		}

		tex, e := texture_create_from_pixels(raw_data(atlas.pixels), ATLAS_SIZE, ATLAS_SIZE)
		if e != nil do return .GPU_TEXTURE

		for entry in atlas.entries {
			img := &image_slice[entry.image]
			index := strings.index(img.path, asset_dir) + len(asset_dir) + int(dir_slash)
			path := strings.concatenate({"res://", img.path[index:]})

			textures.by_path[path] = Texture_Handle(len(textures.slots))
			append(
				&textures.slots,
				Texture_Slot {
					page = tex,
					size = {img.w, img.h},
					rect = {
						f32(entry.x) / ATLAS_SIZE,
						f32(entry.y) / ATLAS_SIZE,
						f32(entry.x + entry.w) / ATLAS_SIZE,
						f32(entry.y + entry.h) / ATLAS_SIZE,
					},
				},
			)
		}

		if len(unpacked) == 0 do break

		delete(image_slice)
		image_slice = make([]Image, len(unpacked))
		for i, idx in unpacked {
			image_slice[idx] = images[i]
		}
	}

	return nil
}

@(private)
texture_destroy :: proc() {
	seen: map[^sdl3.GPUTexture]struct{}
	defer delete(seen)

	for &ts in textures.slots {
		if _, ok := seen[ts.page]; !ok {
			sdl3.ReleaseGPUTexture(state.device, ts.page)
			seen[ts.page] = {}
		}
	}

	for k, _ in textures.by_path {
		delete(k)
	}

	delete(textures.slots)
	delete(textures.by_path)
	delete(textures.asset_dir)
}

texture_find :: proc(path: string) -> Texture_Handle {
	th, ok := textures.by_path[path]
	if ok do return th
	else do return 0
}

@(private)
texture_load :: proc(path: string) -> (th: Texture_Handle, err: Graphics_Error) {
	if h := texture_find(path); h != 0 do return h, nil

	img, ok := image_load(path)
	if !ok do return -1, .GPU_TEXTURE
	defer image_destroy(&img)

	tex := texture_create_from_pixels(raw_data(img.pixels), img.w, img.h) or_return
	tex_handle := Texture_Handle(len(textures.slots))
	append(&textures.slots, Texture_Slot{page = tex, size = {img.w, img.h}, rect = {0, 0, 1, 1}})

	dir_slash := textures.asset_dir[len(textures.asset_dir) - 1] != '/'
	index := strings.index(img.path, textures.asset_dir) + len(textures.asset_dir) + int(dir_slash)
	path := strings.concatenate({"res://", img.path[index:]})
	textures.by_path[path] = tex_handle

	return tex_handle, nil
}

@(private)
texture_slot :: proc(th: Texture_Handle) -> Texture_Slot {
	if th < 0 || int(th) >= len(textures.slots) do return textures.slots[0]
	return textures.slots[th]
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
