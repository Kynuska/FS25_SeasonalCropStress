# FS25_SeasonalCropStress

![GitHub Downloads](https://img.shields.io/github/downloads/TheCodingDad-TisonK/FS25_SeasonalCropStress/total?style=flat-square&color=brightgreen)
![GitHub Release](https://img.shields.io/github/v/release/TheCodingDad-TisonK/FS25_SeasonalCropStress?style=flat-square&color=blue)
![License](https://img.shields.io/badge/license-All%20Rights%20Reserved-red?style=flat-square)

> *"I planted wheat in June and had a perfect field by August — until I didn't. Three days without rain during heading and I lost 40% of my yield. Never ignored the moisture gauge again."*
> — Beta tester, Season 2 playthrough

---

FS25 farms look lush even when your crops are quietly dying of thirst. This mod changes that.

**Seasonal Crop Stress & Irrigation Manager** adds real soil moisture physics to every field on your farm. Rain replenishes. Heat evaporates. Sandy soil drains fast; clay holds longer. When moisture drops below critical thresholds during the growth windows that matter most — wheat during heading, corn during pollination — stress accumulates and your yield shrinks. Place a center-pivot irrigator, schedule it, and protect what you've grown. Play it right and your harvest beats vanilla. Ignore it and you'll wonder why your combines are running light.

Phases 1 and 2 are live. Phase 3 (Crop Consultant NPC, NPCFavor integration) is in active development. Phase 4 (FS25_UsedPlus integration, drip irrigation, Precision Farming overlay) is planned.

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

### Phase 3 — Crop Consultant 🚧 In Development

- **Alert system**: three severity levels fire as moisture drops
  - INFO (40–50%): *"Field X getting dry — monitor conditions"* — 4s notification
  - WARNING (25–40%): *"Field X moisture low — irrigation recommended"* — 6s notification
  - CRITICAL (<25%): *"Field X at drought threshold — irrigate NOW!"* — 10s notification
- 12-in-game-hour cooldown per field per severity to prevent spam
- **Crop Consultant dialog** (`Shift+C` or `csConsultant` console command) — top 5 fields by risk, recommended actions, 3-day forecast
- Optional **FS25_NPCFavor integration**: Alex Chen, Agronomist NPC — generates favor quests (SOIL_SAMPLE, IRRIGATION_CHECK, EMERGENCY_WATER, SEASONAL_PLAN) and routes alerts through NPC dialog

### Phase 4 — Economy & Polish 📋 Planned

- Drip irrigation line placeable with linear field coverage
- Optional **FS25_UsedPlus integration**: crop insurance, used equipment marketplace listings, wear-based flow degradation
- **Precision Farming DLC overlay**: moisture layer on PF soil map, soil type data from PF samples
- Full translation set: DE, FR, NL, PL

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

---

## 🌱 Crop Critical Windows

| Crop | Critical Window | Moisture Threshold | Max Yield Loss |
|------|----------------|--------------------|----------------|
| Wheat | Heading (stage 5–6) | 35% | 60% |
| Barley | Heading (stage 5–6) | 35% | 55% |
| Corn | Pollination (stage 4–5) | 40% | 60% |
| Canola | Flowering (stage 4–5) | 30% | 50% |
| Sunflower | Head fill (stage 5–6) | 35% | 55% |
| Soybeans | Pod fill (stage 5–6) | 40% | 60% |
| Sugar Beet | Bulking (stage 4–6) | 30% | 45% |
| Potato | Tuber fill (stage 4–6) | 45% | 50% |

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
    ├── translation_de.xml           ← Phase 1 keys only
    ├── translation_fr.xml           ← Phase 1 keys only
    └── translation_nl.xml           ← Phase 1 keys only
```

---

## ⚠️ Known Limitations

- **Placeholder 3D assets** — center pivot and water pump use minimal placeholder `.i3d` files. No rotation animation on the pivot arm yet. Final art assets planned before v1.0 public release.
- **No mod icon** — `icon.dds` is a placeholder. A proper icon is planned before public release.
- **Translations** — only English is complete. DE/FR/NL cover Phase 1 HUD keys only. Full translation pass planned for Phase 4.
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