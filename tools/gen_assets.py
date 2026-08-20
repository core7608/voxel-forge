#!/usr/bin/env python3
"""Generates the placeholder art assets for Voxel Forge (run from the repo root):

  assets/generated/blocks_atlas.png  — 64x64, 4x4 cells of 16px (matches BlockMaterial.atlas_cell)
  assets/generated/icons.png         — 64x96, 4 columns x 6 rows of 16px icons
  assets/generated/default_skin.png  — 192x128, 3x2 grid of 64px skin regions

These keep the game fully playable before (or without) downloading the
Kenney/KayKit packs. Replace blocks_atlas.png with a proper Kenney-style
atlas whenever you like — the cell order is stable (see MATERIALS below).

Pure stdlib (zlib + struct), no PIL needed.
"""
import os
import random
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "generated")

# id -> (name, base rgb) — order MUST match assets/materials/*.tres atlas_cell
MATERIALS = [
    ("grass", (107, 158, 84)),
    ("dirt", (133, 97, 64)),
    ("stone", (140, 140, 148)),
    ("bedrock", (62, 62, 69)),
    ("sand", (217, 199, 140)),
    ("log", (115, 82, 46)),
    ("leaves", (77, 133, 64)),
    ("iron_ore", (140, 140, 148)),
    ("planks", (184, 140, 87)),
    ("treated_wood", (140, 107, 67)),
    ("brick", (158, 84, 71)),
    ("reinforced", (158, 158, 166)),
    ("steel_column", (115, 133, 158)),
    ("foundation", (89, 92, 102)),
    ("marble", (230, 230, 237)),
    ("spare", (40, 40, 46)),
]


def write_png(path, w, h, px):
    """px: list of rows of (r,g,b,a)."""
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    raw = b"".join(
        b"\x00" + b"".join(struct.pack("4B", *p) for p in row) for row in px
    )
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)
    print("wrote", os.path.relpath(path, ROOT))


def jitter(c, rnd, amt=14):
    return tuple(max(0, min(255, v + rnd.randint(-amt, amt))) for v in c)


def cell_noise(base, rnd, amt=14):
    """16x16 speckled tile."""
    rows = []
    for y in range(16):
        row = []
        for x in range(16):
            row.append((*jitter(base, rnd, amt), 255))
        rows.append(row)
    return rows


def cell_planks(base, rnd, horizontal=True):
    rows = []
    for y in range(16):
        row = []
        for x in range(16):
            c = jitter(base, rnd, 8)
            if horizontal and y % 8 == 7:
                c = (max(0, c[0] - 60), max(0, c[1] - 45), max(0, c[2] - 30))
            if not horizontal and x % 8 == 7:
                c = (max(0, c[0] - 60), max(0, c[1] - 45), max(0, c[2] - 30))
            row.append((*c, 255))
        rows.append(row)
    return rows


def cell_brick(base, rnd):
    rows = []
    for y in range(16):
        row = []
        for x in range(16):
            c = jitter(base, rnd, 6)
            mortar = (y % 8 == 7) or ((x + (4 if (y // 8) % 2 else 12)) % 8 == 7 and y % 8 != 7)
            if mortar:
                c = (200, 195, 185)
            row.append((*c, 255))
        rows.append(row)
    return rows


def cell_rebar(base, rnd):
    rows = []
    for y in range(16):
        row = []
        for x in range(16):
            c = jitter(base, rnd, 10)
            if x % 8 == 0 or y % 8 == 0:
                c = (70, 75, 85)
            if (x % 8 == 4) and (y % 8 == 4):
                c = (90, 95, 105)
            row.append((*c, 255))
        rows.append(row)
    return rows


def cell_log(base, rnd):
    rows = []
    for y in range(16):
        row = []
        for x in range(16):
            c = jitter(base, rnd, 8)
            if x in (2, 9):
                c = (max(0, c[0] - 45), max(0, c[1] - 32), max(0, c[2] - 20))
            row.append((*c, 255))
        rows.append(row)
    return rows


def cell_ore(base, rnd):
    rows = cell_noise(base, rnd, 8)
    for (x, y) in [(2, 3), (9, 2), (12, 8), (5, 10), (11, 13), (3, 14)]:
        rows[y][x] = (216, 150, 88, 255)
        rows[y][x + 1] = (198, 128, 70, 255)
    return rows


def cell_steel(base, rnd):
    rows = []
    for y in range(16):
        row = []
        for x in range(16):
            c = jitter(base, rnd, 6)
            d = abs(x - 7.5) + abs(y - 7.5)
            if d < 2.2:
                c = (210, 215, 225)
            elif (x == 7 or x == 8) or (y == 7 or y == 8):
                c = (80, 92, 110)
            row.append((*c, 255))
        rows.append(row)
    return rows


def cell_foundation(base, rnd):
    rows = cell_noise(base, rnd, 8)
    for y in range(16):
        for x in range(16):
            if x in (0, 15) or y in (0, 15):
                rows[y][x] = (52, 54, 62, 255)
    return rows


def cell_marble(base, rnd):
    rows = cell_noise(base, rnd, 4)
    for y in range(16):
        for x in range(16):
            if (x + y * 3) % 11 == 0:
                rows[y][x] = (190, 195, 210, 255)
    return rows


def build_cell(i, rnd):
    name, base = MATERIALS[i]
    if name == "grass":
        rows = cell_noise(base, rnd, 16)
        for y in range(3):
            for x in range(16):
                rows[y][x] = (*jitter((90, 160, 70), rnd, 12), 255)
        return rows
    if name in ("dirt", "bedrock", "sand"):
        return cell_noise(base, rnd, 12 if name != "bedrock" else 6)
    if name == "stone":
        return cell_noise(base, rnd, 10)
    if name == "log":
        return cell_log(base, rnd)
    if name == "leaves":
        rows = cell_noise(base, rnd, 18)
        for y in range(16):
            for x in range(16):
                if (x * 7 + y * 13) % 23 == 0:
                    rows[y][x] = (38, 84, 34, 255)
        return rows
    if name == "iron_ore":
        return cell_ore(base, rnd)
    if name == "planks":
        return cell_planks(base, rnd)
    if name == "treated_wood":
        return cell_planks(base, rnd)
    if name == "brick":
        return cell_brick(base, rnd)
    if name == "reinforced":
        return cell_rebar(base, rnd)
    if name == "steel_column":
        return cell_steel(base, rnd)
    if name == "foundation":
        return cell_foundation(base, rnd)
    if name == "marble":
        return cell_marble(base, rnd)
    return cell_noise(base, rnd, 10)


def gen_atlas():
    rnd = random.Random(7)
    W, H, C = 64, 64, 16
    px = [[(30, 30, 34, 255)] * W for _ in range(H)]
    for i in range(C):
        cell = build_cell(i, rnd)
        cx, cy = (i % 4) * 16, (i // 4) * 16
        for y in range(16):
            for x in range(16):
                px[cy + y][cx + x] = cell[y][x]
    write_png(os.path.join(OUT, "blocks_atlas.png"), W, H, px)


def gen_icons():
    rnd = random.Random(11)
    W, H, COLS = 64, 96, 4
    px = [[(30, 30, 34, 255)] * W for _ in range(H)]
    for i in range(16):  # block icons (same cells as atlas)
        cell = build_cell(i, rnd)
        cx, cy = (i % COLS) * 16, (i // COLS) * 16
        for y in range(16):
            for x in range(16):
                px[cy + y][cx + x] = cell[y][x]
    # apple (cell 16)
    cell = [[(30, 30, 34, 255)] * 16 for _ in range(16)]
    for y in range(16):
        for x in range(16):
            dx, dy = x - 7.5, y - 9.0
            if dx * dx + dy * dy * 1.2 < 30:
                cell[y][x] = (214, 52, 44, 255)
            if dx * dx + dy * dy * 1.2 < 22:
                cell[y][x] = (232, 70, 58, 255)
    cell[4][8] = (120, 80, 40, 255)
    cell[3][8] = (120, 80, 40, 255)
    cell[2][9] = (80, 140, 60, 255)
    # meat (cell 17)
    cell2 = [[(30, 30, 34, 255)] * 16 for _ in range(16)]
    for y in range(16):
        for x in range(16):
            dx, dy = x - 8, y - 8
            if dx * dx / 42 + dy * dy / 28 < 1:
                cell2[y][x] = (186, 96, 70, 255)
            if abs(dx) < 2 and abs(dy) < 2:
                cell2[y][x] = (235, 230, 225, 255)
    for (cell, i) in [(cell, 16), (cell2, 17)]:
        cx, cy = (i % COLS) * 16, (i // COLS) * 16
        for y in range(16):
            for x in range(16):
                px[cy + y][cx + x] = cell[y][x]
    write_png(os.path.join(OUT, "icons.png"), W, H, px)


def fill_region(px, x0, y0, w, h, base, rnd, amt=10):
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            px[y][x] = (*jitter(base, rnd, amt), 255)


def gen_skin():
    rnd = random.Random(23)
    W, H, S = 192, 128, 64
    px = [[(20, 20, 24, 255)] * W for _ in range(H)]
    SKIN, SHIRT, PANTS, HAIR = (222, 178, 140), (72, 122, 178), (90, 80, 120), (96, 66, 44)
    # head (0): skin + hair top + eyes
    fill_region(px, 0, 0, S, S, SKIN, rnd, 8)
    for y in range(0, 20):
        for x in range(0, S):
            px[y][x] = (*jitter(HAIR, rnd, 10), 255)
    for (ex, ey) in [(20, 30), (44, 30)]:
        for y in range(ey, ey + 6):
            for x in range(ex, ex + 6):
                px[y][x] = (40, 40, 48, 255)
    # torso (1): shirt
    fill_region(px, S, 0, S, S, SHIRT, rnd, 10)
    for x in range(S, 2 * S):
        px[50][x] = (40, 45, 60, 255)
    # armR (2): sleeve top + skin bottom
    fill_region(px, 2 * S, 0, S, 26, SHIRT, rnd, 10)
    fill_region(px, 2 * S, 26, S, S - 26, SKIN, rnd, 8)
    # armL (3)
    fill_region(px, 0, S, S, 26, SHIRT, rnd, 10)
    fill_region(px, 0, S + 26, S, S - 26, SKIN, rnd, 8)
    # legR (4): pants
    fill_region(px, S, S, S, S, PANTS, rnd, 10)
    # legL (5): pants
    fill_region(px, 2 * S, S, S, S, PANTS, rnd, 10)
    write_png(os.path.join(OUT, "default_skin.png"), W, H, px)


def main():
    os.makedirs(OUT, exist_ok=True)
    gen_atlas()
    gen_icons()
    gen_skin()
    print("done.")


if __name__ == "__main__":
    main()
