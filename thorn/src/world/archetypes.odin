package world

import "base:intrinsics"
import "base:runtime"
import "core:mem"

SIG_WORDS :: 4
MAX_ARCH_COMPONENTS :: SIG_WORDS * 64

EntityID :: u64
EntityIndex :: int
EntityGen :: u32
ComponentID :: int

ArchSig :: distinct [SIG_WORDS]u64

ArchColumn :: struct {
	data: [dynamic]byte,
	size: int,
}

Archetype :: struct {
	sig:        ArchSig,
	entities:   [dynamic]EntityIndex,
	columns:    [dynamic]ArchColumn, // ordered by ascending ComponentID
	components: map[ComponentID]int, // ComponentID -> column index
}

// Non-nil address handed out for zero-sized components (tags)
@(private = "file")
zst_sentinel: u8


// Iterator over set bits, ascending. Usage:
//   it := arch_sig_iter(sig)
//   for cid in arch_sig_next(&it) { ... }
ArchSigIter :: struct {
	sig:  ArchSig,
	word: int,
	bits: u64,
}

@(private)
arch_sig_iter :: proc "contextless" (s: ArchSig) -> ArchSigIter {
	return {sig = s, word = 0, bits = s[0]}
}

@(private)
arch_sig_next :: proc "contextless" (it: ^ArchSigIter) -> (id: ComponentID, ok: bool) {
	for it.bits == 0 {
		it.word += 1
		if it.word >= SIG_WORDS do return 0, false
		it.bits = it.sig[it.word]
	}
	b := int(intrinsics.count_trailing_zeros(it.bits))
	it.bits &= it.bits - 1
	return it.word * 64 + b, true
}

// sizes[i] is the component size for the i-th set bit of sig (ascending ID order)
@(private)
create_archetype :: proc(
	sig: ArchSig,
	sizes: []int,
	allocator: runtime.Allocator,
) -> (
	arch: Archetype,
) {
	count := arch_sig_count(sig)
	ensure(len(sizes) == count)

	arch.sig = sig
	arch.entities = make([dynamic]EntityIndex)
	arch.columns = make([dynamic]ArchColumn, count)
	arch.components = make(map[ComponentID]int)

	i := 0
	it := arch_sig_iter(sig)
	for cid in arch_sig_next(&it) {
		arch.columns[i].size = sizes[i]
		if sizes[i] > 0 {
			arch.columns[i].data = make([dynamic]byte)
		}
		arch.components[cid] = i
		i += 1
	}
}

@(private)
destroy_archetype :: proc(arch: ^Archetype) {
	for c in arch.columns {
		delete(c.data)
	}

	delete(arch.columns)
	delete(arch.components)
	delete(arch.entities)
	arch^ = {}
}

@(private)
arch_add_row :: proc(arch: ^Archetype, index: EntityIndex) -> int {
	append(&arch.entities, index)
	for &c in arch.columns {
		if c.size == 0 do continue
		old := len(c.data)
		resize(&c.data, old + c.size)
		mem.zero(&c.data[old], c.size)
	}

	return len(arch.entities) - 1
}

// Swap-remove. Returns the entity index that was moved into `row`, or -1 if none.
@(private)
arch_remove_row :: proc(arch: ^Archetype, row: int) -> (moved: EntityIndex) {
	ensure(row < len(arch.entities) && row >= 0)

	last := len(arch.entities) - 1
	moved = -1

	if row != last {
		for &c in arch.columns {
			if c.size == 0 do continue
			mem.copy(&c.data[row * c.size], &c.data[last * c.size], c.size)
		}
		arch.entities[row] = arch.entities[last]
		moved = arch.entities[row]
	}

	pop(&arch.entities)
	for &c in arch.columns {
		if c.size == 0 do continue
		resize(&c.data, last * c.size)
	}

	return moved
}

// Copies shared components into `to`, then swap-removes from `from`.
// Returns the new row in `to` and the entity (if any) moved within `from`.
@(private)
arch_migrate_row :: proc(
	from, to: ^Archetype,
	from_row: int,
) -> (
	new_row: int,
	moved: EntityIndex,
) {
	ensure(from != nil && to != nil && from != to)
	ensure(from_row < len(from.entities) && from_row >= 0)

	to_row := arch_add_row(to, from.entities[from_row])

	it := arch_sig_iter(from.sig & to.sig)
	for cid in arch_sig_next(&it) {
		from_col := &from.columns[from.components[cid]]
		if from_col.size == 0 do continue
		to_col := &to.columns[to.components[cid]]

		mem.copy(
			&to_col.data[to_col.size * to_row],
			&from_col.data[from_col.size * from_row],
			from_col.size,
		)
	}

	return to_row, arch_remove_row(from, from_row)
}

@(private)
arch_get_component :: proc(arch: ^Archetype, row: int, comp: ComponentID) -> rawptr {
	ensure(row < len(arch.entities) && row >= 0)

	if col_idx, ok := arch.components[comp]; ok {
		col := &arch.columns[col_idx]
		if col.size == 0 do return &zst_sentinel
		return &col.data[col.size * row]
	}

	return nil
}

@(private)
arch_sig_set :: #force_inline proc "contextless" (s: ^ArchSig, id: ComponentID) {
	s[id >> 6] |= u64(1) << (u64(id) & 63)
}

@(private)
arch_sig_clear :: #force_inline proc "contextless" (s: ^ArchSig, id: ComponentID) {
	s[id >> 6] &~= u64(1) << (u64(id) & 63)
}

@(private)
arch_sig_has :: #force_inline proc "contextless" (s: ArchSig, id: ComponentID) -> bool {
	return s[id >> 6] & (u64(1) << (u64(id) & 63)) != 0
}

@(private)
arch_sig_contains_all :: #force_inline proc "contextless" (arch, required: ArchSig) -> bool {
	return (arch & required) == required
}

@(private)
arch_sig_contains_none :: #force_inline proc "contextless" (arch, excluded: ArchSig) -> bool {
	return (arch & excluded) == ArchSig{}
}

// Number of set bits (replacement for card())
@(private)
arch_sig_count :: proc "contextless" (s: ArchSig) -> (n: int) {
	for word in s {
		n += int(intrinsics.count_ones(word))
	}
	return
}
