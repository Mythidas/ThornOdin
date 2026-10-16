package core

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
	handler: proc(app: ^Application, e: ThornEvent),
) {
	if window == nil || app == nil do return

	event: sdl3.Event
	for sdl3.PollEvent(&event) {
		#partial switch event.type {
		case .QUIT:
			handler(app, {type = .WINDOW_CLOSE, info = {}})
			break
		case .WINDOW_RESIZED:
			handler(
				app,
				{
					type = .WINDOW_RESIZE,
					info = WindowResizeEvent {
						width = event.window.data1,
						height = event.window.data2,
					},
				},
			)
			break
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
