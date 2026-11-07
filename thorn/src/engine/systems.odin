package engine

import "thorn:core"
import "thorn:graphics"
import "thorn:physics2d"

Animator_View :: struct {
	anims:   []graphics.Animator,
	sprites: []graphics.Sprite,
}

Sprite_View :: struct {
	sprites:    []graphics.Sprite,
	transforms: []core.Transform,
}

Camera_View :: struct {
	camera:    []graphics.Camera,
	transform: []core.Transform,
}

Physics_2D_View :: struct {
	bodys:      []physics2d.Rigidbody,
	colliders:  []physics2d.Collider,
	transforms: []core.Transform,
}

animator_update :: proc(view: Animator_View, dt: f32) {
	for &anim, i in view.anims {
		graphics.animator_update(&anim, dt)
		view.sprites[i] = graphics.animator_get_sprite(&anim)
	}
}

sprites_update :: proc(view: Sprite_View, dt: f32) {
	for s, i in view.sprites {
		graphics.draw_sprite(transform = view.transforms[i], sprite = s)
	}
}

camera_update :: proc(view: Camera_View, dt: f32) {
	graphics.set_camera(view.camera[0], view.transform[0])
}

physics_2d_pre_update :: proc(view: Physics_2D_View, dt: f32) {
	if get_active_scene() == nil do return

	for &body, i in view.bodys {
		if !physics2d.is_valid(&body) {
			physics2d.body_create(&get_active_scene().world, &body)
		}

		if !physics2d.is_valid(&view.colliders[i]) && physics2d.is_valid(&body) {
			physics2d.shape_create(&view.colliders[i], &body)
		}
	}
}

physics_2d_fixed_update :: proc(view: Physics_2D_View, dt: f32) {
	for &body, i in view.bodys {
		if body.type == .STATIC {
			physics2d.body_set_transform(&body, view.transforms[i])
		} else if body.type == .DYNAMIC {
			pos := physics2d.body_get_position(&body)
			rot := physics2d.body_get_rotation(&body)
			view.transforms[i].position.xy = pos
			view.transforms[i].rotation.z = rot
		}
	}
}

register_default_systems :: proc() {
	register_system(system_query_helper(Animator_View, .PRE_UPDATE, animator_update))
	register_system(system_query_helper(Sprite_View, .RENDER, sprites_update))
	register_system(system_query_helper(Camera_View, .UPDATE, camera_update))
	register_system(system_query_helper(Physics_2D_View, .PRE_UPDATE, physics_2d_pre_update))
	register_system(system_query_helper(Physics_2D_View, .FIXED_UPDATE, physics_2d_fixed_update))
}
