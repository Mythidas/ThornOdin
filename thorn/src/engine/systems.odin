package engine

import "thorn:core"
import "thorn:graphics"

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

register_default_systems :: proc() {
	register_system(system_query_helper(Animator_View, .PRE_UPDATE, animator_update))
	register_system(system_query_helper(Sprite_View, .RENDER, sprites_update))
	register_system(system_query_helper(Camera_View, .UPDATE, camera_update))
}
