package graphics

import "core:log"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

import stbi "vendor:stb/image"

Image :: struct {
	path:   string,
	w, h:   int,
	pixels: []byte,
}

image_load :: proc(path: string, allocator := context.allocator) -> (Image, bool) {
	w, h, n: i32
	cpath := strings.clone_to_cstring(path)
	defer delete(cpath)

	stbi.set_flip_vertically_on_load(1)
	bytes := stbi.load(cpath, &w, &h, &n, 4)
	if bytes == nil {
		log.warnf("Failed to load image: %s", path)
		return {}, false
	}
	defer stbi.image_free(bytes)

	data := slice.clone(bytes[:w * h * 4], allocator)
	return {path = strings.clone(path, allocator), w = int(w), h = int(h), pixels = data}, true
}

image_destroy :: proc(img: ^Image, allocator := context.allocator) {
	if img == nil do return

	delete(img.path, allocator)
	delete(img.pixels, allocator)
	img^ = {}
}

image_destroy_all :: proc(imgs: []Image, allocator := context.allocator) {
	if imgs == nil do return

	for &img in imgs {
		image_destroy(&img)
	}

	delete(imgs, allocator)
}

image_find_all :: proc(
	dir: string,
	exts: []string = {".png", ".jpg"},
	allocator := context.allocator,
) -> []Image {
	w := os.walker_create(dir)
	defer os.walker_destroy(&w)

	imgs := make([dynamic]Image, allocator)
	defer delete(imgs)

	for entry in os.walker_walk(&w) {
		if p, err := os.walker_error(&w); err != nil {
			log.errorf("Failed to walk directory %s: %v", p, err)
			break
		}

		if entry.type != .Regular && entry.type != .Symlink do continue
		if !is_image(entry.name, exts) do continue

		if img, ok := image_load(entry.fullpath); ok {
			append(&imgs, img)
		}
	}

	return slice.clone(imgs[:], allocator)
}

@(private = "file")
is_image :: proc(name: string, exts: []string) -> bool {
	ext := filepath.ext(name)
	for &v in exts {
		if strings.equal_fold(ext, v) do return true
	}

	return false
}
