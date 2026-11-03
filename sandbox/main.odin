package main

import "core:log"
import "core:math/linalg"
import "core:mem"
import "thorn:core"
import "thorn:engine"
import "thorn:graphics"
import "thorn:input"
import "thorn:resource"
import "thorn:world"

Player_Anim :: enum {
	IDLE_N,
	IDLE_S,
	IDLE_E,
	IDLE_W,
}

player: struct {
	transform: core.Transform,
	animator:  graphics.Animator,
	anim_set:  graphics.Anim_Clip_Set,
}

camera: struct {
	camera:    graphics.Camera,
	transform: core.Transform,
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
			log.errorf("%v leaked %m", leak.location, leak.size)
		}

		for bad in track.bad_free_array {
			log.errorf("%v bad free", bad)
		}
	}

	err := engine.initialize()
	if err != nil {
		log.errorf("Thorn failed to init: %v", err)
		return
	}
	defer engine.terminate()
	defer delete(player.anim_set.clips)

	scene := world.scene_create()
	defer world.scene_destroy(&scene)

	ents := [3]world.Entity_ID{}
	for i in 0 ..< 3 {
		ents[i] = world.scene_create_enity(&scene)
		t := world.scene_add_component(&scene, ents[i], core.Transform)
		t.scale = {1, 1, 1}

		s := world.scene_add_component(&scene, ents[i], graphics.Sprite)
		s^ = resource.load_sprite("res://emblem.png")
		s.rect = {0, 0, 1, 1}
	}

	camera.camera.clear_color = {0.2, 0.5, 0.6, 1}
	camera.camera.mode = .ORTHOGRAPHIC
	camera.camera.near = -1
	camera.camera.far = 1
	camera.camera.fov = 90
	camera.camera.zoom = 5
	camera.transform.position.z = -6
	camera.transform.scale = {1, 1, 1}

	append(
		&player.anim_set.clips,
		graphics.Anim_Clip{resource.load_sprite("res://IDLE/idle_up.png"), 8, {8, 1}, true},
	)
	append(
		&player.anim_set.clips,
		graphics.Anim_Clip{resource.load_sprite("res://IDLE/idle_down.png"), 8, {8, 1}, true},
	)
	append(
		&player.anim_set.clips,
		graphics.Anim_Clip{resource.load_sprite("res://IDLE/idle_right.png"), 8, {8, 1}, true},
	)
	append(
		&player.anim_set.clips,
		graphics.Anim_Clip{resource.load_sprite("res://IDLE/idle_left.png"), 8, {8, 1}, true},
	)

	player.transform.scale = {1, 1, 1}

	player.animator.set = &player.anim_set
	graphics.animator_play(&player.animator, int(Player_Anim.IDLE_S))

	Tester :: struct {
		t: []core.Transform,
		s: []graphics.Sprite,
	}

	q: world.Scene_Query
	q = world.query_create(&scene, Tester)
	defer world.query_destroy(&q)

	for engine.tick() {
		// Scene Testing
		world.query_refresh(&q, &scene)
		world.query_reset(&q)

		graphics.begin_frame(camera.camera, camera.transform)
		graphics.draw_sprite(
			transform = player.transform,
			sprite = graphics.animator_get_sprite(&player.animator),
		)

		for m in world.query_next(&q, Tester) {
			for &t, i in m.t {
				t.position.x = linalg.sin(f32(engine.elapsed_time())) * f32(i + 1)
				graphics.draw_sprite(transform = t, sprite = m.s[i])
			}
		}

		graphics.end_frame()

		if input.is_pressed(.ESCAPE) {
			break
		}

		graphics.animator_update(&player.animator, engine.delta_time())
		dir := input.get_vector(.D, .A, .W, .S)
		if dir != {0, 0} {
			player.transform.position.xy += linalg.normalize(dir) * 2.5 * engine.delta_time()

			if dir.x > 0 {
				graphics.animator_play(&player.animator, int(Player_Anim.IDLE_E))
			} else if dir.x < 0 {
				graphics.animator_play(&player.animator, int(Player_Anim.IDLE_W))
			} else if dir.y > 0 {
				graphics.animator_play(&player.animator, int(Player_Anim.IDLE_N))
			} else {
				graphics.animator_play(&player.animator, int(Player_Anim.IDLE_S))
			}
		}

	}
}
