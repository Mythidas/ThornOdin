package world_test

import world "../../src/world"
import "core:math/rand"
import "core:testing"

TComponentA :: struct {
	var_a: int,
	var_b: f32,
	var_c: [2]f32,
}
TComponentB :: struct {
	var_a: [2]f32,
	var_b: int,
	var_c: f32,
}
TComponentC :: struct {}

@(test)
add_row_grows_every_column :: proc(t: ^testing.T) {
	arch: world.Archetype
	make_test_archetype(&arch, 10)
	defer world.destroy_archetype(&arch)

	validate_test_archetype(&arch, t)

	sizes := make([dynamic]int)
	defer delete(sizes)

	for c in arch.columns {
		append(&sizes, len(c.data))
	}

	ent_count := len(arch.entities)
	new_row := world.arch_add_row(&arch, 54)
	validate_test_archetype(&arch, t)

	testing.expect(t, new_row == ent_count, "Add row failed to append to entities")

	for c, i in arch.columns {
		current_size := len(c.data)
		testing.expect(t, current_size == sizes[i] + c.size, "Column did not grow correctly")
	}
}

@(test)
add_row_zeroes_new_data :: proc(t: ^testing.T) {
	arch: world.Archetype
	make_test_archetype(&arch, 3)
	defer world.destroy_archetype(&arch)

	row := world.arch_add_row(&arch, 99)
	c_a := cast(^TComponentA)world.arch_get_component(&arch, row, 0)
	c_b := cast(^TComponentB)world.arch_get_component(&arch, row, 1)

	testing.expect(t, c_a^ == TComponentA{}, "New row for component A was not zeroed")
	testing.expect(t, c_b^ == TComponentB{}, "New row for component B was not zeroed")
}

@(test)
zero_sized_component_returns_non_nil :: proc(t: ^testing.T) {
	arch: world.Archetype
	make_test_archetype(&arch, 3)
	defer world.destroy_archetype(&arch)

	for row in 0 ..< len(arch.entities) {
		ptr := world.arch_get_component(&arch, row, 2)
		testing.expect(t, ptr != nil, "Zero-sized component should return a non-nil pointer")
	}

	// A component that is not in the archetype must still return nil
	testing.expect(
		t,
		world.arch_get_component(&arch, 0, 3) == nil,
		"Missing component should return nil",
	)
}

@(test)
remove_row_swaps_last_into_place :: proc(t: ^testing.T) {
	arch: world.Archetype
	make_test_archetype(&arch, 10)
	defer world.destroy_archetype(&arch)

	last := len(arch.entities) - 1
	last_ent := arch.entities[last]
	last_a := cast(^TComponentA)world.arch_get_component(&arch, last, 0)
	last_b := cast(^TComponentB)world.arch_get_component(&arch, last, 1)
	expected_a := last_a^
	expected_b := last_b^

	moved := world.arch_remove_row(&arch, 2)
	validate_test_archetype(&arch, t)

	testing.expect(t, moved == last_ent, "Remove row should report the entity that was moved")
	testing.expect(t, len(arch.entities) == last, "Entity count should shrink by one")
	testing.expect(t, arch.entities[2] == last_ent, "Last entity was not swapped into the row")

	a := cast(^TComponentA)world.arch_get_component(&arch, 2, 0)
	b := cast(^TComponentB)world.arch_get_component(&arch, 2, 1)
	testing.expect(t, a^ == expected_a, "Component A data was not moved with the entity")
	testing.expect(t, b^ == expected_b, "Component B data was not moved with the entity")
}

@(test)
remove_last_row_moves_nothing :: proc(t: ^testing.T) {
	arch: world.Archetype
	make_test_archetype(&arch, 5)
	defer world.destroy_archetype(&arch)

	moved := world.arch_remove_row(&arch, len(arch.entities) - 1)
	validate_test_archetype(&arch, t)

	testing.expect(t, moved == -1, "Removing the last row should not move any entity")
	testing.expect(t, len(arch.entities) == 4, "Entity count should shrink by one")
}

@(test)
migrate_row_copies_shared_components :: proc(t: ^testing.T) {
	from: world.Archetype
	make_test_archetype(&from, 10)
	defer world.destroy_archetype(&from)

	// Destination only has components 0 (A) and 2 (C)
	to_sig: world.ArchSig
	world.arch_sig_set(&to_sig, 0)
	world.arch_sig_set(&to_sig, 2)

	to: world.Archetype
	world.create_archetype(&to, to_sig, {size_of(TComponentA), size_of(TComponentC)})
	defer world.destroy_archetype(&to)

	from_row := 3
	migrating_ent := from.entities[from_row]
	last_ent := from.entities[len(from.entities) - 1]
	expected_a := (cast(^TComponentA)world.arch_get_component(&from, from_row, 0))^

	new_row, moved := world.arch_migrate_row(&from, &to, from_row)
	validate_test_archetype(&from, t)
	validate_test_archetype(&to, t)

	testing.expect(t, new_row == 0, "First row in the destination should be 0")
	testing.expect(t, moved == last_ent, "Source should report the swapped-in entity")
	testing.expect(t, len(from.entities) == 9, "Source should lose one row")
	testing.expect(t, len(to.entities) == 1, "Destination should gain one row")
	testing.expect(t, to.entities[new_row] == migrating_ent, "Wrong entity in destination")

	a := cast(^TComponentA)world.arch_get_component(&to, new_row, 0)
	testing.expect(t, a != nil && a^ == expected_a, "Shared component data was not copied")
	testing.expect(
		t,
		world.arch_get_component(&to, new_row, 1) == nil,
		"Destination should not have component B",
	)
}

make_test_archetype :: proc(arch: ^world.Archetype, count: int) {
	sig: world.ArchSig
	world.arch_sig_set(&sig, 0)
	world.arch_sig_set(&sig, 1)
	world.arch_sig_set(&sig, 2)

	// Sizes are in ascending ComponentID order
	world.create_archetype(
		arch,
		sig,
		{size_of(TComponentA), size_of(TComponentB), size_of(TComponentC)},
	)

	for i in 1 ..< count + 1 {
		row := world.arch_add_row(arch, i)
		c_a := cast(^TComponentA)world.arch_get_component(arch, row, 0)
		c_b := cast(^TComponentB)world.arch_get_component(arch, row, 1)
		ensure(c_a != nil && c_b != nil, "Get Component failed to return a valid ptr")

		c_a.var_a = i * int(rand.int32_range(0, 10_000))
		c_a.var_b = f32(i) * rand.float32_range(0, 10_000)
		c_a.var_c = {
			f32(i) * rand.float32_range(0, 10_000),
			f32(i) * rand.float32_range(0, 10_000),
		}

		c_b.var_a = {
			f32(i) * rand.float32_range(0, 10_000),
			f32(i) * rand.float32_range(0, 10_000),
		}
		c_b.var_b = i * int(rand.int32_range(0, 10_000))
		c_b.var_c = f32(i) * rand.float32_range(0, 10_000)
	}
}

validate_test_archetype :: proc(arch: ^world.Archetype, t: ^testing.T) -> bool {
	sig_count := world.arch_sig_count(arch.sig)
	testing.expect(t, len(arch.columns) == sig_count, "Column count does not match signature")

	seen_c := make(map[world.ComponentID]struct{})
	defer delete(seen_c)

	it := world.arch_sig_iter(arch.sig)
	for cid in world.arch_sig_next(&it) {
		comp_idx, ok := arch.components[cid]
		testing.expect(t, ok == true, "ComponentID from signature not in a.components")
		if !ok do continue

		col := &arch.columns[comp_idx]
		testing.expect(
			t,
			len(col.data) == len(arch.entities) * col.size,
			"Column data size does not match entities size",
		)

		seen_c[cid] = {}
	}
	testing.expect(t, len(seen_c) == sig_count, "a.sig may contain duplicate ComponentID values")

	seen := make(map[world.EntityIndex]struct{})
	defer delete(seen)

	for i in arch.entities {
		seen[i] = {}
	}
	testing.expect(t, len(seen) == len(arch.entities), "Duplicate entities found in archetype")

	return true
}
