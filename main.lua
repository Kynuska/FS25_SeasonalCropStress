-- ============================================================
-- FS25_SeasonalCropStress — main.lua
-- Entry point. Loads all modules via source() in strict dependency
-- order, then wires up FS25 lifecycle hooks.
--
-- Load phases:
--   1. Event bus + constants
--   2. Weather bridge
--   3. Core simulation (soil, stress, irrigation stub)
--   4. Player-facing (HUD, consultant stub)
--   5. Optional mod bridges (stubs — activated at runtime if mods present)
--   6. Persistence
--   7. GUI panels
--   8. Central coordinator (depends on everything above)
-- ============================================================

local modDir = g_currentModDirectory

-- Phase 1: Weather bridge
source(modDir .. "src/WeatherIntegration.lua")

-- Phase 2: Core simulation
source(modDir .. "src/SoilMoistureSystem.lua")
source(modDir .. "src/CropStressModifier.lua")
source(modDir .. "src/IrrigationManager.lua")       -- Phase 2 stub

-- Phase 3: Player-facing systems
source(modDir .. "src/HUDOverlay.lua")
source(modDir .. "src/CropConsultant.lua")           -- Phase 3 stub

-- Phase 4: Optional mod bridges
source(modDir .. "src/NPCIntegration.lua")           -- Phase 3 stub
source(modDir .. "src/FinanceIntegration.lua")       -- Phase 4 stub

-- Phase 5: Persistence
source(modDir .. "src/SaveLoadHandler.lua")

-- Phase 6: GUI panels
source(modDir .. "gui/FieldMoisturePanel.lua")
source(modDir .. "gui/IrrigationScheduleDialog.lua") -- Phase 2 stub
source(modDir .. "gui/CropConsultantDialog.lua")     -- Phase 3 stub

-- Phase 7: Central coordinator (must load last)
source(modDir .. "src/CropStressManager.lua")

-- ============================================================
-- Install harvest yield hook (patches HarvestingMachine at load time,
-- before any vehicles are created — correct timing for function patching)
-- ============================================================
CropStressModifier.installHarvestHook()

-- ============================================================
-- Lifecycle reference — set in Mission00.load, cleared in FSBaseMission.delete
-- ============================================================
local g_csManager = nil

-- 1. Mission load: create the manager
Mission00.load = Utils.appendedFunction(Mission00.load, function(self, ...)
    g_csManager = CropStressManager.new()
    getfenv(0)["g_cropStressManager"] = g_csManager
    g_logManager:devInfo("[CropStress]", "CropStressManager created (v1.0.0.0)")
end)

-- 2. Mission fully loaded: initialize all systems
Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, function(self, ...)
    if g_csManager == nil then return end

    g_csManager:initialize()

    -- Register HUD toggle input after mission is ready
    if g_inputBinding ~= nil and InputAction ~= nil and InputAction.CS_TOGGLE_HUD ~= nil then
        g_inputBinding:registerActionEvent(
            InputAction.CS_TOGGLE_HUD,
            g_csManager,
            CropStressManager.onToggleHUD,
            false, -- triggerUp
            true,  -- triggerDown
            false, -- triggerAlways
            true   -- startActive
        )
    end

    -- Register console debug commands
    if addConsoleCommand ~= nil then
        addConsoleCommand("csHelp",
            "List all CropStress debug commands",
            "consoleHelp", g_csManager)
        addConsoleCommand("csStatus",
            "Print full system status to log",
            "consoleStatus", g_csManager)
        addConsoleCommand("csSetMoisture",
            "Set field moisture: csSetMoisture <fieldId> <0.0-1.0>",
            "consoleSetMoisture", g_csManager)
        addConsoleCommand("csForceStress",
            "Force maximum stress on a field: csForceStress <fieldId>",
            "consoleForceStress", g_csManager)
        addConsoleCommand("csSimulateHeat",
            "Simulate heat wave for N in-game days: csSimulateHeat <days>",
            "consoleSimulateHeat", g_csManager)
        addConsoleCommand("csDebug",
            "Toggle verbose debug logging",
            "consoleToggleDebug", g_csManager)
    end
end)

-- 3. Per-frame update
FSBaseMission.update = Utils.appendedFunction(FSBaseMission.update, function(self, dt)
    if g_csManager ~= nil then
        g_csManager:update(dt)
    end
end)

-- 4. Draw hook (HUD rendering)
FSBaseMission.draw = Utils.appendedFunction(FSBaseMission.draw, function(self)
    if g_csManager ~= nil then
        g_csManager:draw()
    end
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
        end
    end
end)

-- 6. Save
FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, function(self, xmlFile)
    if g_csManager ~= nil then
        g_csManager:saveToXMLFile(xmlFile)
    end
end)

-- 7. Load saved state (fires after fields are populated)
Mission00.onStartMission = Utils.appendedFunction(Mission00.onStartMission, function(self, ...)
    if g_csManager ~= nil then
        g_csManager:loadFromXMLFile()
    end
end)

-- 8. Multiplayer: send initial state to new client
FSBaseMission.sendInitialClientState = Utils.appendedFunction(
    FSBaseMission.sendInitialClientState,
    function(self, connection, objectId, farmId)
        if g_csManager ~= nil then
            g_csManager:sendInitialClientState(connection)
        end
    end
)
