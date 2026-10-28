package main

import "core:log"
import "core:mem"
import "thorn:engine"
import "thorn:graphics"
import "thorn:input"

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

	err := engine.init()
	if err != nil {
		log.errorf("Thorn failed to init: %v", err)
		return
	}
	defer engine.destroy()

	for engine.tick() {
		graphics.begin_frame(
			{90, 10, -1, 1, {0.2, 0.5, 0.6, 1}, .ORTHOGRAPHIC},
			{0, 0, -6},
			{0, 0, 0},
		)
		graphics.draw_quad()
		graphics.end_frame()

		if input.is_pressed(.ESCAPE) {
			engine.quit()
		}
	}
}
