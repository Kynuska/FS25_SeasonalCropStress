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
- [ ] Create `modDesc.xml` with correct `descVersion="72"`, multiplayer flag, input bindings, placeable type declarations, and l10n prefix
- [ ] Create `main.lua` entry point with `Utils.appendedFunction` hooks for all lifecycle events (see Section 5 of ModPlan)
- [ ] Create `src/` directory and all empty `.lua` stubs so `main.lua` source order loads without errors
- [ ] Create `translations/translation_en.xml` with all string keys from Section 14 of ModPlan
- [ ] Create `config/cropStressDefaults.xml` with per-crop threshold defaults
- [ ] Verify mod loads in FS25 with zero log errors (empty stubs are fine at this stage)

#### SoilMoistureSystem.lua
- [ ] Implement `SoilMoistureSystem:initialize()` — enumerate fields via `fieldManager:getFields()`, build `fieldMoistureData` table, call `applyFirstLoadEstimate()`
- [ ] Implement `applyFirstLoadEstimate()` — season + temp aware starting moisture (sandy/summer ~0.35, clay/spring ~0.65), set `wasEstimated = true`
- [ ] Implement `detectSoilType(field)` — terrain layer check → PF soil map check → default "loamy"
- [ ] Implement `hourlyUpdate()` — evapotranspiration formula (baseRate × tempMod × seasonMod × soilMod), irrigation gain, publish `CS_MOISTURE_UPDATED`
- [ ] Implement critical threshold detection inside `hourlyUpdate()` — publish `CS_CRITICAL_THRESHOLD` when moisture < 0.25
- [ ] Implement `onWeatherChanged()` — subscribe to `WEATHER_CHANGED`, apply rain gain (verify MessageType name against LUADOC)
- [ ] Implement `getIrrigationRate(fieldId)` — returns 0 if not irrigating; called by hourlyUpdate
- [ ] Implement `getMoisture(fieldId)` — simple getter used by HUD and WeatherIntegration
- [ ] Implement `SoilMoistureSystem:delete()` — `unsubscribeAll(self)`, clear init flag
- [ ] **TEST:** New game start — all fields at plausible moisture, no log errors
- [ ] **TEST:** `csSetMoisture` console command forces a field to a value correctly

#### WeatherIntegration.lua
- [ ] Implement `WeatherIntegration:initialize()` — subscribe to weather events, set defaults
- [ ] Implement `hourlyPoll()` — read current temp, season, humidity from environment API
- [ ] Implement `onWeatherChanged()` — forward to internal `CS_WEATHER_FOR_MOISTURE` event
- [ ] Implement `getMoistureForecast(fieldId, days)` — 5-day projection using `getForecast()` + evap formula
- [ ] Implement `WeatherIntegration:delete()` — `unsubscribeAll(self)`
- [ ] **TEST:** Forecast returns 5 values, none outside 0.0–1.0

#### CropStressModifier.lua
- [ ] Implement `CRITICAL_WINDOWS` table with all 8 crop types
- [ ] Implement `CropStressModifier:initialize()` — init `fieldStress` table, hook `HarvestingMachine.doGroundWorkArea` via `appendedFunction`
- [ ] Implement `hourlyStressUpdate()` — iterate fields, check growth stage vs critical window, accumulate stress, publish `CS_STRESS_APPLIED`
- [ ] Implement `onDoGroundWorkArea()` — intercept harvest fill amount, apply stress multiplier, reset stress after harvest (verify `workArea` property names against LUADOC)
- [ ] Implement `getStress(fieldId)` — simple getter for HUD
- [ ] **TEST:** `csForceStress <fieldId>` → harvest that field → yield is visibly reduced
- [ ] **TEST:** Field with no stress harvests at 100% yield

#### SaveLoadHandler.lua
- [ ] Implement `SaveLoadHandler:saveToXML()` — write field moisture, stress, and irrigation schedules to `<cropStress>` block
- [ ] Implement `SaveLoadHandler:loadFromXML()` — read all three blocks, handle nil returns with `or` fallbacks, clear `wasEstimated` flag on loaded values
- [ ] Hook save into `FSCareerMissionInfo.saveToXMLFile` via `appendedFunction`
- [ ] Hook load into `Mission00.onStartMission` via `appendedFunction`
- [ ] **TEST:** Save game → reload → all moisture and stress values match exactly
- [ ] **TEST:** Fresh game (no save data) loads without errors

#### HUDOverlay.lua (Phase 1 — basic, no forecast)
- [ ] Create `gui/FieldMoisturePanel.xml` — follow `TakeLoanDialog.xml` structure, root `<GUI>`, no `onClose`/`onOpen` callback names
- [ ] Implement `HUDOverlay:initialize()` — load GUI element, register `CS_TOGGLE_HUD` input action
- [ ] Implement `HUDOverlay:draw()` — draw moisture bars for up to 5 fields, color-coded (green/yellow/red), normalized coordinates only
- [ ] Implement `getMoistureColor(moisture)` — green >0.6, yellow 0.3–0.6, red <0.3
- [ ] Implement `drawMoistureBar()` — bar + percentage + field name + crop type
- [ ] Implement `drawStressWarning()` — show stress indicator when stress > 0.2
- [ ] Implement empty state — "No critical fields — all crops healthy" message when `visibleFields` is empty
- [ ] Implement first-time tooltip — one-time explanation of what the bar means (stored in config after first show)
- [ ] Implement auto-show logic — show when player enters field in critical window with moisture < 0.5
- [ ] Implement auto-hide logic — hide after 30 in-game minutes with no critical fields
- [ ] Implement `CS_MOISTURE_UPDATED` subscriber — update `visibleFields` list
- [ ] **TEST:** Shift+M toggles panel on/off
- [ ] **TEST:** Panel auto-shows when entering a stressed field
- [ ] **TEST:** Empty state message appears when all fields are healthy

#### CropStressManager.lua (coordinator)
- [ ] Implement `CropStressManager:new()` — instantiate all subsystems
- [ ] Implement `initialize()` — call each subsystem's `initialize()` in correct order, call `detectOptionalMods()`
- [ ] Implement `detectOptionalMods()` — check for `g_npcFavorSystem`, `g_usedPlusManager`, `g_precisionFarming`
- [ ] Implement `update(dt)` — drive hourly tick counter, call `hourlyUpdate()` on soil, stress, and weather systems
- [ ] Implement `delete()` — call `delete()` on all subsystems in reverse order
- [ ] Register `g_cropStressManager` as global
- [ ] **TEST:** Load game → play 1 in-game hour → moisture changes, no errors in log

#### Console Debug Commands
- [ ] Implement `debugPrintStatus()` — print all field moisture + stress values to log
- [ ] Implement `debugSetMoisture(fieldIdStr, valueStr)` — force moisture on a field
- [ ] Implement `debugForceStress(fieldIdStr)` — set stress to 1.0 on a field
- [ ] Implement `debugSimulateHeat(daysStr)` — run N days of summer evaporation
- [ ] Implement `debugToggleVerbose()` — toggle verbose event logging
- [ ] Register all commands in `main.lua` under `g_addTestCommands` guard

#### Config File
- [ ] Implement `cropStressConfig.xml` read on startup with fallback defaults for all values
- [ ] Expose difficulty multipliers (`stressMultiplier`, `evaporationMultiplier`, `rainAbsorptionMultiplier`) to formulas in SoilMoistureSystem and CropStressModifier

#### Phase 1 Final Validation
- [ ] All 5 Phase 1 test scenarios pass (see Section 15 of ModPlan)
- [ ] Zero errors in `log.txt` on clean load
- [ ] Zero errors on save/reload cycle
- [ ] `bash build.sh --deploy` produces a valid ZIP with no backslash paths

---

### PHASE 2 — Irrigation Infrastructure

#### WaterPump placeable
- [ ] Create `placeables/waterPump/waterPump.xml` — placeable spec with water source config
- [ ] Create `placeables/waterPump/waterPump.lua` — `onLoad`, `onDelete`, `onWriteStream`, `onReadStream`
- [ ] Register pump with `IrrigationManager` on `onLoad`
- [ ] Implement proximity `E` interaction to connect/disconnect irrigation systems
- [ ] Implement 500m detection radius for supplying connected irrigation systems
- [ ] **TEST:** Place pump near river → connect a pivot → pivot activates

#### CenterPivot placeable
- [ ] Create `placeables/centerPivot/centerPivot.xml` — with `pivotRadius`, water consumption, electrical consumption, price, maintenance cost
- [ ] Create `placeables/centerPivot/centerPivot.lua` — `onLoad`, `onDelete`, `onUpdate` (arm animation), `onWriteStream`, `onReadStream`
- [ ] Use `parent="base"` NOT `parent="handTool"` in spec
- [ ] Implement arm rotation animation when `isActive = true`
- [ ] Register with `IrrigationManager` on `onLoad`, deregister on `onDelete`

#### IrrigationManager.lua
- [ ] Implement `IrrigationManager:initialize()` — init `irrigationSystems` table
- [ ] Implement `registerIrrigationSystem(placeable)` — build system data entry
- [ ] Implement `deregisterIrrigationSystem(placeableId)`
- [ ] Implement `detectCoveredFields(placeable)` — circle/polygon intersection using X/Z coordinates
- [ ] Implement `fieldIntersectsCircle(field, cx, cz, radius)` — check field polygon vs circle
- [ ] Implement `calculateFlowRate(placeable)` — read from placeable XML
- [ ] Implement `calculateCost(placeable)` — read from placeable XML
- [ ] Implement `calculatePressureMultiplier(distance)` — linear 100%→70% over 0→500m, 0% beyond
- [ ] Implement `checkWaterAvailability(system)` — check connected pump has water
- [ ] Implement `hourlyScheduleCheck()` — compare current hour/day vs schedule, activate/deactivate
- [ ] Implement `activateSystem(id)` — set active, publish `CS_IRRIGATION_STARTED` for each covered field with effective rate
- [ ] Implement `deactivateSystem(id)` — set inactive, publish `CS_IRRIGATION_STOPPED`
- [ ] Implement `getIrrigationRate(fieldId)` — returns effective rate for SoilMoistureSystem to use
- [ ] Implement `IrrigationManager:delete()` — `unsubscribeAll`, deactivate all systems

#### Irrigation Schedule Dialog
- [ ] Create `gui/IrrigationScheduleDialog.xml` — copy `TakeLoanDialog.xml` structure, `<GUI>` root, custom callback names
- [ ] Create `gui/IrrigationScheduleDialog.lua` — dialog logic
- [ ] Day-of-week toggle buttons (Mon–Sun, 7 individual buttons)
- [ ] Start/end time selectors via `MultiTextOption` — set texts via `setTexts()` in Lua, NOT via XML `<texts>` children
- [ ] Display flow rate, efficiency, estimated cost, wear level
- [ ] List covered fields with their current moisture + crop stage
- [ ] "Irrigate Now" button — immediately activate system
- [ ] "Save Schedule" button — write schedule back to system data and trigger save
- [ ] Open dialog on `E` near a system or `Shift+I` keybind
- [ ] **TEST:** Change schedule → save → reload → schedule persists

#### Irrigation Costs (vanilla — no UsedPlus yet)
- [ ] Implement hourly cost deduction in `CropStressManager:update()` via `updateFunds(-cost, "OTHER", true)`
- [ ] **TEST:** Run irrigation overnight → farm balance decreases by expected amount

#### Save/Load — Irrigation Extension
- [ ] Extend `SaveLoadHandler` to save/load irrigation system schedules and active states
- [ ] **TEST:** Active irrigation → save → reload → still active with correct schedule

#### Phase 2 Final Validation
- [ ] All Phase 2 test scenarios pass (scenarios 4+ from Section 15)
- [ ] Center pivot animates when active
- [ ] Pressure curve: pivot at 250m gets ~85% flow; pivot at 600m gets 0%
- [ ] Zero errors in log

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
- [ ] Implement `FinanceIntegration:initialize()` — detect `g_usedPlusManager`, subscribe to irrigation events
- [ ] Implement `chargeHourlyCosts()` — route through `g_usedPlusManager:recordExpense()` if present, otherwise direct `updateFunds`
- [ ] Implement `getEquipmentWearLevel(vehicleId)` — read UsedPlus DNA reliability, convert to 0–1 wear scale
- [ ] Implement `onIrrigationStarted()` / `onIrrigationStopped()` — track cost cycle start/stop times
- [ ] Implement `enableUsedPlusMode()` — called by `CropStressManager` after detection
- [ ] Implement `FinanceIntegration:delete()` — `unsubscribeAll`
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

*(No sessions logged yet — this file was just created. First agent: start at "Create modDesc.xml" under Phase 1 → Project Scaffolding.)*

---

## Quick Reference: Where to Start

**If no sessions are logged:** Start at the very first unchecked item under Phase 1 → Project Scaffolding.

**If sessions are logged:** Read the most recent entry. Find "Next agent should start at:" and go there.

**If an item is marked `[~]` (in progress):** Read the session note for that item before continuing — there may be a partial implementation, a known issue, or a branch that needs review before proceeding.

**If an item is marked `[!]` (blocked):** Read the note. Do not attempt to work around a blocker without documenting the workaround here first.

---

*DEVELOPMENT.md — created alongside plan v2.0. Maintained by all contributors. Last updated: session initialization.*