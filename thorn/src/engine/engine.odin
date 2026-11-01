package engine

import "thorn:event"
import "thorn:graphics"
import "thorn:input"
import "thorn:resource"
import "thorn:window"

import "core:log"
import "core:time"

Engine_Error :: union #shared_nil {
	window.Window_Error,
	graphics.Graphics_Error,
	resource.Resource_Error,
}

@(private)
state: struct {
	init:       bool,
	running:    bool,
	last_frame: time.Tick,
	delta_time: f64,
}

initialize :: proc() -> (err: Engine_Error) {
	ensure(state.init == false, "Engine.init() already called")

	window.initialize({title = "Thorn Engine", width = 1280, height = 720}) or_return
	defer if err != nil do window.terminate()

	graphics.initialize() or_return
	defer if err != nil do graphics.terminate()

	resource.initialize("res") or_return
	defer if err != nil do resource.terminate()

	state.init = true
	state.running = true
	state.last_frame = time.tick_now()

	log.info("Engine Initialized")
	return nil
}

terminate :: proc() {
	resource.terminate()
	graphics.terminate()
	window.terminate()

	state.running = false
	state.init = false

	log.info("Engine Terminated")
}

tick :: proc() -> bool {
	assert(state.init, "Engine.init() needs to be called")

	state.delta_time = time.duration_seconds(time.tick_since(state.last_frame))

	input.tick()
	window.tick(window_event_handler)

	state.last_frame = time.tick_now()
	return state.running
}

delta_time :: proc() -> f32 {
	return f32(state.delta_time)
}

@(private)
window_event_handler :: proc(tev: event.Thorn_Event) {
	#partial switch e in tev {
	case event.Window_Close_Event:
		state.running = false
		return
	}

	input.on_event(tev)
}
