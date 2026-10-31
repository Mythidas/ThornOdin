package graphics

import stbrp "vendor:stb/rect_pack"

@(private = "file")
CHANNELS :: 4

Atlas_Entry :: struct {
	image:      int,
	x, y, w, h: int,
}

Atlas :: struct {
	pixels:  []byte,
	entries: [dynamic]Atlas_Entry,
}

atlas_pack :: proc(
	w, h: int,
	images: []Image,
	padding := 1,
	allocator := context.allocator,
) -> (
	atlas: Atlas,
	unpacked: [dynamic]int,
) {
	atlas.pixels = make([]byte, w * h * CHANNELS, allocator)
	atlas.entries = make([dynamic]Atlas_Entry, allocator)
	unpacked = make([dynamic]int, allocator)

	stb_ctx: stbrp.Context = {}
	nodes := make([]stbrp.Node, w)
	rects := make([]stbrp.Rect, len(images))
	defer delete(nodes)
	defer delete(rects)

	for i in 0 ..< len(images) {
		rects[i].id = i32(i)
		rects[i].w = stbrp.Coord(images[i].w + padding)
		rects[i].h = stbrp.Coord(images[i].h + padding)
	}

	stbrp.init_target(&stb_ctx, i32(w), i32(h), raw_data(nodes), i32(w))
	_ = stbrp.pack_rects(&stb_ctx, raw_data(rects), i32(len(rects)))

	for r in rects {
		if !r.was_packed {
			append(&unpacked, int(r.id))
			continue
		}

		append(
			&atlas.entries,
			Atlas_Entry {
				image = int(r.id),
				x = int(r.x) + padding,
				y = int(r.y) + padding,
				w = int(r.w) - padding,
				h = int(r.h) - padding,
			},
		)

		for row in 0 ..< int(r.h) - padding {
			img := &images[r.id]
			src := img.pixels[row * int(img.w) * CHANNELS:][:img.w * CHANNELS]
			dst_off := ((int(r.y) + row) * w + int(r.x)) * CHANNELS
			copy(atlas.pixels[dst_off:], src)
		}
	}

	return atlas, unpacked
}

atlas_destroy :: proc(atlas: ^Atlas, allocator := context.allocator) {
	if atlas == nil do return

	delete(atlas.pixels, allocator)
	delete(atlas.entries)
	atlas^ = {}
}
