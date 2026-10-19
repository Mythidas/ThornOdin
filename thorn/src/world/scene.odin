package world

import "base:runtime"

Scene :: struct {
	reg: Registry,
}

create_scene :: proc(allocator: runtime.Allocator) -> (scene: Scene) {
	scene.reg = create_registry(allocator)
}

destroy_scene :: proc(s: ^Scene) {
	ensure(s != nil, "Scene can not be nil")

	destroy_registry(s.reg)
	scene^ = {}
}
