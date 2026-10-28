package graphics

import "core:log"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "vendor:sdl3"
import stbi "vendor:stb/image"
import stbrp "vendor:stb/rect_pack"

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

@(private = "file")
Texture_Ref :: struct {
	path: string,
	w, h: int,
	data: []byte,
}

texture_init :: proc(asset_dir: string) {
	refs := make([dynamic]Texture_Ref)
	defer {
		for &ref in refs {
			delete(ref.path)
		}

		delete(refs)
	}
	crawl_dir(&refs, asset_dir)

	stb_ctx: stbrp.Context = {}
	nodes := make([]stbrp.Node, 2048)
	rects := make([]stbrp.Rect, len(refs))
	defer delete(nodes)
	defer delete(rects)

	for i in 0 ..< len(refs) {
		rects[i].id = i32(i)
		rects[i].w = stbrp.Coord(refs[i].w)
		rects[i].h = stbrp.Coord(refs[i].h)
	}

	stbrp.init_target(&stb_ctx, 2048, 2048, raw_data(nodes), 2048)
	result := stbrp.pack_rects(&stb_ctx, raw_data(rects), i32(len(rects)))
	if result != 1 do log.info("More pages needed")

	ATLAS_W :: 2048
	ATLAS_H :: 2048
	CHANNELS :: 4

	pixels := make([]u8, ATLAS_W * ATLAS_H * CHANNELS)
	defer delete(pixels)

	for r in rects {
		if !r.was_packed do continue

		ref := &refs[r.id]
		append(
			&textures.slots,
			Texture_Slot {
				page = nil,
				size = {ref.w, ref.h},
				rect = {
					f32(r.x) / ATLAS_W,
					f32(r.y) / ATLAS_H,
					f32(r.x + r.w) / ATLAS_W,
					f32(r.y + r.h) / ATLAS_H,
				},
			},
		)
		textures.by_path[ref.path] = Texture_Handle(len(textures.slots) - 1)

		for row in 0 ..< int(r.h) {
			src := ref.data[row * ref.w * CHANNELS:][:ref.w * CHANNELS]
			dst_off := ((int(r.y) + row) * ATLAS_W + int(r.x)) * CHANNELS
			copy(pixels[dst_off:], src)
		}

		delete(ref.data)
	}

	page, err := texture_create_from_pixels(raw_data(pixels), ATLAS_W, ATLAS_H)
	if err != nil do return

	for &s in textures.slots {
		if s.page == nil {
			s.page = page
		}
	}
}

texture_destroy :: proc() {
	seen: map[^sdl3.GPUTexture]struct{}
	defer delete(seen)

	for &ts in textures.slots {
		if _, ok := seen[ts.page]; !ok {
			sdl3.ReleaseGPUTexture(state.device, ts.page)
			seen[ts.page] = {}
		}
	}

	delete(textures.slots)
	delete(textures.by_path)
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

@(private)
texture_create_from_path :: proc(path: string) -> (s: Texture_Slot, err: Texture_Error) {
	w, h, n: i32
	bytes := stbi.load(strings.clone_to_cstring(path), &w, &h, &n, 4)

	if bytes == nil do return {}, .TEXTURE_IMAGE_LOAD
	defer stbi.image_free(bytes)

	tex := texture_create_from_pixels(bytes, int(w), int(h)) or_return
	return {page = tex, size = {int(w), int(h)}, rect = {0, 0, 1, 1}}, nil
}

@(private)
texture_create_from_pixels :: proc(
	pixels: [^]u8,
	w, h: int,
) -> (
	tex: ^sdl3.GPUTexture,
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
	gputex := sdl3.CreateGPUTexture(state.device, tex_info)
	if gputex == nil {
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
		texture = gputex,
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
	return gputex, nil
}

@(private = "file")
read_image :: proc(path: string) -> (Texture_Ref, Texture_Error) {
	w, h, n: i32
	bytes := stbi.load(strings.clone_to_cstring(path, context.temp_allocator), &w, &h, &n, 4)
	if bytes == nil {
		log.warnf("Failed to read image %s: %s", path, stbi.failure_reason())
		return {}, .TEXTURE_IMAGE_LOAD
	}
	defer stbi.image_free(bytes)

	return Texture_Ref {
			path = strings.clone(path),
			w = int(w),
			h = int(h),
			data = slice.clone(bytes[:w * h * n]),
		},
		nil
}

@(private = "file")
is_image :: proc(name: string) -> bool {
	ext := filepath.ext(name)
	return strings.equal_fold(ext, ".png") || strings.equal_fold(ext, ".jpg")
}

@(private = "file")
crawl_dir :: proc(refs: ^[dynamic]Texture_Ref, path: string) {
	dirs, err := os.read_directory_by_path(path, 0, context.allocator)
	if err != nil {
		log.errorf("Failed to read dir %s: %v", path, err)
		return
	}
	defer os.file_info_slice_delete(dirs, context.allocator)

	for dir in dirs {
		#partial switch dir.type {
		case .Directory:
			crawl_dir(refs, dir.fullpath)
		case .Regular:
			if !is_image(dir.name) do continue
			if img, err := read_image(dir.fullpath); err == nil {
				append(refs, img)
			}
		}
	}
}
