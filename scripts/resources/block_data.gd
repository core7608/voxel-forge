class_name BlockData
extends Resource
## BlockData — the visual model binding for a block material.
##
## Points a block type at a REAL imported Kenney/KayKit .glb model instead of a
## procedurally-generated primitive cube. The model is "baked" once (loaded,
## merged, scaled so its footprint fills the 1x1x1 grid cell, bottom at y=0)
## and then instanced into the chunk mesh — see scripts/voxel/block_model_baker.gd.
##
## If model_path is empty (or the file is missing), the renderer falls back to
## the classic textured unit-cube so the world never breaks.

@export var display_name: String = ""
## Path to a .glb/.gltf/.tscn model (res:// or user://).
@export_file("*.glb", "*.gltf", "*.tscn") var model_path: String = ""
## Scale the model uniformly so its largest horizontal dimension fills 1.0
## (the grid cell footprint). Vertical keeps the model's natural proportions.
@export var fit_to_grid: bool = true
## Slightly shrink the block so adjacent blocks don't share a coplanar face
## (avoids z-fighting at seams). 1.0 = exact fill, 0.98 = visible seams.
@export_range(0.5, 1.0) var inset: float = 0.98
## Optional albedo tint applied on top of the model's own texture.
@export var tint: Color = Color.WHITE
## Extra rotation applied to the model (radians, Y axis only).
@export var rotation_y: float = 0.0
## If true, a missing/invalid model silently falls back to a unit cube.
@export var fallback_to_cube: bool = true

func has_model() -> bool:
	return model_path != "" and ResourceLoader.exists(model_path)
