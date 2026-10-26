package event

WindowCloseEvent :: struct {}
WindowResizeEvent :: struct {
	width:  i32,
	height: i32,
}

KeyPressEvent :: struct {
	key:    u8,
	repeat: bool,
}
KeyReleaseEvent :: struct {
	key: u8,
}

MouseMoveEvent :: struct {
	pos: [2]f32,
}
MouseScrollEvent :: struct {
	scroll: f32,
}

ThornEvent :: union {
	WindowCloseEvent,
	WindowResizeEvent,
	KeyPressEvent,
	KeyReleaseEvent,
	MouseMoveEvent,
	MouseScrollEvent,
}
