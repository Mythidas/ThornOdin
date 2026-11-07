package ecs

import "thorn:core"

Entity_Handle :: core.Handle(Entity_Slot)

Entity_Slot :: struct {
	arch: int,
	row:  int,
}

@(private)
EMPTY_ARCH :: 0

@(private)
Registry :: struct {
	entities:        core.Handle_Store(Entity_Slot),
	components:      map[typeid]Component_ID,
	component_sizes: [dynamic]int, // indexed by Component_ID
	component_hooks: [dynamic]Component_Hooks,
	archetypes:      [dynamic]Archetype,
	by_sig:          map[Arch_Sig]int,
}

@(private)
registry_create :: proc(allocator := context.allocator) -> (reg: Registry) {
	reg.entities = core.handles_store_create(Entity_Slot, allocator)
	reg.components = make(map[typeid]Component_ID, allocator)
	reg.component_sizes = make([dynamic]int, allocator)
	reg.archetypes = make([dynamic]Archetype, allocator)
	reg.by_sig = make(map[Arch_Sig]int, allocator)

	idx := get_or_create_archetype(&reg, Arch_Sig{})
	assert(idx == EMPTY_ARCH)
	return reg
}

@(private)
registry_destroy :: proc(reg: ^Registry) {
	if reg == nil do return

	for &a in reg.archetypes {
		archetype_destroy(&a)
	}

	core.handles_store_destroy(&reg.entities)
	delete(reg.components)
	delete(reg.component_sizes)
	delete(reg.component_hooks)
	delete(reg.archetypes)
	delete(reg.by_sig)
	reg^ = {}
}

@(private)
registry_create_entity :: proc(r: ^Registry) -> Entity_Handle {
	h, ent := core.handles_slot_acquire(&r.entities)

	ent.arch = EMPTY_ARCH
	ent.row = arch_add_row(&r.archetypes[EMPTY_ARCH], h.idx)
	return h
}

@(private)
registry_destroy_entity :: proc(r: ^Registry, id: Entity_Handle) {
	ent, ok := core.handles_slot_get(&r.entities, id)
	if !ok do return

	if ent.arch != -1 && ent.row != -1 {
		arch := &r.archetypes[ent.arch]
		if moved := arch_remove_row(arch, ent.row); moved != -1 {
			r.entities.data[moved].data.row = ent.row
		}
	}

	ent.arch = -1
	ent.row = -1
	core.handles_slot_release(&r.entities, id)
}

@(private)
registry_add_component :: proc(r: ^Registry, id: Entity_Handle, $T: typeid) -> ^T {
	ent, ok := core.handles_slot_get(&r.entities, id)
	if !ok || ent.arch == -1 || ent.row == -1 do return nil

	cid := get_or_create_component_id(r, T, size_of(T))

	sig := r.archetypes[ent.arch].sig
	if arch_sig_has(sig, cid) do return registry_get_component(r, id, T)
	arch_sig_set(&sig, cid)

	// May grow r.archetypes, so take archetype pointers only afterwards
	to_idx := get_or_create_archetype(r, sig)
	from := &r.archetypes[ent.arch]
	to := &r.archetypes[to_idx]

	new_row, moved := arch_migrate_row(from, to, ent.row)
	if moved != -1 do r.entities.data[moved].data.row = ent.row

	ent.arch = to_idx
	ent.row = new_row
	return cast(^T)arch_get_component(to, new_row, cid)
}

@(private)
registry_get_component :: proc(r: ^Registry, id: Entity_Handle, $T: typeid) -> ^T {
	ent, ok := core.handles_slot_get(&r.entities, id)
	if !ok || ent.arch == -1 || ent.row == -1 do return nil

	cid, found := get_component_id(r, T)
	if !found do return nil

	return cast(^T)arch_get_component(&r.archetypes[ent.arch], ent.row, cid)
}

@(private)
registry_has_component :: proc(r: ^Registry, id: Entity_Handle, $T: typeid) -> bool {
	ent, ok := core.handles_slot_get(&r.entities, id)
	if !ok || ent.arch == -1 do return false

	cid, known := get_component_id(r, T)
	return known && arch_sig_has(r.archetypes[ent.arch].sig, cid)
}

@(private)
registry_remove_component :: proc(r: ^Registry, id: Entity_Handle, $T: typeid) {
	ent, ok := core.handles_slot_get(&r.entities, id)
	if !ok || ent.arch == -1 || ent.row == -1 do return

	cid, ok := get_component_id(r, T)
	if !ok do return

	sig := r.archetypes[ent.arch].sig
	if !arch_sig_has(sig, cid) do return
	arch_sig_clear(&sig, cid)

	to_idx := get_or_create_archetype(r, sig)
	from := &r.archetypes[ent.arch]
	to := &r.archetypes[to_idx]

	new_row, moved := arch_migrate_row(from, to, ent.row)
	if moved != -1 do r.entities.data[moved].data.row = ent.row

	ent.arch = to_idx
	ent.row = new_row
}

@(private)
registry_entity_id :: proc(r: ^Registry, idx: u32) -> Entity_Handle {
	return {idx, r.entities.data[idx].gen}
}

@(private)
get_component_id :: proc(r: ^Registry, t: typeid) -> (Component_ID, bool) {
	if c, ok := r.components[t]; ok {
		return c, true
	}
	return 0, false
}

@(private)
get_or_create_component_id :: proc(r: ^Registry, t: typeid, size: int = 0) -> Component_ID {
	if c, ok := r.components[t]; ok {
		return c
	}

	ensure(
		len(r.component_sizes) < MAX_ARCH_COMPONENTS,
		"component limit reached, raise SIG_WORDS",
	)

	cid := Component_ID(len(r.component_sizes))
	hooks, found := state.hooks[t]
	append(&r.component_sizes, size)
	append(&r.component_hooks, found ? hooks : {})

	r.components[t] = cid
	return cid
}

@(private = "file")
get_or_create_archetype :: proc(r: ^Registry, sig: Arch_Sig) -> int {
	if idx, ok := r.by_sig[sig]; ok {
		return idx
	}

	sizes := make([]int, arch_sig_count(sig))
	defer delete(sizes)

	i := 0
	it := arch_sig_iter(sig)
	for cid in arch_sig_next(&it) {
		sizes[i] = r.component_sizes[cid]
		i += 1
	}

	idx := len(r.archetypes)
	append(&r.archetypes, archetype_create(sig, sizes, r.archetypes.allocator))
	r.by_sig[sig] = idx
	return idx
}
