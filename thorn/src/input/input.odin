package input

import "thorn:event"

@(private)
state: struct {
	keys_down:     [Key]bool,
	keys_pressed:  [Key]bool,
	keys_released: [Key]bool,
	mouse_pos:     [2]f32,
	mouse_delta:   [2]f32,
	mouse_scroll:  f32,
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
		state.mouse_delta = state.mouse_pos - e.pos
		state.mouse_pos = e.pos
	case event.Mouse_Scroll_Event:
		state.mouse_scroll += e.scroll
	}
}

tick :: proc() {
	state.keys_pressed = {}
	state.keys_released = {}
	state.mouse_delta = {}
	state.mouse_scroll = 0
}

is_down :: proc(k: Key) -> bool {return state.keys_down[k]}
is_pressed :: proc(k: Key) -> bool {return state.keys_pressed[k]}
is_released :: proc(k: Key) -> bool {return state.keys_released[k]}

mouse_pos :: proc() -> [2]f32 {return state.mouse_pos}
mouse_delta :: proc() -> [2]f32 {return state.mouse_delta}
mouse_scroll :: proc() -> f32 {return state.mouse_scroll}

