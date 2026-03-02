# DEVELOPMENT.md
## FS25_SeasonalCropStress — Release Checklist

> Phases 1–4 are code-complete. This file tracks everything that must be **verified in-game** or **created** before v1.0 ships.
>
> `[ ]` = not done · `[x]` = done · `[s]` = skipped (optional mod not installed in dev env)

---

## BLOCKER — In-Game Verification

Everything below must pass before tagging v1.0. Run these in order on a clean save.

### Core Systems

- [ ] Mod loads with **zero errors** in log.txt on a clean game start
- [ ] New game: all fields initialized at plausible moisture (spring ~60%, summer ~40%), no log errors
- [ ] Play 1 in-game hour → moisture values change, no log errors
- [ ] `csSetMoisture <fieldId> <value>` forces a field to the correct moisture
- [ ] `csForceStress <fieldId>` → harvest that field → yield is visibly reduced (not 100%)
- [ ] Field with **no stress** harvests at 100% yield (stress system doesn't penalize clean fields)
- [ ] Save game → reload → all moisture and stress values match exactly
- [ ] Fresh game with **no save data** loads cleanly (no nil errors from SaveLoadHandler)

> **PRIORITY:** Confirm `env.currentDayInPeriod` is a valid FS25 API. If nil, irrigation scheduling silently never fires (always defaults to day 1). Check `csStatus` log output for current day.

### HUD

- [ ] `Shift+M` toggles the moisture HUD panel on and off
- [ ] HUD auto-shows when player enters a field in a critical growth window with moisture < 50%
- [ ] HUD shows "No critical fields" empty-state message when all fields are healthy
- [ ] 5-day forecast shows 5 distinct values (0.0–1.0 range), updates when selected field changes
- [ ] Drag HUD to new position → save game → reload → panel appears at saved position

### Irrigation

- [ ] Place water pump → place center pivot within 500m → pivot activates (registers water source, shows as active in `csStatus`)
- [ ] `E` near center pivot (within 8m) → Irrigation Schedule dialog opens cleanly, all elements visible, no layout overflow
- [ ] Change schedule (days + hours) → Save Schedule → reload game → schedule persists
- [ ] Run irrigation overnight → farm balance decreases by expected hourly cost
- [ ] Active irrigation system + custom schedule → save → reload → still active with correct schedule
- [ ] Pressure curve: pivot at 250m from pump gets ~85% rated flow; pivot at 600m gets 0% (check `csStatus` for effective rate)
- [ ] Place drip line across a field → moisture rises in the covered area each hourly tick

> **PRIORITY:** Test drip line at 90° rotation — verify coverage zone matches the rotated visual direction (ry sign in `dripLine.lua` may need flipping if coverage box appears perpendicular to the line).

### Crop Consultant / Alerts

- [ ] Set a field to 15% moisture → `CS_CRITICAL_THRESHOLD` warning appears within 1 in-game hour
- [ ] Warning does **not** repeat on the same field for 12 in-game hours (cooldown works)

### Settings & Multiplayer

- [ ] ESC → Settings → Game Settings → "Seasonal Crop Stress" section: all 10 controls appear and respond correctly
- [ ] Toggle mod **off** → save → reload → mod stays disabled (boolean trap regression: `false or default` must not revert to `true`)
- [ ] Join MP server as client → client receives host's settings, not defaults (`CropStressSettingsSyncEvent` bulk sync)

---

## OPTIONAL MOD TESTS

Run these only if the corresponding mod is available. Failures here are **not v1.0 blockers** — all integrations are gated behind runtime nil checks.

### NPCFavor

- [s] With NPCFavor loaded: Alex Chen NPC appears in world, relationship starts at 10
- [s] With NPCFavor loaded: `EMERGENCY_WATER` favor task fires when a field drops below 15% in a critical growth window
- [ ] **Without** NPCFavor: mod loads cleanly, zero nil-access errors in log

### UsedPlus

- [s] With UsedPlus loaded: irrigation costs appear in UsedPlus finance manager under "OPERATIONAL" category
- [s] With UsedPlus loaded: worn pump (DNA reliability 0.6) delivers ~76% of rated flow (wear degrades output)
- [ ] **Without** UsedPlus: vanilla `updateFunds` still deducts irrigation costs each hour
- [s] With UsedPlus loaded: pre-owned center pivot appears in used equipment marketplace at a discount

### Precision Farming DLC

- [s] With PF DLC: moisture overlay layer visible on PF soil analysis map view
- [s] With PF DLC: soil type data from PF matches what SoilMoistureSystem uses per field

### Localization

- [ ] Switch game language to **German (DE)** → all mod UI text is German, no `?cs_*?` fallback strings visible
- [ ] Switch game language to **Polish (PL)** → all mod UI text is Polish, no fallback strings

---

## PHASE 6 — Final Assets

Code is complete. These are art and packaging tasks.

### 3D Assets

- [ ] Commission or create final **center pivot** `.i3d` — arm rotation animation, proper LOD nodes, textured
- [ ] Commission or create final **water pump** `.i3d` — textured static model
- [ ] Update `centerPivot.xml` and `waterPump.xml` `<image>` paths to use final art (currently using `$data/` placeholder DDS files)

### Mod Icon

- [ ] Create `icon.dds` — mod browser icon (512×512 or 256×256, DXT1)
  - Currently using placeholder; verify it displays correctly in mod browser before publishing

---

## PHASE 6 — Release Packaging

- [ ] Write **v1.0.0.0 changelog** (feature list, known limitations, optional mod compatibility notes)
- [ ] `bash build.sh --deploy` — final build; verify ZIP has **no backslash paths**, all 40+ files included
- [ ] **Clean install test:** install from ZIP into a fresh mods folder → zero errors on first launch
- [ ] Tag `v1.0.0.0` in git

---

## PHASE 6 — Community Release

- [ ] Record gameplay footage: drought stress accumulating → irrigation response → yield comparison (TestMap or ElmCreek)
- [ ] Draft **Steam Workshop listing**: title, description, feature bullets, screenshots, required/optional mod notes
- [ ] Set up post-launch monitoring: watch `log.txt` reports from players for first 2 weeks; known potential failure points are `env.currentDayInPeriod` and the ry sign on drip line rotation

---

## Known Acceptable Limitations (ship with notes)

These are non-fatal, expected, and documented:

| Issue | Status |
|-------|--------|
| Center pivot arm does not rotate visually | Placeholder i3d — fixed in Phase 6 art pass |
| "Missing clear areas / indoor areas / ai update areas" in log for placeables | Optional FS25 placement features — not required for functionality |
| WeatherIntegration `getMoistureForecast` uses current weather, not FS25 forecast API | `weather:getForecast()` existence unverified; current projection is acceptable for v1.0 |
| UsedEquipmentMarketplace `registerUsedEquipment` API unverified | UsedPlus integration calls are nil-guarded; will silently no-op if API mismatches |
| PrecisionFarming `registerOverlay` API unverified | Same — nil-guarded, silently disabled if API mismatches |
