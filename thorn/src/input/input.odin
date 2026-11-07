package input

import "core:math/linalg"
import "thorn:core"
import "thorn:event"

@(private)
state: struct {
	keys_down:     [Key]bool,
	keys_pressed:  [Key]bool,
	keys_released: [Key]bool,
	mouse_pos:     core.Vec2,
	mouse_delta:   core.Vec2,
	mouse_scroll:  f32,
}

tick :: proc() {
	state.keys_pressed = {}
	state.keys_released = {}
	state.mouse_delta = {}
	state.mouse_scroll = 0
}

on_event :: proc(tev: event.Thorn_Event) {
	#partial switch e in tev {
	case event.Key_Press_Event:
		if e.repeat do return
		if !state.keys_down[Key(e.key)] {
			state.keys_pressed[Key(e.key)] = true
		}
		state.keys_down[Key(e.key)] = true
	case event.Key_Release_Event:
		if state.keys_down[Key(e.key)] {
			state.keys_released[Key(e.key)] = true
		}
		state.keys_down[Key(e.key)] = false
	case event.Mouse_Move_Event:
		state.mouse_delta += e.pos - state.mouse_pos
		state.mouse_pos = e.pos
	case event.Mouse_Scroll_Event:
		state.mouse_scroll += e.scroll
	}
}

is_down :: proc(k: Key) -> bool {return state.keys_down[k]}
is_pressed :: proc(k: Key) -> bool {return state.keys_pressed[k]}
is_released :: proc(k: Key) -> bool {return state.keys_released[k]}

mouse_pos :: proc() -> core.Vec2 {return state.mouse_pos}
mouse_delta :: proc() -> core.Vec2 {return state.mouse_delta}
mouse_scroll :: proc() -> f32 {return state.mouse_scroll}

get_vector :: proc(pos_x, neg_x, pos_y, neg_y: Key) -> core.Vec2 {
	xval := int(is_down(pos_x)) - int(is_down(neg_x))
	yval := int(is_down(pos_y)) - int(is_down(neg_y))

	if xval == 0 && yval == 0 do return {0, 0}
	return linalg.normalize([2]f32{f32(xval), f32(yval)})
}

get_axis :: proc(pos, neg: Key) -> f32 {
	return f32(int(is_down(pos)) - int(is_down(neg)))
}
