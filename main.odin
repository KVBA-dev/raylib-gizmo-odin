package main

import "core:fmt"
import st "core:strings"
import rg "raygizmo"
import rl "vendor:raylib"

main :: proc() {
	rl.InitWindow(1280, 1024, "raygizmo-test")
	defer rl.CloseWindow()

	cube_transform := rg.GizmoIdentity()

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

	b := st.Builder{}
	st.builder_init(&b)
	defer st.builder_destroy(&b)

	for !rl.WindowShouldClose() {

		st.builder_reset(&b)
		fmt.sbprint(&b, rg.GIZMO)
		gizmo_cstr := st.clone_to_cstring(st.to_string(b))
		defer delete(gizmo_cstr)
		rl.BeginDrawing()
		{
			rl.ClearBackground(rl.BLACK)

			rl.BeginMode3D(cam)
			{
				cube_model.transform = rg.GizmoToMatrix(cube_transform)
				rl.DrawModel(cube_model, {0, 0, 0}, 1, rl.GOLD)

				rg.DrawGizmo3D({.Translate, .Rotate, .Scale}, &cube_transform)
				rl.DrawRay(rl.GetScreenToWorldRay(rl.GetMousePosition(), cam), rl.GREEN)
			}
			rl.EndMode3D()
			rl.DrawText(gizmo_cstr, 10, 10, 10, rl.WHITE)
		}
		rl.EndDrawing()
	}
}
