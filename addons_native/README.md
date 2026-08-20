# addons_native — خطة C# (Godot.NET)

مجلد **تخطيطي** للمرحلة التالية. في الـ Prototype الحالي كل المنطق في GDScript
(حسب البرومبت: "يُقبل تأجيل C# والبدء بـ GDScript بالكامل مع علامة واضحة
على الأجزاء المرشحة للتحويل لاحقاً").

## المرشّحات للتحويل (معلّمة `[C#-CANDIDATE]` في الكود)

| الملف الحالي | السبب | الواجهة المقترحة |
|---|---|---|
| `scripts/systems/structural_integrity.gd` | Flood-fill/Graph على عالم كبير يتكرر مع كل بلوك | Node `StructuralIntegrityNative` بنفس الـ methods/signals (`recompute_full`, `preview`, `state_at`, `instability_changed`, `collapsed`) |
| `scripts/voxel/chunk_mesher.gd` | توليد ArrayMesh (Greedy Meshing + multithread) | Node `ChunkMesherNative.build(world, chunk) -> ArrayMesh` |
| `scripts/voxel/terrain_generator.gd` | تعبئة خلايا بالجملة (fast noise + hash) | `TerrainGeneratorNative.fill(world, seed)` |

## قواعد الانتقال

1. الـ C# Nodes تتواصل مع GDScript **عبر Node API عادي** (method calls + signals) — زي أي Node.
2. الـ API لازم يفضل مطابق (نفس الأسماء/الأنواع) عشان كود الـ Gameplay ما يلمس حاجة.
3. الاختبار: `scenes/smoke_test.tscn` لازم تعدي على الـ Native build (نفس الـ 23 فحص).
4. تفعيل C# في Godot: Project Settings → .NET → Enable .NET، ثم `dotnet build`
   مع `Godot.NET.Sdk` (4.4) في ملف `.csproj` هنا.
