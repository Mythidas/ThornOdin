package core

import ev "thorn:event"
import "thorn:input"

import "core:log"
import "vendor:sdl3"

WindowError :: enum {
	NONE,
	SDL_INIT,
	SDL_CREATE_WINDOW,
}

Window :: struct {
	handle: ^sdl3.Window,
}

create_window :: proc(window: ^Window) -> (err: WindowError) {
	if !sdl3.Init(sdl3.InitFlags{.VIDEO}) {
		log.errorf("SDL_Init failed: %s", sdl3.GetError())
		return .SDL_INIT
	}

	window.handle = sdl3.CreateWindow("Rythm", 1280, 720, sdl3.WindowFlags{.RESIZABLE})
	defer if err != nil do destroy_window(window)

	if window.handle == nil do return .SDL_CREATE_WINDOW
	return .NONE
}

window_tick :: proc(
	window: ^Window,
	app: ^Application,
	handler: proc(app: ^Application, e: ev.ThornEvent),
) {
	if window == nil || app == nil do return

	event: sdl3.Event
	for sdl3.PollEvent(&event) {
		#partial switch event.type {
		case .QUIT:
			handler(app, ev.WindowCloseEvent{})
			break
		case .WINDOW_RESIZED:
			handler(
				app,
				ev.WindowResizeEvent{width = event.window.data1, height = event.window.data2},
			)
			break
		case .KEY_DOWN:
			handler(
				app,
				ev.KeyPressEvent {
					key = u8(input.key_from_scancode(event.key.scancode)),
					repeat = event.key.repeat,
				},
			)
		case .KEY_UP:
			handler(app, ev.KeyReleaseEvent{key = u8(input.key_from_scancode(event.key.scancode))})
		case .MOUSE_BUTTON_DOWN:
			handler(
				app,
				ev.KeyPressEvent{key = u8(input.key_from_mouse_button(event.button.button))},
			)
		case .MOUSE_BUTTON_UP:
			handler(
				app,
				ev.KeyReleaseEvent{key = u8(input.key_from_mouse_button(event.button.button))},
			)
		case .MOUSE_MOTION:
			handler(app, ev.MouseMoveEvent{pos = {event.motion.xrel, event.motion.yrel}})
		case .MOUSE_WHEEL:
			handler(app, ev.MouseScrollEvent{scroll = event.wheel.y})
		}
	}
}

destroy_window :: proc(window: ^Window) {
	if window == nil do return

	if window.handle != nil {
		sdl3.DestroyWindow(window.handle)
		window.handle = nil
	}

	sdl3.QuitSubSystem({.VIDEO})
	window^ = {}
}
