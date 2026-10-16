package graphics

import "base:runtime"
import "core:mem"

Error :: union {
	SDLError,
	ShaderError,
	mem.Allocator_Error,
}

SDLError :: enum {
	CREATE_GRAPHICS_PIPELINE,
	CREATE_GPU_SHADER,
	CREATE_GPU_DEVICE,
	CLAIM_WINDOW,
}

ShaderError :: enum {
	INVALID_FILE,
}
