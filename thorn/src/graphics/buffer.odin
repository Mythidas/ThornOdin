package graphics

import "core:log"
import "vendor:sdl3"

@(private)
GPU_Buffer :: struct {
	handle: ^sdl3.GPUBuffer,
	size:   u32,
}

@(private)
buffer_create :: proc(ci: sdl3.GPUBufferCreateInfo) -> (buff: GPU_Buffer, err: Graphics_Error) {
	buff.handle = sdl3.CreateGPUBuffer(state.device, ci)
	if buff.handle == nil {
		log.errorf("Failed to create gpu buffer: %s", sdl3.GetError())
		return {}, .GPU_BUFFER
	}

	buff.size = ci.size
	return buff, nil
}

@(private)
buffer_destroy :: proc(buff: ^GPU_Buffer) {
	sdl3.ReleaseGPUBuffer(state.device, buff.handle)
	buff^ = {}
}

@(private)
buffer_upload :: proc(
	buff: ^GPU_Buffer,
	data: []$T,
	transfer_buffer: ^sdl3.GPUTransferBuffer = nil,
) -> Graphics_Error {
	size := len(data) * size_of(T)

	if buff^ == {} || buff.handle == nil {
		log.warnf("GPU_Buffer is invalid: %v", buff.handle)
		return .GPU_BUFFER
	}
	if size == 0 {
		log.warnf("Data array is empty")
		return .GPU_BUFFER
	}
	if u32(size) > buff.size {
		log.warnf("Data array overflows buffer: Buffer Size (%v), Data Size (%v)", buff.size, size)
		return .GPU_BUFFER
	}

	tb := transfer_buffer
	if tb == nil {
		tb = sdl3.CreateGPUTransferBuffer(
			state.device,
			sdl3.GPUTransferBufferCreateInfo{usage = .UPLOAD, size = u32(size)},
		)
		if tb == nil {
			log.errorf("Failed to create transfer buffer: %s", sdl3.GetError())
			return .GPU_BUFFER
		}
	}

	defer if transfer_buffer == nil {
		sdl3.ReleaseGPUTransferBuffer(state.device, tb)
	}

	mapped := ([^]T)(sdl3.MapGPUTransferBuffer(state.device, tb, transfer_buffer != nil))
	if mapped == nil {
		log.errorf("Failed to get buffer mapping: %s", sdl3.GetError())
		return .GPU_BUFFER
	}

	copy(mapped[:len(data)], data[:])
	sdl3.UnmapGPUTransferBuffer(state.device, tb)

	cmd := sdl3.AcquireGPUCommandBuffer(state.device)
	if cmd == nil {
		log.errorf("Failed to acquire cmd buffer: %s", sdl3.GetError())
		return .GPU_BUFFER
	}

	copy_pass := sdl3.BeginGPUCopyPass(cmd)
	src := sdl3.GPUTransferBufferLocation {
		transfer_buffer = tb,
		offset          = 0,
	}
	dst := sdl3.GPUBufferRegion {
		buffer = buff.handle,
		offset = 0,
		size   = u32(size),
	}

	sdl3.UploadToGPUBuffer(copy_pass, src, dst, false)
	sdl3.EndGPUCopyPass(copy_pass)
	if !sdl3.SubmitGPUCommandBuffer(cmd) {
		log.errorf("GPU Command submit failed: %s", sdl3.GetError())
		return .GPU_BUFFER
	}

	return nil
}
