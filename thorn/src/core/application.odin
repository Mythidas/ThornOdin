package core

import "thorn:event"
import "thorn:graphics"
import "thorn:input"

import "core:time"
import "vendor:sdl3"

AppError :: union #shared_nil {
	WindowError,
	graphics.Error,
}

Frame :: struct {
	dt:       f64,
	renderer: ^graphics.Renderer,
}

Layer :: struct {
	on_attach: proc(),
	on_detach: proc(),
	on_event:  proc(e: event.ThornEvent) -> bool,
	on_update: proc(f: ^Frame),
}

Application :: struct {
	window:   Window,
	renderer: graphics.Renderer,
	running:  bool,
	layers:   [dynamic]^Layer,
}

application_init :: proc(app: ^Application) -> (err: AppError) {
	ensure(app != nil)
	defer if err != nil do application_destroy(app)

	create_window(&app.window) or_return
	graphics.create_renderer(&app.renderer, app.window.handle) or_return

	app.layers = make([dynamic]^Layer)

	return nil
}

application_destroy :: proc(app: ^Application) {
	ensure(app != nil)

	graphics.destroy_renderer(&app.renderer)
	destroy_window(&app.window)

	#reverse for &l in app.layers {
		if l.on_detach != nil do l.on_detach()
	}

	delete(app.layers)
	sdl3.Quit()
}

application_run :: proc(app: ^Application) {
	ensure(app != nil)
	app.running = true

	last_frame := time.now()

	for app.running {
		window_tick(&app.window, app, application_on_event)

		graphics.renderer_begin_frame(
			&app.renderer,
			graphics.Camera{90, 10, -1, 1, {0.2, 0.5, 0.6, 1}, .ORTHOGRAPHIC},
			{0, 0, -6},
			{0, 0, 0},
		)

		frame := Frame {
			dt       = time.duration_milliseconds(time.since(last_frame)),
			renderer = &app.renderer,
		}

		for &l in app.layers {
			if l.on_update != nil do l.on_update(&frame)
		}

		graphics.renderer_end_frame(&app.renderer)
		input.on_update()

		last_frame = time.now()
	}
}

application_attach_layer :: proc(app: ^Application, l: ^Layer) {
	ensure(app != nil, "App can not be nil")
	ensure(l != nil, "Layer can not be nil")

	append(&app.layers, l)
	if l.on_attach != nil do l.on_attach()
}

@(private = "file")
application_on_event :: proc(app: ^Application, tev: event.ThornEvent) {
	#partial switch e in tev {
	case event.WindowCloseEvent:
		app.running = false
		return
	}

	input.on_event(tev)

	// Process events through different features
	for &l in app.layers {
		if l.on_event != nil {
			if result := l.on_event(tev); result do break
		}
	}
}
