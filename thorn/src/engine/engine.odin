package engine

import "thorn:event"
import "thorn:graphics"
import "thorn:input"
import "thorn:window"

import "core:time"

Engine_Error :: union #shared_nil {
	window.Window_Error,
	graphics.Graphics_Error,
}

@(private)
state: struct {
	init:       bool,
	running:    bool,
	last_frame: time.Time,
	delta_time: f64,
}

init :: proc() -> (err: Engine_Error) {
	ensure(state.init == false, "Engine.init() already called")

	window.init({title = "Thorn Engine", width = 1280, height = 720}) or_return
	defer if err != nil do window.destroy()

	graphics.init() or_return
	defer if err != nil do graphics.destroy()

	state.init = true
	state.running = true
	return nil
}

destroy :: proc() {
	graphics.destroy()
	window.destroy()

	state.running = false
	state.init = false
}

quit :: proc() {
	state.running = false
}

tick :: proc() -> bool {
	assert(state.init, "Engine.init() needs to be called")

	state.delta_time = time.duration_milliseconds(time.since(state.last_frame))

	input.tick()
	window.tick(window_event_handler)

	state.last_frame = time.now()
	return state.running
}

get_delta_time :: proc() -> f64 {
	return state.delta_time
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
