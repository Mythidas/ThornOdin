package core

import "core:math/linalg"

Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32

IVec2 :: [2]int
IVec3 :: [3]int
IVec4 :: [4]int

Mat4 :: matrix[4, 4]f32

Rect :: struct {
	x_min, y_min: f32,
	x_max, y_max: f32,
}

Transform :: struct {
	position: Vec3,
	rotation: Vec3,
	scale:    Vec3,
}

transform_matrix :: proc(t: Transform) -> Mat4 {
	return(
		linalg.matrix4_translate(t.position) *
		linalg.matrix4_rotate(linalg.to_radians(t.rotation.x), [3]f32{1, 0, 0}) *
		linalg.matrix4_rotate(linalg.to_radians(t.rotation.y), [3]f32{0, 1, 0}) *
		linalg.matrix4_rotate(linalg.to_radians(t.rotation.z), [3]f32{0, 0, 1}) *
		linalg.matrix4_scale(t.scale) \
	)
}
