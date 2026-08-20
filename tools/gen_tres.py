#!/usr/bin/env python3
"""Regenerates all material .tres files (with embedded BlockData model
bindings) + recipe .tres files in the explicit-script format. Run from the
repo root. Every block material points at a REAL imported Kenney model."""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MD = "res://assets/kenney/mini-dungeon/models/"
NK = "res://assets/kenney/nature-kit/Models/GLTF format/"


def write(path, content):
    full = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w") as f:
        f.write(content)
    print("wrote", os.path.relpath(full, ROOT))


# (id, name, model_relpath, tint(r,g,b) or None)
BLOCKS = [
    (1,  "Grass",          NK + "ground_grass.glb",   None),
    (2,  "Dirt",           MD + "dirt.glb",           None),
    (3,  "Stone",          NK + "cliff_block_stone.glb", None),
    (4,  "Bedrock",        NK + "cliff_block_rock.glb", None),
    (5,  "Sand",           NK + "platform_beach.glb", None),
    (6,  "Log",            MD + "wood-structure.glb", None),
    (7,  "Leaves",         NK + "tree_blocks.glb",    None),
    (8,  "Iron Ore",       NK + "rock_smallA.glb",    (0.85, 0.80, 0.75)),
    (9,  "Planks",         MD + "wood-support.glb",   None),
    (10, "Treated Wood",   MD + "wood-structure.glb", (0.72, 0.55, 0.38)),
    (11, "Brick",          MD + "wall.glb",           None),
    (12, "Reinforced",     MD + "wall-narrow.glb",    (0.78, 0.84, 0.92)),
    (13, "Steel Column",   MD + "column.glb",         None),
    (14, "Foundation",     MD + "floor.glb",          None),
]

# physical/structural defaults per id: (weight, support, span, break_time, drop, drop_chance, is_terrain, unbreakable, foundation)
PHYS = {
    1: (1.0, 80.0, 1, 0.7, 2, 1.0, True, False, False),
    2: (1.0, 60.0, 1, 0.5, -2, 1.0, True, False, False),
    3: (2.0, 100.0, 1, 1.2, -2, 1.0, True, False, False),
    4: (999.0, 99999.0, 0, 0.0, -2, 1.0, True, True, False),
    5: (0.8, 40.0, 0, 0.4, -2, 1.0, True, False, False),
    6: (1.0, 50.0, 2, 0.9, -2, 1.0, False, False, False),
    7: (0.3, 20.0, 0, 0.3, 101, 0.35, False, False, False),
    8: (2.0, 80.0, 1, 2.0, -2, 1.0, False, False, False),
    9: (0.8, 40.0, 2, 0.8, -2, 1.0, False, False, False),
    10: (1.0, 70.0, 3, 1.1, -2, 1.0, False, False, False),
    11: (1.5, 90.0, 1, 1.4, -2, 1.0, False, False, False),
    12: (2.5, 160.0, 5, 2.2, -2, 1.0, False, False, False),
    13: (2.0, 400.0, 1, 2.0, -2, 1.0, False, False, False),
    14: (3.0, 500.0, 1, 1.5, -2, 1.0, False, False, True),
}

# base albedo colours (used for the icon + cube fallback)
COLORS = {
    1: (0.42, 0.62, 0.33), 2: (0.52, 0.38, 0.25), 3: (0.55, 0.55, 0.58),
    4: (0.24, 0.24, 0.27), 5: (0.85, 0.78, 0.55), 6: (0.45, 0.32, 0.18),
    7: (0.30, 0.52, 0.25), 8: (0.55, 0.55, 0.58), 9: (0.72, 0.55, 0.34),
    10: (0.55, 0.42, 0.26), 11: (0.62, 0.33, 0.28), 12: (0.62, 0.62, 0.65),
    13: (0.45, 0.52, 0.62), 14: (0.35, 0.36, 0.40),
}


def material_tres(i, name, model, tint):
    w, sup, span, bt, drop, dc, terr, unb, fnd = PHYS[i]
    r, g, b = COLORS[i]
    tint_line = "tint = Color(%.2f, %.2f, %.2f, 1)" % tint if tint else "tint = Color(1, 1, 1, 1)"
    lines = []
    lines.append('[gd_resource type="Resource" script_class="BlockMaterial" format=3]')
    lines.append("")
    lines.append('[ext_resource type="Script" path="res://scripts/resources/block_material.gd" id="1_s"]')
    lines.append('[ext_resource type="Script" path="res://scripts/resources/block_data.gd" id="2_s"]')
    lines.append("")
    lines.append('[sub_resource type="Resource" id="Resource_bd"]')
    lines.append('script = ExtResource("2_s")')
    lines.append('display_name = "%s"' % name)
    lines.append('model_path = "%s"' % model)
    lines.append('fit_to_grid = true')
    lines.append("inset = 0.98")
    lines.append(tint_line)
    lines.append("")
    lines.append("[resource]")
    lines.append('script = ExtResource("1_s")')
    lines.append("id = %d" % i)
    lines.append("atlas_cell = %d" % (i - 1))
    lines.append('name = "%s"' % name)
    lines.append("color = Color(%.2f, %.2f, %.2f, 1)" % (r, g, b))
    lines.append("weight = %.1f" % w)
    lines.append("support_value = %.1f" % sup)
    lines.append("max_span = %d" % span)
    lines.append("break_time = %.1f" % bt)
    if drop != -2:
        lines.append("drop = %d" % drop)
    if dc != 1.0:
        lines.append("drop_chance = %.2f" % dc)
    if terr:
        lines.append("is_terrain = true")
    if unb:
        lines.append("unbreakable = true")
    if fnd:
        lines.append("foundation = true")
    lines.append('block_data = SubResource("Resource_bd")')
    lines.append("")
    write("assets/materials/%02d_%s.tres" % (i, name.lower().replace(" ", "_")), "\n".join(lines))


def recipe_tres(path, i, name, inputs, output, count):
    inps = ",\n".join("%d: %d" % (k, v) for k, v in sorted(inputs.items()))
    content = '\n'.join([
        '[gd_resource type="Resource" script_class="CraftRecipe" format=3]',
        "",
        '[ext_resource type="Script" path="res://scripts/resources/craft_recipe.gd" id="1_s"]',
        "",
        "[resource]",
        'script = ExtResource("1_s")',
        'name = "%s"' % name,
        "inputs = {\n%s\n}" % inps,
        "output = %d" % output,
        "output_count = %d" % count,
        "",
    ])
    write("assets/recipes/%02d_%s.tres" % (i, path), content)


def main():
    for (i, name, model, tint) in BLOCKS:
        material_tres(i, name, model, tint)

    recipe_tres("planks", 1, "Planks", {6: 1}, 9, 4)
    recipe_tres("treated_wood", 2, "Treated Wood", {9: 2}, 10, 2)
    recipe_tres("brick", 3, "Brick", {3: 1}, 11, 2)
    recipe_tres("reinforced", 4, "Reinforced (rebar + stone)", {3: 2, 8: 1}, 12, 1)
    recipe_tres("steel_column", 5, "Steel Column", {8: 2}, 13, 1)
    recipe_tres("foundation", 6, "Foundation", {3: 4}, 14, 1)
    # weapons (real Kenney Mini Dungeon models)
    recipe_tres("sword", 7, "Sword", {9: 2, 8: 1}, 201, 1)
    recipe_tres("spear", 8, "Spear", {6: 2, 9: 1}, 202, 1)
    recipe_tres("shield", 9, "Shield", {9: 3}, 203, 1)

    # example mod marble (id 15)
    w, sup, span, bt = 2.0, 120.0, 3, 1.6
    content = "\n".join([
        '[gd_resource type="Resource" script_class="BlockMaterial" format=3]',
        "",
        '[ext_resource type="Script" path="res://scripts/resources/block_material.gd" id="1_s"]',
        '[ext_resource type="Script" path="res://scripts/resources/block_data.gd" id="2_s"]',
        "",
        '[sub_resource type="Resource" id="Resource_bd"]',
        'script = ExtResource("2_s")',
        'display_name = "Marble"',
        'model_path = "%scliff_block_stone.glb"' % NK,
        "fit_to_grid = true",
        "inset = 0.98",
        "tint = Color(0.92, 0.92, 0.95, 1)",
        "",
        "[resource]",
        'script = ExtResource("1_s")',
        "id = 15",
        "atlas_cell = 14",
        'name = "Marble"',
        "color = Color(0.9, 0.9, 0.93, 1)",
        "weight = %.1f" % w,
        "support_value = %.1f" % sup,
        "max_span = %d" % span,
        "break_time = %.1f" % bt,
        'block_data = SubResource("Resource_bd")',
        "",
    ])
    write("mods/example_marble/materials/marble.tres", content)
    print("done.")


if __name__ == "__main__":
    main()
