package core

Handle :: distinct struct($T: typeid) {
	idx, gen: u32,
}

Handle_Slot :: struct($T: typeid) {
	gen:  u32,
	data: T,
}

Handle_Store :: struct($T: typeid) {
	data: [dynamic]Handle_Slot(T),
	free: [dynamic]u32,
}

handles_store_create :: proc(
	$T: typeid,
	allocator := context.allocator,
) -> (
	store: Handle_Store(T),
) {
	return {data = make([dynamic]Handle_Slot(T), allocator), free = make([dynamic]u32, allocator)}
}

handles_store_destroy :: proc(s: ^Handle_Store($T)) {
	if s == nil do return

	delete(s.data)
	delete(s.free)
	s^ = {}
}

handles_slot_acquire :: proc(store: ^Handle_Store($T)) -> (h: Handle(T), data: ^T) {
	if len(store.free) > 0 {
		idx := pop(&store.free)
		return {idx = idx, gen = store.data[idx].gen}, &store.data[idx].data
	}

	append(&store.data, Handle_Slot(T){gen = 1})
	idx := u32(len(store.data) - 1)
	return {idx = idx, gen = 1}, &store.data[idx].data
}

handles_slot_get :: proc(store: ^Handle_Store($T), h: Handle(T)) -> (data: ^T, ok: bool) {
	if h.idx >= u32(len(store.data)) do return nil, false

	if slot := &store.data[h.idx]; slot.gen == h.gen {
		return &slot.data, true
	}
	return nil, false
}

handles_slot_release :: proc(store: ^Handle_Store($T), h: Handle(T)) {
	ensure(h.idx < u32(len(store.data)), "Index exceeds data array")
	if store.data[h.idx].gen != h.gen do return

	store.data[h.idx] = Handle_Slot(T) {
		gen = h.gen + 1,
	}
	append(&store.free, h.idx)
}

handles_slot_get_or_default :: proc(store: ^Handle_Store($T), h: Handle(T)) -> ^T {
	if data, ok := handles_slot_get(store, h); ok do return data
	return &store.data[0].data
}
