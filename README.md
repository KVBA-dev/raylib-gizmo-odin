# raylib-gizmo-odin

This is an Odin port of raylib-gizmo by [Claudio Z. (cloudofoz)](https://github.com/cloudofoz)
[Link to original repository](https://github.com/cloudofoz/raylib-gizmo/)

This library allows to draw gizmos in 3D scene. It's got immediate-mode-like behaviour,
meaning all of the drawing and input handling happens in a single function call.

At this stage, the library is functional, however there are some bugs, namely around
rotation and scale gizmos. It also requires a reference to a `rl.Camera3D`, which the
original does not have.

Here's an example program

```odin
package main

import rg "raygizmo"
import rl "vendor:raylib"

main :: proc() {
	rl.InitWindow(1280, 1024, "raygizmo-test")
	defer rl.CloseWindow()

	// This is a transform that will be edited using the gizmo
	cube_transform := rg.GizmoIdentity()

	// Example model
	cube := rl.GenMeshCube(1, 1, 1)
	cube_model := rl.LoadModelFromMesh(cube)
	defer rl.UnloadModel(cube_model)

	cam := rl.Camera3D {
		position   = {-10, 2, -5},
		target     = {0, 0, 0},
		projection = .PERSPECTIVE,
		up         = {0, 1, 0},
		fovy       = 70,
	}

	// Camera reference
	rg.SetCamera(&cam)

	// Flags: they determine what gizmos are active, and in what space: local or view
	// NOTE: scale gizmo supports local space only
	flags: rg.GizmoFlags = {.Translate, .Local}

	for !rl.WindowShouldClose() {

		// Switch gizmos with Q, W, or E keys
		if rl.IsKeyPressed(.Q) {
			flags = {.Translate, .Local}
		}
		if rl.IsKeyPressed(.W) {
			flags = {.Rotate, .Local}
		}
		if rl.IsKeyPressed(.E) {
			flags = {.Scale, .Local}
		}
		// Reset transform with R key
		if rl.IsKeyPressed(.R) {
			cube_transform = rg.GizmoIdentity()
		}

		rl.BeginDrawing()
		{
			rl.ClearBackground(rl.BLACK)

			rl.BeginMode3D(cam)
			{
				// Transform our gizmo to the model's transform
				cube_model.transform = rg.GizmoToMatrix(cube_transform)
				rl.DrawModel(cube_model, {0, 0, 0}, 1, rl.GOLD)
				rl.DrawModelWires(cube_model, {0, 0, 0}, 1, rl.ORANGE)

				// Draw gizmo, update cube_transform
				rg.DrawGizmo3D(flags, &cube_transform)
			}
			rl.EndMode3D()
		}
		rl.EndDrawing()
	}
}
```
