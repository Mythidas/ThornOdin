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
import "vendor:box2d"

Player_Anim :: enum {
	IDLE_N,
	IDLE_S,
	IDLE_E,
	IDLE_W,
}

anim_set: graphics.Anim_Clip_Set

Player :: struct {}
Player_View :: struct {
	tags:       []Player,
	transforms: []core.Transform,
	anims:      []graphics.Animator,
}

player_move :: proc(view: Player_View, dt: f32) {
	dir := input.get_vector(.D, .A, .W, .S)
	if dir == {0, 0} do return

	for &t, i in view.transforms {
		t.position.xy += linalg.normalize(dir) * 2.5 * dt

		if dir.x > 0 {
			graphics.animator_play(&view.anims[i], int(Player_Anim.IDLE_E))
		} else if dir.x < 0 {
			graphics.animator_play(&view.anims[i], int(Player_Anim.IDLE_W))
		} else if dir.y > 0 {
			graphics.animator_play(&view.anims[i], int(Player_Anim.IDLE_N))
		} else {
			graphics.animator_play(&view.anims[i], int(Player_Anim.IDLE_S))
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

	scene := world.scene_create()
	defer world.scene_destroy(&scene)

	engine.register_system(engine.system_query_helper(Player_View, .UPDATE, player_move))

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

	p1 := world.scene_create_enity(&scene)
	p1_t := world.scene_add_component(&scene, p1, core.Transform)
	p1_t.scale = {1, 1, 1}

	p1_anim := world.scene_add_component(&scene, p1, graphics.Animator)
	p1_anim.set = &anim_set
	graphics.animator_play(p1_anim, int(Player_Anim.IDLE_S))
	world.scene_add_component(&scene, p1, Player)

	world.scene_add_component(&scene, p1, graphics.Sprite)

	ents := [3]world.Entity_Handle{}
	for i in 0 ..< 3 {
		ents[i] = world.scene_create_enity(&scene)
		t := world.scene_add_component(&scene, ents[i], core.Transform)
		t.scale = {1, 1, 1}

		s := world.scene_add_component(&scene, ents[i], graphics.Sprite)
		s^ = resource.load_sprite("res://emblem.png")
		s.rect = {0, 0, 1, 1}
	}

	cam := world.scene_create_enity(&scene)
	c := world.scene_add_component(&scene, cam, graphics.Camera)
	c^ = {
		clear_color = {0.2, 0.5, 0.6, 1},
		mode        = .ORTHOGRAPHIC,
		near        = -1,
		far         = 1,
		zoom        = 5,
	}
	cam_t := world.scene_add_component(&scene, cam, core.Transform)
	cam_t.position.z = -6
	cam_t.scale = {1, 1, 1}

	engine.set_active_scene(&scene)

	for engine.tick() {
		if input.is_pressed(.ESCAPE) {
			break
		}
	}
}

box2aa :: proc() {
	world_def := box2d.DefaultWorldDef()
	world_def.gravity = {0, -10.0}
	world_id := box2d.CreateWorld(world_def)
	defer box2d.DestroyWorld(world_id)

	ground_def := box2d.DefaultBodyDef()
	ground_def.position = {0, -10}
	ground_id := box2d.CreateBody(world_id, ground_def)
	defer box2d.DestroyBody(ground_id)

	ground_box := box2d.MakeBox(50, 10)
	ground_shape_def := box2d.DefaultShapeDef()
	ground_shape := box2d.CreatePolygonShape(ground_id, ground_shape_def, &ground_box)
	defer box2d.DestroyShape(ground_shape, true)

	body_def := box2d.DefaultBodyDef()
	body_def.type = .dynamicBody
	body_def.position = {0, 4}
	body_id := box2d.CreateBody(world_id, body_def)
	defer box2d.DestroyBody(body_id)

	body_box := box2d.MakeBox(1, 1)
	body_shape_def := box2d.DefaultShapeDef()
	body_shape_def.density = 1
	body_shape_def.material.friction = 0.3
	body_shape := box2d.CreatePolygonShape(body_id, body_shape_def, &body_box)
	defer box2d.DestroyShape(body_shape, true)
}
