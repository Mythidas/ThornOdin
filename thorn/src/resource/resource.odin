package resource

import "core:log"
import "core:strings"
import "thorn:graphics"

@(private = "file")
TEX_ATLAS_SIZE :: 2048

Resource_Error :: enum {
	NONE,
	TEXTURE_PACKING,
}

@(private)
state: struct {
	init:        bool,
	dir_slash:   bool,
	asset_dir:   string,
	tex_by_path: map[string]graphics.Texture_Handle,
}

initialize :: proc(asset_dir: string) -> Resource_Error {
	ensure(state.init == false, "Resource.initialize() has already been called")

	state.asset_dir = strings.clone(asset_dir)
	state.dir_slash = asset_dir[len(asset_dir) - 1] != '/'
	state.tex_by_path = make(map[string]graphics.Texture_Handle)

	images := image_find_all(asset_dir)
	if len(images) == 0 do return nil
	defer image_destroy_all(images)

	image_slice := make([]Image, len(images))
	copy_slice(image_slice, images)
	defer delete(image_slice)

	for {
		atlas, unpacked := atlas_pack(TEX_ATLAS_SIZE, TEX_ATLAS_SIZE, image_slice)
		defer atlas_destroy(&atlas)
		defer delete(unpacked)

		if len(atlas.entries) == 0 {
			log.infof("Files to large to pack: %v", len(unpacked))
			break
		}

		tex, e := graphics.page_create(atlas.pixels, TEX_ATLAS_SIZE, TEX_ATLAS_SIZE)
		if e != nil do return .TEXTURE_PACKING

		for entry in atlas.entries {
			img := &image_slice[entry.image]
			path := parse_path(img.path)

			handle, err := graphics.texture_create(tex, entry.x, entry.y, entry.w, entry.h)
			if err != nil {
				log.errorf("Failed to creat texture fo atlas entry: %s", path)
				return .TEXTURE_PACKING
			}
			state.tex_by_path[path] = handle
		}

		if len(unpacked) == 0 do break

		delete(image_slice)
		image_slice = make([]Image, len(unpacked))
		for i, idx in unpacked {
			image_slice[idx] = images[i]
		}
	}

	log.infof("Resource Initialized: Textures (%v)", len(state.tex_by_path))
	state.init = true
	return nil
}

terminate :: proc() {
	ensure(state.init, "Resource.initialize() needs to be called")

	for k, _ in state.tex_by_path {
		delete(k)
	}

	delete(state.asset_dir)
	delete(state.tex_by_path)
	state = {}

	log.info("Resource Terminated")
}

load_sprite :: proc(path: string) -> graphics.Sprite {
	parsed := parse_path(path)
	defer delete(parsed)

	tex, ok := state.tex_by_path[parsed]
	if !ok do return {}

	return {texture = tex}
}

@(private)
parse_path :: proc(path: string) -> string {
	if strings.starts_with(path, "res://") do return strings.clone(path)

	index := strings.index(path, state.asset_dir) + len(state.asset_dir) + int(state.dir_slash)
	return strings.concatenate({"res://", path[index:]})
}
