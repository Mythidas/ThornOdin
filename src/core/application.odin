package core

import "../graphics"

import "vendor:sdl3"

AppError :: union #shared_nil {
	WindowError,
	graphics.Error,
}

Application :: struct {
	window:   Window,
	renderer: graphics.Renderer,
	_running: bool,
}

application_init :: proc(app: ^Application) -> (err: AppError) {
	ensure(app != nil)
	defer if err != nil do application_destroy(app)

	create_window(&app.window) or_return
	graphics.create_renderer(&app.renderer, app.window.handle) or_return

	return nil
}

application_run :: proc(app: ^Application) {
	ensure(app != nil)
	app._running = true

	for app._running {
		window_tick(&app.window, app, application_on_event)

		graphics.renderer_begin_frame(
			&app.renderer,
			graphics.Camera{90, 10, -1, 1, {0.2, 0.5, 0.6, 1}, .ORTHOGRAPHIC},
			{0, 0, -6},
			{0, 0, 0},
		)
		graphics.draw_quad(&app.renderer)
		graphics.draw_quad(&app.renderer, {2, 0, 0}, {0, 0, 45})
		graphics.renderer_end_frame(&app.renderer)
	}
}

application_destroy :: proc(app: ^Application) {
	ensure(app != nil)

	graphics.destroy_renderer(&app.renderer)
	destroy_window(&app.window)
	sdl3.Quit()
}

application_on_event :: proc(app: ^Application, e: ThornEvent) {
	ensure(app != nil)

	if e.type == .WINDOW_CLOSE {
		app._running = false
		return
	}

	// Process events through different features
}
