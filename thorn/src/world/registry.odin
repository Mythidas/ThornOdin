package world

Entity_Slot :: struct {
	arch: int,
	row:  int,
	gen:  Entity_Gen,
}

Component :: struct {
	id:   Component_ID,
	size: int,
}

@(private)
EMPTY_ARCH :: 0

@(private)
Registry :: struct {
	entities:        [dynamic]Entity_Slot,
	components:      map[typeid]Component,
	component_sizes: [dynamic]int, // indexed by Component_ID
	archetypes:      [dynamic]Archetype,
	free_entities:   [dynamic]Entity_Index,
	by_sig:          map[Arch_Sig]int,
}

@(private)
registry_create :: proc(allocator := context.allocator) -> (reg: Registry) {
	reg.entities = make([dynamic]Entity_Slot, allocator)
	reg.components = make(map[typeid]Component, allocator)
	reg.component_sizes = make([dynamic]int, allocator)
	reg.archetypes = make([dynamic]Archetype, allocator)
	reg.free_entities = make([dynamic]Entity_Index, allocator)
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

	delete(reg.entities)
	delete(reg.components)
	delete(reg.component_sizes)
	delete(reg.archetypes)
	delete(reg.free_entities)
	delete(reg.by_sig)
	reg^ = {}
}

@(private)
registry_create_entity :: proc(r: ^Registry) -> Entity_ID {
	index: Entity_Index
	if len(r.free_entities) > 0 {
		index = pop(&r.free_entities)
	} else {
		index = Entity_Index(len(r.entities))
		append(&r.entities, Entity_Slot{-1, -1, 0})
	}

	ent := &r.entities[index]
	ent.arch = EMPTY_ARCH
	ent.row = arch_add_row(&r.archetypes[EMPTY_ARCH], index)

	return Entity_ID{index, ent.gen}
}

@(private)
registry_destroy_entity :: proc(r: ^Registry, id: Entity_ID) {
	if !is_valid_entity_id(r, id) do return

	ent := &r.entities[id.index]

	if ent.arch != -1 && ent.row != -1 {
		arch := &r.archetypes[ent.arch]
		if moved := arch_remove_row(arch, ent.row); moved != -1 {
			r.entities[moved].row = ent.row
		}
	}

	ent.arch = -1
	ent.row = -1
	ent.gen += 1
	append(&r.free_entities, id.index)
}

@(private)
registry_add_component :: proc(r: ^Registry, id: Entity_ID, $T: typeid) -> ^T {
	if !is_valid_entity_id(r, id) do return nil

	ent := &r.entities[id.index]
	if ent.arch == -1 || ent.row == -1 do return nil

	cid := get_or_create_component_id(r, T, size_of(T))

	sig := r.archetypes[ent.arch].sig
	if arch_sig_has(sig, cid) do return registry_get_component(r, id, T)
	arch_sig_set(&sig, cid)

	// May grow r.archetypes, so take archetype pointers only afterwards
	to_idx := get_or_create_archetype(r, sig)
	from := &r.archetypes[ent.arch]
	to := &r.archetypes[to_idx]

	new_row, moved := arch_migrate_row(from, to, ent.row)
	if moved != -1 do r.entities[moved].row = ent.row

	ent.arch = to_idx
	ent.row = new_row
	return cast(^T)arch_get_component(to, new_row, cid)
}

@(private)
registry_get_component :: proc(r: ^Registry, id: Entity_ID, $T: typeid) -> ^T {
	if !is_valid_entity_id(r, id) do return nil

	ent := &r.entities[id.index]
	if ent.arch == -1 || ent.row == -1 do return nil

	cid, ok := get_component_id(r, T)
	if !ok do return nil

	return cast(^T)arch_get_component(&r.archetypes[ent.arch], ent.row, cid)
}

@(private)
registry_has_component :: proc(r: ^Registry, id: Entity_ID, $T: typeid) -> bool {
	if !is_valid_entity_id(r, id) do return false

	ent := &r.entities[id.index]
	if ent.arch == -1 do return false

	cid, ok := get_component_id(r, T)
	return ok && arch_sig_has(r.archetypes[ent.arch].sig, cid)
}

@(private)
registry_remove_component :: proc(r: ^Registry, id: Entity_ID, $T: typeid) {
	if !is_valid_entity_id(r, id) do return

	ent := &r.entities[id.index]
	if ent.arch == -1 || ent.row == -1 do return

	cid, ok := get_component_id(r, T)
	if !ok do return

	sig := r.archetypes[ent.arch].sig
	if !arch_sig_has(sig, cid) do return
	arch_sig_clear(&sig, cid)

	to_idx := get_or_create_archetype(r, sig)
	from := &r.archetypes[ent.arch]
	to := &r.archetypes[to_idx]

	new_row, moved := arch_migrate_row(from, to, ent.row)
	if moved != -1 do r.entities[moved].row = ent.row

	ent.arch = to_idx
	ent.row = new_row
}

@(private)
registry_entity_id :: proc(r: ^Registry, idx: Entity_Index) -> Entity_ID {
	return {idx, r.entities[idx].gen}
}

@(private)
get_component_id :: proc(r: ^Registry, t: typeid) -> (Component_ID, bool) {
	if c, ok := r.components[t]; ok {
		return c.id, true
	}
	return 0, false
}

@(private)
get_or_create_component_id :: proc(r: ^Registry, t: typeid, size: int = 0) -> Component_ID {
	if c, ok := r.components[t]; ok {
		return c.id
	}

	ensure(
		len(r.component_sizes) < MAX_ARCH_COMPONENTS,
		"component limit reached, raise SIG_WORDS",
	)

	cid := Component_ID(len(r.component_sizes))
	append(&r.component_sizes, size)
	r.components[t] = {
		id   = cid,
		size = size,
	}
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

@(private = "file")
is_valid_entity_id :: proc(r: ^Registry, id: Entity_ID) -> bool {
	return id.index >= 0 && int(id.index) < len(r.entities) && r.entities[id.index].gen == id.gen
}
