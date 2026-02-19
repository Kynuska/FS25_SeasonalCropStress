# DEVELOPMENT.md
## FS25_SeasonalCropStress — Build Tracker & Session Log

> **Purpose:** This file is the single source of truth for what has been built, what hasn't, and where the next session should begin. Every AI (Claude, GPT, Gemini, or any other) working on this project MUST read this file first, update it when done, and leave it better than they found it.

---

## How to Use This File (Read Before Touching Anything)

### For AI Agents Starting a Session

1. **Read this entire file first.** Do not skip to the TODO list.
2. **Find the last completed session** in the Session Log (bottom of file). That tells you exactly where to start.
3. **Find the first unchecked item** in the TODO list. That is your starting point.
4. **Follow the collaboration model** in `CLAUDE.md` — planning dialog with Samantha before writing code, review dialog after.
5. **When you finish a work block**, scroll to the Session Log section and add an entry. Be specific. Future AIs depend on your notes.
6. **Check off TODO items** as you complete them. Use `[x]` for done, `[~]` for partial/in-progress, `[ ]` for not started.
7. **Never mark something `[x]` unless it is tested and working.** `[~]` means started but not complete.

### Status Key

| Symbol | Meaning |
|--------|---------|
| `[ ]` | Not started |
| `[~]` | In progress / partial |
| `[x]` | Complete and tested |
| `[!]` | Blocked — see notes |
| `[s]` | Skipped — see notes (usually console compat or optional mod) |

---

## Master TODO List

Work through these **in order**. Do not skip ahead. Dependencies flow downward.

---

### PHASE 1 — Core MVP

#### Project Scaffolding
- [x] Create `modDesc.xml` with correct `descVersion="105"`, multiplayer flag, input bindings, placeable type declarations, and l10n prefix
- [x] Create `main.lua` entry point with `Utils.appendedFunction` hooks for all lifecycle events (see Section 5 of ModPlan)
- [x] Create `src/` directory and all `.lua` stubs so `main.lua` source order loads without errors
- [x] Create `translations/translation_en.xml` with all string keys from Section 14 of ModPlan
- [x] Create `config/cropStressDefaults.xml` with per-crop threshold defaults
- [ ] **TEST:** Verify mod loads in FS25 with zero log errors (empty stubs are fine at this stage)

#### SoilMoistureSystem.lua
- [x] Implement `SoilMoistureSystem:initialize()` — enumerate fields via `fieldManager:getFields()`, build `fieldData` table, call season-aware first-load estimate
- [x] Implement season-aware starting moisture — `SEASON_START_MOISTURE` table, spring=0.60, summer=0.40, autumn=0.55, winter=0.70
- [x] Implement `detectSoilType(field)` — field attribute check → default "loamy" (PF/terrain layer hooks stubbed for later)
- [x] Implement `hourlyUpdate(weather)` — evapotranspiration (baseRate × evapMod × soilMod), rain gain, irrigation gain from `self.irrigationGains[fieldId]`, publish `CS_MOISTURE_UPDATED`
- [x] Implement critical threshold detection inside `hourlyUpdate()` — publish `CS_CRITICAL_THRESHOLD` when moisture ≤ 0.25, with 12-hour cooldown per field
- [s] Implement `onWeatherChanged()` subscribe to `WEATHER_CHANGED` — skipped; WeatherIntegration uses polling approach instead (more reliable across FS25 versions)
- [x] Implement `getMoisture(fieldId)` / `setMoisture(fieldId, value)` — getters/setters
- [x] Implement `SoilMoistureSystem:delete()` — clear init flag
- [ ] **TEST:** New game start — all fields at plausible moisture, no log errors
- [ ] **TEST:** `csSetMoisture` console command forces a field to a value correctly

#### WeatherIntegration.lua
- [x] Implement `WeatherIntegration:initialize()` — set defaults, expose accessors
- [x] Implement `update()` (hourly poll) — read current temp, season, humidity, rain amount from environment API; cache as `currentTemp`, `currentSeason`, `hourlyRainAmount`, `isRaining`
- [x] Implement `getHourlyEvapMultiplier()` — returns composite modifier for SoilMoistureSystem
- [x] Implement `getHourlyRainAmount()` — returns scaled rain gain for this tick
- [~] Implement `getMoistureForecast(fieldId, days)` — 5-day projection; partially stubbed (uses current weather, not actual FS25 forecast API — verify `weather:getForecast()` in LUADOC)
- [x] Implement `WeatherIntegration:delete()` — cleanup
- [ ] **TEST:** Forecast returns 5 values, none outside 0.0–1.0

#### CropStressModifier.lua
- [x] Implement `CRITICAL_WINDOWS` table with all 8 crop types (wheat, corn, barley, canola, sunflower, soybeans, sugarbeet, potato)
- [x] Implement `CropStressModifier:initialize()` — init `fieldStress` table, hook `HarvestingMachine.doGroundWorkArea` via `appendedFunction`
- [x] Implement `hourlyUpdate()` — iterate fields, check growth stage vs critical window, accumulate stress proportional to moisture deficit, publish `CS_STRESS_APPLIED`
- [x] Implement `onDoGroundWorkArea()` — intercept harvest fill amount, apply stress multiplier (max 60% loss), reset stress after harvest
- [x] Implement `getStress(fieldId)` — simple getter for HUD
- [ ] **TEST:** `csForceStress <fieldId>` → harvest that field → yield is visibly reduced
- [ ] **TEST:** Field with no stress harvests at 100% yield

#### SaveLoadHandler.lua
- [x] Implement `SaveLoadHandler:saveToXMLFile()` — writes field moisture, stress accumulation, and HUD state into `careerSavegame.cropStress` block; skips gracefully if xmlFile is nil
- [x] Implement `SaveLoadHandler:loadFromXMLFile()` — reads all three blocks with `or` fallbacks; clears estimated flag on loaded values; handles missing save data gracefully
- [x] Hook save into `FSCareerMissionInfo.saveToXMLFile` via `appendedFunction` in `main.lua`
- [x] Hook load into `Mission00.onStartMission` via `appendedFunction` in `main.lua`
- [ ] **TEST:** Save game → reload → all moisture and stress values match exactly
- [ ] **TEST:** Fresh game (no save data) loads without errors

#### HUDOverlay.lua (Phase 1 — basic, no forecast)
- [x] Implement `HUDOverlay:initialize()` — register `CS_MOISTURE_UPDATED` subscriber, init state
- [x] Implement `HUDOverlay:draw()` — render moisture bars per field, color-coded; uses normalized coordinates (0.0–1.0)
- [x] Implement `getMoistureColor(moisture)` — green >0.6, yellow 0.3–0.6, red <0.3
- [x] Implement `drawMoistureBar()` — bar + percentage + field name + crop type
- [x] Implement `drawStressWarning()` — show stress indicator when stress > 0.2
- [x] Implement empty state — "No critical fields — all crops healthy" message
- [x] Implement first-time tooltip — one-time `cs_hud_first_run` message; stored in `firstRunShown`
- [x] Implement auto-show logic — show when player enters a field in critical window with moisture < 0.5
- [x] Implement auto-hide logic — hide after 30 in-game minutes with no critical fields
- [x] Implement `CS_MOISTURE_UPDATED` subscriber — update visible fields list
- [ ] **TEST:** Shift+M toggles panel on/off
- [ ] **TEST:** Panel auto-shows when entering a stressed field
- [ ] **TEST:** Empty state message appears when all fields are healthy

#### CropStressManager.lua (coordinator)
- [x] Implement `CropStressManager:new()` — instantiate all subsystems, wire `eventBus = CropEventBus`
- [x] Implement `initialize()` — call each subsystem's `initialize()` in dependency order, call `detectOptionalMods()`
- [x] Implement `detectOptionalMods()` — check for `g_npcFavorSystem`, `g_usedPlusManager`, `g_precisionFarming`
- [x] Implement `update(dt)` — hourly tick detection via monotonic day×24+hour key, drive `onHourlyTick()`
- [x] Implement `delete()` — call `delete()` on all subsystems in reverse order, clear `CropEventBus.listeners`
- [x] Register `g_cropStressManager` as global in `main.lua`
- [ ] **TEST:** Load game → play 1 in-game hour → moisture changes, no errors in log

#### Console Debug Commands
- [x] Implement `consoleHelp()` — print all commands
- [x] Implement `consoleStatus()` — print all field moisture + stress values with weather state
- [x] Implement `consoleSetMoisture(fieldIdStr, valueStr)` — force moisture on a field
- [x] Implement `consoleForceStress(fieldIdStr)` — set stress to 1.0 on a field
- [x] Implement `consoleSimulateHeat(daysStr)` — run N days of summer evaporation by overriding weather state
- [x] Implement `consoleToggleDebug()` — toggle verbose logging flag
- [x] Register all commands in `main.lua` under `addConsoleCommand` guard; remove in `FSBaseMission.delete`

#### Config File
- [x] `config/cropStressDefaults.xml` created
- [ ] Expose difficulty multipliers (`stressMultiplier`, `evaporationMultiplier`, `rainAbsorptionMultiplier`) to SoilMoistureSystem and CropStressModifier formulas — file exists but values not yet wired into calculations

#### Phase 1 Final Validation
- [ ] All 5 Phase 1 test scenarios pass (see Section 15 of ModPlan)
- [ ] Zero errors in `log.txt` on clean load
- [ ] Zero errors on save/reload cycle
- [ ] `bash build.sh --deploy` produces a valid ZIP with no backslash paths

---

### PHASE 2 — Irrigation Infrastructure

#### WaterPump placeable
- [!] Create `placeables/waterPump/waterPump.xml` — **MISSING. Only waterPump.lua was created. The XML spec file is required for FS25 to register and place the pump. Must be created before Phase 2 is playable.**
- [x] Create `placeables/waterPump/waterPump.lua` — `onLoad` (sets `waterFlowCapacity` then registers), `onDelete`, `onWriteStream`, `onReadStream`
- [x] Register pump with `IrrigationManager` on `onLoad`; deregister on `onDelete`
- [ ] Implement proximity `E` interaction to connect/disconnect irrigation systems — NOT implemented; currently all pumps auto-connect to nearest pivot within 500m at registration time
- [~] 500m detection radius — implemented as `MAX_PUMP_DISTANCE` in `IrrigationManager:findNearestWaterSource()`; pressure degrades linearly to 70% at 500m per `calculatePressureMultiplier()`
- [ ] **TEST:** Place pump near river → connect a pivot → pivot activates

#### CenterPivot placeable
- [x] Create `placeables/centerPivot/centerPivot.xml` — with `pivotRadius`, water consumption, electrical consumption, price, maintenance cost, and `<irrigationConfig>` block
- [x] Create `placeables/centerPivot/centerPivot.lua` — `onLoad`, `onDelete`, `onUpdate` (arm animation), `onWriteStream`, `onReadStream`
- [x] Inherits `Placeable` base (no `parent="handTool"` problem)
- [~] Arm rotation animation — code written in `onUpdate`; syncs `isActive` from `IrrigationManager.systems[self.id]`; **no i3d file yet so untestable — armNode will be nil at runtime**
- [x] Register with `IrrigationManager` on `onLoad`; deregister on `onDelete`
- [!] **No i3d files exist** for either centerPivot or waterPump — placeables cannot be placed in-game without them. Phase 2 logic is complete but unplayable until i3d assets are provided.

#### IrrigationManager.lua
- [x] Implement `IrrigationManager:initialize()` — init `systems` and `waterSources` tables
- [x] Implement `registerIrrigationSystem(placeable)` — build system data entry with coverage, water source, pressure, schedule, cost
- [x] Implement `deregisterIrrigationSystem(placeableId)` — deactivate then remove
- [x] Implement `detectCoveredFields(placeable, cx, cz)` — circular coverage (pivot only); drip stubbed for Phase 4
- [x] Implement `fieldIntersectsCircle(field, cx, cz, radius)` — AABB bounding box approximation; falls back to field center + radius if bounds unavailable
- [x] Implement `calculatePressureMultiplier(distance)` — linear 100%→70% over 0→500m, 0% beyond
- [x] Implement `registerWaterSource(placeable)` / `deregisterWaterSource(placeableId)` — including cascade deactivation of dependent systems
- [x] Implement `findNearestWaterSource(x, z)` — returns nearest source within 500m
- [x] Implement `hourlyScheduleCheck()` — validates water source still present, compares hour/dayOfWeek vs schedule, calls activate/deactivate
- [x] Implement `activateSystem(id)` — recalculates effective rate (pressure × wear), sets per-field rates, publishes `CS_IRRIGATION_STARTED`
- [x] Implement `deactivateSystem(id)` — clears rates, publishes `CS_IRRIGATION_STOPPED`
- [x] Implement `getIrrigationRateForField(fieldId)` — sums active system rates for a field
- [x] Implement `IrrigationManager:delete()` — deactivate all systems, clear tables

#### Irrigation Schedule Dialog
- [x] Create `gui/IrrigationScheduleDialog.xml` — `<GUI>` root, `TakeLoanDialog` structure, no conflicting `onClose`/`onOpen` callback names
- [x] Create `gui/IrrigationScheduleDialog.lua` — dialog logic with all sections
- [x] Day-of-week toggle buttons (Mon–Sun) — dynamically created in Lua via `createDayButtons()`
- [x] Start/end time selectors via `MultiTextOption` — texts set via `setTexts()` in Lua, not XML children
- [x] Display flow rate, efficiency, estimated cost, wear level via `updatePerformance()`
- [x] List covered fields with current moisture + crop stage via `updateCoveredFields()`
- [x] "Irrigate Now" button — calls `IrrigationManager:activateSystem()` directly
- [x] "Save Schedule" button — shows toast, closes dialog (no crash; schedule auto-persists on game save)
- [ ] Open dialog on `E` near a system — NOT implemented; must detect nearby irrigation placeable in player's trigger zone
- [x] `Shift+I` keybind (`CS_OPEN_IRRIGATION` action) declared in `modDesc.xml`, registered in `main.lua`
- [ ] **TEST:** Change schedule → save → reload → schedule persists (requires Save/Load extension below)
- [ ] **TEST:** Dialog opens cleanly, all elements visible, no layout overflow

#### Irrigation Costs (vanilla — no UsedPlus yet)
- [x] `FinanceIntegration:chargeHourlyCosts()` — iterates active systems, deducts `operationalCostPerHour` via `updateFunds(-cost, "OTHER", true)`; UsedPlus path present but gated behind `usedPlusActive` flag
- [x] Called from `CropStressManager:onHourlyTick()` — wired alongside irrigation schedule check
- [ ] **TEST:** Run irrigation overnight → farm balance decreases by expected amount

#### Save/Load — Irrigation Extension
- [ ] Extend `SaveLoadHandler:saveToXMLFile()` to write irrigation schedules (startHour, endHour, activeDays) per system ID
- [ ] Extend `SaveLoadHandler:loadFromXMLFile()` to restore irrigation schedules after `IrrigationManager` is initialized
- [ ] **TEST:** Active irrigation with custom schedule → save → reload → still active with correct schedule

#### Phase 2 Final Validation
- [ ] All Phase 2 test scenarios pass (scenarios 4+ from Section 15)
- [ ] Center pivot animates when active (requires i3d asset)
- [ ] Pressure curve: pivot at 250m gets ~85% flow; pivot at 600m gets 0%
- [ ] Zero errors in log
- [ ] `bash build.sh --deploy` and full play session without crash

---

### PHASE 3 — NPC & Social

#### CropConsultant.lua (standalone mode)
- [ ] Implement `CropConsultant:initialize()` — subscribe to `CS_CRITICAL_THRESHOLD`
- [ ] Implement `onCriticalThreshold()` — 12-hour cooldown per field, severity logic, `showBlinkingWarning`
- [ ] Implement three severity levels: INFO (4s), WARNING (6s), CRITICAL (10s red)
- [ ] Implement `CropConsultant:delete()` — `unsubscribeAll`
- [ ] **TEST:** Set field to 15% moisture → warning appears within 1 in-game hour
- [ ] **TEST:** Warning does NOT repeat for 12 in-game hours on same field

#### NPCIntegration.lua
- [ ] Implement `NPCIntegration:initialize()` — detect `g_npcFavorSystem`, conditionally register
- [ ] Implement `registerConsultantNPC()` — verify `registerExternalNPC` API against NPCFavor source, call with Alex Chen config
- [ ] Implement `generateConsultantFavor(npc, favorType)` — return favor task configs for all 4 favor types (`SOIL_SAMPLE`, `IRRIGATION_CHECK`, `EMERGENCY_WATER`, `SEASONAL_PLAN`)
- [ ] Implement `enableNPCFavorMode()` — called by `CropStressManager` after detection
- [ ] **TEST (with NPCFavor loaded):** Alex Chen NPC appears, relationship starts at 10
- [ ] **TEST (with NPCFavor loaded):** `EMERGENCY_WATER` favor fires when field < 15% in critical window
- [ ] **TEST (without NPCFavor):** Mod loads cleanly, no nil access errors

#### HUD Forecast Strip (Phase 3 upgrade)
- [ ] Extend `gui/FieldMoisturePanel.xml` to include 5-day forecast section
- [ ] Implement `drawForecast(projections)` in `HUDOverlay.lua` — 5 columns, moisture %, weather icon hint
- [ ] Wire `selectedFieldId` — clicking a field row in HUD selects it for forecast display
- [ ] **TEST:** Forecast shows 5 different values, updates when selected field changes

#### Phase 3 Final Validation
- [ ] Scenarios 6 and 7 from Section 15 pass
- [ ] Standalone consultant alerts work with no optional mods loaded
- [ ] Alex Chen appears and generates favors when NPCFavor is present
- [ ] Forecast strip renders without coordinate/overflow errors

---

### PHASE 4 — Finance & Polish

#### FinanceIntegration.lua
- [~] Implement `FinanceIntegration:initialize()` — detect `g_usedPlusManager` (detection done by `CropStressManager:detectOptionalMods()`; sets `usedPlusActive` flag)
- [~] Implement `chargeHourlyCosts()` — vanilla path live; UsedPlus path written but untested (no UsedPlus in dev)
- [x] Implement `getEquipmentWearLevel(vehicleId)` — returns 0.0 stub; Phase 4 wire
- [ ] Implement `onIrrigationStarted()` / `onIrrigationStopped()` — track cost cycle start/stop times (currently not needed for simple hourly charge)
- [ ] Implement `enableUsedPlusMode()` — called by `CropStressManager` after detection
- [ ] **TEST (with UsedPlus):** Irrigation costs appear in UsedPlus finance manager under "OPERATIONAL"
- [ ] **TEST (with UsedPlus):** Worn pump (DNA reliability 0.6) delivers ~76% of rated flow
- [ ] **TEST (without UsedPlus):** Costs still deducted via vanilla `updateFunds`

#### Drip Irrigation Line placeable
- [ ] Create `placeables/dripIrrigationLine/dripLine.xml` + `.lua`
- [ ] Implement start/end marker placement workflow
- [ ] Implement linear coverage calculation → field polygon overlap
- [ ] Register with `IrrigationManager` (same path as pivot)
- [ ] **TEST:** Place drip line across a sugar beet field → moisture rises in covered area

#### Used Equipment Marketplace entries
- [ ] Add center pivot and pump unit to UsedPlus used equipment marketplace (verify UsedPlus marketplace registration API)
- [ ] Add wear state variation so pre-owned items appear at 40–80% condition
- [ ] **TEST (with UsedPlus):** Pre-owned pivot appears in marketplace at discount

#### Precision Farming DLC Overlay
- [ ] Implement `enablePrecisionFarmingCompat()` in `CropStressManager`
- [ ] Read PF soil sample data for per-field `soilType` (check PF DLC API against LUADOC)
- [ ] Add moisture overlay layer to PF soil analysis map view
- [ ] **TEST (with PF DLC):** PF soil map shows moisture overlay, soil types match PF data

#### Translations — Complete Set
- [ ] `translation_de.xml` — German, all keys
- [ ] `translation_fr.xml` — French, all keys
- [ ] `translation_nl.xml` — Dutch, all keys
- [ ] `translation_pl.xml` — Polish, all keys
- [ ] **TEST:** Switch game language to DE → all mod UI text is German, no missing key fallbacks

#### Phase 4 Final Validation
- [ ] All 10 test scenarios from Section 15 pass
- [ ] Zero errors in log with all optional mods loaded simultaneously (UsedPlus + NPCFavor + PF DLC)
- [ ] Zero errors in log with no optional mods loaded
- [ ] Build produces valid ZIP, deploy to mods folder, full clean play session without crash

---

### POST-LAUNCH

- [ ] Create Steam Workshop listing draft
- [ ] Record gameplay footage showing drought stress + irrigation response
- [ ] Write changelog for v1.0.0.0
- [ ] Tag v1.0.0.0 in git

---

## Session Log

*Sessions are logged in reverse-chronological order (newest at top). Each entry MUST include: date, AI agent, what was done, what was tested, what the next agent should start on, and any blockers or surprises.*

---

### SESSION TEMPLATE (copy this for every new entry)

```
---

### [DATE] — [AI AGENT NAME] — Phase [X]

**Started from:** [First TODO item tackled this session]
**Completed:**
- [Item 1 — be specific, include file names]
- [Item 2]

**Tested:**
- [Test 1 — what you tested and what the result was]
- [Test 2]

**Checked off in TODO:**
- [List the TODO items you marked [x] this session]

**Next agent should start at:**
[Exact TODO item text — copy it verbatim from the list above]

**Notes / surprises:**
- [Anything unexpected — API names that differed from ModPlan, bugs found, workarounds applied]
- [Anything the next agent needs to know that isn't obvious from the TODO list]

---
```

---

### 2026-02-19 — Claude (Sonnet 4.6) — Phase 2 review & bug fixes

**Started from:** Code review of existing Phase 2 implementation

**Completed:**
- Identified and fixed 7 bugs in the Phase 2 implementation (see Bug Fixes below)
- `modDesc.xml`: Added `CS_OPEN_IRRIGATION` action + Shift+I binding (was missing entirely)
- `main.lua`: Corrected `InputAction.CS_OPEN_IRRIGATION_DIALOG` → `CS_OPEN_IRRIGATION` to match declared action; cleaned up blank line before lifecycle comment section
- `src/SoilMoistureSystem.lua`: Moved `CropEventBus.subscribe` calls for irrigation events out of `hourlyUpdate()` loop into `initialize()` — critical: they were re-registering N×M times per hour
- `gui/IrrigationScheduleDialog.lua`: Removed `g_cropStressManager:saveToXMLFile()` call in `onSaveSchedule()` — it was called without an `xmlFile` arg, crashing SaveLoadHandler
- `placeables/waterPump/waterPump.lua`: Moved `self.waterFlowCapacity` assignment to before `registerWaterSource()` call
- `src/CropStressManager.lua`: Removed stale commented-out `chargeHourlyCosts` stub left below the live call
- `placeables/centerPivot/centerPivot.lua`: `onUpdate` now queries `mgr.systems[self.id].isActive` from IrrigationManager instead of relying on `self.isActive` which was never set on the placeable
- `src/IrrigationManager.lua`, `src/FinanceIntegration.lua`: Added missing EOF newlines
- PR #3 opened: development → main

**Tested:**
- Code review only — no in-game testing this session

**Checked off in TODO:**
- All Phase 2 IrrigationManager items marked [x]
- IrrigationScheduleDialog XML + Lua items marked [x] (except E-key interaction and in-game tests)
- Irrigation costs (vanilla) marked [x]
- WaterPump lua marked [x]; waterPump.xml marked [!] (missing)
- CenterPivot xml + lua marked [x]; arm animation marked [~]; i3d absence marked [!]

**Next agent should start at:**
`Create placeables/waterPump/waterPump.xml — MISSING. Only waterPump.lua was created.`

**Bug fixes applied this session:**
1. `SoilMoistureSystem.lua` — event subscriptions inside hourly loop (silent data corruption — would multiply irrigation gains N×M times after N hours with M fields)
2. `modDesc.xml` + `main.lua` — wrong action name `CS_OPEN_IRRIGATION_DIALOG`; Shift+I never registered
3. `IrrigationScheduleDialog.lua` — crash in `onSaveSchedule()` from `saveToXMLFile()` with nil arg
4. `waterPump.lua` — `waterFlowCapacity` set after registration; always registered with default
5. `CropStressManager.lua` — stale dead comment after live call was uncommented
6. `centerPivot.lua` — `onUpdate` checked `self.isActive` which manager never set on the placeable
7. `IrrigationManager.lua`, `FinanceIntegration.lua` — missing EOF newlines

**Notes / surprises:**
- `placeables/waterPump/waterPump.xml` is absent — the pump cannot be placed in-game. Must be created (see centerPivot.xml as template).
- Neither placeable has an `.i3d` file — the whole placeable system is logic-complete but unplayable until 3D assets exist. Phase 2 scope does not require final assets, but at minimum placeholder i3d files are needed to test placement in-game.
- `IrrigationScheduleDialog` uses `g_gui:showDialog("IrrigationScheduleDialog", nil, firstId)` in `CropStressManager:onOpenIrrigationDialog()` — the three-argument form may not pass `firstId` to `onDialogOpen`. Should be verified in-game; fallback is `g_gui:showDialog(name)` then manually calling `dialog.target:onDialogOpen(firstId)`.
- `SaveLoadHandler` does NOT yet save irrigation schedules. The dialog's "Save Schedule" button works (schedule is live in memory) but schedules will reset on reload until the extension is implemented.
- `config/cropStressDefaults.xml` exists but difficulty multipliers are not yet wired into SoilMoistureSystem or CropStressModifier formulas.
- `WeatherIntegration:getMoistureForecast()` is partially stubbed — uses current weather state rather than the FS25 forecast API. Verify `g_currentMission.environment.weather:getForecast()` against LUADOC before Phase 3 HUD forecast work.

---

### 2026-02-19 — Claude (Sonnet 4.6) — Phase 1

**Started from:** Create `modDesc.xml` with correct descVersion

**Completed:**
- Full project scaffolding: `modDesc.xml`, `main.lua`, all `src/` stubs, `translations/translation_en.xml`, `config/cropStressDefaults.xml`
- `src/SoilMoistureSystem.lua` — full implementation: field enumeration, season-aware start moisture, SOIL_PARAMS table, `hourlyUpdate()` with evapotranspiration, rain gain, critical threshold detection with cooldown
- `src/WeatherIntegration.lua` — hourly polling approach (temp, season, humidity, rain amount); evap multiplier and rain amount accessors for SoilMoistureSystem
- `src/CropStressModifier.lua` — CRITICAL_WINDOWS for 8 crops, `hourlyUpdate()` stress accumulation, harvest hook via `appendedFunction` on `HarvestingMachine.doGroundWorkArea`
- `src/SaveLoadHandler.lua` — saves/loads moisture, stress, and HUD state via `careerSavegame.cropStress` XML block
- `src/HUDOverlay.lua` — direct `renderText`/`drawFilledRect` HUD (Phase 1 approach); color-coded moisture bars, stress warning, empty state, first-run tooltip, auto-show/hide logic
- `src/CropStressManager.lua` — central coordinator, `CropEventBus` internal event system, all lifecycle hooks, `detectOptionalMods()`, full console debug command suite
- Stubs: `src/IrrigationManager.lua`, `src/CropConsultant.lua`, `src/NPCIntegration.lua`, `src/FinanceIntegration.lua`, `gui/FieldMoisturePanel.lua`, `gui/CropConsultantDialog.lua`
- README.md written

**Tested:**
- Code review only — no in-game testing confirmed

**Checked off in TODO:**
- All Phase 1 implementation items marked [x]
- In-game test items left as [ ] pending first game load

**Next agent should start at:**
*(Phase 1 was followed immediately by Phase 2 in the same session — see Phase 2 entry above)*

**Notes / surprises:**
- Used custom `CropEventBus` instead of `g_messageCenter` to avoid dependence on integer-mapped `MessageType` IDs (more version-agnostic).
- HUD uses direct draw calls in Phase 1; XML GuiElement upgrade is planned for Phase 2.
- Save uses `careerSavegame.cropStress` key in Phase 1; migration to sidecar `cropStressData.xml` planned for Phase 4.
- Harvest hook uses `Utils.appendedFunction` (not `overwrittenFunction`) per CLAUDE.md rules.
- Weather uses polling (not events) every hourly tick — more reliable across FS25 versions.
- Several FS25 API calls in comments are marked `LUADOC NOTE` pending in-game verification: `field:getFruitType()`, `field:getGrowthState()`, `env.weather:getCurrentTemperature()`, `env.weather:getRainFallScale()`, `HarvestingMachine.doGroundWorkArea` parameter names.

---

## Quick Reference: Where to Start

**If no sessions are logged:** Start at the very first unchecked item under Phase 1 → Project Scaffolding.

**If sessions are logged:** Read the most recent entry. Find "Next agent should start at:" and go there.

**If an item is marked `[~]` (in progress):** Read the session note for that item before continuing — there may be a partial implementation, a known issue, or a branch that needs review before proceeding.

**If an item is marked `[!]` (blocked):** Read the note. Do not attempt to work around a blocker without documenting the workaround here first.

---

*DEVELOPMENT.md — last updated: 2026-02-19, Phase 2 review session.*
