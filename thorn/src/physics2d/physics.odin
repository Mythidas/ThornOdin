package physics2d

import "core:log"
import "thorn:core"
import "vendor:box2d"

Body_Type :: enum {
	STATIC,
	DYNAMIC,
	KINEMATIC,
}

Shape :: struct {
	width, height, radius: f32,
}

Rigidbody :: struct {
	_id:            box2d.BodyId,
	type:           Body_Type,
	gravity_scale:  f32,
	fixed_rotation: bool,
}

Collider :: struct {
	_id:                           box2d.ShapeId,
	shape:                         Shape,
	density, friction, resitution: f32,
	is_trigger:                    bool,
}

World :: struct {
	_id:     box2d.WorldId,
	gravity: core.Vec2,
}

world_create :: proc() -> (w: World) {
	world_def := box2d.DefaultWorldDef()
	world_def.gravity = {0, -9.8}
	w._id = box2d.CreateWorld(world_def)
	w.gravity = {0, -9.8}
	return
}

world_destroy :: proc(w: ^World) {
	if !is_valid(w) do return

	box2d.DestroyWorld(w._id)
	w^ = {}
}

world_update :: proc(w: ^World, dt: f32) {
	if !is_valid(w) do return

	box2d.World_Step(w._id, dt, 4)
}

body_create :: proc(w: ^World, rb: ^Rigidbody) {
	if !is_valid(w) do return
	if is_valid(rb) do return

	body_def := box2d.DefaultBodyDef()
	body_def.type = body_type_to_native(rb.type)
	body_def.gravityScale = rb.gravity_scale
	body_def.fixedRotation = rb.fixed_rotation

	rb._id = box2d.CreateBody(w._id, body_def)
}

body_destroy :: proc(rb: ^Rigidbody) {
	if !is_valid(rb) do return

	box2d.DestroyBody(rb._id)
}

shape_create :: proc(c: ^Collider, rb: ^Rigidbody) {
	if is_valid(c) do return
	if !is_valid(rb) do return

	body_box: box2d.Polygon
	if c.shape.radius > 0 {
		body_box = box2d.MakeRoundedBox(c.shape.width * 0.5, c.shape.height * 0.5, c.shape.radius)
	} else {
		body_box = box2d.MakeBox(c.shape.width * 0.5, c.shape.height * 0.5)
	}

	body_shape_def := box2d.DefaultShapeDef()
	body_shape_def.density = c.density
	body_shape_def.material.friction = c.friction
	body_shape_def.material.restitution = c.resitution
	body_shape_def.isSensor = c.is_trigger
	c._id = box2d.CreatePolygonShape(rb._id, body_shape_def, &body_box)
}

shape_destroy :: proc(c: ^Collider) {
	if !is_valid(c) do return

	box2d.DestroyShape(c._id, true)
}

body_add_impulse :: proc(rb: ^Rigidbody, dir: core.Vec2) {
	if !is_valid(rb) do return

	box2d.Body_ApplyLinearImpulse(rb._id, dir, box2d.Body_GetWorldCenterOfMass(rb._id), true)
}

body_get_position :: proc(rb: ^Rigidbody) -> core.Vec2 {
	if !is_valid(rb) do return {0, 0}

	return box2d.Body_GetPosition(rb._id)
}

body_get_rotation :: proc(rb: ^Rigidbody) -> f32 {
	if !is_valid(rb) do return 0

	return box2d.Rot_GetAngle(box2d.Body_GetRotation(rb._id))
}

body_get_velocity :: proc(rb: ^Rigidbody) -> core.Vec2 {
	if !is_valid(rb) do return {0, 0}

	return box2d.Body_GetLinearVelocity(rb._id)
}

body_set_transform :: proc(rb: ^Rigidbody, transform: core.Transform) {
	if !is_valid(rb) do return

	rot := box2d.MakeRot(transform.rotation.z)
	box2d.Body_SetTransform(rb._id, transform.position.xy, rot)
}

body_set_velocity :: proc(rb: ^Rigidbody, force: core.Vec2) {
	if !is_valid(rb) do return

	box2d.Body_SetLinearVelocity(rb._id, force)
}

body_is_grounded :: proc(rb: ^Rigidbody) -> bool {
	raycast: box2d.RayCastInput
	raycast.origin = body_get_position(rb)
	raycast.translation = {0, 0}

	body_box := box2d.MakeBox(2, 2)
	body_shape_def := box2d.DefaultShapeDef()
	body_shape_def.enableHitEvents = true
	body_shape_def.isSensor = true
	shape := box2d.CreatePolygonShape(rb._id, body_shape_def, &body_box)
	defer box2d.DestroyShape(shape, false)

	result := box2d.RayCastPolygon(raycast, body_box)
	log.info(result, raycast)
	if !result.hit do return false

	// TODO: Check if geometry is floor
	return true
}

is_valid :: proc {
	is_valid_world,
	is_valid_body,
	is_valid_collider,
}

is_valid_world :: proc(w: ^World) -> bool {
	if w == nil do return false
	return box2d.IsValid(w._id)
}

is_valid_body :: proc(rb: ^Rigidbody) -> bool {
	if rb == nil do return false
	return box2d.IsValid(rb._id)
}

is_valid_collider :: proc(c: ^Collider) -> bool {
	if c == nil do return false
	return box2d.IsValid(c._id)
}

@(private = "file")
body_type_to_native :: proc(type: Body_Type) -> box2d.BodyType {
	switch type {
	case .STATIC:
		return .staticBody
	case .DYNAMIC:
		return .dynamicBody
	case .KINEMATIC:
		return .kinematicBody
	}

	return .staticBody
}
