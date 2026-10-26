package window

import "core:log"
import "thorn:event"
import "thorn:input"
import "vendor:sdl3"

Window_Error :: enum {
	NONE,
	WINDOW_SDL_INIT,
	WINDOW_SDL_CREATE_WINDOW,
}


Window_Spec :: struct {
	title:         cstring,
	width, height: i32,
}

@(private)
state: struct {
	init:   bool,
	handle: ^sdl3.Window,
}

init :: proc(spec: Window_Spec) -> (err: Window_Error) {
	ensure(state.init == false, "Window.init() already called")

	if !sdl3.Init(sdl3.InitFlags{.VIDEO}) {
		log.errorf("sdl3.Init failed: %s", sdl3.GetError())
		return .WINDOW_SDL_INIT
	}

	state.handle = sdl3.CreateWindow(spec.title, spec.width, spec.height, {.RESIZABLE})

	if state.handle == nil {
		destroy()
		return .WINDOW_SDL_CREATE_WINDOW
	}

	state.init = true
	return .NONE
}

destroy :: proc() {
	if state.handle == nil do return

	sdl3.DestroyWindow(state.handle)
	sdl3.Quit()
}

tick :: proc(handler: proc(e: event.Thorn_Event)) {
	assert(state.init, "Window.init() must be called")

	ev: sdl3.Event
	for sdl3.PollEvent(&ev) {
		#partial switch ev.type {
		case .QUIT:
			handler(event.Window_Close_Event{})
			break
		case .WINDOW_RESIZED:
			handler(event.Window_Resize_Event{width = ev.window.data1, height = ev.window.data2})
		case .KEY_DOWN:
			handler(
				event.Key_Press_Event {
					key = u8(input.key_from_scancode(ev.key.scancode)),
					repeat = ev.key.repeat,
				},
			)
		case .KEY_UP:
			handler(event.Key_Release_Event{key = u8(input.key_from_scancode(ev.key.scancode))})
		case .MOUSE_BUTTON_DOWN:
			handler(event.Key_Press_Event{key = u8(input.key_from_mouse_button(ev.button.button))})
		case .MOUSE_BUTTON_UP:
			handler(
				event.Key_Release_Event{key = u8(input.key_from_mouse_button(ev.button.button))},
			)
		case .MOUSE_MOTION:
			handler(event.Mouse_Move_Event{pos = {ev.motion.xrel, ev.motion.yrel}})
		case .MOUSE_WHEEL:
			handler(event.Mouse_Scroll_Event{scroll = ev.wheel.y})
		}
	}
}

get_native :: proc() -> ^sdl3.Window {
	return state.handle
}
