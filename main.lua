-- ============================================================
-- FS25_SeasonalCropStress — main.lua
-- Entry point. Loads all modules via source() in strict dependency
-- order, then wires up FS25 lifecycle hooks.
--
-- Load order:
--   1. Weather bridge
--   2. Core simulation (soil, stress, irrigation)
--   3. Settings
--   4. Player-facing systems (HUD, consultant)
--   5. Optional mod bridges (activated at runtime if mods present)
--   6. Event bus
--   7. Persistence
--   8. GUI dialogs
--   9. Central coordinator (depends on everything above)
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

-- Weather bridge
source(modDir .. "src/WeatherIntegration.lua")

-- Core simulation
source(modDir .. "src/SoilMoistureSystem.lua")
source(modDir .. "src/CropStressModifier.lua")
source(modDir .. "src/IrrigationManager.lua")

-- Settings
source(modDir .. "src/settings/CropStressSettings.lua")
source(modDir .. "src/settings/CropStressSettingsIntegration.lua")

-- Player-facing systems
source(modDir .. "src/HUDOverlay.lua")
source(modDir .. "src/CropConsultant.lua")

-- Optional mod bridges
source(modDir .. "src/NPCIntegration.lua")
source(modDir .. "src/FinanceIntegration.lua")
source(modDir .. "src/UsedEquipmentMarketplace.lua")
source(modDir .. "src/PrecisionFarmingOverlay.lua")
source(modDir .. "src/SoilFertilizerIntegration.lua")
source(modDir .. "src/CoursePlayIntegration.lua")
source(modDir .. "src/AutoDriveIntegration.lua")

-- Event bus
source(modDir .. "src/events/CropStressSettingsSyncEvent.lua")

-- Persistence
source(modDir .. "src/SaveLoadHandler.lua")

-- GUI dialog loader (must precede dialog scripts)
source(modDir .. "src/gui/CsDialogLoader.lua")

-- GUI dialogs
source(modDir .. "gui/FieldMoisturePanel.lua")
source(modDir .. "gui/IrrigationScheduleDialog.lua")
source(modDir .. "gui/CropConsultantDialog.lua")

-- Central coordinator (must load last — depends on all modules above)
source(modDir .. "src/CropStressManager.lua")

-- ============================================================
-- Install harvest yield hook.
-- Attempt 1: at source() load time. HarvestingMachine is a base-game
-- global that SHOULD be available here, but log evidence shows it can
-- be nil on some FS25 builds/load orders. The flag prevents double-install.
-- Attempt 2 (retry) happens inside loadMission00Finished below.
-- ============================================================
CropStressModifier.installHarvestHook()

-- ============================================================
-- INPUT BINDING (NPCFavor pattern — confirmed working)
-- Hook PlayerInputComponent.registerActionEvents. This is the ONLY
-- correct point to register action events in FS25; calling
-- g_inputBinding:registerActionEvent directly in loadMission00Finished
-- is not inside the player input context and silently does nothing.
-- ============================================================
local function csToggleHUDCallback(_, _, inputValue)
    if (inputValue or 0) <= 0 then return end
    if g_cropStressManager ~= nil then g_cropStressManager:onToggleHUD() end
end

local function csOpenIrrigationCallback(_, _, inputValue)
    if (inputValue or 0) <= 0 then return end
    if g_cropStressManager ~= nil then g_cropStressManager:onOpenIrrigationDialog() end
end

local function csOpenConsultantCallback(_, _, inputValue)
    if (inputValue or 0) <= 0 then return end
    if g_cropStressManager ~= nil then g_cropStressManager:onOpenConsultantDialog() end
end

do
    if PlayerInputComponent ~= nil and PlayerInputComponent.registerActionEvents ~= nil then
        local origFn = PlayerInputComponent.registerActionEvents
        PlayerInputComponent.registerActionEvents = function(inputComponent, ...)
            origFn(inputComponent, ...)
            if inputComponent.player ~= nil and inputComponent.player.isOwner then
                g_inputBinding:beginActionEventsModification(PlayerInputComponent.INPUT_CONTEXT_NAME)

                local function reg(actionId, callback, labelKey, labelFallback)
                    if actionId == nil then return end
                    local ok, eventId = g_inputBinding:registerActionEvent(
                        actionId, CropStressManager, callback,
                        false, true, false, false, nil, true
                    )
                    if ok and eventId ~= nil then
                        g_inputBinding:setActionEventActive(eventId, true)
                        g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_NORMAL)
                        local label = (g_i18n ~= nil and g_i18n:getText(labelKey)) or labelFallback
                        g_inputBinding:setActionEventText(eventId, label)
                    end
                end

                reg(InputAction.CS_TOGGLE_HUD,     csToggleHUDCallback,      "input_CS_TOGGLE_HUD",      "Toggle Moisture HUD")
                reg(InputAction.CS_OPEN_IRRIGATION, csOpenIrrigationCallback, "input_CS_OPEN_IRRIGATION", "Open Irrigation Manager")
                reg(InputAction.CS_OPEN_CONSULTANT, csOpenConsultantCallback, "input_CS_OPEN_CONSULTANT", "Open Crop Consultant")

                g_inputBinding:endActionEventsModification()
            end
        end
        print("[CropStress] PlayerInputComponent hook installed")
    else
        print("[CropStress] WARNING: PlayerInputComponent.registerActionEvents not available — keybinds will not work")
    end
end

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

    -- Retry harvest hook if it was skipped at load time (HarvestingMachine was nil).
    -- By loadMission00Finished all base-game classes are guaranteed in scope.
    if not CropStressModifier.harvestHookInstalled then
        CropStressModifier.installHarvestHook()
    end

    g_csManager:initialize()

    -- Register dialogs with CsDialogLoader (NPCFavor confirmed pattern).
    -- Dialogs are lazily loaded on first CsDialogLoader.show() call:
    --   ensureLoaded() creates the instance + calls g_gui:loadGui()
    --   → g_gui:loadGui() calls onCreate() → superClass().onCreate() auto-wires elements
    --   show() calls the data setter BEFORE g_gui:showDialog() fires onOpen()
    -- No stored instance references needed on g_csManager.
    CsDialogLoader.init(modDir)
    CsDialogLoader.register("IrrigationScheduleDialog", IrrigationScheduleDialog, "gui/IrrigationScheduleDialog.xml")
    CsDialogLoader.register("CropConsultantDialog",     CropConsultantDialog,     "gui/CropConsultantDialog.xml")

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
    -- Reset dialog instances so the next mission load creates fresh ones.
    CsDialogLoader.cleanup()

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
-- 'self' here is the FSCareerMissionInfo object, which IS the missionInfo
-- (it has savegameDirectory, xmlFile, etc. — same object CropStressSettings:load() receives).
FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, function(self, xmlFile)
    if g_csManager == nil then return end
    -- Save field moisture / stress / irrigation schedules into careerSavegame.xml
    g_csManager:saveToXMLFile(xmlFile)
    -- Save settings into separate sidecar cropStressSettings.xml
    if g_csManager.settings ~= nil then
        g_csManager.settings:saveToXMLFile(self)
    end
end)

-- 7. Load saved state (fires after fields are populated)
Mission00.onStartMission = Utils.appendedFunction(Mission00.onStartMission, function(self, ...)
    if g_csManager ~= nil then
        -- Load settings from savegame first
        if self.missionInfo ~= nil then
            g_csManager.settings:load(self.missionInfo)
            g_csManager:applySettings()
        end
        
        -- Enumerate fields first (fieldManager is guaranteed ready at this lifecycle stage).
        -- lateInitialize() also retries the harvest hook (last safe point for all base classes).
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

-- 9. Mouse events — RMB repositions the HUD panel.
-- addModEventListener is the correct FS25 pattern for raw mouse input in mods.
-- FS25 button numbers: 1=left, 3=right, 2=middle (confirmed via FS25_NPCFavor).
--
-- Defensive stubs for the listener table. Per confirmed FS25_NPCFavor research, FS25 DOES
-- nil-check before calling keyEvent/update/draw/delete — ESC works correctly without stubs
-- (NPCFavor omits them and ESC functions fine). These stubs are kept as defensive practice
-- only; they do NOT prevent any crash.
addModEventListener({
    update   = function(self, dt) end,
    draw     = function(self) end,
    delete   = function(self) end,
    keyEvent = function(self, unicode, sym, modifier, isDown) end,
    mouseEvent = function(self, posX, posY, isDown, isUp, button)
        if g_csManager == nil then return end
        if g_csManager.hudOverlay == nil then return end
        -- Guard: don't intercept while a GUI/dialog is open.
        -- getIsGuiVisible() returns true for both menus and dialogs in FS25 —
        -- getIsDialogVisible() does not exist in all builds, so we don't call it.
        if g_gui ~= nil and g_gui:getIsGuiVisible() then return end
        g_csManager.hudOverlay:onMouseEvent(posX, posY, isDown, isUp, button)
    end
})