package engine

import "thorn:ecs"
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

Engine_Def :: struct {
	fixed_step: f32,
}

@(private)
state: struct {
	def:          Engine_Def,
	init:         bool,
	running:      bool,
	last_frame:   time.Tick,
	elapsed_time: f64,
	fixed_acc:    f64,
	active_scene: ^ecs.Scene,
	systems:      [dynamic]System_Entry,
}

@(private = "file")
system_counter: System_ID = 1

initialize :: proc(def: Engine_Def) -> (err: Engine_Error) {
	ensure(state.init == false, "Engine.initialize() has already called")

	ecs.initialize()
	defer if err != nil do ecs.terminate()

	window.initialize({title = "Thorn Engine", width = 1280, height = 720}) or_return
	defer if err != nil do window.terminate()

	graphics.initialize() or_return
	defer if err != nil do graphics.terminate()

	resource.initialize("res") or_return
	defer if err != nil do resource.terminate()

	register_default_systems()

	state.init = true
	state.running = true
	state.last_frame = time.tick_now()
	state.def = def

	log.info("Engine Initialized")
	return nil
}

terminate :: proc() {
	ensure(state.init, "Engine.initialize() needs to be called")

	resource.terminate()
	graphics.terminate()
	window.terminate()

	for &s in state.systems {
		ecs.query_destroy(&s.system.query)
		free(s.system)
	}
	delete(state.systems)

	state.running = false
	state.init = false

	log.info("Engine Terminated")
}

tick :: proc() -> bool {
	assert(state.init, "Engine.init() needs to be called")

	dt := time.duration_seconds(time.tick_since(state.last_frame))
	state.elapsed_time += dt
	state.fixed_acc += dt
	state.last_frame = time.tick_now()

	run_phase(.PRE_UPDATE, dt)

	input.tick()
	window.tick(window_event_handler)

	run_phase(.UPDATE, dt)

	for state.fixed_acc >= f64(state.def.fixed_step) {
		run_phase(.FIXED_UPDATE, f64(state.def.fixed_step))
		ecs.scene_fixed_update(state.active_scene, state.def.fixed_step)
		state.fixed_acc -= f64(state.def.fixed_step)
	}

	graphics.begin_frame()
	run_phase(.RENDER, dt)
	graphics.end_frame()

	run_phase(.POST_UPDATE, dt)
	return state.running
}

set_active_scene :: proc(scene: ^ecs.Scene) {
	if state.active_scene == scene do return
	for e in state.systems do system_bind(e.system, nil)

	state.active_scene = scene
	for e in state.systems do system_bind(e.system, scene)
}

register_system :: proc(s: System) -> System_ID {
	id := system_counter
	system_counter += 1

	sys := new(System)
	sys^ = s
	append(&state.systems, System_Entry{id, sys})

	if sys.on_attach != nil do s.on_attach(sys)
	system_bind(sys, state.active_scene)
	return id
}

unregister_system :: proc(id: System_ID) {
	if id == 0 do return

	for entry, idx in state.systems {
		if entry.id == id {
			system_bind(entry.system, state.active_scene)
			if entry.system.on_detach != nil {
				entry.system.on_detach(entry.system)
			}

			ordered_remove(&state.systems, idx)
			break
		}
	}
}

elapsed_time :: proc() -> f32 {
	return f32(state.elapsed_time)
}

get_active_scene :: proc() -> ^ecs.Scene {
	return state.active_scene
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

@(private)
run_phase :: proc(p: System_Phase, dt: f64) {
	for entry in state.systems {
		if entry.system.phase != p do continue
		if entry.system.on_update == nil do continue
		if !entry.system.global && state.active_scene == nil do continue

		entry.system.on_update(entry.system, f32(dt))
	}
}
