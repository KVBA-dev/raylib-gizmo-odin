package raygizmo

import "core:math"
import la "core:math/linalg"
import rl "vendor:raylib"
import "vendor:raylib/rlgl"

GizmoFlag :: enum {
	Translate,
	Rotate,
	Scale,
	Local,
	View,
}

GizmoAction :: enum {
	None = 0,
	Translate,
	Scale,
	Rotate,
}

GizmoAxisName :: enum int {
	X = 0,
	Y = 1,
	Z = 2,
}

GizmoActiveAxis :: bit_set[GizmoAxisName]

GizmoFlags :: bit_set[GizmoFlag]

GIZMO_DISABLED :: GizmoFlags{}
GIZMO_ALL :: GizmoFlags{.Translate, .Rotate, .Scale}

GZ_AXIS_X :: 0
GZ_AXIS_Y :: 1
GZ_AXIS_Z :: 2
GIZMO_AXIS_COUNT :: 3

GizmoAxis :: struct {
	normal: rl.Vector3,
	color:  rl.Color,
}

GizmoGlobals :: struct {
	axisCfg:              [GizmoAxisName]GizmoAxis,
	gizmoSize:            f32,
	lineWidth:            f32,
	trArrowWidthFactor:   f32,
	trArrowLengthFactor:  f32,
	trPlaneOffsetFactor:  f32,
	trPlaneSizeFactor:    f32,
	trCircleRadiusFactor: f32,
	trCircleColor:        rl.Color,
	curAction:            GizmoAction,
	activeAxis:           GizmoActiveAxis,
	startTransform:       rl.Transform,
	activeTransform:      ^rl.Transform,
	startWorldMouse:      rl.Vector3,
	camera:               ^rl.Camera,
}

GizmoData :: struct {
	invViewProj:        rl.Matrix,
	curTransform:       ^rl.Transform,
	axis:               [GizmoAxisName]rl.Vector3,
	gizmoSize:          f32,
	camPos:             rl.Vector3,
	right, up, forward: rl.Vector3,
	flags:              GizmoFlags,
}

GIZMO := GizmoGlobals {
	axisCfg = {
		.X = {normal = {1, 0, 0}, color = {229, 72, 91, 255}},
		.Y = {normal = {0, 1, 0}, color = {131, 205, 56, 255}},
		.Z = {normal = {0, 0, 1}, color = {69, 138, 242, 255}},
	},
	gizmoSize = 1.5,
	lineWidth = 1,
	trArrowLengthFactor = 0.15,
	trArrowWidthFactor = 0.1,
	trPlaneOffsetFactor = 0.3,
	trPlaneSizeFactor = 0.15,
	trCircleRadiusFactor = 0.1,
	trCircleColor = {255, 255, 255, 200},
	curAction = .None,
	activeAxis = {},
}

SetCamera :: proc(camera: ^rl.Camera) {
	GIZMO.camera = camera
}

GizmoIdentity :: proc() -> rl.Transform {
	return {rotation = rl.Quaternion(1), scale = {1, 1, 1}, translation = {0, 0, 0}}
}

GizmoToMatrix :: proc(transform: rl.Transform) -> rl.Matrix {
	return rl.MatrixTranspose(
		transmute(rl.Matrix)la.matrix4_from_trs(
			transform.translation,
			transform.rotation,
			transform.scale,
		),
	)
	//return(
	//	rl.MatrixScale(transform.scale.x, transform.scale.y, transform.scale.z) *
	//	rl.QuaternionToMatrix(transform.rotation) *
	//	rl.MatrixTranslate(
	//		transform.translation.x,
	//		transform.translation.y,
	//		transform.translation.z,
	//	) \
	//)
}

DrawGizmo3D :: proc(flags: GizmoFlags, transform: ^rl.Transform) -> bool {
	if flags == GIZMO_DISABLED do return false
	data := GizmoData{}

	matProj := rlgl.GetMatrixProjection()
	matView := rlgl.GetMatrixModelview()
	invMat := rl.MatrixInvert(matView)

	data.invViewProj = rl.MatrixInvert(matProj) * invMat

	/* FIXME:
	data.camPos = {invMat[0, 3], invMat[1, 3], invMat[2, 3]} //{m12, m13, m14}
	data.right = {matView[0, 0], matView[1, 0], matView[2, 0]} //{m0, m4, m8}
	data.up = {matView[0, 1], matView[1, 1], matView[2, 1]} //{m1, m5, m9}
	data.forward = la.normalize(transform.translation - data.camPos)
	//data.forward = la.cross(data.right, data.up)
	*/

	data.camPos = GIZMO.camera.position
	data.forward = la.normalize(transform.translation - data.camPos)
	data.right = la.normalize(la.cross(GIZMO.camera.up, data.forward))
	data.up = la.cross(data.forward, data.right)

	data.curTransform = transform
	data.gizmoSize = GIZMO.gizmoSize * la.distance(data.camPos, transform.translation) * 0.1

	data.flags = flags
	ComputeAxisOrientation(&data)

	rlgl.DrawRenderBatchActive()
	prevLineWidth := rlgl.GetLineWidth()
	rlgl.SetLineWidth(GIZMO.lineWidth)
	rlgl.DisableBackfaceCulling()
	rlgl.DisableDepthTest()
	rlgl.DisableDepthMask()

	for ax in GizmoAxisName {
		if .Translate in data.flags {
			DrawGizmoArrow(&data, ax)
		}
		if .Scale in data.flags {
			DrawGizmoCube(&data, ax)
		}
		if .Translate in data.flags || .Scale in data.flags {
			DrawGizmoPlane(&data, ax)
		}
		if .Rotate in data.flags {
			DrawGizmoCircle(&data, ax)
		}
	}
	if .Scale in data.flags || .Translate in data.flags {
		DrawGizmoCenter(&data)
	}

	rlgl.DrawRenderBatchActive()
	rlgl.SetLineWidth(prevLineWidth)
	rlgl.EnableBackfaceCulling()
	rlgl.EnableDepthTest()
	rlgl.EnableDepthMask()

	if !IsGizmoTransforming() || data.curTransform == GIZMO.activeTransform {
		GizmoHandleInput(&data)
	}

	return IsThisGizmoTransforming(&data)
}

SetGizmoSize :: proc(size: f32) {
	GIZMO.gizmoSize = max(0, size)
}

SetGizmoLineWidth :: proc(width: f32) {
	GIZMO.lineWidth = max(0, width)
}

SetGizmoColors :: proc(x, y, z, center: rl.Color) {
	GIZMO.axisCfg[.X].color = x
	GIZMO.axisCfg[.Y].color = y
	GIZMO.axisCfg[.Z].color = z
	GIZMO.trCircleColor = center
}

SetGizmoGlobalAxis :: proc(right, forward, up: rl.Vector3) {
	GIZMO.axisCfg[.X].normal = la.normalize(right)
	GIZMO.axisCfg[.Y].normal = la.normalize(up)
	GIZMO.axisCfg[.Z].normal = la.normalize(forward)
}

// helper functions ------------------------
@(private)
ComputeAxisOrientation :: proc(gizmoData: ^GizmoData) {
	flags := gizmoData.flags

	if .Scale in flags {
		flags &~= {.View}
		flags |= {.Local}
	}

	if .View in flags {
		gizmoData.axis[.X] = gizmoData.right
		gizmoData.axis[.Y] = gizmoData.up
		gizmoData.axis[.Z] = gizmoData.forward

	} else {
		gizmoData.axis[.X] = GIZMO.axisCfg[.X].normal
		gizmoData.axis[.Y] = GIZMO.axisCfg[.Y].normal
		gizmoData.axis[.Z] = GIZMO.axisCfg[.Z].normal

		if .Local in flags {
			for ax in GizmoAxisName {
				gizmoData.axis[ax] = la.normalize(
					rl.Vector3RotateByQuaternion(
						gizmoData.axis[ax],
						gizmoData.curTransform.rotation,
					),
				)
			}
		}
	}
}

@(private)
IsGizmoAxisActive :: proc(axis: GizmoAxisName) -> bool {
	return(
		(axis == .X && (.X in GIZMO.activeAxis)) ||
		(axis == .Y && (.Y in GIZMO.activeAxis)) ||
		(axis == .Z && (.Z in GIZMO.activeAxis)) \
	)
}

@(private)
CheckGizmoType :: proc(data: ^GizmoData, type: GizmoFlags) -> bool {
	return (data.flags & type) == type
}

@(private)
IsGizmoTransforming :: proc() -> bool {
	return GIZMO.curAction != .None
}

@(private)
IsThisGizmoTransforming :: proc(data: ^GizmoData) -> bool {
	return IsGizmoTransforming() && data.curTransform == GIZMO.activeTransform
}

@(private)
IsGizmoScaling :: proc() -> bool {
	return GIZMO.curAction == .Scale
}

@(private)
IsGizmoTranslating :: proc() -> bool {
	return GIZMO.curAction == .Translate
}

@(private)
IsGizmoRotating :: proc() -> bool {
	return GIZMO.curAction == .Rotate
}

@(private)
Vec3ScreenToWorld :: proc(source: rl.Vector3, matViewProjInv: ^rl.Matrix) -> rl.Vector3 {
	qt := rl.QuaternionTransform(
		transmute(rl.Quaternion)rl.Vector4{source.x, source.y, source.z, 1},
		matViewProjInv^,
	)
	return {qt.x, qt.y, qt.z} / qt.w
}

@(private)
Vec3ScreenToWorldRay :: proc(position: rl.Vector2, matViewProjInv: ^rl.Matrix) -> rl.Ray {
	ray := rl.Ray{}
	width := cast(f32)rl.GetScreenWidth()
	height := cast(f32)rl.GetScreenHeight()
	deviceCoords := rl.Vector2{(2 * position.x) / width - 1, 1 - (2 * position.y) / height}
	nearPoint := Vec3ScreenToWorld(rl.Vector3{deviceCoords.x, deviceCoords.y, 0}, matViewProjInv)
	farPoint := Vec3ScreenToWorld(rl.Vector3{deviceCoords.x, deviceCoords.y, 1}, matViewProjInv)
	cameraPlanePointerPos := Vec3ScreenToWorld(
		rl.Vector3{deviceCoords.x, deviceCoords.y, -1},
		matViewProjInv,
	)
	direction := la.normalize(farPoint - nearPoint)
	ray.position = cameraPlanePointerPos
	ray.direction = direction
	return ray
}

//drawing functions --------------------------
@(private)
DrawGizmoCube :: proc(data: ^GizmoData, axis: GizmoAxisName) {
	if IsThisGizmoTransforming(data) && (!IsGizmoAxisActive(axis) || !IsGizmoScaling()) {
		return
	}

	gizmoSize := CheckGizmoType(data, {.Scale, .Translate}) ? data.gizmoSize * 0.5 : data.gizmoSize
	endPos :=
		data.curTransform.translation +
		data.axis[axis] * gizmoSize * (1 - GIZMO.trArrowWidthFactor)

	rl.DrawLine3D(data.curTransform.translation, endPos, GIZMO.axisCfg[axis].color)

	boxSize := data.gizmoSize * GIZMO.trArrowWidthFactor

	dim1 := data.axis[(GizmoAxisName)((int(axis) + 1) % 3)] * boxSize
	dim2 := data.axis[(GizmoAxisName)((int(axis) + 2) % 3)] * boxSize
	n := data.axis[axis]
	col := GIZMO.axisCfg[axis].color

	depth := n * boxSize

	a := endPos - dim1 * 0.5 - dim2 * 0.5
	b := a + dim1
	c := b + dim2
	d := a + dim2

	e := a + depth
	f := b + depth
	g := c + depth
	h := d + depth

	rlgl.Begin(rlgl.QUADS)

	rlgl.Color4ub(col.r, col.g, col.b, col.a)

	rlgl.Vertex3f(a.x, a.y, a.z)
	rlgl.Vertex3f(b.x, b.y, b.z)
	rlgl.Vertex3f(c.x, c.y, c.z)
	rlgl.Vertex3f(d.x, d.y, d.z)

	rlgl.Vertex3f(e.x, e.y, e.z)
	rlgl.Vertex3f(f.x, f.y, f.z)
	rlgl.Vertex3f(g.x, g.y, g.z)
	rlgl.Vertex3f(h.x, h.y, h.z)

	rlgl.Vertex3f(a.x, a.y, a.z)
	rlgl.Vertex3f(e.x, e.y, e.z)
	rlgl.Vertex3f(f.x, f.y, f.z)
	rlgl.Vertex3f(d.x, d.y, d.z)

	rlgl.Vertex3f(b.x, b.y, b.z)
	rlgl.Vertex3f(f.x, f.y, f.z)
	rlgl.Vertex3f(g.x, g.y, g.z)
	rlgl.Vertex3f(c.x, c.y, c.z)

	rlgl.Vertex3f(a.x, a.y, a.z)
	rlgl.Vertex3f(b.x, b.y, b.z)
	rlgl.Vertex3f(f.x, f.y, f.z)
	rlgl.Vertex3f(e.x, e.y, e.z)

	rlgl.Vertex3f(c.x, c.y, c.z)
	rlgl.Vertex3f(g.x, g.y, g.z)
	rlgl.Vertex3f(h.x, h.y, h.z)
	rlgl.Vertex3f(d.x, d.y, d.z)

	rlgl.End()
}

@(private)
DrawGizmoPlane :: proc(data: ^GizmoData, axis: GizmoAxisName) {
	if IsThisGizmoTransforming(data) {
		return
	}

	dir1 := data.axis[(GizmoAxisName)((int(axis) + 1) % 3)]
	dir2 := data.axis[(GizmoAxisName)((int(axis) + 2) % 3)]
	col := GIZMO.axisCfg[(GizmoAxisName)(int(axis))].color

	offset := GIZMO.trPlaneOffsetFactor * data.gizmoSize
	size := GIZMO.trPlaneSizeFactor * data.gizmoSize

	a := data.curTransform.translation + dir1 * offset + dir2 * offset
	b := a + dir1 * size
	c := b + dir2 * size
	d := a + dir2 * size

	rlgl.Begin(rlgl.QUADS)
	rlgl.Color4ub(col.r, col.g, col.b, u8(f32(col.a) * 0.5))

	rlgl.Vertex3f(a.x, a.y, a.z)
	rlgl.Vertex3f(b.x, b.y, b.z)
	rlgl.Vertex3f(c.x, c.y, c.z)
	rlgl.Vertex3f(d.x, d.y, d.z)

	rlgl.End()

	rlgl.Begin(rlgl.LINES)
	rlgl.Color4ub(col.r, col.g, col.b, col.a)

	rlgl.Vertex3f(a.x, a.y, a.z)
	rlgl.Vertex3f(b.x, b.y, b.z)

	rlgl.Vertex3f(b.x, b.y, b.z)
	rlgl.Vertex3f(c.x, c.y, c.z)

	rlgl.Vertex3f(c.x, c.y, c.z)
	rlgl.Vertex3f(d.x, d.y, d.z)

	rlgl.Vertex3f(d.x, d.y, d.z)
	rlgl.Vertex3f(a.x, a.y, a.z)
	rlgl.End()
}

@(private)
DrawGizmoArrow :: proc(data: ^GizmoData, axis: GizmoAxisName) {
	if IsThisGizmoTransforming(data) && (!IsGizmoAxisActive(axis) || !IsGizmoScaling()) {
		return
	}

	endPos :=
		data.curTransform.translation +
		data.axis[axis] * data.gizmoSize * (1 - GIZMO.trArrowLengthFactor)

	if .Scale not_in data.flags {
		rl.DrawLine3D(data.curTransform.translation, endPos, GIZMO.axisCfg[axis].color)
	}

	arrowLength := data.gizmoSize * GIZMO.trArrowLengthFactor
	arrowWidth := data.gizmoSize * GIZMO.trArrowWidthFactor

	dim1 := data.axis[(GizmoAxisName)((int(axis) + 1) % 3)] * arrowWidth
	dim2 := data.axis[(GizmoAxisName)((int(axis) + 2) % 3)] * arrowWidth
	n := data.axis[axis]
	col := GIZMO.axisCfg[axis].color

	v := endPos + n * arrowLength

	a := endPos - dim1 * 0.5 - dim2 * 0.5
	b := a + dim1
	c := b + dim2
	d := a + dim2

	rlgl.Begin(rlgl.TRIANGLES)

	rlgl.Color4ub(col.r, col.g, col.b, col.a)

	rlgl.Vertex3f(a.x, a.y, a.z)
	rlgl.Vertex3f(b.x, b.y, b.z)
	rlgl.Vertex3f(c.x, c.y, c.z)

	rlgl.Vertex3f(a.x, a.y, a.z)
	rlgl.Vertex3f(c.x, c.y, c.z)
	rlgl.Vertex3f(d.x, d.y, d.z)

	rlgl.Vertex3f(a.x, a.y, a.z)
	rlgl.Vertex3f(v.x, v.y, v.z)
	rlgl.Vertex3f(b.x, b.y, b.z)

	rlgl.Vertex3f(b.x, b.y, b.z)
	rlgl.Vertex3f(v.x, v.y, v.z)
	rlgl.Vertex3f(c.x, c.y, c.z)

	rlgl.Vertex3f(c.x, c.y, c.z)
	rlgl.Vertex3f(v.x, v.y, v.z)
	rlgl.Vertex3f(d.x, d.y, d.z)

	rlgl.Vertex3f(d.x, d.y, d.z)
	rlgl.Vertex3f(v.x, v.y, v.z)
	rlgl.Vertex3f(a.x, a.y, a.z)

	rlgl.End()
}

@(private)
DrawGizmoCenter :: proc(data: ^GizmoData) {
	origin := data.curTransform.translation

	radius := data.gizmoSize * GIZMO.trCircleRadiusFactor
	col := GIZMO.trCircleColor
	angleStep := 15

	rlgl.PushMatrix()

	rlgl.Translatef(origin.x, origin.y, origin.z)
	rlgl.Begin(rlgl.LINES)
	rlgl.Color4ub(col.r, col.g, col.b, col.a)
	i := 0
	for i < 360 {
		defer i += angleStep

		angle := f32(i) * math.RAD_PER_DEG
		p := data.right * math.sin(angle) * radius
		p += data.up * math.cos(angle) * radius
		rlgl.Vertex3f(p.x, p.y, p.z)

		angle += f32(angleStep) * math.RAD_PER_DEG
		p = data.right * math.sin(angle) * radius
		p += data.up * math.cos(angle) * radius
		rlgl.Vertex3f(p.x, p.y, p.z)
	}

	rlgl.End()
	rlgl.PopMatrix()
}

@(private)
DrawGizmoCircle :: proc(data: ^GizmoData, axis: GizmoAxisName) {
	if IsThisGizmoTransforming(data) && (!IsGizmoAxisActive(axis) || !IsGizmoRotating()) {
		return
	}

	origin := data.curTransform.translation

	dir1 := data.axis[(GizmoAxisName)((int(axis) + 1) % 3)]
	dir2 := data.axis[(GizmoAxisName)((int(axis) + 2) % 3)]
	radius := data.gizmoSize
	col := GIZMO.axisCfg[axis].color
	angleStep := 10

	rlgl.PushMatrix()

	rlgl.Translatef(origin.x, origin.y, origin.z)
	rlgl.Begin(rlgl.LINES)

	rlgl.Color4ub(col.r, col.g, col.b, col.a)
	i := 0
	for i < 360 {
		defer i += angleStep

		angle := f32(i) * math.RAD_PER_DEG
		p := dir1 * math.sin(angle) * radius
		p += dir2 * math.cos(angle) * radius
		rlgl.Vertex3f(p.x, p.y, p.z)

		angle += f32(angleStep) * math.RAD_PER_DEG
		p = dir1 * math.sin(angle) * radius
		p += dir2 * math.cos(angle) * radius
		rlgl.Vertex3f(p.x, p.y, p.z)
	}

	rlgl.End()
	rlgl.PopMatrix()
}

// mouse ray to gizmo intersections

@(private)
CheckOrientedBoundingBox :: proc(
	data: ^GizmoData,
	ray: rl.Ray,
	obbCenter: rl.Vector3,
	obbHalfSize: rl.Vector3,
) -> bool {
	oLocal := ray.position - obbCenter
	localRay := rl.Ray{}

	localRay.position = {
		la.dot(oLocal, data.axis[.X]),
		la.dot(oLocal, data.axis[.Y]),
		la.dot(oLocal, data.axis[.Z]),
	}

	localRay.direction = {
		la.dot(ray.direction, data.axis[.X]),
		la.dot(ray.direction, data.axis[.Y]),
		la.dot(ray.direction, data.axis[.Z]),
	}

	aabbLocal := rl.BoundingBox {
		min = -obbHalfSize,
		max = obbHalfSize,
	}

	return rl.GetRayCollisionBox(localRay, aabbLocal).hit
}

@(private)
CheckGizmoAxis :: proc(
	data: ^GizmoData,
	axis: GizmoAxisName,
	ray: rl.Ray,
	type: GizmoFlags,
) -> bool {
	halfDim := [3]f32{}

	halfDim[int(axis)] = data.gizmoSize * 0.5
	halfDim[(int(axis) + 1) % 3] = data.gizmoSize * GIZMO.trArrowWidthFactor * 0.5
	halfDim[(int(axis) + 2) % 3] = halfDim[(int(axis) + 1) % 3]

	if type == {.Scale} && CheckGizmoType(data, {.Translate, .Scale}) {
		halfDim[int(axis)] *= 0.5
	}

	obbCenter := data.curTransform.translation + data.axis[axis] * halfDim[int(axis)]
	return CheckOrientedBoundingBox(data, ray, obbCenter, halfDim)
}

@(private)
CheckGizmoPlane :: proc(data: ^GizmoData, axis: GizmoAxisName, ray: rl.Ray) -> bool {
	dir1 := data.axis[(GizmoAxisName)((int(axis) + 1) % 3)]
	dir2 := data.axis[(GizmoAxisName)((int(axis) + 2) % 3)]

	offset := GIZMO.trPlaneOffsetFactor * data.gizmoSize
	size := GIZMO.trPlaneSizeFactor * data.gizmoSize

	a := data.curTransform.translation + dir1 * offset + dir2 * offset
	b := a + dir1 * size
	c := b + dir2 * size
	d := a + dir2 * size

	return rl.GetRayCollisionQuad(ray, a, b, c, d).hit
}

@(private)
CheckGizmoCircle :: proc(data: ^GizmoData, index: int, ray: rl.Ray) -> bool {
	origin := data.curTransform.translation

	dir1 := data.axis[(GizmoAxisName)((index + 1) % 3)]
	dir2 := data.axis[(GizmoAxisName)((index + 2) % 3)]

	circleRadius := data.gizmoSize
	angleStep := 10

	sphereRadius := circleRadius * math.sin(f32(angleStep) * math.RAD_PER_DEG / 2)

	i := 0
	for i < 360 {
		defer i += angleStep
		angle := f32(i) * math.RAD_PER_DEG
		p := origin + dir1 * math.sin(angle) * circleRadius
		p += dir2 * math.cos(angle) * circleRadius
		if rl.GetRayCollisionSphere(ray, p, sphereRadius).hit {
			return true
		}
	}
	return false
}

@(private)
CheckGizmoCenter :: proc(data: ^GizmoData, ray: rl.Ray) -> bool {
	return(
		rl.GetRayCollisionSphere(ray, data.curTransform.translation, data.gizmoSize * GIZMO.trCircleRadiusFactor).hit \
	)
}

// input handling

@(private)
GetWorldMouse :: proc(data: ^GizmoData) -> rl.Vector3 {
	dist := la.distance(data.camPos, data.curTransform.translation)
	// FIXME:
	//mouseRay := Vec3ScreenToWorldRay(rl.GetMousePosition(), &data.invViewProj)
	mouseRay := rl.GetScreenToWorldRay(rl.GetMousePosition(), GIZMO.camera^)
	return mouseRay.position + mouseRay.direction * dist
}

@(private)
GizmoHandleInput :: proc(data: ^GizmoData) {
	action := GIZMO.curAction
	if action != .None {
		if rl.IsMouseButtonUp(.LEFT) {
			action = .None
			GIZMO.activeAxis = {}
		} else {
			endWorldMouse := GetWorldMouse(data)
			pVec := endWorldMouse - GIZMO.startWorldMouse

			switch action {
			case .Translate:
				GIZMO.activeTransform.translation = GIZMO.startTransform.translation
				if GIZMO.activeAxis == {.X, .Y, .Z} {
					GIZMO.activeTransform.translation +=
						rl.Vector3Project(pVec, data.right) + rl.Vector3Project(pVec, data.up)
				} else {
					prj: rl.Vector3
					if .X in GIZMO.activeAxis {
						prj = rl.Vector3Project(pVec, data.axis[.X])
						GIZMO.activeTransform.translation += prj
					}
					if .Y in GIZMO.activeAxis {
						prj = rl.Vector3Project(pVec, data.axis[.Y])
						GIZMO.activeTransform.translation += prj
					}
					if .Z in GIZMO.activeAxis {
						prj = rl.Vector3Project(pVec, data.axis[.Z])
						GIZMO.activeTransform.translation += prj
					}
				}
			case .Scale:
				GIZMO.activeTransform.scale = GIZMO.startTransform.scale
				if GIZMO.activeAxis == {.X, .Y, .Z} {
					delta := la.dot(pVec, GIZMO.axisCfg[.X].normal)
					GIZMO.activeTransform.scale += {delta, delta, delta}
				} else {
					prj: rl.Vector3
					if .X in GIZMO.activeAxis {
						prj = rl.Vector3Project(pVec, GIZMO.axisCfg[.X].normal)
						GIZMO.activeTransform.scale += prj
					}
					if .Y in GIZMO.activeAxis {
						prj = rl.Vector3Project(pVec, GIZMO.axisCfg[.Y].normal)
						GIZMO.activeTransform.scale += prj
					}
					if .Z in GIZMO.activeAxis {
						prj = rl.Vector3Project(pVec, GIZMO.axisCfg[.Z].normal)
						GIZMO.activeTransform.scale += prj
					}
				}
			case .Rotate:
				GIZMO.activeTransform.rotation = GIZMO.startTransform.rotation
				delta := la.clamp(la.dot(pVec, data.right + data.up), -2 * math.PI, +2 * math.PI)
				if .X in GIZMO.activeAxis {
					q := rl.QuaternionFromAxisAngle(data.axis[.X], delta)
					GIZMO.activeTransform.rotation = q * GIZMO.activeTransform.rotation
				}
				if .Y in GIZMO.activeAxis {
					q := rl.QuaternionFromAxisAngle(data.axis[.Y], delta)
					GIZMO.activeTransform.rotation = q * GIZMO.activeTransform.rotation
				}
				if .Z in GIZMO.activeAxis {
					q := rl.QuaternionFromAxisAngle(data.axis[.Z], delta)
					GIZMO.activeTransform.rotation = q * GIZMO.activeTransform.rotation
				}

				GIZMO.startTransform = GIZMO.activeTransform^
				GIZMO.startWorldMouse = endWorldMouse
			case .None:
			case:
			}
		}
	} else {
		if rl.IsMouseButtonPressed(.LEFT) {
			//mouseRay := Vec3ScreenToWorldRay(rl.GetMousePosition(), &data.invViewProj)
			mouseRay := rl.GetScreenToWorldRay(rl.GetMousePosition(), GIZMO.camera^)

			hit := -1
			action = GizmoAction.None

			k := 0
			for hit == -1 && k < 2 {
				gizmoFlag := k == 0 ? GizmoFlag.Scale : GizmoFlag.Translate
				gizmoAction := k == 0 ? GizmoAction.Scale : GizmoAction.Translate

				if gizmoFlag in data.flags {
					if CheckGizmoCenter(data, mouseRay) {
						action = gizmoAction
						hit = 6
						break
					}
					for axis in GizmoAxisName {
						if CheckGizmoAxis(data, axis, mouseRay, {gizmoFlag}) {
							action = gizmoAction
							hit = int(axis)
							break
						}
						if CheckGizmoPlane(data, axis, mouseRay) {
							action =
								CheckGizmoType(data, {.Scale, .Translate}) ? .Translate : gizmoAction
							hit = 3 + int(axis)
							break
						}
					}
				}
				k += 1
			}
			if hit == -1 && .Rotate in data.flags {
				for axis in GizmoAxisName {
					if CheckGizmoCircle(data, int(axis), mouseRay) {
						action = .Rotate
						hit = int(axis)
						break
					}
				}
			}

			GIZMO.activeAxis = {}
			if hit >= 0 {
				switch hit {
				case 0:
					GIZMO.activeAxis = {.X}
				case 1:
					GIZMO.activeAxis = {.Y}
				case 2:
					GIZMO.activeAxis = {.Z}
				case 3:
					GIZMO.activeAxis = {.Y, .Z}
				case 4:
					GIZMO.activeAxis = {.X, .Z}
				case 5:
					GIZMO.activeAxis = {.X, .Y}
				case 6:
					GIZMO.activeAxis = {.X, .Y, .Z}
				}
				GIZMO.activeTransform = data.curTransform
				GIZMO.startTransform = data.curTransform^
				GIZMO.startWorldMouse = GetWorldMouse(data)
			}
		}
	}
	GIZMO.curAction = action
}
