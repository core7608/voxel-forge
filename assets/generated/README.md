# Placeholder assets مولّدين محلياً (بدون أي اعتماديات)

- `blocks_atlas.png` — 64×64 (4×4 خلايا 16px) — ترتيب الخلايا = `atlas_cell` في `BlockMaterial`:
  0 grass, 1 dirt, 2 stone, 3 bedrock, 4 sand, 5 log, 6 leaves, 7 iron_ore, 8 planks,
  9 treated_wood, 10 brick, 11 reinforced, 12 steel_column, 13 foundation, 14 marble (مود), 15 spare.
- `icons.png` — أيقونات الـ Hotbar (نفس الترتيب + apple=16, meat=17).
- `default_skin.png` — اسكن افتراضي 192×128 (3×2 مناطق 64px: رأس/جذع/ذراعR / ذراعL/رجلR/رجلL).

**التوليد**: `python3 tools/gen_assets.py` (stdlib فقط).
**الاستبدال**: حط atlas بأسلوب Kenney مكان `blocks_atlas.png` بنفس ترتيب الخلايا — مش الكود يلمس حاجة.
