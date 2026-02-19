# FS25_SeasonalCropStress

![GitHub Downloads](https://img.shields.io/github/downloads/TheCodingDad-TisonK/FS25_SeasonalCropStress/total?style=flat-square&color=brightgreen)
![GitHub Release](https://img.shields.io/github/v/release/TheCodingDad-TisonK/FS25_SeasonalCropStress?style=flat-square&color=blue)
![License](https://img.shields.io/badge/license-All%20Rights%20Reserved-red?style=flat-square)

> *"I planted wheat in June and had a perfect field by August — until I didn't. Three days without rain during heading and I lost 40% of my yield. Never ignored the moisture gauge again."*
> — Beta tester, Season 2 playthrough

---

FS25 farms look lush even when your crops are quietly dying of thirst. This mod changes that.

**Seasonal Crop Stress & Irrigation Manager** adds real soil moisture physics to every field on your farm. Rain replenishes. Heat evaporates. Sandy soil drains fast; clay holds longer. When moisture drops below critical thresholds during the growth windows that matter most — wheat during heading, corn during pollination — stress accumulates and your yield shrinks. Play it right and your harvest is better than vanilla. Ignore it and you'll wonder why your combines are running light.

Phase 1 is live. Irrigation hardware, a Crop Consultant NPC, and optional integration with FS25_NPCFavor and FS25_UsedPlus are coming in Phases 2–4.

---

## ✨ Features

**Phase 1 — Soil Moisture & Crop Stress (current)**
- Per-field soil moisture simulation (0–100%) driven by real in-game weather
- Seasonal evapotranspiration: heat accelerates moisture loss, cold slows it
- Soil type modifiers: sandy drains 40% faster, clay retains 30% longer, loam is baseline
- Season-aware field initialization — fields don't all start at 50% on day one
- Crop-specific critical growth windows for 8 crops: wheat, barley, corn, canola, sunflower, soybeans, sugar beet, potato
- Yield stress accumulates during critical windows when moisture falls below crop thresholds
- Harvest yield reduction — up to **60% loss** at maximum stress
- **Field Moisture HUD** overlay showing real-time status for all active fields (press `Shift+M`)
- Color-coded moisture indicators: green (healthy) → yellow (warning) → red (critical)
- Auto-show HUD when a field reaches critical drought threshold
- First-run welcome notification so you know the mod is active
- Full save/load persistence — all field moisture and stress state survives session restarts
- Developer console commands (`csHelp` in the `~` console)

**Coming in Phase 2 — Irrigation Systems**
- Center-pivot and drip irrigation hardware
- Irrigation scheduling UI
- Water source management

**Coming in Phase 3 — Crop Consultant**
- Alex Chen, Agronomist NPC with field recommendations
- Alert system with severity levels
- Optional FS25_NPCFavor integration for relationship-based advice

**Coming in Phase 4 — Economy Integration**
- Crop insurance via optional FS25_UsedPlus integration
- Yield history tracking and analytics

---

## 🌍 Installation

1. Download the latest `FS25_SeasonalCropStress.zip` from [Releases](https://github.com/TheCodingDad-TisonK/FS25_SeasonalCropStress/releases)
2. Copy the ZIP to your mods folder:
   ```
   %USERPROFILE%\Documents\My Games\FarmingSimulator2025\mods\
   ```
3. Launch Farming Simulator 25 and enable **Seasonal Crop Stress & Irrigation Manager** in the Mods menu
4. Start or load a career save — the mod activates automatically

> **Note:** The mod works on any map with standard FS25 fields. Multiplayer is supported; the host runs all simulation calculations.

---

## 🎮 Quick Start

1. **Load your farm** — the soil moisture monitor activates immediately on career load
2. **Press `Shift+M`** to open the Field Moisture HUD in the bottom-left corner
3. Watch the color indicators: **green** is healthy, **yellow** needs attention, **red** means irrigate now
4. Fields in critical drought will **automatically open the HUD** and trigger an alert
5. Type `csHelp` in the developer console (`~` key) to see all available commands
6. At harvest, fields that suffered drought stress during critical growth windows will yield less — sometimes significantly less

> **Tip:** Sandy-soil fields dry out much faster during heatwaves. Check them daily in summer.

---

## 🖥️ Console Commands

Open the developer console with the `~` (tilde) key, then type any command below.

| Command | Arguments | Description |
|---------|-----------|-------------|
| `csHelp` | — | List all available Crop Stress commands |
| `csStatus` | — | System overview: active fields, moisture averages, stress totals |
| `csSetMoisture` | `<fieldId> <0-100>` | Manually set a field's moisture percentage |
| `csForceStress` | `<fieldId> <0-1>` | Manually set a field's accumulated stress value |
| `csSimulateHeat` | `[days]` | Simulate N days of extreme heat (38°C, no rain) — default 3 days |
| `csDebug` | — | Toggle debug logging to `log.txt` |

---

## 🌱 Crop Critical Windows

Each crop has specific growth stages where moisture deficits cause the most damage.

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
| **WeatherIntegration** | `src/WeatherIntegration.lua` | Polls FS25 environment for temperature, rainfall, and season each hour |
| **SoilMoistureSystem** | `src/SoilMoistureSystem.lua` | Per-field moisture state; evapotranspiration; rain absorption; soil type modifiers |
| **CropStressModifier** | `src/CropStressModifier.lua` | Crop critical windows; stress accumulation; harvest yield reduction hook |
| **HUDOverlay** | `src/HUDOverlay.lua` | Immediate-mode field moisture display; color coding; auto-show on critical alert |
| **SaveLoadHandler** | `src/SaveLoadHandler.lua` | Persist all field moisture and stress values inside careerSavegame.xml |
| **IrrigationManager** | `src/IrrigationManager.lua` | *(Phase 2 stub)* Center-pivot and drip irrigation systems |
| **CropConsultant** | `src/CropConsultant.lua` | *(Phase 3 stub)* Agronomist NPC advisor with alert severity system |
| **NPCIntegration** | `src/NPCIntegration.lua` | *(Phase 3 stub)* Optional FS25_NPCFavor bridge for relationship-gated advice |
| **FinanceIntegration** | `src/FinanceIntegration.lua` | *(Phase 4 stub)* Optional FS25_UsedPlus crop insurance bridge |

**Event System:** Modules communicate via `CropEventBus` — a custom string-keyed publish/subscribe emitter that avoids dependency on FS25's version-specific integer `MessageType` IDs.

| Event | Publisher | Subscriber(s) |
|-------|-----------|---------------|
| `CS_MOISTURE_UPDATED` | SoilMoistureSystem | HUDOverlay |
| `CS_CRITICAL_THRESHOLD` | SoilMoistureSystem | HUDOverlay, CropConsultant |
| `CS_STRESS_ACCUMULATED` | CropStressModifier | HUDOverlay |
| `CS_HARVEST_COMPLETE` | CropStressModifier | SaveLoadHandler, FinanceIntegration |

---

## 📂 File Structure

```
FS25_SeasonalCropStress/
├── modDesc.xml                          # Mod descriptor — declares main.lua only
├── main.lua                             # Entry point — source() load order + lifecycle hooks
│
├── config/
│   └── cropStressDefaults.xml           # All tunable simulation defaults
│
├── src/
│   ├── WeatherIntegration.lua           # Weather polling
│   ├── SoilMoistureSystem.lua           # Per-field moisture simulation
│   ├── CropStressModifier.lua           # Critical windows + harvest hook
│   ├── CropStressManager.lua            # Coordinator + CropEventBus
│   ├── HUDOverlay.lua                   # Field moisture HUD
│   ├── SaveLoadHandler.lua              # Save/load persistence
│   ├── IrrigationManager.lua            # [Phase 2] Irrigation systems stub
│   ├── CropConsultant.lua               # [Phase 3] Agronomist NPC stub
│   ├── NPCIntegration.lua               # [Phase 3] NPCFavor bridge stub
│   └── FinanceIntegration.lua           # [Phase 4] UsedPlus bridge stub
│
├── gui/
│   ├── FieldMoisturePanel.lua           # [Phase 2] Detailed field panel stub
│   ├── IrrigationScheduleDialog.lua     # [Phase 2] Scheduling UI stub
│   └── CropConsultantDialog.lua         # [Phase 3] Consultant dialog stub
│
└── translations/
    ├── translation_en.xml               # English (complete)
    ├── translation_de.xml               # German (Phase 1 keys)
    ├── translation_fr.xml               # French (Phase 1 keys)
    └── translation_nl.xml               # Dutch (Phase 1 keys)
```

---

## ⚠️ Known Limitations

- **Phase 2–4 systems are stubs** — irrigation hardware, the Crop Consultant NPC, and economy integration are not yet functional
- **Harvest yield hook requires field position mapping** — the `getFieldIdAtPosition()` function uses a best-effort spatial query; fields with unusual geometry may not match correctly in all cases
- **Translations** — only English has a full translation; DE/FR/NL cover Phase 1 HUD keys only; additional language files are not yet created
- **No 3D assets** — the mod has no icon DDS file yet; a placeholder icon is planned before the first public release
- **Multiplayer** — the host runs all simulation; clients see synced field state but simulation accuracy depends on the host's tick rate
- **Weather API** — weather data is polled via multiple fallback paths to support different FS25 patch versions; if a patch changes the weather API, `WeatherIntegration.lua` may need updating

---

## 📖 Documentation

- [Mod Plan & Phase Roadmap](FS25_SeasonalCropStress_ModPlan.md) — full technical blueprint for all four phases
- [CLAUDE.md](CLAUDE.md) — architecture guide and contributor notes for AI-assisted development

---

## 📝 License & Credits

**Author:** TisonK
**Version:** 1.0.0.0 (Phase 1)

© TisonK — All Rights Reserved.

This mod is provided for personal use. Redistribution, modification, or reupload without explicit permission from the author is not permitted.

---

*Farming Simulator 25 is published by GIANTS Software. This mod is an independent fan creation and is not affiliated with or endorsed by GIANTS Software.*
