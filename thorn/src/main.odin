package main

import "core:log"
import "core:math/linalg"
import "core:mem"
import "thorn:core"
import "thorn:engine"
import "thorn:graphics"
import "thorn:input"
import "thorn:resource"

player: struct {
	transform: core.Transform,
	idle_s:    graphics.Sprite,
	idle_n:    graphics.Sprite,
	idle_e:    graphics.Sprite,
	idle_w:    graphics.Sprite,
	animator:  graphics.Animator,
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

	camera.camera.clear_color = {0.2, 0.5, 0.6, 1}
	camera.camera.mode = .ORTHOGRAPHIC
	camera.camera.near = -1
	camera.camera.far = 1
	camera.camera.fov = 90
	camera.camera.zoom = 5
	camera.transform.position.z = -6
	camera.transform.scale = {1, 1, 1}

	player.idle_s = resource.load_sprite("res://IDLE/idle_down.png")
	player.idle_n = resource.load_sprite("res://IDLE/idle_up.png")
	player.idle_e = resource.load_sprite("res://IDLE/idle_right.png")
	player.idle_w = resource.load_sprite("res://IDLE/idle_left.png")

	player.idle_s.frames = {8, 1}
	player.idle_n.frames = {8, 1}
	player.idle_e.frames = {8, 1}
	player.idle_w.frames = {8, 1}

	player.animator.frame_rate = 8
	player.animator.loop = true
	player.transform.scale = {1, 1, 1}

	graphics.animator_play(&player.animator, player.idle_s)

	for engine.tick() {
		graphics.begin_frame(camera.camera, camera.transform)
		graphics.draw_sprite(
			transform = player.transform,
			sprite = graphics.animator_sprite_view(&player.animator),
		)
		graphics.end_frame()

		if input.is_pressed(.ESCAPE) {
			break
		}

		graphics.animator_update(&player.animator, engine.delta_time())
		dir := input.get_vector(.D, .A, .W, .S)
		if dir != {0, 0} {
			player.transform.position.xy += linalg.normalize(dir) * 2.5 * engine.delta_time()

			if dir.x > 0 {
				graphics.animator_play(&player.animator, player.idle_e)
			} else if dir.x < 0 {
				graphics.animator_play(&player.animator, player.idle_w)
			} else if dir.y > 0 {
				graphics.animator_play(&player.animator, player.idle_n)
			} else {
				graphics.animator_play(&player.animator, player.idle_s)
			}
		}
	}
}
