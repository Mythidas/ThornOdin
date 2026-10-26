package main

import "core"
import "core:log"
import "core:mem"
import "graphics"
import "input"

position: [3]f32 = {0, 0, 0}

test_layer := core.Layer {
	on_update = proc(f: ^core.Frame) {
		graphics.draw_quad(f.renderer, position)

		if input.is_down(.D) {
			position.x += 10.0 * f32(f.dt)
		}

		if input.is_pressed(.ESCAPE) {
			log.info("test")
		}
	},
}

main :: proc() {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)
	defer mem.tracking_allocator_destroy(&track)

	context.logger = log.create_console_logger(allocator = track.backing)
	defer log.destroy_console_logger(context.logger, allocator = track.backing)

	defer {
		for _, leak in track.allocation_map {
			log.infof("%v leaked %m", leak.location, leak.size)
		}
	}

	app: core.Application

	if err := core.application_init(&app); err != nil {
		core.application_destroy(&app)
		log.error("Failed to init application!")
		return
	}
	defer core.application_destroy(&app)

	core.application_attach_layer(&app, &test_layer)
	core.application_run(&app)
}
