package engine

import "thorn:ecs"

System_ID :: distinct u64

System :: struct {
	data:                 rawptr,
	scene:                ^ecs.Scene,
	query:                ecs.Scene_Query,
	phase:                System_Phase,
	global:               bool,
	on_attach, on_detach: proc(system: ^System),
	on_update:            proc(system: ^System, dt: f32),
	on_scene_change:      proc(system: ^System, scene: ^ecs.Scene),
}

System_Phase :: enum {
	FIXED_UPDATE,
	POST_UPDATE,
	PRE_UPDATE,
	UPDATE,
	RENDER,
}

System_Entry :: struct {
	id:     System_ID,
	system: ^System,
}

@(private)
system_bind :: proc(s: ^System, scene: ^ecs.Scene) {
	if s.scene == scene do return

	s.scene = scene
	if s.on_scene_change != nil do s.on_scene_change(s, scene)
}

system_query_helper :: proc(
	$T: typeid,
	phase: System_Phase,
	$update: proc(view: T, dt: f32),
) -> (
	sys: System,
) {
	sys.global = false
	sys.phase = phase
	sys.on_update = proc(system: ^System, dt: f32) {
		ecs.query_rescan(&system.query)
		ecs.query_reset(&system.query)

		for chunk in ecs.query_next(&system.query, T) {
			update(chunk, dt)
		}
	}

	sys.on_detach = proc(s: ^System) {
		ecs.query_destroy(&s.query)
	}

	sys.on_scene_change = proc(s: ^System, scene: ^ecs.Scene) {
		ecs.query_destroy(&s.query)
		if scene != nil {
			s.query = ecs.query_create(scene, T)
		}
	}

	return sys
}
