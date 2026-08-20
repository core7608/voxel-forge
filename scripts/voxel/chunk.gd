class_name VoxelChunk
extends Node3D
## A 16x32x16 column chunk. Blocks live in a flat byte array (4096*2 cells).

const SX := 16
const SY := 32
const SZ := 16

var cx := 0
var cz := 0
var blocks: PackedByteArray
var mesh_instance: MeshInstance3D

func _init(p_cx: int, p_cz: int) -> void:
	cx = p_cx
	cz = p_cz
	blocks = PackedByteArray()
	blocks.resize(SX * SY * SZ)
	mesh_instance = MeshInstance3D.new()
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mesh_instance)

func idx(lx: int, ly: int, lz: int) -> int:
	return (lx * SZ + lz) * SY + ly

func get_local(lx: int, ly: int, lz: int) -> int:
	return blocks[idx(lx, ly, lz)]

func set_local(lx: int, ly: int, lz: int, m: int) -> void:
	blocks[idx(lx, ly, lz)] = m
