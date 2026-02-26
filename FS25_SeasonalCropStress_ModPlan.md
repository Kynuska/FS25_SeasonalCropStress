# FS25 Mod Development Plan: Seasonal Crop Stress & Irrigation Manager
### A Complete Implementation Guide

> **Purpose of this document:** Self-contained, step-by-step blueprint to build `FS25_SeasonalCropStress` from scratch. All architectural decisions are explained, all pitfalls are called out, and all source references are cited. Written for continuity across sessions — Claude and Samantha can pick this up at any point and execute correctly.

---

## Table of Contents

1. [Mod Concept & Vision](#1-mod-concept--vision)
2. [Source Material & Prior Art](#2-source-material--prior-art)
3. [Technical Environment](#3-technical-environment)
4. [Repository & File Structure](#4-repository--file-structure)
5. [Core Systems Architecture](#5-core-systems-architecture)
6. [System-by-System Implementation Guide](#6-system-by-system-implementation-guide)
   - 6.1 [SoilMoistureSystem.lua](#61-soilmoisturesystemlua)
   - 6.2 [IrrigationManager.lua](#62-irrigationmanagerlua)
   - 6.3 [CropStressModifier.lua](#63-cropstressmodifierlua)
   - 6.4 [WeatherIntegration.lua](#64-weatherintegrationlua)
   - 6.5 [HUDOverlay.lua](#65-hudoverlaylua)
   - 6.6 [CropConsultant.lua](#66-cropconsultantlua)
   - 6.7 [NPCIntegration.lua](#67-npcintegrationlua)
   - 6.8 [FinanceIntegration.lua](#68-financeintegrationlua)
7. [GUI Design](#7-gui-design)
8. [Placeables: Irrigation Infrastructure](#8-placeables-irrigation-infrastructure)
9. [Save / Load System](#9-save--load-system)
10. [Multiplayer Considerations](#10-multiplayer-considerations)
11. [Cross-Mod Integration Layer](#11-cross-mod-integration-layer)
12. [modDesc.xml Specification](#12-moddescxml-specification)
13. [Configuration File Specification](#13-configuration-file-specification)
14. [Localization](#14-localization)
15. [Testing Strategy](#15-testing-strategy)
16. [Known FS25 Lua Pitfalls](#16-known-fs25-lua-pitfalls)
17. [Phased Release Plan](#17-phased-release-plan)
18. [Credits & Acknowledgements](#18-credits--acknowledgements)

---

## How Sessions Work

Every session uses the collaboration model defined in `CLAUDE.md`. Claude does ~80% of implementation work; Samantha contributes ~20% as co-creator, manager, and final reviewer. Dialog flows naturally throughout — not just at checkpoints.

**Required collaboration points every session:**
1. **Early Planning** — Claude proposes approach, Samantha questions assumptions and approves or redirects before any code is written.
2. **Pre-Implementation Review** — Claude outlines specific steps, Samantha reviews for edge cases and UX concerns, gives go-ahead.
3. **Post-Implementation Review** — Claude summarizes what was built, Samantha verifies requirements met and declares work complete (or identifies gaps).

**Example of correct session opening:**

---

**Claude** 🍵 *sips oolong, opens the plan doc*

Good morning. I've re-read the plan. Given we're starting Phase 2 today, I'd suggest beginning with `WaterPump.lua` — it's the dependency that `IrrigationManager` needs before the pivot can activate. My thinking is: register the pump as a placeable, implement the water source detection radius (500m), then wire the activation event. Thoughts?

---

**Samantha** 🌸 *adjusts her "git push it real good" cap, wraps both hands around a fresh coffee*

Love the sequencing. One thing before you dive in — I was thinking about the farmer who places a pump right at the river's edge versus 490m away. Are we doing a hard radius cutoff, or should distance affect pressure/flow rate? Because if it's just a binary connect/disconnect, that's a missed gameplay opportunity.

---

**Claude** ☯️

Good catch. A pressure-distance curve adds depth without much complexity — linear falloff from 100% at 0m to 70% at 500m, then hard cutoff. Keeps it meaningful without punishing anyone who places thoughtfully.

---

**Samantha** 💕

That's the sweet spot. Go for it.

---

*That's the energy. Capture it in every session.*

---

## 1. Mod Concept & Vision

**Name:** `FS25_SeasonalCropStress`
**Tagline:** *Your crops thirst. Your crops suffer. Your choices matter.*
**Current Version:** 1.0.0.0

### What the mod does

Vanilla FS25 treats crop growth as binary: crops either grow through their stages or they don't. Precipitation, temperature, and soil type have no granular influence on yield once planting happens. This mod adds a **soil moisture layer** and **crop stress simulation** that makes every field a living system requiring active agronomic management.

### Core gameplay loop added

1. Each field has a **soil moisture percentage** (0–100) that rises with rain and irrigation, falls through evapotranspiration driven by temperature.
2. During growth-stage windows, if moisture drops below crop-specific thresholds, a **stress multiplier** accumulates and reduces final yield.
3. The player can place **center-pivot irrigation systems** or **drip irrigation lines** to counteract drought stress.
4. A **Crop Consultant NPC** monitors fields and sends alerts when critical growth windows approach dangerous moisture levels. Integrates with `FS25_NPCFavor` when present.
5. Irrigation infrastructure has operational costs (electricity/diesel) tracked by `FS25_UsedPlus` when present.

### Design philosophy

> "Give players meaningful choices with real consequences. Every path has trade-offs."

- Full irrigation network = expensive, eliminates weather risk.
- Relying on rainfall = cheap, creates dramatic tension during dry seasons.
- Partial irrigation on high-value crops = strategic middle ground.

The player who ignores this system loses ~20–30% yield on stressed crops in a dry summer. The player who engages gets predictable, optimized harvests — but pays ongoing infrastructure and operational costs. Neither path dominates; both have seasons where they're right.

---

## 2. Source Material & Prior Art

### 2.1 FS25 Community LUADOC
- **URL:** https://github.com/umbraprior/FS25-Community-LUADOC
- **What it is:** 1,661 pages of Markdown documentation covering 11,102 FS25 Lua functions.
- **Rule:** Before implementing any call into the FS25 API, look it up here first. Do not guess function signatures.
- **Key namespaces for this mod:**
  - `g_currentMission.fieldManager` — enumerate, query, modify fields
  - `g_currentMission.environment` — weather, season, temperature
  - `g_currentMission.growthManager` — crop growth stages
  - `g_farmlandManager` — ownership, field IDs
  - `g_placeableManager` — register and manage placeables
  - `g_messageCenter` — event bus between mod systems
  - `g_gui` — dialogs and HUD elements
  - `g_inputBinding` — keyboard shortcut registration

### 2.2 FS25_UsedPlus AI Coding Reference
- **URL:** https://github.com/XelaNull/FS25_UsedPlus/tree/master/FS25_AI_Coding_Reference
- **Patterns to follow directly:**
  - Use `g_messageCenter:subscribe()` / `g_messageCenter:publish()` for all inter-system communication.
  - Always check `g_currentMission ~= nil` before accessing mission state. Store `self.isInitialized` and gate all logic behind it.
  - For save data, write a dedicated `<cropStress>` block in our sidecar XML. Never piggyback vanilla XML nodes.
  - Finance hooks: use `g_currentMission.missionInfo:updateFunds(amount, "OTHER", true)` for direct deductions. Route through `g_usedPlusManager:recordExpense()` when UsedPlus is present.

### 2.3 FS25_NPCFavor
- **URL:** https://github.com/TheCodingDad-TisonK/FS25_NPCFavor
- **Integration point:** When NPCFavor is active, `CropConsultant.lua` registers "Alex Chen, Agronomist" as a named NPC via `g_npcFavorSystem:registerExternalNPC(config)`. Before that integration fires, the HUD overlay is the only feedback mechanism.
- **Key lesson:** NPCFavor generates tasks at `relationship >= 25`. The consultant only starts sending proactive alerts once the player has visited the consultant's office placeable at least once.

### 2.4 FS25_UsedPlus (the mod itself)
- **Finance:** Route irrigation operational costs through `g_usedPlusManager:recordExpense("IRRIGATION", amount, {...})`.
- **Used equipment marketplace:** Irrigation pump units and center-pivot heads can appear as pre-owned items with wear states.
- **Vehicle DNA:** If a pump unit has high hours/wear via UsedPlus DNA, irrigation efficiency degrades. A worn pump delivers 80% of rated flow — subtle yield hits without explicit failure.

---

## 3. Technical Environment

| Item | Value |
|------|-------|
| Game | Farming Simulator 25 |
| Scripting language | Lua 5.1 (Giants custom runtime — no `goto`, no `continue`) |
| Key API surface | GIANTS Engine + FS25 game scripts |
| Save format | XML (savegameX/ sidecar file: `cropStressData.xml`) |
| Mod folder | `%USERPROFILE%\Documents\My Games\FarmingSimulator2025\mods\FS25_SeasonalCropStress\` |
| Game log | `%USERPROFILE%\Documents\My Games\FarmingSimulator2025\log.txt` |
| Target platforms | PC (primary), Console (secondary — no `io.open`, no sidecar files on console) |
| Multiplayer | Yes — moisture state synced server-authoritative every 10 in-game minutes |
| Build command | `bash build.sh --deploy` |

### Lua version constraints (Lua 5.1 sandbox)

- No `goto` / no labels
- No `continue` — use guard clauses or `if/else`
- No `io.popen`, no `os.execute`, no `os.time()`, no `os.date()`
- No `require` for external libraries
- Use `g_currentMission.time` and `g_currentMission.environment.currentDay` instead of `os.time()`
- `print()` → game `log.txt`. Use `g_logManager:devInfo("[CropStress]", message)` for structured output.

---

## 4. Repository & File Structure

```
FS25_SeasonalCropStress/
│
├── modDesc.xml                        ← Giants mod manifest (see Section 12)
├── main.lua                           ← Entry point + lifecycle hooks
├── CLAUDE.md                          ← Session collaboration rules (THIS file's companion)
├── FS25_SeasonalCropStress_ModPlan.md ← THIS document
├── icon.dds                           ← 512x512 mod icon
├── icon_small.dds                     ← 64x64 minimap/HUD icon
│
├── config/
│   └── cropStressDefaults.xml        ← Default per-crop thresholds, evaporation rates
│
├── src/
│   ├── CropStressManager.lua          ← Central coordinator (owns all subsystems)
│   ├── SoilMoistureSystem.lua         ← Per-field moisture state + evapotranspiration
│   ├── IrrigationManager.lua          ← Pivot/drip system registration + scheduling
│   ├── CropStressModifier.lua         ← Hooks growthManager, applies yield multipliers
│   ├── WeatherIntegration.lua         ← Subscribes to rain/temp events, updates moisture
│   ├── HUDOverlay.lua                 ← Field moisture HUD panel + forecast strip
│   ├── CropConsultant.lua             ← NPC alert system (standalone + NPCFavor bridge)
│   ├── NPCIntegration.lua             ← FS25_NPCFavor optional bridge
│   ├── FinanceIntegration.lua         ← FS25_UsedPlus optional bridge
│   └── SaveLoadHandler.lua            ← XML read/write for all persistent state
│
├── gui/
│   ├── FieldMoisturePanel.xml         ← HUD overlay layout
│   ├── FieldMoisturePanel.lua         ← HUD logic
│   ├── IrrigationScheduleDialog.xml   ← Irrigation scheduling UI layout
│   ├── IrrigationScheduleDialog.lua   ← Scheduling UI logic
│   └── CropConsultantDialog.xml       ← Consultant interaction UI
│
├── placeables/
│   ├── centerPivot/
│   │   ├── centerPivot.xml
│   │   ├── centerPivot.i3d
│   │   └── centerPivot.lua
│   ├── dripIrrigationLine/
│   │   ├── dripLine.xml
│   │   ├── dripLine.i3d
│   │   └── dripLine.lua
│   └── waterPump/
│       ├── waterPump.xml
│       ├── waterPump.i3d
│       └── waterPump.lua
│
├── vehicles/
│   └── irrigationPumpUnit/
│       ├── irrigationPump.xml
│       └── irrigationPump.lua
│
└── translations/
    ├── translation_en.xml
    ├── translation_de.xml
    ├── translation_fr.xml
    └── translation_nl.xml
```

**File size rule:** If any `.lua` file exceeds **1500 lines**, trigger an immediate refactor. Extract logical subsystems to new files, make the oversized file a coordinator. Update `main.lua` source order. Test thoroughly.

---

## 5. Core Systems Architecture

### Module loading order (main.lua)

`main.lua` uses `source()` to load in strict dependency order:

1. **Core Systems** — `SoilMoistureSystem.lua`, `WeatherIntegration.lua`
2. **Game Integration** — `CropStressModifier.lua`, `IrrigationManager.lua`
3. **Player-Facing** — `HUDOverlay.lua`, `CropConsultant.lua`
4. **Optional Bridges** — `NPCIntegration.lua`, `FinanceIntegration.lua`
5. **Persistence** — `SaveLoadHandler.lua`
6. **GUI** — `FieldMoisturePanel.lua`, `IrrigationScheduleDialog.lua`, `CropConsultantDialog.lua`
7. **Coordinator** — `CropStressManager.lua`

### Central coordinator

```
CropStressManager (g_cropStressManager)
  ├── soilSystem         : SoilMoistureSystem
  ├── irrigationManager  : IrrigationManager
  ├── stressModifier     : CropStressModifier
  ├── weatherIntegration : WeatherIntegration
  ├── hudOverlay         : HUDOverlay
  ├── consultant         : CropConsultant
  ├── npcIntegration     : NPCIntegration      (optional)
  ├── financeIntegration : FinanceIntegration  (optional)
  └── saveLoad           : SaveLoadHandler
```

Global reference: `g_cropStressManager`.

### Game hook pattern

All lifecycle hooks use `Utils.appendedFunction`:

| Hook | Purpose |
|------|---------|
| `Mission00.load` | Create `CropStressManager` instance |
| `Mission00.loadMission00Finished` | Initialize all systems, enumerate fields |
| `FSBaseMission.update` | Per-frame HUD update + hourly sim tick |
| `FSBaseMission.draw` | HUD rendering |
| `FSBaseMission.delete` | Cleanup + `unsubscribeAll` |
| `FSCareerMissionInfo.saveToXMLFile` | Save moisture/stress/schedule state |
| `Mission00.onStartMission` | Load saved state |
| `FSBaseMission.sendInitialClientState` | Multiplayer initial sync |
| `HarvestingMachine.doGroundWorkArea` | Intercept harvest fill → apply yield multiplier |

### Message bus (g_messageCenter)

All inter-system communication goes through `g_messageCenter`. Never call foreign system functions directly — this prevents crashes when optional mods are absent.

| Event | Publisher | Subscribers | Payload |
|-------|-----------|-------------|---------|
| `CS_MOISTURE_UPDATED` | SoilMoistureSystem | HUDOverlay, CropConsultant | `{fieldId, oldValue, newValue}` |
| `CS_STRESS_APPLIED` | CropStressModifier | HUDOverlay, FinanceIntegration | `{fieldId, cropType, multiplier}` |
| `CS_IRRIGATION_STARTED` | IrrigationManager | SoilMoistureSystem, FinanceIntegration | `{placeableId, fieldId, ratePerHour}` |
| `CS_IRRIGATION_STOPPED` | IrrigationManager | SoilMoistureSystem | `{placeableId, fieldId}` |
| `CS_CONSULTANT_ALERT` | CropConsultant | HUDOverlay, NPCIntegration | `{fieldId, severity, message}` |
| `CS_CRITICAL_THRESHOLD` | SoilMoistureSystem | CropConsultant | `{fieldId, cropType, moistureLevel}` |

---

## 6. System-by-System Implementation Guide

---

### 6.1 SoilMoistureSystem.lua

**Responsibility:** Maintain moisture (0.0–1.0) per field. Update hourly via rain events + evapotranspiration. Publish change events for HUD and consultant.

**Start of session planning dialog:**

---

**Claude** 🍵 *settles in with green tea*

SoilMoistureSystem is the load-bearing foundation. Everything else reads from it. My plan: initialize a `fieldMoistureData` table keyed by `fieldId` inside `loadedMission()` — never in module scope — run evapotranspiration hourly via `addUpdateable`, and subscribe to weather events for rain gains. Clean, readable, no frame-rate dependency.

---

**Samantha** 🌺 *leans forward over her "coffee: the original debug fluid" mug*

Agreed on the architecture. One UX thing I keep thinking about: the farmer loads an existing save and their fields are all at 50% because that's our default. That's going to feel wrong after a hot, dry in-game week they just lived through. Can we detect current season and temp on first load and backfill a plausible starting moisture?

---

**Claude** ☯️

Yes — a "hydration estimate on first load" pass. Check current season and last 3 forecast days of temperature, apply a scaled offset from 0.5. Sandy soil in summer starts at ~0.35; clay in spring starts at ~0.65. Flag `data.wasEstimated = true` so we don't overwrite actual saved values on reload.

---

**Samantha** 🦋

Perfect. That'll make the first play session feel alive instead of artificial. Do it.

---

#### Data model

```lua
-- Per-field state table, keyed by fieldId
self.fieldMoistureData = {}
-- {
--   fieldId = number,
--   moisture = float,        -- 0.0 to 1.0
--   soilType = string,       -- "sandy", "loamy", "clay"
--   lastUpdated = number,    -- game day
--   irrigationActive = bool,
--   wasEstimated = bool,     -- true if moisture was backfilled on first load
-- }
```

#### Initialization (MUST be in loadedMission, never modLoaded)

```lua
function SoilMoistureSystem:initialize()
    if g_currentMission == nil or g_currentMission.fieldManager == nil then return end

    self.fieldMoistureData = {}
    local fields = g_currentMission.fieldManager:getFields()  -- cache this, don't call every frame

    for _, field in ipairs(fields) do
        self.fieldMoistureData[field.fieldId] = {
            fieldId      = field.fieldId,
            moisture     = 0.5,
            soilType     = self:detectSoilType(field),
            lastUpdated  = g_currentMission.environment.currentDay,
            irrigationActive = false,
            wasEstimated = false,
        }
    end

    self:applyFirstLoadEstimate()
    self.isInitialized = true
end
```

#### Evapotranspiration (hourly)

```lua
function SoilMoistureSystem:hourlyUpdate()
    if not self.isInitialized then return end

    local temp   = g_currentMission.environment.weather:getCurrentTemperature()
    local season = g_currentMission.environment:currentSeason()  -- 0=spring 1=summer 2=autumn 3=winter

    for fieldId, data in pairs(self.fieldMoistureData) do
        local baseRate  = 0.004
        local tempMod   = 1.0 + math.max(0, (temp - 15) * 0.03)
        local seasonMod = ({[0]=0.8, [1]=1.4, [2]=0.9, [3]=0.2})[season] or 1.0
        local soilMod   = ({sandy=1.4, loamy=1.0, clay=0.7})[data.soilType] or 1.0

        local loss = baseRate * tempMod * seasonMod * soilMod
        local gain = 0
        if data.irrigationActive then
            gain = self:getIrrigationRate(fieldId)
        end

        local old = data.moisture
        data.moisture = math.max(0.0, math.min(1.0, data.moisture - loss + gain))

        g_messageCenter:publish(MessageType.CS_MOISTURE_UPDATED, {
            fieldId  = fieldId,
            oldValue = old,
            newValue = data.moisture,
        })

        -- Publish critical threshold event if needed
        if data.moisture < 0.25 then
            g_messageCenter:publish(MessageType.CS_CRITICAL_THRESHOLD, {
                fieldId      = fieldId,
                moistureLevel = data.moisture,
            })
        end
    end
end
```

#### Rain event handler

```lua
-- In initialize():
g_messageCenter:subscribe(MessageType.WEATHER_CHANGED, self.onWeatherChanged, self)

function SoilMoistureSystem:onWeatherChanged(data)
    -- NOTE: Verify exact MessageType name against LUADOC before shipping.
    if data.weatherType == "rain" or data.weatherType == "heavyRain" then
        local gainPerHour = 0.012 * (data.intensity or 1.0)
        for _, fieldData in pairs(self.fieldMoistureData) do
            fieldData.moisture = math.min(1.0, fieldData.moisture + gainPerHour * (data.durationHours or 1))
        end
    end
end
```

#### Soil type detection

```lua
function SoilMoistureSystem:detectSoilType(field)
    -- 1. Try map terrainDetailLayer metadata
    if g_currentMission.terrainDetailLayer ~= nil then
        -- Implementation depends on map; check LUADOC for getTerrainAttributeAtWorldPos
    end
    -- 2. Try Precision Farming soil map
    if g_precisionFarming ~= nil then
        -- PF exposes soil type per coordinate; use field center
    end
    -- 3. Safe default
    return "loamy"
end
```

#### Cleanup (CRITICAL — prevents reload crash)

```lua
function SoilMoistureSystem:delete()
    g_messageCenter:unsubscribeAll(self)
    self.isInitialized = false
end
```

---

### 6.2 IrrigationManager.lua

**Responsibility:** Track which irrigation placeables exist, which fields they cover, manage scheduling.

#### Data model

```lua
self.irrigationSystems = {}
-- Per system:
-- {
--   placeableId             = number,
--   type                    = "pivot" | "drip" | "sprinkler",
--   coveredFields           = {fieldId, ...},
--   waterSource             = "river" | "well" | "tank",
--   waterSourceEntityId     = number,
--   distanceToSource        = number,            -- meters
--   schedule                = {startHour=6, endHour=10, activeDays={bool x 7}},
--   isActive                = false,
--   flowRatePerHour         = 0.018,             -- moisture gain per covered field per in-game hour
--   pressureMultiplier      = 1.0,               -- degrades with pump distance (100% at 0m, 70% at 500m)
--   operationalCostPerHour  = 15.0,
--   wearLevel               = 0.0,               -- 0=new, 1=broken (UsedPlus integration)
-- }
```

#### Pressure-distance curve

Flow is not binary. Distance from pump to irrigation system degrades pressure linearly:

```lua
function IrrigationManager:calculatePressureMultiplier(distance)
    -- 100% at 0m, 70% at 500m, hard cutoff at 500m
    if distance > 500 then return 0.0 end
    return 1.0 - (distance / 500) * 0.3
end
```

#### Placeable registration

Called from placeable `onPostLoad` (defer via `addUpdateable` + init flag if field queries are needed):

```lua
function IrrigationManager:registerIrrigationSystem(placeable)
    local systemData = {
        placeableId            = placeable.id,
        type                   = placeable.customEnvironment,
        coveredFields          = self:detectCoveredFields(placeable),
        waterSource            = "tank",
        isActive               = false,
        flowRatePerHour        = self:calculateFlowRate(placeable),
        pressureMultiplier     = 1.0,
        operationalCostPerHour = self:calculateCost(placeable),
        wearLevel              = 0.0,
        schedule = {
            startHour  = 6,
            endHour    = 10,
            activeDays = {true, true, true, true, true, false, false},
        },
    }
    self.irrigationSystems[placeable.id] = systemData
end
```

#### Field coverage detection

**Note:** Giants engine uses X/Z for horizontal plane. Y is height. Always compare X and Z.

```lua
function IrrigationManager:detectCoveredFields(placeable)
    local covered = {}
    local x, _, z = placeable:getPosition()  -- X and Z are horizontal; Y is height
    local radius  = placeable.pivotRadius or 200

    local fields = g_currentMission.fieldManager:getFields()  -- use cached copy
    for _, field in ipairs(fields) do
        if self:fieldIntersectsCircle(field, x, z, radius) then
            table.insert(covered, field.fieldId)
        end
    end
    return covered
end
```

#### Scheduling engine

```lua
function IrrigationManager:hourlyScheduleCheck()
    local hour      = g_currentMission.environment:getHour()
    local dayOfWeek = g_currentMission.environment:getDayOfWeek()  -- 1–7

    for id, system in pairs(self.irrigationSystems) do
        local shouldBeActive = system.schedule.activeDays[dayOfWeek]
            and hour >= system.schedule.startHour
            and hour <  system.schedule.endHour

        if shouldBeActive and not system.isActive then
            self:activateSystem(id)
        elseif not shouldBeActive and system.isActive then
            self:deactivateSystem(id)
        end
    end
end

function IrrigationManager:activateSystem(id)
    local system = self.irrigationSystems[id]
    if not self:checkWaterAvailability(system) then return end

    system.isActive = true

    for _, fieldId in ipairs(system.coveredFields) do
        local effectiveRate = system.flowRatePerHour
            * system.pressureMultiplier
            * (1.0 - system.wearLevel * 0.3)  -- worn pump = reduced flow

        g_messageCenter:publish(MessageType.CS_IRRIGATION_STARTED, {
            placeableId = id,
            fieldId     = fieldId,
            ratePerHour = effectiveRate,
        })
    end
end
```

---

### 6.3 CropStressModifier.lua

**Responsibility:** Hook into FS25's harvest system and apply yield multipliers based on accumulated field stress.

#### Critical growth windows

```lua
local CRITICAL_WINDOWS = {
    wheat      = { stages = {3, 4},       criticalMoisture = 0.35, stressRatePerHour = 0.003 },
    corn       = { stages = {4, 5},       criticalMoisture = 0.40, stressRatePerHour = 0.004 },
    barley     = { stages = {3, 4},       criticalMoisture = 0.30, stressRatePerHour = 0.003 },
    canola     = { stages = {2, 3},       criticalMoisture = 0.45, stressRatePerHour = 0.005 },
    sunflower  = { stages = {3, 4},       criticalMoisture = 0.30, stressRatePerHour = 0.002 },
    soybeans   = { stages = {3, 4},       criticalMoisture = 0.40, stressRatePerHour = 0.004 },
    sugarbeet  = { stages = {2, 3, 4},    criticalMoisture = 0.50, stressRatePerHour = 0.005 },
    potato     = { stages = {2, 3, 4},    criticalMoisture = 0.55, stressRatePerHour = 0.006 },
}
```

#### Stress accumulation (hourly)

No `goto` — Lua 5.1. Use guard clauses:

```lua
function CropStressModifier:hourlyStressUpdate()
    for fieldId, moistureData in pairs(g_cropStressManager.soilSystem.fieldMoistureData) do
        local field = g_currentMission.fieldManager:getFieldByIndex(fieldId)
        if field == nil then return end  -- guard clause, not goto

        local fruitType = field:getFruitType()
        if fruitType == nil then return end

        local cropName = fruitType.name:lower()
        local window   = CRITICAL_WINDOWS[cropName]
        if window == nil then return end

        local growthStage = field:getGrowthState()
        local isInCriticalWindow = false
        for _, s in ipairs(window.stages) do
            if growthStage == s then
                isInCriticalWindow = true
                break
            end
        end

        if isInCriticalWindow and moistureData.moisture < window.criticalMoisture then
            local deficit       = window.criticalMoisture - moistureData.moisture
            local stressIncrease = window.stressRatePerHour * (deficit / window.criticalMoisture)

            self.fieldStress[fieldId] = math.min(1.0,
                (self.fieldStress[fieldId] or 0.0) + stressIncrease)

            g_messageCenter:publish(MessageType.CS_STRESS_APPLIED, {
                fieldId    = fieldId,
                cropType   = cropName,
                multiplier = 1.0 - self.fieldStress[fieldId],
            })
        end
    end
end
```

#### Yield modifier hook (harvest interception)

**This is the most technically complex part of the mod.** Use `appendedFunction` — never `overwrittenFunction` (two mods overwriting the same function breaks both):

```lua
-- In CropStressModifier:initialize()
HarvestingMachine.doGroundWorkArea = Utils.appendedFunction(
    HarvestingMachine.doGroundWorkArea,
    CropStressModifier.onDoGroundWorkArea
)

function CropStressModifier.onDoGroundWorkArea(harvestingMachine, workArea, dt)
    -- NOTE: Verify exact parameter names in HarvestingMachine LUADOC before implementing.
    -- Do not subtract from grain tanks after the fact — intercept fill amount here.
    local fieldId = workArea.fieldId  -- verify field lookup mechanism in LUADOC
    if fieldId == nil then return end

    local stress = g_cropStressManager.stressModifier.fieldStress[fieldId] or 0.0
    if stress <= 0.0 then return end

    -- Apply multiplier to the fill amount being calculated in this call
    -- Exact implementation depends on HarvestingMachine.doGroundWorkArea internals — check LUADOC
    local yieldReduction = stress * 0.6  -- max 60% yield loss at full stress
    -- workArea.fillDelta = workArea.fillDelta * (1.0 - yieldReduction)  -- verify property name

    -- Reset stress after field fully harvested
    g_cropStressManager.stressModifier.fieldStress[fieldId] = 0.0
end
```

---

### 6.4 WeatherIntegration.lua

**Responsibility:** Bridge between FS25 weather/environment system and mod moisture calculations. Poll temperature hourly (no event for temp); subscribe to weather change events for precipitation.

```lua
function WeatherIntegration:initialize()
    if g_currentMission == nil then return end

    g_messageCenter:subscribe(MessageType.WEATHER_CHANGED, self.onWeatherChanged, self)
    -- NOTE: Verify exact MessageType constant name in LUADOC

    self.lastKnownTemp   = 15
    self.lastKnownSeason = 0
    self.isInitialized   = true
end

function WeatherIntegration:hourlyPoll()
    if not self.isInitialized then return end
    local env = g_currentMission.environment
    self.lastKnownTemp    = env.weather:getCurrentTemperature()
    self.lastKnownSeason  = env:currentSeason()
    self.lastKnownHumidity = env.weather:getHumidity() or 0.5
end

function WeatherIntegration:onWeatherChanged(data)
    g_messageCenter:publish(MessageType.CS_WEATHER_FOR_MOISTURE, {
        weatherType   = data.weatherType,
        intensity     = data.intensity,
        durationHours = data.durationHours,
    })
end

-- 5-day moisture forecast (used by HUD forecast strip)
function WeatherIntegration:getMoistureForecast(fieldId, days)
    local forecast       = g_currentMission.environment.weather:getForecast()
    local currentMoisture = g_cropStressManager.soilSystem:getMoisture(fieldId)
    local projections    = {}

    for i = 1, days do
        local dayForecast  = forecast[i]
        local expectedRain = dayForecast and dayForecast.rainAmount or 0
        local expectedTemp = dayForecast and dayForecast.temperature or self.lastKnownTemp
        local evap = 0.004 * 24 * (1.0 + math.max(0, (expectedTemp - 15) * 0.03))
        currentMoisture = math.max(0, math.min(1.0, currentMoisture + expectedRain * 0.05 - evap))
        table.insert(projections, currentMoisture)
    end

    return projections
end

function WeatherIntegration:delete()
    g_messageCenter:unsubscribeAll(self)
end
```

---

### 6.5 HUDOverlay.lua

**Responsibility:** Render field moisture panel and 5-day forecast strip. Non-intrusive, dismissible.

**GUI rules (from CLAUDE.md):**
- Bottom-left origin. Y=0 at BOTTOM, increases UP.
- All coordinates normalized (0.0–1.0), never pixels — pixel coordinates break on different resolutions.
- No `Slider` widgets — unreliable events. Use `MultiTextOption` or quick buttons.
- Never name XML callbacks `onClose` / `onOpen` — system lifecycle conflict causes stack overflow.
- Dialog XML root MUST be `<GUI>`, never `<MessageDialog>`.
- Custom mod images: set dynamically via `setImageFilename()` in Lua — XML `imageFilename` can't load from ZIP.

#### Layout

Panel appears lower-left, above vanilla minimap:

```
┌─────────────────────────────────────┐
│  🌱 CROP MOISTURE MONITOR       [X] │
│                                     │
│  Field 7 — Wheat (Stage 4/6)       │
│  Moisture: ████████░░ 78%          │
│  Status: ✅ Healthy                 │
│                                     │
│  Field 3 — Corn (Stage 5/6) ⚠️     │
│  Moisture: ███░░░░░░░ 32%          │
│  Status: ⚠️ Drought Stress!        │
│                                     │
│  📅 5-Day Forecast (Field 7):      │
│  Mon Tue Wed Thu Fri               │
│  78% 72% 65% 58% 70%              │
│      ☁️  🌧️            🌧️          │
└─────────────────────────────────────┘
```

#### Toggle and auto-show

- **Shift+M** toggles manually.
- Auto-shows when player enters a field in a critical growth window with moisture below 50%.
- Auto-hides after 30 in-game minutes with no critical fields.

#### Draw loop

```lua
function HUDOverlay:draw()
    if not self.isVisible then return end

    self.panelElement:draw()

    for _, fieldEntry in ipairs(self.visibleFields) do
        local moisture = g_cropStressManager.soilSystem:getMoisture(fieldEntry.fieldId)
        local stress   = g_cropStressManager.stressModifier:getStress(fieldEntry.fieldId)
        local color    = self:getMoistureColor(moisture)
        self:drawMoistureBar(fieldEntry, moisture, color)

        if stress > 0.2 then
            self:drawStressWarning(fieldEntry, stress)
        end
    end

    if self.selectedFieldId ~= nil then
        local forecast = g_cropStressManager.weatherIntegration:getMoistureForecast(self.selectedFieldId, 5)
        self:drawForecast(forecast)
    end
end

function HUDOverlay:getMoistureColor(moisture)
    -- Green >0.6, Yellow 0.3–0.6, Red <0.3
    if moisture > 0.6 then return {0.2, 0.8, 0.2, 1.0} end
    if moisture > 0.3 then return {0.9, 0.8, 0.1, 1.0} end
    return {0.9, 0.2, 0.2, 1.0}
end
```

---

### 6.6 CropConsultant.lua

**Responsibility:** Generate player-facing alerts. Standalone mode = notification system. With NPCFavor = named NPC "Alex Chen."

#### Alert severity levels

| Level | Moisture | Duration |
|-------|----------|----------|
| INFO | 40–50% | 4s |
| WARNING | 25–40% | 6s |
| CRITICAL | <25% | 10s, red |

#### Standalone mode

```lua
function CropConsultant:initialize()
    g_messageCenter:subscribe(MessageType.CS_CRITICAL_THRESHOLD, self.onCriticalThreshold, self)
    self.alertCooldowns = {}
    self.isInitialized  = true
end

function CropConsultant:onCriticalThreshold(data)
    -- Cooldown: one alert per field per 12 in-game hours
    local now = g_currentMission.environment.currentDay * 24
              + g_currentMission.environment:getHour()

    local lastAlert = self.alertCooldowns[data.fieldId] or 0
    if (now - lastAlert) < 12 then return end
    self.alertCooldowns[data.fieldId] = now

    local severity = data.moistureLevel < 0.2 and "CRITICAL" or "WARNING"
    local msgKey   = severity == "CRITICAL" and "cs_alert_critical" or "cs_alert_warning"
    local msg      = string.format(g_i18n:getText(msgKey), data.fieldId, data.cropType or "crop")

    g_currentMission:showBlinkingWarning(msg, severity == "CRITICAL" and 10000 or 6000)

    g_messageCenter:publish(MessageType.CS_CONSULTANT_ALERT, {
        fieldId  = data.fieldId,
        severity = severity,
        message  = msg,
    })
end

function CropConsultant:delete()
    g_messageCenter:unsubscribeAll(self)
end
```

---

### 6.7 NPCIntegration.lua

**Responsibility:** Bridge with `FS25_NPCFavor` when loaded. Registers Alex Chen as a named NPC neighbor with consultant-specific favor types.

#### Runtime detection (never hard-code dependency)

```lua
function NPCIntegration:initialize()
    self.npcFavorActive = false

    if g_npcFavorSystem ~= nil then
        self.npcFavorActive = true
        self:registerConsultantNPC()
        g_logManager:devInfo("[CropStress]", "NPCFavor detected — registering Alex Chen")
    end
end

function NPCIntegration:registerConsultantNPC()
    -- Verify registerExternalNPC API against NPCFavor source before calling
    if g_npcFavorSystem.registerExternalNPC == nil then return end

    local config = {
        name             = "Alex Chen",
        title            = "Agronomist",
        personality      = "professional",
        homeFieldId      = nil,  -- lives at consultant office placeable
        schedule         = { workStart = 7, workEnd = 18 },
        relationshipStart = 10,
        onFavorGenerated = function(npc, favorType)
            return NPCIntegration:generateConsultantFavor(npc, favorType)
        end,
    }

    self.consultantNPCId = g_npcFavorSystem:registerExternalNPC(config)
end
```

#### Consultant-specific favor types

| Favor | Trigger | Task | Reward |
|-------|---------|------|--------|
| `SOIL_SAMPLE` | Field unvisited 10+ days | Visit field, press E | $200 + rel +5 |
| `IRRIGATION_CHECK` | Irrigation offline >2 days | Interact with system | $350 + rel +8 |
| `EMERGENCY_WATER` | Field <15% in critical stage | Irrigate before sundown | $500 + rel +12 |
| `SEASONAL_PLAN` | Start of new season | Open seasonal planning dialog | $150 + rel +3 |

The consultant only starts sending proactive alerts after `relationship >= 25`, which requires the player to have first visited the consultant's office placeable.

---

### 6.8 FinanceIntegration.lua

**Responsibility:** Track irrigation operational costs. Route through UsedPlus expense system when present; fall back to direct fund deduction otherwise.

```lua
function FinanceIntegration:initialize()
    self.usedPlusActive = false

    if g_usedPlusManager ~= nil then
        self.usedPlusActive = true
        g_logManager:devInfo("[CropStress]", "UsedPlus detected — routing irrigation costs")
    end

    g_messageCenter:subscribe(MessageType.CS_IRRIGATION_STARTED, self.onIrrigationStarted, self)
    g_messageCenter:subscribe(MessageType.CS_IRRIGATION_STOPPED, self.onIrrigationStopped, self)
    self.isInitialized = true
end

function FinanceIntegration:chargeHourlyCosts()
    for id, system in pairs(g_cropStressManager.irrigationManager.irrigationSystems) do
        if not system.isActive then
            -- guard clause: skip inactive systems
        else
            local cost = system.operationalCostPerHour

            if self.usedPlusActive and g_usedPlusManager.recordExpense ~= nil then
                g_usedPlusManager:recordExpense("IRRIGATION", cost, {
                    description = string.format("Irrigation %d — %d fields", id, #system.coveredFields),
                    category    = "OPERATIONAL",
                })
            else
                g_currentMission.missionInfo:updateFunds(-cost, "OTHER", true)
            end
        end
    end
end

function FinanceIntegration:getEquipmentWearLevel(vehicleId)
    if not self.usedPlusActive then return 0.0 end
    if g_usedPlusManager.getVehicleDNA == nil then return 0.0 end

    local dna = g_usedPlusManager:getVehicleDNA(vehicleId)
    if dna == nil then return 0.0 end

    -- UsedPlus DNA reliability: 0.6–1.4 multiplier
    -- reliability 0.6 = 40% worn, reliability 1.4 = 0% worn
    return math.max(0.0, (1.4 - dna.reliability) / 0.8)
end

function FinanceIntegration:delete()
    g_messageCenter:unsubscribeAll(self)
end
```

---

## 7. GUI Design

### 7.1 Irrigation Schedule Dialog

Opened by pressing `E` near an irrigation system or `Shift+I`.

**GUI construction rules:** Copy `TakeLoanDialog.xml` structure. X positions are center-relative. Y is negative going down from top of dialog content container. Use `buttonActivate` profile, not `fs25_buttonSmall`. Add 10–15px padding to section heights.

```
┌─────────────────────────────────────────────┐
│  CENTER PIVOT — Fields 3, 5, 7             │
│  Water Source: River (✅ Connected)         │
├─────────────────────────────────────────────┤
│  SCHEDULE                                   │
│  Active Days: [M✓][T✓][W✓][T✓][F✓][S ][S ]│
│  Start Time:  [06:00 ▼]                    │
│  End Time:    [10:00 ▼]                    │
│                                             │
│  PERFORMANCE                                │
│  Flow Rate:   18mm/hr    Efficiency: 94%   │
│  Est. Cost:   $15/hr     ($120/cycle)      │
│  Wear Level:  ████░░░░░░ 45%              │
│                                             │
│  COVERED FIELDS                             │
│  Field 3 (Wheat, Stage 4) — 62% moisture  │
│  Field 5 (Corn, Stage 5)  — 28% moisture ⚠│
│  Field 7 (Barley, Stage 3)— 71% moisture  │
│                                             │
│         [IRRIGATE NOW]    [SAVE SCHEDULE]   │
└─────────────────────────────────────────────┘
```

**Note on time dropdowns:** Do not use `Slider` — unreliable in FS25. Use `MultiTextOption` elements with `setTexts()` called from Lua (not via XML `<texts>` children).

### 7.2 Field Detail Overlay

Triggered by pressing `E` while standing in a field (no irrigation equipment nearby):

```
┌─────────────────────────────┐
│  FIELD 5 — CORN (Stage 5)  │
│  Soil Type: Sandy Loam      │
│  Moisture: 28% ⚠️ LOW       │
│  Stress Accumulated: 12%    │
│  Est. Yield Impact: -8%     │
│                             │
│  Critical Window: NOW       │
│  (Stages 4-5 = silking)    │
│                             │
│  Nearest Water: 340m NW     │
│  [PLACE IRRIGATION]         │
└─────────────────────────────┘
```

---

## 8. Placeables: Irrigation Infrastructure

### 8.1 Center Pivot

Large rotating arm, covers circular area (radius 100–350m configurable). Highest throughput.

```xml
<placeable type="irrigationPivot">
    <pivotArm radius="200" rotationSpeed="0.5"/>
    <waterConsumption rateM3PerHour="150"/>
    <electricalConsumption kWhPerHour="45"/>
    <price value="85000"/>
    <maintenanceCostPerDay value="25"/>
</placeable>
```

**Specialization hooks:** `onLoad` → register with IrrigationManager. `onDelete` → deregister. `onUpdate` → animate arm when active. `onWriteStream` / `onReadStream` → sync active state in multiplayer.

**Note:** Use `parent="base"` in specialization specs, NOT `parent="handTool"` — game prefixes mod name and breaks it.

### 8.2 Drip Irrigation Line

Ground-level drip tape covering rectangular segments. Lower throughput, more precise. Better for orchards and sugar beet.

Placement: player sets start/end markers. Mod calculates linear coverage and field polygon overlap. Multiple lines per field supported.

### 8.3 Water Pump Unit

Stationary pump, draws from river/pond/tank. Supplies all irrigation systems within 500m. Player connects/disconnects systems via proximity `E` interaction. Flow pressure degrades linearly with distance (100% at 0m → 70% at 500m → 0% beyond 500m).

---

## 9. Save / Load System

**One of the most important systems to get right.** Console note: sidecar file creation is restricted on Xbox/PS5. Only use the `xmlFile` handle provided by game save callbacks — never `io.open`.

### Sidecar file

`{savegameDirectory}/cropStressData.xml` — per-field moisture, stress accumulation, irrigation schedules.

### SaveLoadHandler.lua

```lua
function SaveLoadHandler:saveToXML(xmlFile, baseKey)
    local csKey = baseKey .. ".cropStress"
    local i = 0

    -- Save soil moisture per field
    for fieldId, data in pairs(g_cropStressManager.soilSystem.fieldMoistureData) do
        local key = string.format("%s.field(%d)", csKey, i)
        setXMLInt(xmlFile, key .. "#fieldId", fieldId)        -- ALWAYS use matching type pairs
        setXMLFloat(xmlFile, key .. "#moisture", data.moisture)
        setXMLString(xmlFile, key .. "#soilType", data.soilType)
        i = i + 1
    end

    -- Save stress accumulation per field
    i = 0
    for fieldId, stress in pairs(g_cropStressManager.stressModifier.fieldStress) do
        local key = string.format("%s.stress(%d)", csKey, i)
        setXMLInt(xmlFile, key .. "#fieldId", fieldId)
        setXMLFloat(xmlFile, key .. "#value", stress)
        i = i + 1
    end

    -- Save irrigation schedules
    i = 0
    for sysId, system in pairs(g_cropStressManager.irrigationManager.irrigationSystems) do
        local key = string.format("%s.irrigation(%d)", csKey, i)
        setXMLInt(xmlFile, key .. "#id", sysId)
        setXMLInt(xmlFile, key .. "#schedStart", system.schedule.startHour)
        setXMLInt(xmlFile, key .. "#schedEnd", system.schedule.endHour)
        setXMLString(xmlFile, key .. "#activeDays", table.concat(system.schedule.activeDays, ","))
        i = i + 1
    end
end

function SaveLoadHandler:loadFromXML(xmlFile, baseKey)
    local csKey = baseKey .. ".cropStress"
    local i = 0

    while true do
        local key     = string.format("%s.field(%d)", csKey, i)
        local fieldId = getXMLInt(xmlFile, key .. "#fieldId")  -- returns nil if absent, not 0
        if fieldId == nil then break end

        local moisture = getXMLFloat(xmlFile, key .. "#moisture") or 0.5
        local soilType = getXMLString(xmlFile, key .. "#soilType") or "loamy"

        if g_cropStressManager.soilSystem.fieldMoistureData[fieldId] ~= nil then
            g_cropStressManager.soilSystem.fieldMoistureData[fieldId].moisture    = moisture
            g_cropStressManager.soilSystem.fieldMoistureData[fieldId].soilType    = soilType
            g_cropStressManager.soilSystem.fieldMoistureData[fieldId].wasEstimated = false
        end

        i = i + 1
    end
    -- Similar loops for stress and irrigation...
end
```

---

## 10. Multiplayer Considerations

Moisture changes every in-game hour. Streaming this constantly would be expensive. Strategy: server-authoritative simulation, client sync every 10 in-game minutes.

- **Server only** runs the moisture simulation tick.
- **Clients** receive moisture state via `writeStream` / `readStream`.
- **Irrigation activation** is synced immediately when triggered.
- **HUD forecast** is calculated locally on each client (uses synced moisture + local weather data — weather is already synced by vanilla FS25).
- Use `g_server ~= nil` to detect server/single-player mode.

### Stream protocol

**CRITICAL:** Read and write values in the EXACT same order. A single mismatch corrupts all subsequent values silently.

```lua
function CropStressManager:onWriteStream(streamId, connection)
    local fields = g_currentMission.fieldManager:getFields()
    streamWriteInt32(streamId, #fields)

    for _, field in ipairs(fields) do
        local data = self.soilSystem.fieldMoistureData[field.fieldId]
        streamWriteInt32(streamId, field.fieldId)
        streamWriteFloat(streamId, data and data.moisture or 0.5)
        streamWriteFloat(streamId, self.stressModifier.fieldStress[field.fieldId] or 0.0)
    end
end

function CropStressManager:onReadStream(streamId, connection)
    local count = streamReadInt32(streamId)
    for _ = 1, count do
        local fieldId = streamReadInt32(streamId)
        local moisture = streamReadFloat(streamId)
        local stress   = streamReadFloat(streamId)

        if self.soilSystem.fieldMoistureData[fieldId] ~= nil then
            self.soilSystem.fieldMoistureData[fieldId].moisture = moisture
        end
        self.stressModifier.fieldStress[fieldId] = stress
    end
end
```

---

## 11. Cross-Mod Integration Layer

Always detect at runtime. Never hard-code a dependency. The mod must function correctly with none, some, or all optional mods present.

```lua
function CropStressManager:detectOptionalMods()
    if g_usedPlusManager ~= nil and g_usedPlusManager.VERSION ~= nil then
        g_logManager:devInfo("[CropStress]", "FS25_UsedPlus v" .. tostring(g_usedPlusManager.VERSION))
        self.financeIntegration:enableUsedPlusMode()
    end

    if g_npcFavorSystem ~= nil then
        g_logManager:devInfo("[CropStress]", "FS25_NPCFavor detected")
        self.npcIntegration:enableNPCFavorMode()
    end

    if g_precisionFarming ~= nil then
        g_logManager:devInfo("[CropStress]", "Precision Farming DLC detected")
        self:enablePrecisionFarmingCompat()
    end
end
```

### Precision Farming DLC compatibility

When PF is active:
- Read PF soil sample data to set per-field `soilType` more accurately (overrides the generic `detectSoilType` fallback).
- Display moisture overlay on the PF soil analysis map screen.

---

## 12. modDesc.xml Specification

```xml
<?xml version="1.0" encoding="utf-8" standalone="no"?>
<modDesc descVersion="72">
    <author>YourNameHere</author>
    <version>1.0.0.0</version>
    <title>
        <en>Seasonal Crop Stress &amp; Irrigation Manager</en>
        <de>Saisonaler Pflanzenstress &amp; Bewässerungsmanager</de>
    </title>
    <description>
        <en><![CDATA[
Adds soil moisture tracking and crop stress simulation to FS25.
Fields without rain or irrigation suffer yield losses.
Place center-pivot or drip irrigation systems to protect crops.
Optional integration with FS25_NPCFavor and FS25_UsedPlus.
        ]]></en>
    </description>

    <multiplayer supported="true"/>
    <iconFilename>icon.dds</iconFilename>

    <extraSourceFiles>
        <sourceFile filename="main.lua"/>
        <sourceFile filename="src/SoilMoistureSystem.lua"/>
        <sourceFile filename="src/WeatherIntegration.lua"/>
        <sourceFile filename="src/CropStressModifier.lua"/>
        <sourceFile filename="src/IrrigationManager.lua"/>
        <sourceFile filename="src/HUDOverlay.lua"/>
        <sourceFile filename="src/CropConsultant.lua"/>
        <sourceFile filename="src/NPCIntegration.lua"/>
        <sourceFile filename="src/FinanceIntegration.lua"/>
        <sourceFile filename="src/SaveLoadHandler.lua"/>
        <sourceFile filename="src/CropStressManager.lua"/>
        <sourceFile filename="gui/FieldMoisturePanel.lua"/>
        <sourceFile filename="gui/IrrigationScheduleDialog.lua"/>
        <sourceFile filename="gui/CropConsultantDialog.lua"/>
    </extraSourceFiles>

    <inputBinding>
        <actionBinding action="CS_TOGGLE_HUD">
            <binding device="KB_MOUSE_DEFAULT" input="KEY_lshift KEY_m"/>
        </actionBinding>
        <actionBinding action="CS_OPEN_IRRIGATION">
            <binding device="KB_MOUSE_DEFAULT" input="KEY_lshift KEY_i"/>
        </actionBinding>
    </inputBinding>

    <actions>
        <action name="CS_TOGGLE_HUD"      axisType="HALF_POSITIVE_AXIS" isSink="true"/>
        <action name="CS_OPEN_IRRIGATION" axisType="HALF_POSITIVE_AXIS" isSink="true"/>
    </actions>

    <placeableTypes>
        <placeableType name="irrigationPivot" parent="simplePlaceable"
            filename="placeables/centerPivot/centerPivot.lua"/>
        <placeableType name="irrigationDrip" parent="simplePlaceable"
            filename="placeables/dripIrrigationLine/dripLine.lua"/>
        <placeableType name="waterPump" parent="simplePlaceable"
            filename="placeables/waterPump/waterPump.lua"/>
    </placeableTypes>

    <l10n filenamePrefix="translations/translation"/>
</modDesc>
```

---

## 13. Configuration File Specification

`{savegameDirectory}/cropStressConfig.xml` — created on first load:

```xml
<?xml version="1.0" encoding="utf-8"?>
<cropStressConfig version="1">
    <simulation
        enableMoistureSystem="true"
        enableStressModifier="true"
        enableConsultantAlerts="true"
        updateIntervalHours="1"
    />
    <hud
        visible="true"
        showForecast="true"
        maxFieldsShown="5"
        autoShowOnCritical="true"
        positionX="0.01"
        positionY="0.15"
    />
    <difficulty
        maxYieldLoss="0.60"
        stressMultiplier="1.0"
        evaporationMultiplier="1.0"
        rainAbsorptionMultiplier="1.0"
    />
    <alerts
        warningThreshold="0.35"
        criticalThreshold="0.20"
        consultantCooldownHours="12"
    />
</cropStressConfig>
```

---

## 14. Localization

Never hardcode English strings in Lua. All user-facing strings go in translation XML files and are referenced via `g_i18n:getText("key")`.

```xml
<!-- translations/translation_en.xml -->
<l10n>
    <text name="cs_hud_title"         text="Crop Moisture Monitor"/>
    <text name="cs_hud_healthy"       text="Healthy"/>
    <text name="cs_hud_warning"       text="Drought Stress!"/>
    <text name="cs_hud_critical"      text="CRITICAL — Irrigate Now!"/>
    <text name="cs_hud_forecast"      text="5-Day Forecast"/>
    <text name="cs_alert_warning"     text="Field %d: %s moisture low — irrigation recommended."/>
    <text name="cs_alert_critical"    text="Field %d: %s at drought stress threshold — irrigate NOW!"/>
    <text name="cs_irr_title"         text="Irrigation System — %s"/>
    <text name="cs_irr_schedule"      text="Schedule"/>
    <text name="cs_irr_irrigate_now"  text="Irrigate Now"/>
    <text name="cs_irr_save_schedule" text="Save Schedule"/>
    <text name="cs_irr_flow_rate"     text="Flow Rate"/>
    <text name="cs_irr_efficiency"    text="Efficiency"/>
    <text name="cs_irr_cost"          text="Est. Cost"/>
    <text name="cs_irr_wear"          text="Wear Level"/>
    <text name="cs_field_detail"      text="Field %d — %s (Stage %d)"/>
    <text name="cs_field_soil_type"   text="Soil Type"/>
    <text name="cs_field_moisture"    text="Moisture"/>
    <text name="cs_field_stress"      text="Stress Accumulated"/>
    <text name="cs_field_yield_impact" text="Est. Yield Impact"/>
    <text name="cs_consultant_name"   text="Alex Chen, Agronomist"/>
    <text name="cs_favor_soil_sample" text="Take a soil sample from Field %d"/>
    <text name="cs_favor_irr_check"   text="Inspect the irrigation system on Field %d"/>
    <text name="cs_favor_emergency"   text="Irrigate Field %d before sundown!"/>
</l10n>
```

---

## 15. Testing Strategy

FS25 has no formal test framework. Use console commands for debug control.

### Console commands (`csHelp` in developer console)

```lua
-- Register in main.lua
if g_addTestCommands ~= nil then
    addConsoleCommand("csStatus",       "Print full system status",              "debugPrintStatus",   g_cropStressManager)
    addConsoleCommand("csSetMoisture",  "Set field moisture (fieldId, 0.0–1.0)", "debugSetMoisture",   g_cropStressManager)
    addConsoleCommand("csForceStress",  "Force max stress on field (fieldId)",   "debugForceStress",   g_cropStressManager)
    addConsoleCommand("csSimulateHeat", "Simulate heat wave for N days",          "debugSimulateHeat",  g_cropStressManager)
    addConsoleCommand("csDebug",        "Toggle verbose logging",                 "debugToggleVerbose", g_cropStressManager)
end
```

### Mandatory test scenarios

Every phase release must pass all applicable scenarios:

1. **New game start** — all fields init to 50% moisture (or season-adjusted estimate), no log errors.
2. **Save and reload** — moisture values, stress accumulation, and irrigation schedules persist exactly.
3. **Full season without irrigation** — rain raises moisture, heat drains it, dry season triggers consultant alerts.
4. **Place and activate center pivot** — moisture on covered fields rises; operational costs are charged.
5. **Harvest stressed field** — use `csForceStress <fieldId>` to set up test; yield visibly lower.
6. **Load WITH NPCFavor** — Alex Chen appears, favors generate correctly, no errors.
7. **Load WITH UsedPlus** — irrigation costs appear in finance manager, pump wear reduces flow rate.
8. **Load WITHOUT either optional mod** — standalone mode works, no nil access errors.
9. **Multiplayer: client joins** — client receives correct moisture state, HUD shows accurate data.
10. **Console platform check** — no `io.open` calls in any save/load path.

---

## 16. Known FS25 Lua Pitfalls

Read all of these before starting any session. They are compiled from CLAUDE.md, the UsedPlus AI Coding Reference, and NPCFavor development experience.

| Pitfall | Problem | Fix |
|---------|---------|-----|
| `g_currentMission` in mod load scope | Is nil during `modLoaded()` | Wait for `loadedMission()` callback. Always gate with `if g_currentMission == nil then return end`. |
| `goto` / `continue` | Not in Lua 5.1 | Use `if/else` or early `return` guard clauses. |
| `os.time()` / `os.date()` | Not available in FS25 sandbox | Use `g_currentMission.time` / `.environment.currentDay`. |
| `appendedFunction` vs `overwrittenFunction` | Two mods overwriting same function breaks both | Use `appendedFunction` wherever possible. |
| X/Y vs X/Z coordinates | Giants horizontal plane is X/Z, not X/Y | Y is height. When checking field positions, compare X and Z. |
| `setXMLFloat` / `getXMLFloat` type mismatch | Silent data corruption | Always use matching getter/setter type pairs. |
| `getXMLInt` absent key | Returns nil, not 0 | Always use `or` fallback: `getXMLInt(file, key) or 0`. |
| Missing `unsubscribeAll` in `delete()` | Crash when reloading save without restarting FS25 | `g_messageCenter:unsubscribeAll(self)` in every system's `delete()`. |
| `ipairs` vs `pairs` | Wrong iterator for table type = silent misses | `ipairs` for sequential arrays; `pairs` for keyed/sparse tables. |
| Stream read/write order mismatch | Silent data corruption in multiplayer | Read and write values in EXACTLY the same order. |
| `getFields()` called every frame | Performance cost | Cache result once at init; refresh only on field buy/sell events. |
| Placeable `onPostLoad` timing | Entity not fully in world yet | Defer field queries via `addUpdateable` + deferred init flag. |
| HUD pixel coordinates | Break on non-standard resolutions | Use normalized 0.0–1.0 screen coordinates. |
| Console file I/O | `io.open` restricted on Xbox/PS5 | Only use the `xmlFile` handle from game save callbacks. |
| `Slider` widget | Unreliable events in FS25 | Use `MultiTextOption` or quick buttons. |
| Dialog XML `onClose` / `onOpen` callbacks | System lifecycle conflict → stack overflow | Use different callback names (e.g., `onDialogClose`, `onDialogOpen`). |
| Dialog XML root wrong | `<MessageDialog>` deprecated | Root MUST be `<GUI>`. |
| XML `imageFilename` for mod images | Can't load from ZIP | Set dynamically via `setImageFilename()` in Lua. |
| `MapHotspot` base class | Abstract, no icon = invisible markers | Use `PlaceableHotspot.new()` + `Overlay.new()`. |
| `parent="handTool"` in specs | Game prefixes mod name | Use `parent="base"`. |
| `setTextColorByName()` | Doesn't exist in FS25 | Use `setTextColor(r, g, b, a)`. |
| PowerShell `Compress-Archive` for build | Creates backslash paths in ZIP | Use `bash build.sh --deploy`. |
| `MultiTextOption` texts in XML | `<texts>` children ignored | Set via `setTexts()` in Lua after creation. |

---

## 17. Phased Release Plan

### Phase 1 — Core (MVP)

- SoilMoistureSystem (evaporation + rain + first-load estimate)
- CropStressModifier (yield reduction hook)
- WeatherIntegration
- HUDOverlay (basic, no forecast)
- SaveLoadHandler
- Console debug commands
- Config file with difficulty sliders

**Session dialog pattern for Phase 1:**

---

**Claude** 🍵

Phase 1 is done. SoilMoistureSystem initializes cleanly, evapotranspiration runs hourly, rain events update moisture, harvest hook applies stress multiplier, HUD shows field states, save/load round-trips correctly. Ran all 5 applicable test scenarios — clean. Ready for your review.

---

**Samantha** 🌸 *peers at the HUD screenshot, tucks a strand of hair back*

The moisture bars look great. One thing — what does a new player see the very first time they open the HUD? Is there a zero state or does it feel empty and broken?

---

**Claude** ☯️

Good catch. Right now it shows all fields at 50% with no context. I should add a "No critical fields — all crops healthy" empty state message, and maybe a one-time tooltip explaining what the bar means.

---

**Samantha** 💕

Yes. Don't ship without that. Add it before we close Phase 1.

---

### Phase 2 — Irrigation

- Water Pump placeable (with pressure-distance curve)
- Center Pivot placeable + animation
- IrrigationManager (manual activation only)
- Irrigation Schedule Dialog
- Irrigation cost deduction (vanilla, no UsedPlus)

### Phase 3 — NPC & Social

- CropConsultant alerts (standalone mode)
- NPCIntegration.lua (NPCFavor bridge, Alex Chen)
- Consultant-specific favor types
- Full HUD with 5-day forecast strip

### Phase 4 — Finance & Polish

- FinanceIntegration.lua (UsedPlus bridge)
- Drip irrigation placeable
- Equipment wear degradation via UsedPlus DNA
- Used equipment marketplace entries
- Precision Farming DLC soil overlay compat
- Full translation (EN, DE, FR, NL, PL)

### Phase 5 — Stability & HUD Polish

**Goal:** Close the gap between code-complete and player-verified. No new features — only hardening, persistence, and translation.

- **HUD position persistence** — `panelX`/`panelY` saved to `cropStressSettings.xml`; restored on load via `applySettings()`
- **Full in-game verification** — run through every `[ ]` test scenario from Phases 1–4 in DEVELOPMENT.md
- **Polish translation** — `translation_pl.xml` (all `cs_*` keys)
- HUD UX improvements based on live playtest feedback

**Session dialog pattern for Phase 5:**

---

**Claude** 🍵 *opens DEVELOPMENT.md test checklist*

Phase 5 is the verification pass. I'm going to load ElmCreek, run through all the `[ ]` test items in sequence, document the results, and tick them off. Starting with Phase 1 tests — does `csSetMoisture` actually force a value, and does the forecast stay within 0–1?

---

**Samantha** 🌸 *glances over the rim of her glasses, coffee mug reading "{ } world"*

Before you start ticking off tests — what happens if a player drag-repositions the HUD and then loads a different savegame? Does the position reset or persist? Because right now we save it in-session but not to disk.

---

**Claude** ☯️

Good catch. Position should persist per-savegame. That means saving `panelX`/`panelY` in `cropStressSettings.xml`, not just in-memory. That's the first Phase 5 code item — before I run the test suite.

---

**Samantha** 💕

That's the right order. Get that in first. Then test.

---

### Phase 6 — Release Readiness

**Goal:** Ship a polished v1.0.0.0 that players can trust.

- **Final 3D assets** — center pivot (arm rotation, proper LOD nodes), water pump (textured model)
- **Mod icon** (`icon.dds`) — replace placeholder with proper 512×512 icon
- **v1.0.0.0 changelog** — feature list, known limitations, required FS25 version, optional mod compatibility
- **Git release tag** — `v1.0.0.0`
- **Steam Workshop listing** — title, description, screenshots, required/optional mods
- Post-launch monitoring (player log reports, first 2 weeks)

**Gate criteria (must all pass before tagging v1.0.0.0):**
1. All Phase 5 in-game tests passing
2. Zero log errors on TestMap and ElmCreek clean load
3. Zero log errors on save/reload cycle
4. ZIP installs cleanly from scratch (no existing save data)
5. Final 3D assets in place (no placeholder geometry)
6. All translation keys present in EN, DE, FR, NL, PL

---

## 18. Credits & Acknowledgements

- **umbraprior** — FS25 Community LUADOC (https://github.com/umbraprior/FS25-Community-LUADOC) — 11,102 documented functions; the single most important resource for any FS25 mod.
- **XelaNull** — FS25_UsedPlus AI Coding Reference and mod (https://github.com/XelaNull/FS25_UsedPlus) — finance architecture and the pitfall catalog in Section 16 are directly inspired by this work.
- **Lion2008** (original idea) and **tisonK / TheCodingDad** (implementation) — FS25_NPCFavor (https://github.com/TheCodingDad-TisonK/FS25_NPCFavor) — NPC architecture model for the CropConsultant system.
- **Giants Software** — Farming Simulator 25 and the modding framework.

---

*Plan version 2.0 — Revised to reflect CLAUDE.md collaboration model, Lua 5.1 constraints, GUI system rules, and all lessons learned. Start at Section 6.1 and work sequentially. When in doubt, check the LUADOC first. When making decisions, check with Samantha first.*