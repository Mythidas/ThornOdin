package ecs

import "thorn:core"
import "thorn:physics2d"

Scene :: struct {
	reg:   Registry,
	world: physics2d.World,
}

scene_create :: proc(allocator := context.allocator) -> (scene: Scene) {
	scene.reg = registry_create(allocator)
	scene.world = physics2d.world_create()
	return scene
}

scene_destroy :: proc(s: ^Scene) {
	if s == nil do return

	for &arch in s.reg.archetypes {
		for row in 0 ..< len(arch.entities) {
			scene_detach_comps(s, &arch, row)
		}
	}

	registry_destroy(&s.reg)
	physics2d.world_destroy(&s.world)
	s^ = {}
}

scene_fixed_update :: proc(s: ^Scene, dt: f32) {
	if s == nil do return

	physics2d.world_update(&s.world, dt)
}

scene_create_enity :: proc(s: ^Scene) -> Entity_Handle {
	return registry_create_entity(&s.reg)
}

scene_destroy_entity :: proc(s: ^Scene, ent: Entity_Handle) {
	data, ok := core.handles_slot_get(&s.reg.entities, ent)
	if !ok do return

	scene_detach_comps(s, &s.reg.archetypes[data.arch], data.row)
	registry_destroy_entity(&s.reg, ent)
}

scene_add_component :: proc(s: ^Scene, ent: Entity_Handle, $T: typeid) -> ^T {
	had := registry_has_component(&s.reg, ent, T)
	comp := registry_add_component(&s.reg, ent, T)
	if comp == nil || had do return comp

	cid, _ := get_component_id(&s.reg, T)
	if on_attach := s.reg.component_hooks[cid].on_attach; on_attach != nil {
		on_attach(s, ent, comp)
	}
	return comp
}

scene_get_component :: proc(s: ^Scene, ent: Entity_Handle, $T: typeid) -> ^T {
	return registry_get_component(&s.reg, ent, T)
}

scene_remove_component :: proc(s: ^Scene, ent: Entity_Handle, $T: typeid) {
	comp := registry_get_component(&s.reg, ent, T)
	if comp != nil {
		if s.reg.components[T].hooks.on_detach != nil {
			s.reg.components[T].hooks.on_detach(s, ent, comp)
		}
	}

	registry_remove_component(&s.reg, ent, T)
}


scene_detach_comps :: proc(s: ^Scene, arch: ^Archetype, row: int) {
	ent := registry_entity_id(&s.reg, arch.entities[row])

	it := arch_sig_iter(arch.sig)
	for cid in arch_sig_next(&it) {
		if on_detach := s.reg.component_hooks[cid].on_detach; on_detach != nil {
			on_detach(s, ent, arch_get_component(arch, row, cid))
		}
	}
}
