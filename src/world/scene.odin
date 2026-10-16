package world

INVALID_ENTITY: EntityID : max(u64)

EntityID :: u64
EntityIndex :: int
EntityVersion :: u32
ComponentID :: int

ComponentInfo :: struct {
	id:   typeid,
	size: int,
}

EntityInfo :: struct {
	archetype:  int,
	row:        int,
	generation: u32,
}

Registry :: struct {
	counter:       int,
	component_ids: map[typeid]ComponentID,
	components:    [dynamic]ComponentInfo,
	archetypes:    [dynamic]Archetype,
	entities:      [dynamic]EntityInfo,
	free_entities: [dynamic]EntityIndex,
	by_sig:        map[Signature]int,
}

create_registry :: proc(reg: ^Registry) {
	if reg == nil do return

	reg.counter = 0
	reg.component_ids = make(map[typeid]ComponentID)
	reg.components = make([dynamic]ComponentInfo)
	reg.archetypes = make([dynamic]Archetype)
	reg.entities = make([dynamic]EntityInfo)
	reg.by_sig = make(map[Signature]int)

	get_component_id(reg, ArchetypeDefault)
	get_or_create_archetype_idx(reg, get_signature_of(reg, ArchetypeDefault))
}

destroy_registry :: proc(reg: ^Registry) {
	if reg == nil do return

	for &a in reg.archetypes {
		destroy_archetype(&a)
	}

	delete(reg.component_ids)
	delete(reg.components)
	delete(reg.archetypes)
	delete(reg.entities)
	delete(reg.by_sig)
	reg^ = {}
}

create_entity :: proc(reg: ^Registry) -> EntityID {
	if reg == nil do return max(u64)

	if len(reg.free_entities) > 0 {
		index := pop(&reg.free_entities)
		id := pack_entity_id(u32(index), reg.entities[index].generation)
		archetype_create_entity(&reg.archetypes[0], index)
		return id
	}

	id := pack_entity_id(u32(reg.counter), 0)
	reg.counter += 1

	append(&reg.entities, EntityInfo{0, 0, 0})
	archetype_create_entity(&reg.archetypes[0], len(reg.entities) - 1)
	return id
}

destroy_entity :: proc(reg: ^Registry, id: EntityID) {
	if !entity_id_valid(reg, id) do return
	index, _ := unpack_entity_id(id)

	// TODO: Cleanup archetype

	append(&reg.free_entities, index)
	reg.entities[index].generation += 1
	reg.entities[index].archetype = -1
	reg.entities[index].row = -1
}

get_component :: proc(reg: ^Registry, id: EntityID, $T: typeid) -> ^T {
	if !entity_id_valid(reg, id) do return nil
	index, _ := unpack_entity_id(id)

	return(
		cast(^T)archetype_get_component(
			&reg.archetypes[reg.entities[index].archetype],
			index,
			reg.component_ids[T],
		) \
	)
}

create_component :: proc(reg: ^Registry, id: EntityID, $T: typeid) -> ^T {
	if !entity_id_valid(reg, id) do return nil
	index, _ := unpack_entity_id(id)

	cid := get_component_id(reg, T)
	reg.components[cid] = {T, size_of(T)}

	from_arch: int = 0
	sig := get_signature_of(reg, T)

	from_arch = reg.entities[index].archetype
	if from_arch != 0 do sig += reg.archetypes[from_arch].sig

	if sig == reg.archetypes[from_arch].sig {
		return(
			cast(^T)archetype_get_component(
				&reg.archetypes[from_arch],
				index,
				reg.component_ids[T],
			) \
		)
	}

	to_arch := get_or_create_archetype_idx(reg, sig)
	move_entity_to_arch(reg, &reg.archetypes[from_arch], &reg.archetypes[to_arch], id)

	return cast(^T)archetype_get_component(&reg.archetypes[to_arch], index, reg.component_ids[T])
}

destroy_component :: proc() {}

@(private = "file")
pack_entity_id :: proc(index: u32, generation: EntityVersion) -> EntityID {
	return EntityID((u64(generation) << 32) | u64(index))
}

@(private = "file")
unpack_entity_id :: proc(id: EntityID) -> (EntityIndex, EntityVersion) {
	return int(u32(id)), u32(id >> 32)
}

@(private = "file")
entity_id_valid :: proc(reg: ^Registry, id: EntityID) -> bool {
	index, version := unpack_entity_id(id)
	return reg != nil && index < len(reg.entities) && reg.entities[index].generation == version
}

@(private = "file")
get_component_id :: proc(reg: ^Registry, $T: typeid) -> ComponentID {
	if id, ok := reg.component_ids[T]; ok {
		return id
	}

	id := ComponentID(len(reg.components))
	append(&reg.components, ComponentInfo{T, size_of(T)})
	reg.component_ids[T] = id
	return id
}

@(private = "file")
get_signature_of :: proc(reg: ^Registry, ids: ..typeid) -> (sig: Signature) {
	for t in ids {
		sig += {reg.component_ids[t]}
	}
	return
}

@(private = "file")
get_or_create_archetype_idx :: proc(reg: ^Registry, sig: Signature) -> int {
	if idx, ok := reg.by_sig[sig]; ok {
		return idx
	}

	append(&reg.archetypes, Archetype{})
	idx := len(reg.archetypes) - 1
	reg.by_sig[sig] = idx

	create_archetype(reg, &reg.archetypes[idx], sig)
	return idx
}

@(private = "file")
move_entity_to_arch :: proc(reg: ^Registry, from, to: ^Archetype, id: EntityID) {
	if !entity_id_valid(reg, id) do return
	index, _ := unpack_entity_id(id)

	from_idx := archetype_get_entity_index(from, index)
	if from_idx == -1 do return

	to_idx, replaced_idx := archetype_move_entity(from, to, index)

	// Update moved entity
	reg.entities[to.entities[to_idx]].row = to_idx
	reg.entities[to.entities[to_idx]].archetype = reg.by_sig[to.sig]

	// Update replaced entity
	reg.entities[from.entities[replaced_idx]].row = replaced_idx
}
