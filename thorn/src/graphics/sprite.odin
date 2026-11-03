package graphics

import "thorn:core"

Sprite :: struct {
	texture: Texture_Handle,
	rect:    core.Rect,
}

Anim_Clip :: struct {
	sprite:     Sprite,
	frame_rate: int,
	frames:     core.IVec2,
	loop:       bool,
}

Anim_Clip_Set :: struct {
	clips: [dynamic]Anim_Clip,
}

Animator :: struct {
	set:          ^Anim_Clip_Set,
	_current:     int,
	_frame:       int,
	_tick:        f32,
	_frame_count: int,
}

animator_play :: proc(a: ^Animator, clip: int) {
	if a._current == clip && a._frame != a._frame_count do return

	a._current = clip
	animator_reset(a)
}

animator_add_clip :: proc(a: ^Animator, c: Anim_Clip) -> int {
	append(&a.set.clips, c)
	return len(a.set.clips) - 1
}

animator_update :: proc(a: ^Animator, dt: f32) {
	clip := &a.set.clips[a._current]
	if clip.frame_rate <= 0 || a._frame_count == 0 do return

	a._tick -= dt
	for a._tick <= 0 {
		a._tick += 1 / f32(clip.frame_rate)
		a._frame += 1
		if a._frame >= a._frame_count {
			if !clip.loop {
				a._frame = a._frame_count - 1
				a._tick = 0
				return
			}
			a._frame = 0
		}
	}
}

animator_reset :: proc(a: ^Animator) {
	clip := a.set.clips[a._current]
	a._frame_count = clip.frames.x * clip.frames.y
	a._tick = 1 / f32(clip.frame_rate)
	a._frame = 0
}

animator_get_sprite :: proc(a: ^Animator) -> Sprite {
	s := a.set.clips[a._current]
	if s.frames.x == 0 || s.frames.y == 0 {
		return {s.sprite.texture, {0, 0, 1, 1}}
	}

	col := f32(a._frame % s.frames.x)
	row := f32(a._frame / s.frames.x)
	w := 1 / f32(s.frames.x)
	h := 1 / f32(s.frames.y)
	return {s.sprite.texture, {col * w, row * h, (col + 1) * w, (row + 1) * h}}
}
