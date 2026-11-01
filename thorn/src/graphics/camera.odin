package graphics

import "core:math/linalg"
import "thorn:core"

Camera_Projection :: enum {
	ORTHOGRAPHIC,
	PERSPECTIVE,
}

Camera :: struct {
	fov:         f32,
	zoom:        f32,
	near, far:   f32,
	clear_color: core.Color,
	mode:        Camera_Projection,
}

@(private)
camera_calculate_matrix :: proc(
	cam: Camera,
	cam_transform: core.Transform,
	w, h: f32,
) -> core.Mat4 {
	aspect: f32 = w / h

	mat := linalg.MATRIX4F32_IDENTITY
	if cam.mode == .PERSPECTIVE {
		mat = linalg.matrix4_perspective(linalg.to_radians(cam.fov), aspect, cam.near, cam.far)
	} else {
		half_h: f32 = cam.zoom * 0.5
		half_w: f32 = half_h * aspect
		mat = linalg.matrix_ortho3d(-half_w, half_w, -half_h, half_h, cam.near, cam.far)
	}

	return mat * core.transform_matrix(cam_transform)
}
