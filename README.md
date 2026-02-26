# FS25_SeasonalCropStress

![GitHub Downloads](https://img.shields.io/github/downloads/TheCodingDad-TisonK/FS25_SeasonalCropStress/total?style=flat-square&color=brightgreen)
![GitHub Release](https://img.shields.io/github/v/release/TheCodingDad-TisonK/FS25_SeasonalCropStress?style=flat-square&color=blue)
![License](https://img.shields.io/badge/license-All%20Rights%20Reserved-red?style=flat-square)

> *"I planted wheat in June and had a perfect field by August — until I didn't. Three days without rain during heading and I lost 40% of my yield. Never ignored the moisture gauge again."*
> — Beta tester, Season 2 playthrough

---

FS25 farms look lush even when your crops are quietly dying of thirst. This mod changes that.

**Seasonal Crop Stress & Irrigation Manager** adds real soil moisture physics to every field on your farm. Rain replenishes. Heat evaporates. Sandy soil drains fast; clay holds longer. When moisture drops below critical thresholds during the growth windows that matter most — wheat during heading, corn during pollination — stress accumulates and your yield shrinks. Place a center-pivot irrigator, schedule it, and protect what you've grown. Play it right and your harvest beats vanilla. Ignore it and you'll wonder why your combines are running light.

Phases 1–3 are complete. Phase 4 (Finance & Polish) is in active development. Phases 5–6 (Stability, HUD polish, and release readiness) are planned.

---

## ✨ Features

### Phase 1 — Soil Moisture & Crop Stress ✅ Live

- Per-field soil moisture simulation (0–100%) driven by real in-game weather
- Seasonal evapotranspiration: heat accelerates moisture loss, cold slows it
- Soil type modifiers: sandy drains 40% faster, clay retains 30% longer, loam is baseline
- Season-aware field initialization — fields don't all start at 50% on day one
- Crop-specific critical growth windows for 8 crops: wheat, barley, corn, canola, sunflower, soybeans, sugar beet, potato
- Yield stress accumulates during critical windows when moisture falls below crop thresholds
- Harvest yield reduction — up to **60% loss** at maximum stress
- **Field Moisture HUD** overlay (press `Shift+M`) — color-coded bars for every active field
- Click any field row in the HUD to see its **5-day moisture forecast** strip
- Color-coded moisture indicators: green (healthy) → yellow (warning) → red (critical)
- Auto-show HUD when a field reaches critical drought threshold
- First-run welcome notification so you know the mod is active
- Full save/load persistence — all field moisture and stress state survives session restarts
- Developer console commands (`csHelp` in the `~` console)

### Phase 2 — Irrigation Infrastructure ✅ Live

- **Center Pivot Irrigator** placeable — circular field coverage up to 200m radius
- **Water Pump** placeable — place near any water source; auto-connects to pivots within 500m
- Pressure curve: flow degrades linearly from 100% at 0m to 70% at 500m; zero beyond
- **Irrigation Schedule Dialog** (press `E` near a pivot, or `Shift+I`) — set active days, start/end hour, view covered fields and flow rate
- "Irrigate Now" button for immediate manual activation
- Operational costs charged to farm account each active hour
- Irrigation schedule persists across saves and reloads
- Equipment wear level tracked (used in Phase 4 UsedPlus integration)

### Phase 3 — Crop Consultant ✅ Live

- **Alert system**: three severity levels fire as moisture drops
  - INFO (40–50%): *"Field X getting dry — monitor conditions"* — 4s notification
  - WARNING (25–40%): *"Field X moisture low — irrigation recommended"* — 6s notification
  - CRITICAL (<25%): *"Field X at drought threshold — irrigate NOW!"* — 10s notification
- 12-in-game-hour cooldown per field per severity to prevent spam
- **Crop Consultant dialog** (`Shift+C` or `csConsultant` console command) — top 5 fields by risk, recommended actions, 3-day forecast
- Optional **FS25_NPCFavor integration**: Alex Chen, Agronomist NPC — generates favor quests (SOIL_SAMPLE, IRRIGATION_CHECK, EMERGENCY_WATER, SEASONAL_PLAN) and routes alerts through NPC dialog

### Settings System ✅ Live

A full in-game settings system lets you tune the simulation without editing files:

- **ESC → Settings → Game Settings** — scroll to the "Seasonal Crop Stress" section
- **Enable/disable the mod** at any time without uninstalling
- **Difficulty** (Easy / Normal / Hard) — scales stress accumulation rate and evaporation speed
- **Evaporation Rate** (Slow / Normal / Fast) — fine-tune independently of difficulty
- **Max Yield Loss** (30% / 45% / 60% / 75%) — cap how much drought can hurt your harvest
- **Critical Threshold** (15% / 25% / 35%) — moisture level that triggers stress accumulation
- **Irrigation Costs** toggle — enable or disable running costs for active systems
- **Crop Alerts** toggle and cooldown (4h / 8h / 12h / 24h) — control alert frequency
- **Debug Mode** toggle — verbose simulation logging to `log.txt`
- Settings persist per-savegame in `cropStressSettings.xml`
- Multiplayer: settings are server-authoritative and pushed to all clients on join

### Phase 4 — Economy & Polish 🚧 In Development

- FinanceIntegration: UsedPlus integration code written (awaiting in-game test)
- Drip irrigation line placeable with linear field coverage *(planned)*
- Used equipment marketplace entries *(planned)*
- Precision Farming DLC overlay *(planned)*
- Polish translations *(planned)*

### Phase 5 — Stability & HUD Polish 📋 Planned

- **HUD position persistence** — panel drag position saved to `cropStressSettings.xml` and restored on next load
- **In-game verification** — run through all remaining `[ ]` test scenarios across Phases 1–4
- **Polish translation** (`translation_pl.xml`) — complete Polish locale
- HUD UX improvements based on in-game feedback

### Phase 6 — Release Readiness 📋 Planned

- Final 3D art assets for center pivot (arm rotation animation) and water pump
- Mod icon (`icon.dds`) — replace placeholder
- Steam Workshop listing draft
- v1.0.0.0 changelog and git release tag
- Post-launch monitoring plan

---

## Recent Fixes

### February 26, 2026 — HUD Rendering Fix & Drag-to-Reposition

- **Fixed:** HUD colored rectangles rendered corrupted and spammed `setOverlayColor: Argument 1 has wrong type. Expected: Float. Actual: Nil` every frame. Root cause: `drawFilledRect` uses an internal overlay handle that was never initialized. Replaced throughout with `createImageOverlay("dataS/menu/base/graph_pixel.dds")` + `setOverlayColor(handle, r,g,b,a)` + `renderOverlay(handle, x,y,w,h)` — the confirmed pattern from FS25_NPCFavor.
- **Added:** HUD panel drag-to-reposition. Right-click the HUD to enter **Edit Mode** (orange border). Left-click drag to move the panel anywhere on screen. Right-click again to exit. Implemented via `addModEventListener mouseEvent` with FS25-confirmed button mapping (1=left, 3=right).

### February 26, 2026 — Settings Bug Fixes & ESC Menu

- **Fixed:** Boolean save/load trap — disabling the mod, HUD, or alerts would silently re-enable on next load
- **Fixed:** `settings.enabled` toggle now actually stops the simulation and hides the HUD
- **Fixed:** Multiplayer clients now receive the host's settings on join
- **Fixed:** ESC menu Settings section — previous version used a non-existent FS25 API and was completely invisible. Rewritten using the confirmed `BinaryOptionElement` / `MultiTextOptionElement` pattern

### February 24, 2026 — Settings System

Full settings system added: 10 configurable options exposed in the ESC menu Game Settings page, with per-savegame XML persistence and multiplayer sync.

### February 24, 2026 — Core Polish Pass

Resolved critical wiring issues from initial implementation: missing placeable type declarations, console command gaps, 15 missing translation keys, i3d root node naming conflicts, `addTrigger` signature fix.

---

## 🌍 Installation

1. Download the latest `FS25_SeasonalCropStress.zip` from [Releases](https://github.com/TheCodingDad-TisonK/FS25_SeasonalCropStress/releases)
2. Copy the ZIP to your mods folder:
   ```
   %USERPROFILE%\Documents\My Games\FarmingSimulator2025\mods\
   ```
3. Launch Farming Simulator 25 and enable **Seasonal Crop Stress & Irrigation Manager** in the Mods menu
4. Start or load a career save — the mod activates automatically

> **Multiplayer:** The host runs all simulation calculations. Clients see synced field state. The host's tick rate determines simulation accuracy.

---

## 🎮 Quick Start

1. **Load your farm** — the soil moisture monitor activates immediately on career load
2. **Press `Shift+M`** to open the Field Moisture HUD in the bottom-left corner
3. **Click any field row** to see its 5-day moisture forecast below the panel
4. **Press `Shift+C`** to open the Crop Consultant — field risk summary, recommendations, and optional NPC panel
5. Watch the color indicators: **green** is healthy, **yellow** needs attention, **red** means irrigate now
6. **Place a Water Pump** near a water source, then place a **Center Pivot** within 500m
7. Press **`E`** near the pivot (or `Shift+I`) to open the irrigation schedule dialog
8. At harvest, fields that suffered drought stress during critical growth windows will yield less

> **Tip:** Right-click the HUD panel to enter Edit Mode — then drag it anywhere on screen with left-click.

> **Tip:** Sandy-soil fields dry out much faster during heatwaves. Check them daily in summer.

---

## 🖥️ Console Commands

Open the developer console with the `~` (tilde) key.

| Command | Arguments | Description |
|---------|-----------|-------------|
| `csHelp` | — | List all available Crop Stress commands |
| `csStatus` | — | System overview: active fields, moisture averages, stress totals |
| `csSetMoisture` | `<fieldId> <0-1>` | Manually set a field's moisture level |
| `csForceStress` | `<fieldId>` | Force maximum stress on a field |
| `csSimulateHeat` | `[days]` | Simulate N days of extreme heat (38°C, no rain) |
| `csConsultant` | — | Open the Crop Consultant dialog directly |
| `csDebug` | — | Toggle verbose debug logging to `log.txt` |

---

## ⌨️ Key Bindings

| Action | Default | Description |
|--------|---------|-------------|
| `Shift+M` | CS_TOGGLE_HUD | Toggle the Field Moisture HUD |
| `Shift+I` | CS_OPEN_IRRIGATION | Open Irrigation Schedule dialog |
| `Shift+C` | CS_OPEN_CONSULTANT | Open Crop Consultant dialog |
| `E` (near pivot) | ACTIVATE_HANDTOOL | Open schedule for that specific pivot |
| `RMB` (on HUD) | — | Toggle HUD Edit Mode — drag with LMB to reposition panel |

---

## 🌱 Crop Critical Windows

| Crop | Critical Window | Moisture Threshold | Max Yield Loss |
|------|----------------|--------------------|----------------|
| Wheat | Heading (stage 3–4) | 35% | 60% |
| Barley | Heading (stage 3–4) | 30% | 55% |
| Corn | Pollination (stage 4–5) | 40% | 60% |
| Canola | Flowering (stage 2–3) | 45% | 50% |
| Sunflower | Head fill (stage 3–4) | 30% | 55% |
| Soybeans | Pod fill (stage 3–4) | 40% | 60% |
| Sugar Beet | Bulking (stage 2–4) | 50% | 45% |
| Potato | Tuber fill (stage 2–4) | 55% | 50% |

---

## 🏗️ Architecture

| Subsystem | File | Responsibility |
|-----------|------|----------------|
| **CropStressManager** | `src/CropStressManager.lua` | Central coordinator; owns all subsystems; CropEventBus; hourly tick |
| **WeatherIntegration** | `src/WeatherIntegration.lua` | Polls FS25 environment for temperature, rainfall, season; 5-day moisture forecast projection |
| **SoilMoistureSystem** | `src/SoilMoistureSystem.lua` | Per-field moisture state; evapotranspiration; rain absorption; soil type modifiers |
| **CropStressModifier** | `src/CropStressModifier.lua` | Crop critical windows; stress accumulation; harvest yield reduction hook |
| **IrrigationManager** | `src/IrrigationManager.lua` | Center-pivot and pump registration; coverage detection; schedule activation; pressure curve |
| **CropConsultant** | `src/CropConsultant.lua` | Three-tier alert system; 12h cooldown; hourly proactive evaluation; NPCFavor delegate |
| **NPCIntegration** | `src/NPCIntegration.lua` | *(Phase 3)* Optional FS25_NPCFavor bridge; Alex Chen NPC; 4 favor types; safe runtime detection |
| **HUDOverlay** | `src/HUDOverlay.lua` | Field moisture display; click-to-select rows; 5-day forecast strip; auto-show on critical alert |
| **SaveLoadHandler** | `src/SaveLoadHandler.lua` | Persist field moisture, stress, HUD state, and irrigation schedules inside careerSavegame.xml |
| **FinanceIntegration** | `src/FinanceIntegration.lua` | *(Phase 4)* Hourly irrigation costs; optional FS25_UsedPlus bridge |

**Event System:** Modules communicate via `CropEventBus` — a lightweight internal publish/subscribe emitter. Avoids dependency on FS25's version-specific integer `MessageType` IDs.

| Event | Publisher | Subscriber(s) |
|-------|-----------|---------------|
| `CS_MOISTURE_UPDATED` | SoilMoistureSystem | HUDOverlay, CropConsultant |
| `CS_CRITICAL_THRESHOLD` | SoilMoistureSystem | HUDOverlay, CropConsultant |
| `CS_STRESS_ACCUMULATED` | CropStressModifier | HUDOverlay |
| `CS_IRRIGATION_STARTED` | IrrigationManager | SoilMoistureSystem |
| `CS_IRRIGATION_STOPPED` | IrrigationManager | SoilMoistureSystem |
| `CS_HARVEST_COMPLETE` | CropStressModifier | SaveLoadHandler, FinanceIntegration |

---

## 📂 File Structure

```
FS25_SeasonalCropStress/
├── modDesc.xml
├── main.lua
│
├── config/
│   └── cropStressDefaults.xml
│
├── src/
│   ├── WeatherIntegration.lua
│   ├── SoilMoistureSystem.lua
│   ├── CropStressModifier.lua
│   ├── CropStressManager.lua
│   ├── IrrigationManager.lua
│   ├── HUDOverlay.lua
│   ├── CropConsultant.lua           ← Phase 3 live
│   ├── NPCIntegration.lua           ← Phase 3 live (NPCFavor optional)
│   ├── SaveLoadHandler.lua
│   └── FinanceIntegration.lua       ← Phase 4 stub
│
├── gui/
│   ├── IrrigationScheduleDialog.lua
│   ├── IrrigationScheduleDialog.xml
│   ├── CropConsultantDialog.lua     ← Phase 3 live
│   ├── CropConsultantDialog.xml     ← Phase 3 live
│   └── FieldMoisturePanel.lua
│
├── placeables/
│   ├── centerPivot/
│   │   ├── centerPivot.xml
│   │   ├── centerPivot.lua
│   │   └── centerPivot.i3d          ← placeholder geometry
│   └── waterPump/
│       ├── waterPump.xml
│       ├── waterPump.lua
│       └── waterPump.i3d            ← placeholder geometry
│
└── translations/
    ├── translation_en.xml           ← complete
    ├── translation_de.xml           ← complete (Phase 1-3)
    ├── translation_fr.xml           ← complete (Phase 1-3)
    └── translation_nl.xml           ← complete (Phase 1-3)
```

---

## ⚠️ Known Limitations

- **Placeholder 3D assets** — center pivot and water pump use minimal placeholder `.i3d` files. No rotation animation on the pivot arm yet. Final art assets planned before v1.0 public release.
- **No mod icon** — `icon.dds` is a placeholder. A proper icon is planned before public release.
- **Drip irrigation** — not yet implemented. Planned for Phase 4.
- **Harvest yield hook** — uses a best-effort spatial query to map harvester position to field ID. Fields with unusual geometry may not match correctly in all cases.
- **Weather forecast** — the 5-day forecast uses current-weather linear projection, not FS25's internal forecast. It's directionally accurate but won't reflect forecast rain events.
- **NPCFavor API** — NPCIntegration calls are written against the expected FS25_NPCFavor v1.2 API but have not been tested against a live build. All calls are nil-guarded; the mod loads cleanly without FS25_NPCFavor present.
- **Multiplayer** — simulation runs on host only; clients see synced state but have no direct simulation authority.

---

## 📖 Documentation

- [Mod Plan & Phase Roadmap](FS25_SeasonalCropStress_ModPlan.md) — full technical blueprint for all four phases
- [CLAUDE.md](CLAUDE.md) — architecture guide and contributor notes for AI-assisted development
- [DEVELOPMENT.md](DEVELOPMENT.md) — session-by-session build tracker and TODO list

---

## 📝 License & Credits

**Author:** TisonK
**Version:** 1.0.0.0 (Phases 1–3)

© TisonK — All Rights Reserved.

This mod is provided for personal use. Redistribution, modification, or reupload without explicit written permission from the author is not permitted.

---

*Farming Simulator 25 is published by GIANTS Software. This mod is an independent fan creation and is not affiliated with or endorsed by GIANTS Software.*