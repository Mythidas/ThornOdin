package ecs

@(private)
state: struct {
	init:  bool,
	hooks: map[typeid]Component_Hooks,
}

Component_Hooks :: struct {
	on_attach: proc(s: ^Scene, ent: Entity_Handle, data: rawptr),
	on_detach: proc(s: ^Scene, ent: Entity_Handle, data: rawptr),
}

initialize :: proc() {
	ensure(state.init == false, "World.initialize() has already been called")

	state.hooks = make(map[typeid]Component_Hooks)
	state.init = false
}

terminate :: proc() {
	ensure(state.init, "World.initialize() needs to be called")

	delete(state.hooks)
}

register_hooks :: proc($T: typeid, ch: Component_Hooks) {
	state.hooks[T] = ch
}

component_hooks_helper :: proc(
	$T: typeid,
	$on_attach, $on_detach: proc(s: ^Scene, e: Entity_Handle, data: rawptr),
) -> (
	ch: Component_Hooks,
) {
	when on_attach != nil {
		ch.on_attach = proc(s: ^Scene, e: Entity_Handle, data: rawptr) {on_attach(
				s,
				e,
				cast(^T)data,
			)}
	}

	when on_detach != nil {
		ch.on_detach = proc(s: ^Scene, e: Entity_Handle, data: rawptr) {on_detach(
				s,
				e,
				cast(^T)data,
			)}
	}

	return
}
