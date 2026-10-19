package input

import sdl "vendor:sdl3"

Key :: enum u8 {
	NONE,

	// Letters
	A,
	B,
	C,
	D,
	E,
	F,
	G,
	H,
	I,
	J,
	K,
	L,
	M,
	N,
	O,
	P,
	Q,
	R,
	S,
	T,
	U,
	V,
	W,
	X,
	Y,
	Z,

	// Number row
	NUM_0,
	NUM_1,
	NUM_2,
	NUM_3,
	NUM_4,
	NUM_5,
	NUM_6,
	NUM_7,
	NUM_8,
	NUM_9,

	// Function keys
	F1,
	F2,
	F3,
	F4,
	F5,
	F6,
	F7,
	F8,
	F9,
	F10,
	F11,
	F12,

	// Navigation
	UP,
	DOWN,
	LEFT,
	RIGHT,
	HOME,
	END,
	PAGE_UP,
	PAGE_DOWN,
	INSERT,
	DELETE,

	// Editing / whitespace
	ESCAPE,
	ENTER,
	TAB,
	SPACE,
	BACKSPACE,

	// Punctuation
	MINUS,
	EQUALS,
	LEFT_BRACKET,
	RIGHT_BRACKET,
	BACKSLASH,
	SEMICOLON,
	APOSTROPHE,
	GRAVE,
	COMMA,
	PERIOD,
	SLASH,

	// Modifiers
	LEFT_SHIFT,
	RIGHT_SHIFT,
	LEFT_CTRL,
	RIGHT_CTRL,
	LEFT_ALT,
	RIGHT_ALT,
	LEFT_SUPER,
	RIGHT_SUPER,
	CAPS_LOCK,

	// System
	PRINT_SCREEN,
	SCROLL_LOCK,
	PAUSE,

	// Keypad
	KP_0,
	KP_1,
	KP_2,
	KP_3,
	KP_4,
	KP_5,
	KP_6,
	KP_7,
	KP_8,
	KP_9,
	KP_ENTER,
	KP_PLUS,
	KP_MINUS,
	KP_MULTIPLY,
	KP_DIVIDE,
	KP_PERIOD,

	// Mouse buttons
	MOUSE_LEFT,
	MOUSE_MIDDLE,
	MOUSE_RIGHT,
	MOUSE_X1,
	MOUSE_X2,
}

key_from_scancode :: proc(sc: sdl.Scancode) -> Key {
	// Contiguous ranges in both SDL and the Key enum
	if sc >= .A && sc <= .Z do return Key(int(Key.A) + int(sc - .A))
	if sc >= ._1 && sc <= ._9 do return Key(int(Key.NUM_1) + int(sc - ._1))
	if sc >= .F1 && sc <= .F12 do return Key(int(Key.F1) + int(sc - .F1))

	#partial switch sc {
	case ._0:
		return .NUM_0

	case .UP:
		return .UP
	case .DOWN:
		return .DOWN
	case .LEFT:
		return .LEFT
	case .RIGHT:
		return .RIGHT
	case .HOME:
		return .HOME
	case .END:
		return .END
	case .PAGEUP:
		return .PAGE_UP
	case .PAGEDOWN:
		return .PAGE_DOWN
	case .INSERT:
		return .INSERT
	case .DELETE:
		return .DELETE

	case .ESCAPE:
		return .ESCAPE
	case .RETURN:
		return .ENTER
	case .TAB:
		return .TAB
	case .SPACE:
		return .SPACE
	case .BACKSPACE:
		return .BACKSPACE

	case .MINUS:
		return .MINUS
	case .EQUALS:
		return .EQUALS
	case .LEFTBRACKET:
		return .LEFT_BRACKET
	case .RIGHTBRACKET:
		return .RIGHT_BRACKET
	case .BACKSLASH:
		return .BACKSLASH
	case .SEMICOLON:
		return .SEMICOLON
	case .APOSTROPHE:
		return .APOSTROPHE
	case .GRAVE:
		return .GRAVE
	case .COMMA:
		return .COMMA
	case .PERIOD:
		return .PERIOD
	case .SLASH:
		return .SLASH

	case .LSHIFT:
		return .LEFT_SHIFT
	case .RSHIFT:
		return .RIGHT_SHIFT
	case .LCTRL:
		return .LEFT_CTRL
	case .RCTRL:
		return .RIGHT_CTRL
	case .LALT:
		return .LEFT_ALT
	case .RALT:
		return .RIGHT_ALT
	case .LGUI:
		return .LEFT_SUPER
	case .RGUI:
		return .RIGHT_SUPER
	case .CAPSLOCK:
		return .CAPS_LOCK

	case .PRINTSCREEN:
		return .PRINT_SCREEN
	case .SCROLLLOCK:
		return .SCROLL_LOCK
	case .PAUSE:
		return .PAUSE

	case .KP_0:
		return .KP_0
	case .KP_1:
		return .KP_1
	case .KP_2:
		return .KP_2
	case .KP_3:
		return .KP_3
	case .KP_4:
		return .KP_4
	case .KP_5:
		return .KP_5
	case .KP_6:
		return .KP_6
	case .KP_7:
		return .KP_7
	case .KP_8:
		return .KP_8
	case .KP_9:
		return .KP_9
	case .KP_ENTER:
		return .KP_ENTER
	case .KP_PLUS:
		return .KP_PLUS
	case .KP_MINUS:
		return .KP_MINUS
	case .KP_MULTIPLY:
		return .KP_MULTIPLY
	case .KP_DIVIDE:
		return .KP_DIVIDE
	case .KP_PERIOD:
		return .KP_PERIOD
	}
	return .NONE
}

key_from_mouse_button :: proc(button: u8) -> Key {
	switch button {
	case sdl.BUTTON_LEFT:
		return .MOUSE_LEFT
	case sdl.BUTTON_MIDDLE:
		return .MOUSE_MIDDLE
	case sdl.BUTTON_RIGHT:
		return .MOUSE_RIGHT
	case sdl.BUTTON_X1:
		return .MOUSE_X1
	case sdl.BUTTON_X2:
		return .MOUSE_X2
	}
	return .NONE
}
