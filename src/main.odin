package main

import "core"
import "core:log"
import "core:mem"
import "world"

TestStruct :: struct {
	id:  int,
	pos: [2]f32,
}

main :: proc() {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)
	defer mem.tracking_allocator_destroy(&track)

	context.logger = log.create_console_logger(allocator = track.backing)
	defer log.destroy_console_logger(context.logger, allocator = track.backing)

	defer {
		for _, leak in track.allocation_map {
			log.infof("%v leaked %m", leak.location, leak.size)
		}
	}

	app: core.Application

	if err := core.application_init(&app); err != nil {
		core.application_destroy(&app)
		log.error("Failed to init application!")
		return
	}
	defer core.application_destroy(&app)

	// TESTING

	reg := world.Registry{}
	world.create_registry(&reg)
	log.info("REG CREATED")

	ent1 := world.create_entity(&reg)
	log.info("ENT CREATED")
	comp1 := world.create_component(&reg, ent1, TestStruct)
	log.info("COMP CREATED")
	assert(comp1 != nil)

	comp1.id = 1
	comp1.pos = {0.5, 2.1}
	log.info("COMP UPDATED")

	comp_c := world.get_component(&reg, ent1, TestStruct)
	log.info("COMP FETCHED")
	log.infof(
		"Entity: %v, TestStruct: id [%v], pos [%v, %v]",
		ent1,
		comp_c.id,
		comp_c.pos.x,
		comp_c.pos.y,
	)
	world.destroy_registry(&reg)

	core.application_run(&app)
}
