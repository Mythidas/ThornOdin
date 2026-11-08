package main

import "core:log"
import "core:math/linalg"
import "core:mem"
import "thorn:core"
import "thorn:ecs"
import "thorn:engine"
import "thorn:graphics"
import "thorn:input"
import "thorn:physics2d"
import "thorn:resource"

Player_Anim :: enum {
	IDLE_N,
	IDLE_S,
	IDLE_E,
	IDLE_W,
}

anim_set: graphics.Anim_Clip_Set

Player :: struct {
	dir: f32,
	wants_jump: bool,
	grounded: bool
}

Player_View :: struct {
	players:       []Player,
	transforms: []core.Transform,
	anims:      []graphics.Animator,
}

Player_Move_View :: struct {
	players: []Player,
	bodys: []physics2d.Rigidbody,
}

player_update :: proc(view: Player_View, dt: f32) {
	dir := input.get_axis(.D, .A)

		view.players[0].dir = dir
		view.players[0].wants_jump = input.is_pressed(.SPACE)

		if dir > 0 {
			graphics.animator_play(&view.anims[0], int(Player_Anim.IDLE_E))
		} else if dir < 0 {
			graphics.animator_play(&view.anims[0], int(Player_Anim.IDLE_W))
		}
}

player_move :: proc(view: Player_Move_View, dt: f32) {
	for &body, i in view.bodys {
		vel := physics2d.body_get_velocity(&body)
		vel.x = linalg.lerp(vel.x, view.players[i].dir * 2.5, 20 * dt)
		physics2d.body_set_velocity(&body, vel)

		if view.players[i].wants_jump && physics2d.body_is_grounded(&body) {
			physics2d.body_add_impulse(&body, {0, 100})
		}
	}
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

	err := engine.initialize({fixed_step = 1.0 / 60.0})
	if err != nil {
		log.errorf("Thorn failed to init: %v", err)
		return
	}
	defer engine.terminate()

	anim_set.clips = make([dynamic]graphics.Anim_Clip)
	defer delete(anim_set.clips)

	scene := ecs.scene_create()
	defer ecs.scene_destroy(&scene)

	engine.register_system(engine.system_query_helper(Player_View, .UPDATE, player_update))
	engine.register_system(engine.system_query_helper(Player_Move_View, .FIXED_UPDATE, player_move))

	append(
		&anim_set.clips,
		graphics.Anim_Clip{resource.load_sprite("res://IDLE/idle_up.png"), 8, {8, 1}, true},
	)
	append(
		&anim_set.clips,
		graphics.Anim_Clip{resource.load_sprite("res://IDLE/idle_down.png"), 8, {8, 1}, true},
	)
	append(
		&anim_set.clips,
		graphics.Anim_Clip{resource.load_sprite("res://IDLE/idle_right.png"), 8, {8, 1}, true},
	)
	append(
		&anim_set.clips,
		graphics.Anim_Clip{resource.load_sprite("res://IDLE/idle_left.png"), 8, {8, 1}, true},
	)

	p1 := ecs.scene_create_enity(&scene)
	p1_t := ecs.scene_add_component(&scene, p1, core.Transform)
	p1_t.scale = {1, 1, 1}

	p1_anim := ecs.scene_add_component(&scene, p1, graphics.Animator)
	p1_anim.set = &anim_set
	graphics.animator_play(p1_anim, int(Player_Anim.IDLE_S))
	ecs.scene_add_component(&scene, p1, Player)
	ecs.scene_add_component(&scene, p1, graphics.Sprite)
	rb := ecs.scene_add_component(&scene, p1, physics2d.Rigidbody)
	rb.gravity_scale = 1
	rb.type = .DYNAMIC
	rb.fixed_rotation = true

	col := ecs.scene_add_component(&scene, p1, physics2d.Collider)
	col.density = 1
	col.friction = 0
	col.shape = {
		width  = 1,
		height = 2,
	}

	floor := ecs.scene_create_enity(&scene)
	frb := ecs.scene_add_component(&scene, floor, physics2d.Rigidbody)
	frb.type = .STATIC

	fcol := ecs.scene_add_component(&scene, floor, physics2d.Collider)
	fcol.shape = {
		width  = 40,
		height = 2,
	}
	fcol.friction = 10

	ft := ecs.scene_add_component(&scene, floor, core.Transform)
	ft.position = {0, -2, 0}
	ft.scale = {1, 1, 1}
	fsprite := ecs.scene_add_component(&scene, floor, graphics.Sprite)
	fsprite.rect = {0,0,1,1}

	cam := ecs.scene_create_enity(&scene)
	c := ecs.scene_add_component(&scene, cam, graphics.Camera)
	c^ = {
		clear_color = {0.2, 0.5, 0.6, 1},
		mode        = .ORTHOGRAPHIC,
		near        = -1,
		far         = 1,
		zoom        = 5,
	}
	cam_t := ecs.scene_add_component(&scene, cam, core.Transform)
	cam_t.position.z = -6
	cam_t.scale = {1, 1, 1}

	engine.set_active_scene(&scene)

	for engine.tick() {
		if input.is_pressed(.ESCAPE) {
			break
		}
	}
}
