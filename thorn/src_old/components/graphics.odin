package components

CameraProjection :: enum {
	ORTHOGRAPHIC,
	PERSPECTIVE,
}

Camera :: struct {
	fov:         f32,
	zoom:        f32,
	near, far:   f32,
	clear_color: [4]f32,
	mode:        CameraProjection,
}

Sprite :: struct {
	path:        string,
	clear_color: [4]f32,
}
