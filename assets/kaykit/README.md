# KayKit Assets (CC0)

الحزم المقترحة (مجانية — CC0، من [kaylousberg.com](https://kaylousberg.com)):

| الحزمة | الرابط | الاستخدام المقترح |
|---|---|---|
| **KayKit — Adventurers** | https://kaylousberg.itch.io/kaykit-adventurers | NPCs (الـ Villager الحالي بديل primitives بالستايل نفسه) |
| **KayKit — Dungeon Remastered** | https://kaylousberg.itch.io/kaykit-dungeon-remastered | وحوش ليلية (الـ Monster الحالي primitives) + كهوف |
| **KayKit — Character Animations** | https://kaylousberg.itch.io/kaykit-character-animations | أنيميشن للموديلات (اختياري) |

## ليه مش مضمّنة هنا؟

تحميلات itch.io بتطلب بريد إلكتروني حتى في النسخ المجانية — فمفيش طريقة تحميل نظيفة أوتوماتيكية. **خطواتك (دقيقة واحدة):**

1. افتح أي صفحة في الجدول ← "Download now" ← Free (اكتب بريدك).
2. فكّ الضغط واحط المجلدات هنا: `assets/kaykit/<pack-name>/`.
3. شغّل Godot مرة (استيراد `.glb` تلقائي).

## دمجها في الكود (Next Step صغير)

- NPCs: في `scripts/npc/villager.gd` و`monster.gd` — استبدل `_build_body()` بـ
  `load("res://assets/kaykit/.../x.glb")` (نفس نمط اكتشاف Kenney في `FurnitureCatalog`).
- اللاعب: نظام الـ Skins (PNG 192×128) بيتعمد إنه مستقل عن الموديل عشان يخدم كمان الـ primitives.

**التكريم** (غير ملزم): Kay Lousberg (kaylousberg.com / kaylousberg.itch.io).
