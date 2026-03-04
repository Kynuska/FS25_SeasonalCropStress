<div align="center">

# 🌱 FS25 Seasonal Crop Stress
### *Irrigation Manager Mod*

[![Downloads](https://img.shields.io/github/downloads/TheCodingDad-TisonK/FS25_SeasonalCropStress/total?style=for-the-badge&logo=github&color=4caf50&logoColor=white)](https://github.com/TheCodingDad-TisonK/FS25_SeasonalCropStress/releases)
[![Release](https://img.shields.io/github/v/release/TheCodingDad-TisonK/FS25_SeasonalCropStress?style=for-the-badge&logo=tag&color=76c442&logoColor=white)](https://github.com/TheCodingDad-TisonK/FS25_SeasonalCropStress/releases/latest)
[![License](https://img.shields.io/badge/license-All%20Rights%20Reserved-red?style=for-the-badge&logo=shield&logoColor=white)](#license--credits)
[![Phase](https://img.shields.io/badge/Phase%204-In%20Development-orange?style=for-the-badge&logo=hammer&logoColor=white)](#roadmap)

<br>

> *"I planted wheat in June and had a perfect field by August — until I didn't. Three days without rain during heading and I lost 40% of my yield. Never ignored the moisture gauge again."*
> — Beta tester, Season 2 playthrough

<br>

**FS25 farms look lush even when your crops are quietly dying of thirst. This mod changes that.**

Real soil moisture physics. Heat evaporates. Rain replenishes. Sandy soil drains fast; clay holds longer. When moisture drops below critical thresholds during the windows that matter most — wheat during heading, corn during pollination — stress accumulates and your yield shrinks. Place a center-pivot irrigator, schedule it, and protect what you've grown.

`Singleplayer` • `Multiplayer (host-authoritative)` • `Persistent saves` • `EN / DE / FR / NL`

</div>

---

## 🗺️ Roadmap

| Phase | Status | Contents |
|---|---|---|
| **1** — Soil Moisture & Crop Stress | ✅ Live | Moisture sim, evapotranspiration, soil types, yield loss, Field HUD |
| **2** — Irrigation Infrastructure | ✅ Live | Center pivot, water pump, pressure curve, irrigation schedule dialog |
| **3** — Crop Consultant | ✅ Live | 3-tier alert system, consultant dialog, NPCFavor integration |
| **4** — Economy & Polish | 🔧 In development | Finance integration, drip irrigation, Precision Farming DLC overlay |
| **5** — Stability & HUD Polish | 📋 Planned | HUD position persistence, Polish locale, UX improvements |
| **6** — Release Readiness | 📋 Planned | Final 3D art, mod icon, Steam Workshop, v1.0.0.0 |

---

## ✨ Features

### 🌍 Phase 1 — Soil Moisture & Crop Stress `✅ Live`

| | Feature | Description |
|---|---|---|
| 💧 | **Per-field moisture simulation** | 0–100% moisture driven by real in-game weather |
| 🌡️ | **Seasonal evapotranspiration** | Heat accelerates loss, cold slows it |
| 🪨 | **Soil type modifiers** | Sandy drains 40% faster · Clay retains 30% longer · Loam is baseline |
| 🌾 | **Critical growth windows** | 8 crops each have their own vulnerable stage (see table below) |
| 📉 | **Yield stress system** | Stress accumulates during critical windows — up to **60% yield loss** |
| 📊 | **Field Moisture HUD** | Press `Shift+M` — color-coded bars for every active field |
| 🔮 | **5-day forecast** | Click any field row to see its moisture forecast strip |
| 💾 | **Full persistence** | Moisture & stress state survives session restarts |

### 💦 Phase 2 — Irrigation Infrastructure `✅ Live`

| | Feature | Description |
|---|---|---|
| 🔄 | **Center Pivot Irrigator** | Placeable — circular coverage up to 200m radius |
| ⛽ | **Water Pump** | Placeable near any water source — auto-connects to pivots within 500m |
| 📡 | **Pressure curve** | Flow degrades from 100% at 0m to 70% at 500m; zero beyond |
| 🗓️ | **Irrigation Schedule Dialog** | `E` near pivot or `Shift+I` — set active days, hours & flow rate |
| ⚡ | **Irrigate Now** | Manual one-click activation button |
| 💰 | **Operational costs** | Charged to farm account each active hour (toggleable) |

### 🌿 Phase 3 — Crop Consultant `✅ Live`

> [!NOTE]
> Phase 3 includes optional integration with **FS25_NPCFavor**. The mod loads cleanly without it — all NPC calls are nil-guarded.

**Alert System** — 3 severity levels with cooldown protection:

```
💙 INFO     (40–50%)  "Field X getting dry — monitor conditions"       4s notification
🟡 WARNING  (25–40%)  "Field X moisture low — irrigation recommended"  6s notification
🔴 CRITICAL  (<25%)   "Field X at drought threshold — irrigate NOW!"   10s notification
```

12-in-game-hour cooldown per field per severity to prevent spam.

**Crop Consultant Dialog** (`Shift+C`) — top 5 fields by risk, recommended actions & 3-day forecast.
**NPCFavor bridge** — Alex Chen, Agronomist NPC generates favor quests: `SOIL_SAMPLE`, `IRRIGATION_CHECK`, `EMERGENCY_WATER`, `SEASONAL_PLAN`.

---

## ⚙️ Settings

Open via **ESC → Settings → Game Settings** and scroll to the *"Seasonal Crop Stress"* section.

| Setting | Options | Notes |
|---|---|---|
| **Enable mod** | On / Off | Stops simulation and hides HUD when disabled |
| **Difficulty** | Easy / Normal / Hard | Scales stress rate & evaporation speed |
| **Evaporation Rate** | Slow / Normal / Fast | Fine-tune independently of difficulty |
| **Max Yield Loss** | 30% / 45% / 60% / 75% | Cap how much drought can hurt your harvest |
| **Critical Threshold** | 15% / 25% / 35% | Moisture level that triggers stress accumulation |
| **Irrigation Costs** | On / Off | Enable or disable running costs |
| **Crop Alerts** | On / Off | Toggle the alert system entirely |
| **Alert Cooldown** | 4h / 8h / 12h / 24h | Control alert frequency |
| **Debug Mode** | On / Off | Verbose simulation logging to `log.txt` |

> [!IMPORTANT]
> Settings are **server-authoritative** in multiplayer — the host's settings are pushed to all clients on join. Per-savegame persistence in `cropStressSettings.xml`.

---

## 🌱 Crop Critical Windows

| Crop | Critical Window | Moisture Threshold | Max Yield Loss |
|---|---|---|---|
| 🌾 Wheat | Heading (stage 3–4) | 35% | 60% |
| 🌾 Barley | Heading (stage 3–4) | 30% | 55% |
| 🌽 Corn | Pollination (stage 4–5) | 40% | 60% |
| 🌼 Canola | Flowering (stage 2–3) | 45% | 50% |
| 🌻 Sunflower | Head fill (stage 3–4) | 30% | 55% |
| 🫘 Soybeans | Pod fill (stage 3–4) | 40% | 60% |
| 🟣 Sugar Beet | Bulking (stage 2–4) | 50% | 45% |
| 🥔 Potato | Tuber fill (stage 2–4) | 55% | 50% |

---

## 🛠️ Installation

> [!TIP]
> Already installed? Jump to [Quick Start](#-quick-start).

**1. Download** `FS25_SeasonalCropStress.zip` from the [latest release](https://github.com/TheCodingDad-TisonK/FS25_SeasonalCropStress/releases/latest).

**2. Copy** the ZIP to your mods folder:

| Platform | Path |
|---|---|
| 🪟 Windows | `%USERPROFILE%\Documents\My Games\FarmingSimulator2025\mods\` |
| 🍎 macOS | `~/Library/Application Support/FarmingSimulator2025/mods/` |

**3. Enable** *Seasonal Crop Stress & Irrigation Manager* in the Mods menu.

**4. Load** any career save — the mod activates automatically.

> [!NOTE]
> **Multiplayer:** The host runs all simulation calculations. Clients see synced field state. The host's tick rate determines simulation accuracy.

---

## 🎮 Quick Start

```
1. Load your farm — soil moisture monitoring activates immediately.
2. Press Shift+M    → open the Field Moisture HUD (bottom-left corner)
3. Click a field row → see its 5-day moisture forecast strip
4. Press Shift+C    → open the Crop Consultant for risk summary & recommendations
5. Green = healthy · Yellow = needs attention · Red = irrigate NOW
6. Place a Water Pump near water, then a Center Pivot within 500m
7. Press E near the pivot (or Shift+I) → set your irrigation schedule
8. At harvest, drought-stressed fields yield less — plan ahead!
```

> [!TIP]
> Right-click the HUD panel to enter **Edit Mode** (orange border) — then drag it anywhere on screen with left-click.

> [!TIP]
> Sandy-soil fields dry out much faster during heatwaves. Check them daily in summer.

---

## ⌨️ Key Bindings

| Keys | Action |
|---|---|
| `Shift+M` | Toggle the Field Moisture HUD |
| `Shift+I` | Open Irrigation Schedule dialog |
| `Shift+C` | Open Crop Consultant dialog |
| `E` *(near pivot)* | Open schedule for that specific pivot |
| `RMB` *(on HUD)* | Toggle Edit Mode — drag with `LMB` to reposition |

---

## 🖥️ Console Commands

Open the developer console with the **`~`** key:

| Command | Arguments | Description |
|---|---|---|
| `csHelp` | — | List all available Crop Stress commands |
| `csStatus` | — | System overview: active fields, moisture averages, stress totals |
| `csSetMoisture` | `<fieldId> <0-1>` | Manually set a field's moisture level |
| `csForceStress` | `<fieldId>` | Force maximum stress on a field |
| `csSimulateHeat` | `[days]` | Simulate N days of extreme heat (38°C, no rain) |
| `csConsultant` | — | Open the Crop Consultant dialog directly |
| `csDebug` | — | Toggle verbose debug logging to `log.txt` |

---

## 🏗️ Architecture

```
CropStressManager           Central coordinator — CropEventBus, hourly tick, all subsystems
├── WeatherIntegration      Polls FS25 environment: temperature, rainfall, season, 5-day forecast
├── SoilMoistureSystem      Per-field moisture state, evapotranspiration, soil type modifiers
├── CropStressModifier      Critical windows, stress accumulation, harvest yield reduction hook
├── IrrigationManager       Pivot & pump registration, coverage detection, schedule, pressure curve
├── CropConsultant          3-tier alerts, 12h cooldown, proactive evaluation, NPCFavor delegate
├── NPCIntegration          [Phase 3] Optional NPCFavor bridge — Alex Chen NPC, 4 favor types
├── HUDOverlay              Field moisture display, click-to-select, 5-day forecast strip
├── SaveLoadHandler         Persist moisture, stress, HUD state, schedules in careerSavegame.xml
└── FinanceIntegration      [Phase 4] Hourly irrigation costs, optional UsedPlus bridge
```

**Event System:** Modules communicate via `CropEventBus` — a lightweight internal pub/sub emitter that avoids dependency on FS25's version-specific `MessageType` IDs.

| Event | Publisher | Subscribers |
|---|---|---|
| `CS_MOISTURE_UPDATED` | SoilMoistureSystem | HUDOverlay, CropConsultant |
| `CS_CRITICAL_THRESHOLD` | SoilMoistureSystem | HUDOverlay, CropConsultant |
| `CS_STRESS_ACCUMULATED` | CropStressModifier | HUDOverlay |
| `CS_IRRIGATION_STARTED` | IrrigationManager | SoilMoistureSystem |
| `CS_IRRIGATION_STOPPED` | IrrigationManager | SoilMoistureSystem |
| `CS_HARVEST_COMPLETE` | CropStressModifier | SaveLoadHandler, FinanceIntegration |

<details>
<summary>📂 <strong>Full File Structure</strong></summary>

```
FS25_SeasonalCropStress/
├── modDesc.xml
├── main.lua
│
├── config/
│   └── cropStressDefaults.xml
│
├── src/
│   ├── CropStressManager.lua
│   ├── WeatherIntegration.lua
│   ├── SoilMoistureSystem.lua
│   ├── CropStressModifier.lua
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
    ├── translation_de.xml           ← complete (Phase 1–3)
    ├── translation_fr.xml           ← complete (Phase 1–3)
    └── translation_nl.xml           ← complete (Phase 1–3)
```

</details>

---

## 📋 Recent Fixes

<details>
<summary><strong>February 26, 2026</strong> — HUD Rendering Fix & Drag-to-Reposition</summary>

- **Fixed:** HUD colored rectangles rendered corrupted and spammed `setOverlayColor: Argument 1 has wrong type. Expected: Float. Actual: Nil` every frame. Root cause: `drawFilledRect` uses an internal overlay handle that was never initialized. Replaced throughout with `createImageOverlay` + `setOverlayColor` + `renderOverlay` — the confirmed pattern from FS25_NPCFavor.
- **Added:** HUD panel drag-to-reposition. Right-click the HUD to enter **Edit Mode** (orange border). Left-click drag to move anywhere on screen. Right-click again to exit.

</details>

<details>
<summary><strong>February 26, 2026</strong> — Settings Bug Fixes & ESC Menu</summary>

- **Fixed:** Boolean save/load trap — disabling the mod, HUD, or alerts would silently re-enable on next load
- **Fixed:** `settings.enabled` toggle now actually stops the simulation and hides the HUD
- **Fixed:** Multiplayer clients now receive the host's settings on join
- **Fixed:** ESC menu Settings section — previous version used a non-existent FS25 API. Rewritten using the confirmed `BinaryOptionElement` / `MultiTextOptionElement` pattern

</details>

<details>
<summary><strong>February 24, 2026</strong> — Settings System & Core Polish Pass</summary>

- Full settings system added: 10 configurable options in ESC menu with per-savegame XML persistence and multiplayer sync
- Resolved critical wiring issues: missing placeable type declarations, console command gaps, 15 missing translation keys, i3d root node naming conflicts, `addTrigger` signature fix

</details>

---

## ⚠️ Known Limitations

> [!WARNING]
> These are known issues currently in the backlog — they do not break the mod.

| Issue | Details |
|---|---|
| 🎨 **Placeholder 3D assets** | Center pivot and water pump use minimal `.i3d` files. No pivot arm rotation yet. Final art planned before v1.0. |
| 🖼️ **No mod icon** | `icon.dds` is a placeholder. Planned before public release. |
| 💧 **No drip irrigation** | Linear field coverage system planned for Phase 4. |
| 🌾 **Harvest yield hook** | Uses spatial query to map harvester → field ID. Fields with unusual geometry may not match correctly. |
| 🔮 **Weather forecast** | 5-day forecast uses linear projection from current conditions — won't reflect FS25's internal forecast rain events. |
| 🤝 **NPCFavor API** | Written against FS25_NPCFavor v1.2 API but not yet tested against a live build. Loads cleanly without it. |
| 🌐 **Multiplayer** | Simulation runs on host only; clients see synced state but have no direct simulation authority. |

---

## 📖 Documentation

| Doc | Description |
|---|---|
| [Mod Plan & Phase Roadmap](FS25_SeasonalCropStress_ModPlan.md) | Full technical blueprint for all phases |
| [CLAUDE.md](CLAUDE.md) | Architecture guide & contributor notes for AI-assisted development |
| [DEVELOPMENT.md](DEVELOPMENT.md) | Session-by-session build tracker and TODO list |

---

## 📝 License & Credits

> [!CAUTION]
> Redistribution, modification, or reupload without explicit written permission from the author is **not permitted**.

**Author:** TisonK · **Version:** 1.0.0.0 *(Phases 1–3)*

© TisonK — All Rights Reserved. This mod is provided for personal use.

---

<div align="center">

*Farming Simulator 25 is published by GIANTS Software. This is an independent fan creation, not affiliated with or endorsed by GIANTS Software.*

*Play it right and your harvest beats vanilla. Ignore it and you'll wonder why your combines are running light.* 🌾

</div>
