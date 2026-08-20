# ⛏️ Voxel Forge — Prototype

**لعبة Voxel للبناء والسيرفايفال بستايل Kenney/KayKit — Godot 4.4**

نسخة ماين كرافت... لكن **المباني لازم تقف صح**: نظام فيزياء إنشائية مبسّط يمنع "البيوت الطايحة في الهوا" ويخلي البناء قرار هندسي ممتع بدل الضغط الأعمى على البلوكات.

```
┌─────────────────────────────────────────────────────────┐
│  خشب: Cantilever حتى 2 بلوك                              │
│  حجر: حتى بلوكة 1   ·   حديد تسليح (Reinforced): حتى 5  │
│  أسفاس (Foundation) + أعمدة فولاذية للأحمال الثقيلة        │
│  بلوكة غير مدعومة = تحذير 12 ثانية = انهيار فيزيائي 💥     │
└─────────────────────────────────────────────────────────┘
```

## ✅ اللي جاهز في الـ Prototype ده

| النظام | الحالة |
|---|---|
| **كل الأصول 3D موديلات Kenney حقيقية مستوردة** (بلوكات/شخصيات/أسلحة/أثاث) — مفيش placeholder | ✅ |
| عالم Voxel إجرائي موسّع 128×128×40 (FastNoiseLite: تضاريس، رمال، خام حديد، أشجار) | ✅ |
| تكسير/وضع بلوكات (Raycast DDA + Grid) — كل بلوك **موديل Kenney حقيقي** مبني على الشبكة 1×1×1 | ✅ |
| 8 بلوكات بناء إضافية (Cobblestone، Rock Pile، Stairs، Walls، Boulder...) من موديلات Kenney الجاهزة | ✅ |
| **الفيزياء الإنشائية**: Support + Span + Load + Grace Period + انهيار حطام | ✅ |
| **Ghost Preview** بألوان (أخضر/أصفر/أحمر) + **Structural Info Mode** (V) | ✅ |
| Inventory + Hotbar + Crafting (خشب→ألواح→مُعالج، حجر→طوب/خرسانة مسلحة/أعمدة، **أسلحة**) | ✅ |
| Creative / Survival (صحة، جوع، ليل/نهار، وحوش ليلية) | ✅ |
| **شخصيات Kenney حقيقية**: لاعب (Mini Characters) + NPC (character-human) + 4 أنواع موبات ليلية (Orc/Raider/Scout/Dungeon Guard) | ✅ |
| **أسلحة Kenney** (Sword/Spear/Shield) — موديل حقيقي في اليد + ضرر مختلف + Crafting | ✅ |
| أثاث Kenney غير-Voxel: وضع حر + دوران + Snap + **Design Mode** (قياس بالمتر، تبديل ألوان، حفظ/تحميل `.tres`) | ✅ |
| NPCs (Karim) بطلبات بناء حقيقية تدفع عملة | ✅ |
| تحديات يومية إجرائية (برج/جسر/عدد بلوكات) | ✅ |
| Skins (PNG بمقاس 192×128 + استيراد مخصص) | ✅ |
| Multiplayer: Listen Server (ENet) + مزامنة بلوكات/أثاث/حالة لاعب + **Dedicated Server** (`--server`) | ✅ |
| Mod Loader (مواد/وصفات/سكريبتات مقيّدة بمفتاح أمان) + Mod مثال (Marble) | ✅ |
| Save/Load (JSON: فقط "الفرق" عن التضاريس المولّدة) | ✅ |
| CI (GitHub Actions) + Smoke Test headless (**31 فحص** شاملة تكامل الأصول) | ✅ |

## ▶️ التشغيل

**المتطلبات**: [Godot 4.4 stable](https://godotengine.org/download) (بدون أي إضافة).

```bash
# 1) افتح المشروع في Godot (File → Import → project.godot) — الاستيراد يتم تلقائياً
# 2) شغّل: F5 (المشهد الرئيسي scenes/main.tscn)
```

**Headless / CI / سيرفر مخصّص:**

```bash
godot --headless --import                          # استيراد الأصول
godot --headless scenes/smoke_test.tscn            # الاختبارات (31 فحص)
godot --headless --server                           # Dedicated Server (منفذ 7000)
```

## 🎮 التحكم

| الزر | الوظيفة |
|---|---|
| WASD + Shift | حركة / جري |
| LMB (مستمر) | تكسير (سرعة حسب المادة في Survival) |
| RMB | وضع بلوك / أثاث |
| MMB | التقاط نوع البلوك |
| 1-9 / عجلة الماوس | اختيار Hotbar |
| F | طيران (Creative) |
| Tab / C | حقيبة / تصنيع |
| **B** | لوحة الأثاث (LMB وضع، R دوران 15°، Ctrl+R ب90°، G Snap) |
| **T** | Design Mode (تحديد LMB، X لون، M قياس بالمتر، Ctrl+K حفظ، Ctrl+L تحميل) |
| **V** | Structural Info (خط الدعم + span/load لكل بلوك) |
| E / Q / Esc | تفاعل مع NPC / أكل / إيقاف مؤقت |

## ️ الفيزياء الإنشائية — الخلاصة

قاعدة كل بلوك:

1. **الدعم**: لازم تتوصل بالأرض (أو بلوك Foundation واقف على الأرض) بسلسلة بلوكات متصلة.
2. **المدى (Span)**: كل مادة لها حد أفقي أقصى: الخشب 2، الحجر 1، Reinforced 5، Foundation/Aعمدة 1 — التراكب العمودي مجاني (ده الـ Pillar).
3. **الحمل (Load)**: وزن البلوكات فوقك في نفس العمود لا يتجاوز `support_value`.

الحالة غير المستقرة: **وميض أحمر + شرخ + صوت + عداد 12 ثانية** — زوّد دعامة قبل ما يخلص الوقت، وإلا الجزء الغير مدعوم **يتفكك لحطام فيزيائي** (RigidBody مؤقت) ويختفي/يسقط موارد جزئية.

**التوازن كله في ملفات** `assets/materials/*.tres` (Span / Weight / Support) — عدّل بدون كود. التفاصيل الكاملة: [docs/structural_system.md](docs/structural_system.md)

## 👥 الأونلاين

- **Host**: القائمة الرئيسية → "Host World" → شارك الـ IP (منفذ 7000).
- **Join**: "Join" + الـ IP.
- السيرفر **Authoritative**: العميل يبعت طلبات، الهوست يطبّق ويبث الفروقات فقط.
- **Dedicated**: نفس المشروع بـ `godot --headless --server` (بدون واجهة).

## 🧩 المودات

مجلد `res://mods/` (أو `user://mods/`) — كل مود مجلد فيه `mod.tres` (Material/Recipe/Script paths). انسخ `mods/example_marble/` وابدأ. سكريبتات المودات **معطّلة افتراضياً** (مفتاح "Trust mod scripts" في القائمة — تحذير أمني واضح). API كامل: [docs/modding_api.md](docs/modding_api.md)

## 🎨 الأصول — كل الموديلات Kenney حقيقية

كل عنصر 3D في اللعبة (بلوكات، شخصيات، أسلحة، أثاث) هو **موديل `.glb` حقيقي مستورد من حزم Kenney** (CC0)، مضمّن في الريبو ومربوط بالكود:

- **بلوكات**: كل `BlockMaterial` فيه `BlockData` بيشاور على `.glb` (في `assets/materials/*.tres`). الموديل بيتحمّل مرة، بيتدمج، ويتسكّل على خلية الشبكة 1×1×1 (`block_model_baker.gd`) وبيتوضع في الـ chunk mesh. البلوكات الإضافية تستخدم `stones`, `rocks`, `stairs`, `wall-half`, `wall-opening`, `floor-detail`, و`rock_largeA` — كلها ملفات Kenney جاهزة، مش موديلات مولّدة بالكود. التوثيق الكامل: [docs/ASSET_CREDITS.md](docs/ASSET_CREDITS.md).
- **الشخصيات**: اللاعب (Mini Characters `character-male-a`)، الـ NPC (`character-human`)، وأربعة موبات ليلية: Orc وRaider وScout وDungeon Guard — كلها موديلات Kenney حقيقية جاهزة من Mini Dungeon وMini Characters.
- **الأسلحة**: Sword/Spear/Shield من Mini Dungeon — بتظهر كموديل حقيقي في يد اللاعب.
- **الأثاث**: 12 قطعة من Furniture Kit + 2 (Barrel/Chest) من Mini Dungeon — كلها `.glb` حقيقية.
- **Kenney Packs المضمّنة**: `Mini Dungeon` + `Nature Kit` + `Furniture Kit` + `Mini Characters` (مقصوصة لموديلات الاستخدام فقط، ~5MB).
- **KayKit** (CC0): **مش مضمّنة** — itch.io بيطلب بريد حتى للنسخة المجانية فمفيش تحميل أوتوماتيكي. اللعبة عمداً بتستخدم موديلات Kenney المتماثلة بصرياً. رابط الحزم وخطوات الإضافة الاختيارية: [assets/kaykit/README.md](assets/kaykit/README.md).
- **Placeholder art** (أيقونات 2D + بديل unit-cube + اسكن افتراضي) مولّد محلياً في `assets/generated/` (`tools/gen_assets.py`) — ده مش موديلات 3D للعبة.

## 📁 بنية المشروع

```
scenes/        → main, player, smoke_test
scripts/
  autoload/    → InputBridge, Blocks, Sfx, Game, World, Crafting, Net, Saves, Mods
  voxel/       → chunk, chunk_mesher, block_model_baker, terrain_generator, voxel_ray, voxel_mover
  systems/     → structural_integrity, furniture_system, character_model, day_night, challenges, skins, inventory
  resources/   → block_data, block_material, craft_recipe, design_blueprint, mod_manifest
  player/ npc/ fx/ ui/ test/
assets/
  materials/   → .tres لكل مادة (التوازن + BlockData→موديل Kenney)
  recipes/     → .tres للوصفات (بلوكات + أسلحة)
  kenney/      → mini-dungeon, nature-kit, furniture-kit, mini-characters (موديلات .glb حقيقية)
  kaykit/ generated/
mods/          → example_marble (قالب)
docs/ tools/ .github/
```

الأجزاء أداء-حرجة معلّمة بـ **`[C#-CANDIDATE]`** في الكود (الفيزياء الإنشائية + الـ Meshing) — مستعدة للنقل لـ C# (Godot.NET) بنفس الواجهة.

## 🚀 CI / GitHub

- `.github/workflows/ci.yml`: على كل Push/PR → استيراد + **smoke test headless** (صورة `godot-ci/godot:4.4`).
- الريبو نظيف من `.godot/` (`.gitignore`).
- التوزيع لاحقاً: GitHub Releases بملفات Export (Windows/Mac/Linux).

## 🗺️ خارطة الطريق (Backlog من البرومبت)

Photo Mode · تسريب مياه · حريق حسب المادة · عزل حراري · مواسم · Server Browser + Land Claim · Copy-Paste تصميم · إضاءة Sun Path · Achievements · Tutorial تفاعلي · موبايل (Input Actions جاهز — بس نضيف Virtual Joystick) · Console (خارج النطاق — ترخيص).

## 📜 الترخيص

الكود: **MIT** (عدّل حسب رغبتك — مثال: ترخيص "Credit required"). الأصول: CC0 (Kenney + KayKit) — التكريم في `assets/*/README.md`.
