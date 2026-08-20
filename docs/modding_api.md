# Modding API — التوثيق

مبدأ: **بسيط وقابل للتنفيذ من مطور واحد** (مش Forge).

## هيكل المود

```
mods/my_mod/
├── mod.tres              ← ModManifest (الوصف)
├── materials/*.tres      ← BlockMaterial (بلوكات جديدة)
├── recipes/*.tres        ← CraftRecipe (وصفات جديدة)
└── scripts/*.gd          ← Hooks اختيارية (تحتاج Trust مفعّل)
```

`mod.tres`:

```
[gd_resource type="Resource" script_class="ModManifest" format=3]
[ext_resource type="Script" path="res://scripts/resources/mod_manifest.gd" id="1_s"]
[resource]
script = ExtResource("1_s")
name = "My Mod"
version = "1.0"
materials = PackedStringArray("materials/myblock.tres")
recipes   = PackedStringArray("recipes/myrecipe.tres")
scripts   = PackedStringArray("scripts/hook.gd")
```

## إضافة بلوك

أنشئ `BlockMaterial` بـ `id` فريد (المواد الأساسية: 1-22, مود Marble المثال: 30 — خد رقم جديد):

```
id = 40
name = "Obsidian"
color = Color(0.15, 0.1, 0.2)
weight = 3.0
support_value = 200.0
max_span = 2
break_time = 3.0
drop = -2            # -2 = نفسه
```

البلوك الجديد بيظهر فوراً في Hotbar الـ Creative وفي كل الأنظمة (الإنشائية/الحفظ/النت).

## إضافة وصفة

```
name = "Obsidian Brick"
inputs = { 40: 2, 3: 1 }
output = 41
output_count = 1
```

## Hooks (سكريبتات — مفتاح أمان مطلوب)

السكريبتات بتتحمّل بعد الـ autoloads وبتقدر تتوصّل لأي إشارة عامة:

```gdscript
extends Node
func _ready() -> void:
    Game.block_placed.connect(_on_placed)   # (pos, mat, peer)
    # Game.block_broken, Game.mode_changed, Game.coins_changed,
    # Game.toast_requested, Structural: instability_changed / collapsed
func _on_placed(pos, mat, peer):
    pass
```

**تحذير أمني**: سكريبت مود = كود بيتنفذ بامتيازات اللعبة بالكامل. مفاتيح التفعيل في القائمة الرئيسية مع توضيح المخاطر (نفس فلسفة مودات ماين كرافت الكلاسيكية — التوزيع اليدوي/الـ GitHub Repos).

## توزيع المودات

بدون متجر: GitHub Releases / Repos منفصلة / مجلد `community-mods` يستقبل PRs (انظر README).
