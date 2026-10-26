package event

Window_Close_Event :: struct {}
Window_Resize_Event :: struct {
	width:  i32,
	height: i32,
}

Key_Press_Event :: struct {
	key:    u8,
	repeat: bool,
}
Key_Release_Event :: struct {
	key: u8,
}

Mouse_Move_Event :: struct {
	pos: [2]f32,
}
Mouse_Scroll_Event :: struct {
	scroll: f32,
}

Thorn_Event :: union {
	Window_Close_Event,
	Window_Resize_Event,
	Key_Press_Event,
	Key_Release_Event,
	Mouse_Move_Event,
	Mouse_Scroll_Event,
}
