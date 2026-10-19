package world

import "base:runtime"

Entity :: struct {
	arch: int,
	row:  int,
	gen:  EntityGen,
}

Component :: struct {
	id:   ComponentID,
	size: int,
}

EMPTY_ARCH :: 0

Registry :: struct {
	allocator:       runtime.Allocator,
	entities:        [dynamic]Entity,
	components:      map[typeid]Component,
	component_sizes: [dynamic]int, // indexed by ComponentID
	archetypes:      [dynamic]Archetype,
	free_entities:   [dynamic]EntityIndex,
	by_sig:          map[ArchSig]int,
}

@(private)
create_registry :: proc(allocator: runtime.Allocator) -> (reg: Registry) {
	reg.allocator = allocator
	reg.entities = make([dynamic]Entity, allocator)
	reg.components = make(map[typeid]Component, allocator)
	reg.component_sizes = make([dynamic]int, allocator)
	reg.archetypes = make([dynamic]Archetype, allocator)
	reg.free_entities = make([dynamic]EntityIndex, allocator)
	reg.by_sig = make(map[ArchSig]int, allocator)

	// Archetype 0 is the empty archetype every new entity starts in
	idx := get_or_create_archetype(reg, ArchSig{})
	ensure(idx == EMPTY_ARCH)
}

@(private)
destroy_registry :: proc(reg: ^Registry) {
	for &a in reg.archetypes {
		destroy_archetype(&a)
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
create_entity :: proc(r: ^Registry) -> EntityID {
	index: EntityIndex
	if len(r.free_entities) > 0 {
		index = pop(&r.free_entities)
	} else {
		index = len(r.entities)
		append(&r.entities, Entity{-1, -1, 0})
	}

	ent := &r.entities[index]
	ent.arch = EMPTY_ARCH
	ent.row = arch_add_row(&r.archetypes[EMPTY_ARCH], index)

	return pack_entity_id(u32(index), ent.gen)
}

@(private)
destroy_entity :: proc(r: ^Registry, id: EntityID) {
	idx, gen := unpack_entity_id(id)
	if !is_valid_entity_id(r, idx, gen) do return

	ent := &r.entities[idx]

	if ent.arch != -1 && ent.row != -1 {
		arch := &r.archetypes[ent.arch]
		if moved := arch_remove_row(arch, ent.row); moved != -1 {
			r.entities[moved].row = ent.row
		}
	}

	ent.arch = -1
	ent.row = -1
	ent.gen += 1
	append(&r.free_entities, idx)
}

@(private)
add_component :: proc(r: ^Registry, id: EntityID, $T: typeid) -> ^T {
	idx, gen := unpack_entity_id(id)
	if !is_valid_entity_id(r, idx, gen) do return nil

	ent := &r.entities[idx]
	if ent.arch == -1 || ent.row == -1 do return nil

	cid := get_or_create_component_id(r, T, size_of(T))

	sig := r.archetypes[ent.arch].sig
	if arch_sig_has(sig, cid) do return get_component(r, id, T)
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
get_component :: proc(r: ^Registry, id: EntityID, $T: typeid) -> ^T {
	idx, gen := unpack_entity_id(id)
	if !is_valid_entity_id(r, idx, gen) do return nil

	ent := &r.entities[idx]
	if ent.arch == -1 || ent.row == -1 do return nil

	cid, ok := get_component_id(r, T)
	if !ok do return nil

	return cast(^T)arch_get_component(&r.archetypes[ent.arch], ent.row, cid)
}

@(private)
has_component :: proc(r: ^Registry, id: EntityID, $T: typeid) -> bool {
	idx, gen := unpack_entity_id(id)
	if !is_valid_entity_id(r, idx, gen) do return false

	ent := &r.entities[idx]
	if ent.arch == -1 do return false

	cid, ok := get_component_id(r, T)
	return ok && arch_sig_has(r.archetypes[ent.arch].sig, cid)
}

@(private)
remove_component :: proc(r: ^Registry, id: EntityID, $T: typeid) {
	idx, gen := unpack_entity_id(id)
	if !is_valid_entity_id(r, idx, gen) do return

	ent := &r.entities[idx]
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

@(private = "file")
get_or_create_archetype :: proc(r: ^Registry, sig: ArchSig) -> int {
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

	idx := append(&r.archetypes, create_archetype(&r.archetypes[idx], sig, sizes, r.allocator))
	r.by_sig[sig] = idx
	return idx
}

@(private = "file")
get_component_id :: proc(r: ^Registry, t: typeid) -> (ComponentID, bool) {
	if c, ok := r.components[t]; ok {
		return c.id, true
	}
	return 0, false
}

@(private = "file")
get_or_create_component_id :: proc(r: ^Registry, t: typeid, size: int = 0) -> ComponentID {
	if c, ok := r.components[t]; ok {
		return c.id
	}

	ensure(
		len(r.component_sizes) < MAX_ARCH_COMPONENTS,
		"component limit reached, raise SIG_WORDS",
	)

	cid := len(r.component_sizes)
	append(&r.component_sizes, size)
	r.components[t] = {
		id   = cid,
		size = size,
	}
	return cid
}

@(private = "file")
pack_entity_id :: proc(idx, gen: u32) -> EntityID {
	return EntityID((u64(idx) << 32) | u64(gen))
}

@(private = "file")
unpack_entity_id :: proc(id: EntityID) -> (EntityIndex, EntityGen) {
	return EntityIndex(id >> 32), EntityGen(id)
}

@(private = "file")
is_valid_entity_id :: proc(r: ^Registry, idx: EntityIndex, gen: EntityGen) -> bool {
	return idx >= 0 && idx < len(r.entities) && r.entities[idx].gen == gen
}
