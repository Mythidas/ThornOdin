package ecs

import "base:runtime"
import "core:reflect"

Query_Field :: struct {
	offset: uintptr,
	comp:   Component_ID,
}

Query_Match :: struct {
	arch:     ^Archetype,
	col_base: int,
}

Scene_Query :: struct {
	view:        typeid,
	fields:      []Query_Field,
	matches:     [dynamic]Query_Match,
	col_indices: [dynamic]int,
	scanned:     int,
	current:     int,
	scene:       ^Scene,
}

query_create :: proc(s: ^Scene, $T: typeid, allocator := context.allocator) -> (q: Scene_Query) {
	assert(reflect.is_struct(type_info_of(T)))

	n := reflect.struct_field_count(T)
	q.view = T
	q.fields = make([]Query_Field, n, allocator)
	q.matches = make([dynamic]Query_Match, allocator)
	q.col_indices = make([dynamic]int, allocator)
	q.scene = s

	for i in 0 ..< n {
		f := reflect.struct_field_at(T, i)
		info := runtime.type_info_base(f.type)
		sl, is_slice := info.variant.(runtime.Type_Info_Slice)
		assert(is_slice, "Query view fields must be slices")

		cid := get_or_create_component_id(&s.reg, sl.elem.id, sl.elem_size)

		q.fields[i] = {
			offset = f.offset,
			comp   = cid,
		}
	}

	return
}

query_destroy :: proc(q: ^Scene_Query) {
	if q == nil do return

	delete(q.fields)
	delete(q.matches)
	delete(q.col_indices)
	q^ = {}
}

query_rescan :: proc(q: ^Scene_Query) {
	for ; q.scanned < len(q.scene.reg.archetypes); q.scanned += 1 {
		arch := &q.scene.reg.archetypes[q.scanned]

		base := len(q.col_indices)
		matched := true
		for f in q.fields {
			idx, ok := arch_col_idx(arch, f.comp)
			if !ok {
				matched = false
				break
			}
			append(&q.col_indices, idx)
		}

		if matched {
			append(&q.matches, Query_Match{arch, base})
		} else {
			resize(&q.col_indices, base)
		}
	}
}

query_reset :: proc(q: ^Scene_Query) {
	q.current = 0
}

query_next :: proc(q: ^Scene_Query, $T: typeid) -> (view: T, ok: bool) {
	assert(T == q.view, "query_next called with a different view type")

	for q.current < len(q.matches) {
		m := q.matches[q.current]
		q.current += 1
		if len(m.arch.entities) == 0 do continue

		for f, i in q.fields {
			col := &m.arch.columns[q.col_indices[m.col_base + i]]
			raw := (^runtime.Raw_Slice)(uintptr(&view) + f.offset)
			raw.data = col.size == 0 ? rawptr(&zst_sentinel) : raw_data(col.data)
			raw.len = len(m.arch.entities)
		}

		return view, true
	}

	return {}, false
}

@(private = "file")
arch_col_idx :: proc(arch: ^Archetype, id: Component_ID) -> (int, bool) {
	for aid, i in arch.components {
		if aid == id do return i, true
	}

	return -1, false
}
