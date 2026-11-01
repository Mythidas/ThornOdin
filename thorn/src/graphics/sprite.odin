package graphics

import "thorn:core"

Sprite :: struct {
	texture: Texture_Handle,
	frames:  core.IVec2,
}

Sprite_View :: struct {
	texture: Texture_Handle,
	uvs:     core.Rect,
}

Animator :: struct {
	frame_rate:   int,
	loop:         bool,
	_tick:        f32,
	_frame:       int,
	_frame_count: int,
	_sprite:      Sprite,
}

animator_play :: proc(a: ^Animator, s: Sprite) {
	if a._sprite.texture == s.texture do return

	animator_reset(a)
	a._sprite = s
	a._frame_count = s.frames.x * s.frames.y
}

animator_update :: proc(a: ^Animator, dt: f32) {
	if a.frame_rate <= 0 || a._frame_count == 0 do return

	a._tick -= dt
	for a._tick <= 0 {
		a._tick += 1 / f32(a.frame_rate)
		a._frame += 1
		if a._frame >= a._frame_count {
			if !a.loop {
				a._frame = a._frame_count - 1
				a._tick = 0
				return
			}
			a._frame = 0
		}
	}
}

animator_reset :: proc(a: ^Animator) {
	a._tick = 1 / f32(a.frame_rate)
	a._frame = 0
}

animator_sprite_view :: proc(a: ^Animator) -> Sprite_View {
	s := a._sprite
	if s.frames.x == 0 || s.frames.y == 0 {
		return {s.texture, {0, 0, 1, 1}}
	}

	col := f32(a._frame % s.frames.x)
	row := f32(a._frame / s.frames.x)
	w := 1 / f32(s.frames.x)
	h := 1 / f32(s.frames.y)
	return {s.texture, {col * w, row * h, (col + 1) * w, (row + 1) * h}}
}
