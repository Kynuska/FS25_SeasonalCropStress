-- ============================================================
-- FS25_SeasonalCropStress — main.lua
-- Entry point. Loads all modules via source() in strict dependency
-- order, then wires up FS25 lifecycle hooks.
--
-- Load phases:
--   1. Weather bridge
--   2. Core simulation (soil, stress, irrigation)
--   3. Player-facing (HUD, consultant)
--   4. Optional mod bridges (activated at runtime if mods present)
--   5. Persistence
--   6. GUI panels
--   7. Central coordinator (depends on everything above)
-- ============================================================

local modDir = g_currentModDirectory

-- ============================================================
-- FOCUSMANAGER NIL-NODE GUARD — patch the CLASS, not the instance.
--
-- Root cause (FS25 v1.16 regression):
--   When any mod calls g_gui:loadGui() the GUI system calls
--   loadSharedI3DFile for the button focus-ring indicator i3d.
--   In v1.16 that callback fires with nil as i3dNode when the
--   file is already cached as a shared i3d.
--   FocusManager.lua:94 then does elementsByNodeId[nil] = element
--   → "table index is nil" crash, which leaves currentFocusElement
--   in a corrupt state → FocusManager.lua:126 cascade every frame.
--
-- Why CLASS-level (not instance): g_gui.focusManager is nil at both
-- mod load time AND loadMission00Finished in FS25 v1.16. Patching
-- FocusManager (the class table) covers all instances via Lua __index
-- dispatch and is unaffected by when g_gui initialises its fields.
-- ============================================================
do
    if type(FocusManager) == "table" and type(FocusManager.loadSharedI3DFileFinished) == "function" then
        local origFn = FocusManager.loadSharedI3DFileFinished
        FocusManager.loadSharedI3DFileFinished = function(self, i3dNode, failedReason, args)
            if i3dNode == nil then
                print("[CropStress] FocusManager nil-node guard triggered — suppressed")
                return
            end
            return origFn(self, i3dNode, failedReason, args)
        end
        print("[CropStress] FocusManager nil-node guard applied to FocusManager class")
    else
        print("[CropStress] WARNING: FocusManager class guard skipped — FocusManager not available at load time")
    end
end

-- Phase 1: Weather bridge
source(modDir .. "src/WeatherIntegration.lua")

-- Phase 2: Core simulation
source(modDir .. "src/SoilMoistureSystem.lua")
source(modDir .. "src/CropStressModifier.lua")
source(modDir .. "src/IrrigationManager.lua")

-- Phase 3: Player-facing systems
source(modDir .. "src/HUDOverlay.lua")
source(modDir .. "src/CropConsultant.lua")

-- Phase 4: Optional mod bridges
source(modDir .. "src/NPCIntegration.lua")
source(modDir .. "src/FinanceIntegration.lua")
source(modDir .. "src/UsedEquipmentMarketplace.lua")  -- FIX: was missing, caused nil crash in CropStressManager.new()
source(modDir .. "src/PrecisionFarmingOverlay.lua")   -- FIX: was missing, caused nil crash in CropStressManager.new()

-- Phase 5: Persistence
source(modDir .. "src/SaveLoadHandler.lua")

-- Phase 6: GUI panels
source(modDir .. "gui/FieldMoisturePanel.lua")
source(modDir .. "gui/IrrigationScheduleDialog.lua")
source(modDir .. "gui/CropConsultantDialog.lua")

-- Phase 7: Central coordinator (must load last -- depends on all of the above)
source(modDir .. "src/CropStressManager.lua")

-- ============================================================
-- Install harvest yield hook (patches HarvestingMachine at load time,
-- before any vehicles are created -- correct timing for function patching)
-- ============================================================
CropStressModifier.installHarvestHook()

-- ============================================================
-- Lifecycle reference -- set in Mission00.load, cleared in FSBaseMission.delete
-- ============================================================
local g_csManager = nil

-- 1. Mission load: create the manager
Mission00.load = Utils.appendedFunction(Mission00.load, function(self, ...)
    g_csManager = CropStressManager.new()
    getfenv(0)["g_cropStressManager"] = g_csManager
    print("[CropStress] CropStressManager created (v1.0.0.0)")
end)

-- 2. Mission fully loaded: initialize all systems
Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, function(self, ...)
    if g_csManager == nil then return end

    g_csManager:initialize()

    -- ── DIAGNOSTIC BLOCK (remove once FocusManager path is confirmed) ────────
    -- Find the actual field name FS25 uses to store the FocusManager on g_gui,
    -- and verify which scope exposes g_NPCSystem.
    do
        -- 1. FocusManager: search g_gui fields for an object with loadSharedI3DFileFinished
        print("[CropStress] DIAG: g_gui type=" .. tostring(type(g_gui)))
        if type(g_gui) == "table" then
            print("[CropStress] DIAG: g_gui.focusManager=" .. tostring(g_gui.focusManager))
            local fmKey = nil
            for k, v in pairs(g_gui) do
                if type(v) == "table" and type(v.loadSharedI3DFileFinished) == "function" then
                    fmKey = k
                    print("[CropStress] DIAG: FocusManager found at g_gui." .. tostring(k))
                end
            end
            if fmKey == nil then
                print("[CropStress] DIAG: FocusManager NOT found in top-level g_gui fields")
            end
        end

        -- 2. NPCSystem: try multiple scopes
        print("[CropStress] DIAG: g_NPCSystem(direct)=" .. tostring(g_NPCSystem))
        local ok0, v0 = pcall(function() return getfenv(0)["g_NPCSystem"] end)
        print("[CropStress] DIAG: g_NPCSystem(fenv0)=" .. tostring(ok0 and v0 or "ERR"))
        local ok1, v1 = pcall(function() return getfenv(1)["g_NPCSystem"] end)
        print("[CropStress] DIAG: g_NPCSystem(fenv1)=" .. tostring(ok1 and v1 or "ERR"))
    end
    -- ── END DIAGNOSTIC ────────────────────────────────────────────────────────

    -- Register dialogs with the GUI system.
    -- FIX: pass the CLASS TABLE, not a live instance (.new()).
    -- g_gui:loadGui() calls .new() itself after parsing the XML and wiring elements.
    -- Passing a pre-built instance leaves focusElement nil and causes
    -- FocusManager.lua:126 on the next update frame.
    if g_gui ~= nil then
        g_gui:loadGui(
            modDir .. "gui/IrrigationScheduleDialog.xml",
            nil,
            IrrigationScheduleDialog,
            false
        )
        g_gui:loadGui(
            modDir .. "gui/CropConsultantDialog.xml",
            nil,
            CropConsultantDialog,
            false
        )
    end

    -- Register input actions
    if g_inputBinding ~= nil and InputAction ~= nil then
        if InputAction.CS_TOGGLE_HUD ~= nil then
            g_inputBinding:registerActionEvent(
                InputAction.CS_TOGGLE_HUD,
                g_csManager, CropStressManager.onToggleHUD,
                false, true, false, true
            )
        end
        if InputAction.CS_OPEN_IRRIGATION ~= nil then
            g_inputBinding:registerActionEvent(
                InputAction.CS_OPEN_IRRIGATION,
                g_csManager, CropStressManager.onOpenIrrigationDialog,
                false, true, false, true
            )
        end
        if InputAction.CS_OPEN_CONSULTANT ~= nil then
            g_inputBinding:registerActionEvent(
                InputAction.CS_OPEN_CONSULTANT,
                g_csManager, CropStressManager.onOpenConsultantDialog,
                false, true, false, true
            )
        end
    end

    -- Register console debug commands
    if addConsoleCommand ~= nil then
        addConsoleCommand("csHelp",        "List all CropStress debug commands",                           "consoleHelp",        g_csManager)
        addConsoleCommand("csStatus",      "Print full system status to log",                              "consoleStatus",      g_csManager)
        addConsoleCommand("csSetMoisture", "Set field moisture: csSetMoisture <fieldId> <0.0-1.0>",        "consoleSetMoisture", g_csManager)
        addConsoleCommand("csForceStress", "Force maximum stress: csForceStress <fieldId>",                "consoleForceStress", g_csManager)
        addConsoleCommand("csSimulateHeat","Simulate heat wave: csSimulateHeat <days>",                    "consoleSimulateHeat",g_csManager)
        addConsoleCommand("csDebug",       "Toggle verbose debug logging",                                 "consoleToggleDebug", g_csManager)
        addConsoleCommand("csConsultant",  "Open the Crop Consultant dialog",                              "consoleConsultant",  g_csManager)
    end
end)

-- 3. Per-frame update
FSBaseMission.update = Utils.appendedFunction(FSBaseMission.update, function(self, dt)
    if g_csManager ~= nil then g_csManager:update(dt) end
end)

-- 4. Draw hook (HUD rendering)
FSBaseMission.draw = Utils.appendedFunction(FSBaseMission.draw, function(self)
    if g_csManager ~= nil then g_csManager:draw() end
end)

-- 5. Cleanup on mission unload
FSBaseMission.delete = Utils.appendedFunction(FSBaseMission.delete, function(self)
    if g_csManager ~= nil then
        g_csManager:delete()
        g_csManager = nil
        getfenv(0)["g_cropStressManager"] = nil
        if removeConsoleCommand ~= nil then
            removeConsoleCommand("csHelp")
            removeConsoleCommand("csStatus")
            removeConsoleCommand("csSetMoisture")
            removeConsoleCommand("csForceStress")
            removeConsoleCommand("csSimulateHeat")
            removeConsoleCommand("csDebug")
            removeConsoleCommand("csConsultant")
        end
    end
end)

-- 6. Save
FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, function(self, xmlFile)
    if g_csManager ~= nil then g_csManager:saveToXMLFile(xmlFile) end
end)

-- 7. Load saved state (fires after fields are populated)
Mission00.onStartMission = Utils.appendedFunction(Mission00.onStartMission, function(self, ...)
    if g_csManager ~= nil then
        -- Enumerate fields first (fieldManager is guaranteed ready at this lifecycle stage).
        -- lateInitialize() is a no-op if fields were already found during loadMission00Finished.
        g_csManager:lateInitialize()
        g_csManager:loadFromXMLFile()
    end
end)

-- 8. Multiplayer: send initial state to new client
FSBaseMission.sendInitialClientState = Utils.appendedFunction(
    FSBaseMission.sendInitialClientState,
    function(self, connection, objectId, farmId)
        if g_csManager ~= nil then g_csManager:sendInitialClientState(connection) end
    end
)