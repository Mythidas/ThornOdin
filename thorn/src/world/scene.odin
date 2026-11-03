package world

Scene :: struct {
	reg: Registry,
}

scene_create :: proc(allocator := context.allocator) -> (scene: Scene) {
	scene.reg = registry_create(allocator)
	return scene
}

scene_destroy :: proc(s: ^Scene) {
	if s == nil do return

	registry_destroy(&s.reg)
	s^ = {}
}

scene_create_enity :: proc(s: ^Scene) -> Entity_ID {
	return registry_create_entity(&s.reg)
}

scene_destroy_entity :: proc(s: ^Scene, ent: Entity_ID) {
	registry_destroy_entity(&s.reg, ent)
}

scene_add_component :: proc(s: ^Scene, ent: Entity_ID, $T: typeid) -> ^T {
	return registry_add_component(&s.reg, ent, T)
}

scene_get_component :: proc(s: ^Scene, ent: Entity_ID, $T: typeid) -> ^T {
	return registry_get_component(&s.reg, ent, T)
}

scene_remove_component :: proc(s: ^Scene, ent: Entity_ID, $T: typeid) {
	registry_remove_component(&s.reg, ent, T)
}

