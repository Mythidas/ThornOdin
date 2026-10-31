package window

import "core:log"
import "thorn:event"
import "thorn:input"
import "vendor:sdl3"

Window_Error :: enum {
	NONE,
	SDL_INIT,
	SDL_WINDOW,
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
		log.errorf("Failed to init SDL: %s", sdl3.GetError())
		return .SDL_INIT
	}

	state.handle = sdl3.CreateWindow(spec.title, spec.width, spec.height, {.RESIZABLE})
	if state.handle == nil {
		log.errorf("Failed to create SDL window: %s", sdl3.GetError())
		sdl3.QuitSubSystem(sdl3.InitFlags{.VIDEO})
		return .SDL_WINDOW
	}

	state.init = true
	return nil
}

destroy :: proc() {
	ensure(state.init, "Window.init() needs to be called")

	sdl3.DestroyWindow(state.handle)
	sdl3.QuitSubSystem(sdl3.InitFlags{.VIDEO})
	state = {}
}

tick :: proc(handler: proc(e: event.Thorn_Event)) {
	assert(state.init, "Window.init() must be called")

	ev: sdl3.Event
	for sdl3.PollEvent(&ev) {
		#partial switch ev.type {
		case .QUIT:
			handler(event.Window_Close_Event{})
		case .WINDOW_PIXEL_SIZE_CHANGED:
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
			handler(event.Mouse_Move_Event{pos = {ev.motion.x, ev.motion.y}})
		case .MOUSE_WHEEL:
			handler(event.Mouse_Scroll_Event{scroll = ev.wheel.y})
		}
	}
}

get_native :: proc() -> ^sdl3.Window {
	return state.handle
}
