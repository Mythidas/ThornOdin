package core

EventType :: enum {
	// Window
	WINDOW_CLOSE,
	WINDOW_RESIZE,

	// Input
	KEY_PRESSED,
	KEY_RELEASED,
	MOUSE_MOVED,
}

WindowResizeEvent :: struct {
	width:  i32,
	height: i32,
}

KeyChangedEvent :: struct {
	key: i32,
}

EventInfo :: union {
	WindowResizeEvent,
	KeyChangedEvent,
}

ThornEvent :: struct {
	type: EventType,
	info: EventInfo,
}
