# Kenney Assets (CC0)

الحزم المضمّنة في هذا الريبو (مجانية — Creative Commons CC0، من [kenney.nl](https://kenney.nl) — Kenney):

| الحزمة | المجلد | الاستخدام في اللعبة |
|---|---|---|
| **Furniture Kit 1.0** | `furniture-kit/` | كل الأثاث في Design Mode (الكتالوج `FurnitureCatalog` بياخد `.glb` من `Models/GLTF format/` بالاسم: chair, loungeChair, loungeSofa, tableCoffee, table, desk, bedSingle, bookcaseOpen, cabinetBed, lampSquareFloor, rugSquare, pottedPlant) |
| **Nature Kit 1.0** | `nature-kit/` | محتوى جاهز للتوسع: جسور (bridge_*), مخيمات (campfire_*), صخور/جروف (cliff_*) — يمكن إضافتها كأثاث/ديكور لاحقاً |

**ملاحظة استيراد**: Godot 4 يستورد `.glb` تلقائياً عند فتح المشروع (أول مرة يستغرق شوية — ~140 نموذج).

**التكريم** (غير ملزم قانونياً بـ CC0): Kenney (kenney.nl) — "Furniture Kit", "Nature Kit".

## إضافة حزمة Kenney جديدة

1. حمّلها من kenney.nl.
2. ضع المجلد هنا: `assets/kenney/<name-kit>/`.
3. أضف أسماء `.glb` في كتالوج `scripts/systems/furniture_catalog.gd` (ITEMS).
4. شغّل Godot مرة — الاستيراد تلقائي.
