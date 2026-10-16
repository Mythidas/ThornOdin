package world

import "core:mem"

MAX_COMPONENTS :: 128

Signature :: bit_set[0 ..< MAX_COMPONENTS;u128]

ArchetypeDefault :: struct {}
ArchetypeColumn :: struct {
	data: [dynamic]byte,
	size: int,
}

Archetype :: struct {
	sig:        Signature,
	entities:   [dynamic]EntityIndex,
	columns:    [dynamic]ArchetypeColumn,
	components: map[ComponentID]u32,
}

create_archetype :: proc(reg: ^Registry, arch: ^Archetype, sig: Signature) {
	arch.sig = sig
	arch.entities = make([dynamic]EntityIndex)
	arch.columns = make([dynamic]ArchetypeColumn)
	arch.components = make(map[ComponentID]u32)

	for cid in sig {
		append(&arch.columns, ArchetypeColumn{size = reg.components[cid].size})

		if arch.columns[len(arch.columns) - 1].size > 0 {
			arch.columns[len(arch.columns) - 1].data = make([dynamic]byte)
		}
	}
}

destroy_archetype :: proc(arch: ^Archetype) {
	if arch == nil do return

	for c in arch.columns {
		delete(c.data)
	}

	delete(arch.columns)
	delete(arch.entities)
	delete(arch.components)
	arch^ = {}
}

archetype_create_entity :: proc(arch: ^Archetype, entity: EntityIndex) -> int {
	if existing := archetype_get_entity_index(arch, entity); existing != -1 do return existing

	append(&arch.entities, entity)
	for cid in arch.sig {
		col := &arch.columns[arch.components[ComponentID(cid)]]
		resize(&col.data, len(col.data) + col.size)
	}

	return len(arch.entities) - 1
}

archetype_destroy_entity :: proc(arch: ^Archetype, entity: EntityIndex) -> EntityIndex {
	last := len(arch.entities) - 1
	row := archetype_get_entity_index(arch, entity)
	if row == -1 || row == last do return -1

	if !archetype_swap_entities(arch, entity, arch.entities[last]) do return -1
	pop(&arch.entities)
	return arch.entities[row]
}

archetype_get_entity_index :: proc(arch: ^Archetype, index: EntityIndex) -> int {
	if arch == nil do return -1

	for e, i in arch.entities {
		if e == index do return i
	}

	return -1
}

archetype_get_component :: proc(
	arch: ^Archetype,
	entity: EntityIndex,
	comp: ComponentID,
) -> rawptr {
	row := archetype_get_entity_index(arch, entity)
	if row == -1 do return nil

	column := &arch.columns[arch.components[comp]]
	start := row * column.size
	return &column.data[start]
}

archetype_set_component :: proc(
	arch: ^Archetype,
	entity: EntityIndex,
	comp: ComponentID,
	data: rawptr,
) -> bool {
	row := archetype_get_entity_index(arch, entity)
	if row == -1 do return false

	column := &arch.columns[arch.components[comp]]
	size := column.size
	start := row * size

	mem.copy(&column.data[start], data, size)
	return true
}

archetype_swap_entities :: proc(arch: ^Archetype, from_entity, to_entity: EntityIndex) -> bool {
	assert(arch != nil)

	to_row := archetype_get_entity_index(arch, to_entity)
	from_row := archetype_get_entity_index(arch, from_entity)
	assert(from_row != -1)
	assert(to_row != -1)

	for cid in arch.sig {
		copy_to := archetype_get_component(arch, to_entity, cid)
		assert(copy_to != nil)

		from_col := &arch.columns[arch.components[cid]]
		start := from_row * from_col.size

		archetype_set_component(arch, to_entity, cid, &from_col.data[start])
		archetype_set_component(arch, from_entity, cid, &copy_to)
	}

	copy_from := arch.entities[from_row]
	arch.entities[from_row] = arch.entities[to_row]
	arch.entities[to_row] = copy_from
	return true
}

archetype_move_entity :: proc(
	from, to: ^Archetype,
	entity: EntityIndex,
) -> (
	to_idx, replaced_idx: int,
) {
	from_row := archetype_get_entity_index(from, entity)
	if from_row == -1 do return -1, -1

	to_row := archetype_create_entity(to, entity)

	for cid in from.sig & to.sig {
		from_col := &from.columns[from.components[cid]]
		if from_col.size == 0 do continue

		start := from_row * from_col.size
		archetype_set_component(to, entity, cid, &from_col.data[start])
	}

	archetype_destroy_entity(from, entity)
	return to_row, from_row
}
