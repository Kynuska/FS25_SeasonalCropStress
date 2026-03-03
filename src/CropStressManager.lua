-- ============================================================
-- CropStressManager.lua
-- Central coordinator. Owns all subsystems, manages the lifecycle
-- (initialize → hourly tick → draw → delete → save/load) and
-- exposes the global g_cropStressManager reference.
--
-- Also houses CropEventBus — a lightweight internal event emitter
-- used for loose coupling between subsystems. Avoids depending on
-- g_messageCenter's integer-mapped MessageType IDs.
-- ============================================================

-- ============================================================
-- LOGGING HELPER
-- g_logManager may be nil during early load or late delete.
-- ============================================================
local function csLog(msg)
    if g_logManager ~= nil then
        g_logManager:devInfo("[CropStress]", msg)
    else
        print("[CropStress] " .. tostring(msg))
    end
end

-- ============================================================
-- CROP EVENT BUS
-- Simple publish/subscribe for mod-internal events.
-- Subscribers receive (context, data) where context is the
-- object registered as the listener's self/context.
-- ============================================================
CropEventBus = {}
CropEventBus.listeners = {}

function CropEventBus.subscribe(eventName, callback, context)
    if CropEventBus.listeners[eventName] == nil then
        CropEventBus.listeners[eventName] = {}
    end
    table.insert(CropEventBus.listeners[eventName], { cb = callback, ctx = context })
end

function CropEventBus.publish(eventName, data)
    local list = CropEventBus.listeners[eventName]
    if list == nil then return end
    for _, listener in ipairs(list) do
        listener.cb(listener.ctx, data)
    end
end

function CropEventBus.unsubscribeAll(context)
    for _, list in pairs(CropEventBus.listeners) do
        for i = #list, 1, -1 do
            if list[i].ctx == context then
                table.remove(list, i)
            end
        end
    end
end

-- ============================================================
-- CROP STRESS MANAGER
-- ============================================================
CropStressManager = {}
CropStressManager.__index = CropStressManager


function CropStressManager.new()
    local self = setmetatable({}, CropStressManager)

    self.eventBus = CropEventBus

    -- State
    self.isInitialized = false
    self.debugMode     = false

    -- fieldId → field object lookup. Built by buildFieldMap() in installFieldReadyUpdater().
    -- All subsystems use this instead of getFieldByIndex() or linear scans.
    self.fieldById = {}

    -- Hourly tick tracking (monotonic day * 24 + hour)
    self.lastHourKey   = -1

    -- Settings (created here with defaults; loaded and applied in onStartMission)
    self.settings = CropStressSettings.new()

    -- Guard: WeatherIntegration must be loaded before CropStressManager (see main.lua phase order)
    if WeatherIntegration == nil then
        csLog("ERROR: WeatherIntegration is nil — check main.lua source() order")
        return nil
    end
    if WeatherIntegration.new == nil then
        csLog("ERROR: WeatherIntegration.new is nil — class definition incomplete")
        return nil
    end

    -- Subsystems (constructed here, initialized in :initialize() when g_currentMission is ready)
    self.weatherIntegration = WeatherIntegration.new(self)
    self.soilSystem         = SoilMoistureSystem.new(self)
    self.stressModifier     = CropStressModifier.new(self)
    self.irrigationManager  = IrrigationManager.new(self)       -- Phase 2 stub
    self.hudOverlay         = HUDOverlay.new(self)
    self.consultant         = CropConsultant.new(self)
    self.npcIntegration     = NPCIntegration.new(self)
    self.financeIntegration = FinanceIntegration.new(self)      -- Phase 4 stub

    -- Phase 4 optional bridges — guarded so a missing source() doesn't crash the whole mod
    if UsedEquipmentMarketplace ~= nil then
        self.usedEquipmentMarketplace = UsedEquipmentMarketplace.new(self)
    else
        csLog("WARNING: UsedEquipmentMarketplace class not loaded — check main.lua source() order")
        self.usedEquipmentMarketplace = { initialize=function()end, delete=function()end, enableUsedPlusMode=function()end }
    end

    if PrecisionFarmingOverlay ~= nil then
        self.precisionFarmingOverlay = PrecisionFarmingOverlay.new(self)
    else
        csLog("WARNING: PrecisionFarmingOverlay class not loaded — check main.lua source() order")
        self.precisionFarmingOverlay = { initialize=function()end, delete=function()end, enablePrecisionFarmingMode=function()end }
    end

    -- New optional mod bridges (loaded in main.lua after PrecisionFarmingOverlay)
    local function makeNoop(methods)
        local stub = {}
        for _, m in ipairs(methods) do
            if m == "isActive" then
                stub[m] = function() return false end
            elseif m == "getActiveVehicleCount" or m == "getDestinationCount" or m == "getWaterDestinationCount" then
                stub[m] = function() return 0 end
            else
                stub[m] = function() end
            end
        end
        return stub
    end

    if SoilFertilizerIntegration ~= nil then
        self.soilFertilizerIntegration = SoilFertilizerIntegration.new(self)
    else
        csLog("WARNING: SoilFertilizerIntegration class not loaded — check main.lua source() order")
        self.soilFertilizerIntegration = makeNoop({"initialize","delete","enableSoilFertilizerMode","hourlyRefresh","isActive","getFieldEvapMod","getFieldStressMod","getSummary"})
    end

    if CoursePlayIntegration ~= nil then
        self.coursePlayIntegration = CoursePlayIntegration.new(self)
    else
        csLog("WARNING: CoursePlayIntegration class not loaded — check main.lua source() order")
        self.coursePlayIntegration = makeNoop({"initialize","delete","enableCoursePlayMode","hourlyRefresh","isActive","getActiveVehicleCount","getVehiclesOnField","getContextForField"})
    end

    if AutoDriveIntegration ~= nil then
        self.autoDriveIntegration = AutoDriveIntegration.new(self)
    else
        csLog("WARNING: AutoDriveIntegration class not loaded — check main.lua source() order")
        self.autoDriveIntegration = makeNoop({"initialize","delete","enableAutoDriveMode","hourlyRefresh","isActive","getDestinationCount","getWaterDestinationCount","getCriticalAlertHint"})
    end

    self.saveLoad           = SaveLoadHandler.new(self)

    return self
end

-- Called from Mission00.loadMission00Finished — g_currentMission is ready here
function CropStressManager:initialize()
    if g_currentMission == nil then
        csLog("CRITICAL: g_currentMission nil at initialize — aborting")
        return
    end

    -- Initialize subsystems in dependency order
    self.weatherIntegration:initialize()
    self.soilSystem:initialize()
    self.stressModifier:initialize()
    self.irrigationManager:initialize()
    self.hudOverlay:initialize()
    self.consultant:initialize()

    -- Optional mod bridges — each checks for their mod's global at runtime
    self:detectOptionalMods()
    self.npcIntegration:initialize()
    self.financeIntegration:initialize()
    self.usedEquipmentMarketplace:initialize()
    self.precisionFarmingOverlay:initialize()
    self.soilFertilizerIntegration:initialize()
    self.coursePlayIntegration:initialize()
    self.autoDriveIntegration:initialize()

    -- Persistence handler
    self.saveLoad:initialize()

    -- Capture first hour key so hourly tick fires correctly from the start.
    -- env.currentHour is a direct property — not a method call.
    local env = g_currentMission.environment
    if env ~= nil then
        local day  = env.currentMonotonicDay or 0
        local hour = env.currentHour or 0
        self.lastHourKey = day * 24 + hour
    end

    -- NOTE: settings are NOT loaded or applied here.
    -- onStartMission fires after fields are populated and is the correct
    -- lifecycle point to load settings + call applySettings().
    -- (main.lua onStartMission hook handles both.)

    self.isInitialized = true

    csLog(string.format(
        "CropStressManager initialized. Fields tracked: %d",
        self.soilSystem:getFieldCount()
    ))
end

-- Called from loadMission00Finished. Installs a self-removing frame updater
-- (NPCFavor pattern) that polls g_currentMission.isMissionStarted and
-- g_fieldManager.fields each frame. When both are ready it enumerates fields,
-- builds the fieldId lookup map, and removes itself — no lifecycle hooks needed.
function CropStressManager:installFieldReadyUpdater()
    if not self.isInitialized then return end
    if self._fieldReadyUpdaterInstalled then return end
    self._fieldReadyUpdaterInstalled = true

    local manager = self
    local updater = {
        _done = false,
        update = function(u, dt)
            if u._done then return true end

            -- Wait for mission started AND g_fieldManager with at least one field
            if not g_currentMission or not g_currentMission.isMissionStarted then
                return false
            end
            if not g_fieldManager or not g_fieldManager.fields then
                return false
            end
            if next(g_fieldManager.fields) == nil then
                return false  -- fields table exists but is empty — keep waiting
            end

            -- Ready — enumerate and map fields exactly once
            u._done = true

            local found = manager.soilSystem:enumerateFields()
            csLog(string.format("CropStressManager fieldReady: enumerateFields found %d fields", found))

            local mapped = manager:buildFieldMap()
            csLog(string.format("CropStressManager fieldReady: buildFieldMap mapped %d fields", mapped))

            if found == 0 then
                csLog("CropStressManager fieldReady: WARNING — enumerateFields returned 0. Check g_fieldManager.fields.")
            end

            return true  -- remove updater
        end
    }

    if g_currentMission and g_currentMission.addUpdateable then
        g_currentMission:addUpdateable(updater)
        csLog("CropStressManager: field-ready updater installed")
    else
        csLog("CropStressManager: WARNING — addUpdateable not available, attempting immediate enumeration")
        manager.soilSystem:enumerateFields()
        manager:buildFieldMap()
    end
end

-- ============================================================
-- FIELD ID MAP
-- Builds a fieldId → field object lookup table.
-- Must be called AFTER g_fieldManager.fields is populated
-- (installFieldReadyUpdater handles the correct timing).
--
-- Why: getFieldByIndex(n) returns fields[n] — the nth element
-- of an internal array — NOT the field whose field.fieldId == n.
-- On custom maps, deleted/renumbered fields, or any map that
-- loads fields in a different order, getFieldByIndex(fieldId)
-- silently returns the WRONG field. The only correct approach
-- is to iterate getFields() once, build a hash map keyed by
-- field.fieldId, and do all subsequent lookups in O(1).
--
-- Pattern confirmed by every production FS22/FS25 mod (AdditionalFieldInfo,
-- CropRotation, CoursePlay) and explicitly documented on GDN forums.
-- ============================================================
function CropStressManager:buildFieldMap()
    self.fieldById = {}
    if g_fieldManager == nil or g_fieldManager.fields == nil then
        csLog("buildFieldMap: g_fieldManager unavailable — map will be empty")
        return 0
    end

    local count = 0
    for _, field in pairs(g_fieldManager.fields) do
        if field ~= nil and field.fieldId ~= nil then
            self.fieldById[field.fieldId] = field
            count = count + 1
        end
    end

    csLog(string.format("buildFieldMap: %d fields mapped by fieldId", count))
    return count
end

-- Apply current settings to all subsystems.
-- NOTE: settings.enabled is NOT pushed here; it is honoured as an early-return
-- guard in onHourlyTick() and draw() so the simulation simply stops running.
function CropStressManager:applySettings()
    if not self.isInitialized then return end
    if self.settings == nil then return end

    -- Apply settings to subsystems
    self.hudOverlay.isVisible = self.settings.hudVisible
    self.soilSystem:setEvapMultiplier(self.settings:getTotalEvapMultiplier())
    self.soilSystem:setCriticalThreshold(self.settings.criticalThreshold)
    self.stressModifier:setRateMultiplier(self.settings:getDifficultyStressMultiplier())
    self.stressModifier:setMaxYieldLoss(self.settings.maxYieldLoss)
    self.irrigationManager:setCostsEnabled(self.settings.irrigationCosts)
    self.consultant:setAlertsEnabled(self.settings.alertsEnabled)
    self.consultant:setAlertCooldown(self.settings.alertCooldown)
    self.debugMode = self.settings.debugMode

    -- Push persisted HUD position (client-local display preference, not synced to MP)
    self.hudOverlay.panelX = self.settings.hudPanelX
    self.hudOverlay.panelY = self.settings.hudPanelY

    csLog("Settings applied to all subsystems")
end

-- ============================================================
-- PER-FRAME UPDATE (called from FSBaseMission.update hook)
-- ============================================================
function CropStressManager:update(dt)
    if not self.isInitialized then return end
    if g_currentMission == nil then return end

    local env = g_currentMission.environment
    if env == nil then return end

    -- Hourly tick detection
    -- env.currentHour is a direct property, not a method
    local day     = env.currentMonotonicDay or 0
    local hour    = env.currentHour or 0
    local hourKey = day * 24 + hour

    if hourKey ~= self.lastHourKey then
        self.lastHourKey = hourKey
        self:onHourlyTick()
    end

    -- HUD frame update (handles auto-show, input response)
    self.hudOverlay:update(dt)
end

function CropStressManager:onHourlyTick()
    -- Respect the player's master on/off toggle
    if not self.settings.enabled then return end

    -- 1. Poll current weather state
    self.weatherIntegration:update()

    -- 2a. Refresh optional mod data caches before the simulation tick
    self.soilFertilizerIntegration:hourlyRefresh()  -- pH + OM modifiers per field
    self.coursePlayIntegration:hourlyRefresh()        -- CP vehicle positions
    self.autoDriveIntegration:hourlyRefresh()         -- AutoDrive destination count

    -- 2b. Advance soil moisture simulation (reads SoilFertilizer cache internally)
    self.soilSystem:hourlyUpdate(self.weatherIntegration)

    -- 3. Accumulate crop stress where moisture is critical
    self.stressModifier:hourlyUpdate()

    self.irrigationManager:hourlyScheduleCheck()
    self.financeIntegration:chargeHourlyCosts()

    -- Phase 3: Consultant alert evaluation
    self.consultant:hourlyEvaluate()

    if self.debugMode then
        local seasonName = WeatherIntegration.SEASON_NAMES[self.weatherIntegration:getCurrentSeason()]
            or tostring(self.weatherIntegration:getCurrentSeason())
        csLog(string.format(
            "Hourly tick complete. Season=%s Temp=%.1f Rain=%s",
            seasonName,
            self.weatherIntegration:getCurrentTemp(),
            tostring(self.weatherIntegration.isRaining)
        ))
    end
end

-- ============================================================
-- DRAW (called from FSBaseMission.draw hook)
-- ============================================================
function CropStressManager:draw()
    if not self.isInitialized then return end
    if not self.settings.enabled then return end
    self.hudOverlay:draw()
end

-- ============================================================
-- SAVE / LOAD
-- ============================================================
function CropStressManager:saveToXMLFile(xmlFile)
    if not self.isInitialized then return end
    self.saveLoad:saveToXMLFile(xmlFile)
end

function CropStressManager:loadFromXMLFile()
    if not self.isInitialized then return end
    self.saveLoad:loadFromXMLFile()
end

-- ============================================================
-- MULTIPLAYER
-- ============================================================
function CropStressManager:sendInitialClientState(connection)
    if not self.isInitialized then return end
    if g_server == nil then return end  -- only server sends

    -- Push current settings to the joining client so they stay in sync
    -- with the host's configuration.  Field moisture/stress sync is Phase 2
    -- (requires NetworkNode events — raw connection:getStream() is not available).
    CropStressSettingsSyncEvent.sendAllToConnection(connection)
    csLog("MP: sent current settings to new client")
end

-- ============================================================
-- OPTIONAL MOD DETECTION
-- ============================================================
function CropStressManager:detectOptionalMods()
    -- Use plain global access (not getfenv) — FS25 mod sandboxing means getfenv(0)
    -- reads from our mod's own environment, not the shared game global table where
    -- other mods export their globals via getfenv(0)["x"] = val.
    if g_NPCSystem ~= nil then
        csLog("FS25_NPCFavor detected — enabling NPC integration")
        self.npcIntegration.npcFavorActive = true
        -- Also enable NPCFavor mode on the consultant so alerts route through Alex Chen
        self.consultant:enableNPCFavorMode()
    end

    -- UsedPlusAPI is the confirmed public static interface (XelaNull/FS25_UsedPlus).
    -- g_usedPlusManager is the legacy/internal global from older versions — kept as fallback.
    if UsedPlusAPI ~= nil or g_usedPlusManager ~= nil then
        csLog("FS25_UsedPlus detected — enabling finance integration")
        self.financeIntegration:enableUsedPlusMode()
        self.usedEquipmentMarketplace:enableUsedPlusMode()
    end

    if g_precisionFarming ~= nil then
        csLog("Precision Farming DLC detected — enabling PF compat (Phase 4)")
        self.precisionFarmingOverlay:enablePrecisionFarmingMode()
    end

    -- FS25_SoilFertilizer (sibling mod by same author)
    -- Global: g_SoilFertilityManager (confirmed from SoilFertilizer main.lua)
    if g_SoilFertilityManager ~= nil then
        csLog("FS25_SoilFertilizer detected — soil pH and organic matter will affect moisture simulation")
        self.soilFertilizerIntegration:enableSoilFertilizerMode()
    end

    -- CoursePlay FS25
    -- Global: g_Courseplay (capital P — confirmed from Courseplay.lua; FS22 used lowercase g_courseplay)
    if g_Courseplay ~= nil then
        csLog("CoursePlay detected — CP vehicle activity will appear in stress alerts")
        self.coursePlayIntegration:enableCoursePlayMode()
    end

    -- AutoDrive FS25
    -- Global: AutoDrive (no g_ prefix — confirmed from AutoDrive.lua; FS22 used g_autoDrive)
    if AutoDrive ~= nil then
        csLog("AutoDrive detected — water destination hints will appear in critical alerts")
        self.autoDriveIntegration:enableAutoDriveMode()
    end
end

-- ============================================================
-- INPUT EVENT — CONSULTANT DIALOG
-- ============================================================
function CropStressManager:onOpenConsultantDialog()
    -- CsDialogLoader lazily loads the dialog on first call, then shows it.
    -- No data setter needed — CropConsultantDialog.onOpen() reads live data.
    CsDialogLoader.show("CropConsultantDialog")
end

-- ============================================================
-- INPUT EVENT — HUD TOGGLE
-- ============================================================
function CropStressManager:onToggleHUD()
    self.hudOverlay:toggle()
    -- Keep settings in sync so the next save/load persists the player's preference.
    if self.settings ~= nil then
        self.settings.hudVisible = self.hudOverlay.isVisible
    end
end

function CropStressManager:onOpenIrrigationDialog()
    local irrMgr = self.irrigationManager
    if irrMgr == nil then return end

    -- Find first registered system to open (Phase 2 simplified approach)
    local firstId = nil
    for id, _ in pairs(irrMgr.systems) do
        firstId = id
        break
    end

    if firstId ~= nil then
        -- CsDialogLoader.show() calls setSystemId(firstId) BEFORE showDialog(),
        -- so onOpen() sees a valid systemId when it fires.
        CsDialogLoader.show("IrrigationScheduleDialog", "setSystemId", firstId)
    else
        if g_currentMission ~= nil then
            g_currentMission:showBlinkingWarning(
                (g_i18n ~= nil and g_i18n:getText("cs_no_irrigation_systems"))
                or "No irrigation systems registered.", 3000)
        end
    end
end

-- ============================================================
-- CLEANUP
-- ============================================================
function CropStressManager:delete()
    -- Unsubscribe all event bus listeners
    CropEventBus.listeners = {}

    -- Subsystem cleanup (reverse order of init)
    self.autoDriveIntegration:delete()
    self.coursePlayIntegration:delete()
    self.soilFertilizerIntegration:delete()
    self.precisionFarmingOverlay:delete()
    self.usedEquipmentMarketplace:delete()
    self.financeIntegration:delete()
    self.npcIntegration:delete()
    self.consultant:delete()
    self.hudOverlay:delete()
    self.irrigationManager:delete()
    self.stressModifier:delete()
    self.soilSystem:delete()
    self.weatherIntegration:delete()
    self.saveLoad:delete()

    self.isInitialized = false
    csLog("CropStressManager deleted")
end

-- ============================================================
-- DEBUG CONSOLE COMMANDS
-- ============================================================
function CropStressManager:consoleHelp()
    print("=== FS25_SeasonalCropStress Debug Commands ===")
    print("  csStatus               — Print system status overview")
    print("  csSetMoisture <id> <v> — Set field moisture (0.0-1.0)")
    print("  csForceStress <id>     — Force max stress on a field")
    print("  csSimulateHeat <days>  — Simulate heat wave for N in-game days")
    print("  csDebug                — Toggle verbose debug logging")
    print("  csConsultant           — Open the Crop Consultant dialog")
    print("==============================================")
end

function CropStressManager:consoleStatus()
    print("=== CropStress Status ===")
    print(string.format("  Initialized: %s", tostring(self.isInitialized)))
    print(string.format("  Debug mode:  %s", tostring(self.debugMode)))

    if self.weatherIntegration ~= nil then
        local seas = WeatherIntegration.SEASON_NAMES[self.weatherIntegration.currentSeason] or "?"
        print(string.format("  Season: %s  Temp: %.1f°C  Raining: %s",
            seas, self.weatherIntegration.currentTemp,
            tostring(self.weatherIntegration.isRaining)))
    end

    print(string.format("  Fields tracked: %d", self.soilSystem:getFieldCount()))

    -- Optional mod integration status
    print("  Optional integrations:")
    print(string.format("    NPCFavor:       %s", tostring(self.npcIntegration and self.npcIntegration.npcFavorActive or false)))
    print(string.format("    UsedPlus:       %s", tostring(self.financeIntegration and self.financeIntegration.usedPlusActive or false)))
    print(string.format("    PrecisionFarm:  %s", tostring(self.precisionFarmingOverlay and self.precisionFarmingOverlay.pfActive or false)))
    print(string.format("    SoilFertilizer: %s", tostring(self.soilFertilizerIntegration and self.soilFertilizerIntegration.sfActive or false)))
    print(string.format("    CoursePlay:     %s (vehicles active: %d)",
        tostring(self.coursePlayIntegration and self.coursePlayIntegration.cpActive or false),
        self.coursePlayIntegration and self.coursePlayIntegration:getActiveVehicleCount() or 0))
    print(string.format("    AutoDrive:      %s (destinations: %d, water: %d)",
        tostring(self.autoDriveIntegration and self.autoDriveIntegration.adActive or false),
        self.autoDriveIntegration and self.autoDriveIntegration:getDestinationCount()      or 0,
        self.autoDriveIntegration and self.autoDriveIntegration:getWaterDestinationCount() or 0))

    -- Print top 5 driest fields
    local sorted = self.soilSystem:getFieldsSortedByMoisture()
    print("  Driest fields:")
    for i = 1, math.min(5, #sorted) do
        local f = sorted[i]
        local stress = self.stressModifier:getStress(f.fieldId)
        print(string.format("    Field %d: %.1f%% moisture, stress %.2f",
            f.fieldId, f.moisture * 100, stress))
    end
end

function CropStressManager:consoleSetMoisture(fieldIdStr, valueStr)
    local fieldId = tonumber(fieldIdStr)
    local value   = tonumber(valueStr)
    if fieldId == nil or value == nil then
        print("Usage: csSetMoisture <fieldId> <0.0-1.0>")
        return
    end
    value = math.max(0.0, math.min(1.0, value))
    if self.soilSystem:setMoisture(fieldId, value) then
        print(string.format("Field %d moisture set to %.1f%%", fieldId, value * 100))
    else
        print(string.format("Field %d not found in moisture data", fieldId))
    end
end

function CropStressManager:consoleForceStress(fieldIdStr)
    local fieldId = tonumber(fieldIdStr)
    if fieldId == nil then
        print("Usage: csForceStress <fieldId>")
        return
    end
    self.stressModifier.fieldStress[fieldId] = 1.0
    print(string.format("Field %d stress forced to maximum (1.0)", fieldId))
end

function CropStressManager:consoleSimulateHeat(daysStr)
    local days = tonumber(daysStr) or 1
    if days < 1 or days > 30 then
        print("Usage: csSimulateHeat <1-30>")
        return
    end

    -- Temporarily override weather state for the simulation
    local savedTemp = self.weatherIntegration.currentTemp
    local savedRain = self.weatherIntegration.hourlyRainAmount

    self.weatherIntegration.currentTemp      = 38.0  -- extreme heat
    self.weatherIntegration.hourlyRainAmount = 0.0   -- no rain

    for _ = 1, days do
        for _ = 1, 24 do
            self.soilSystem:hourlyUpdate(self.weatherIntegration)
            self.stressModifier:hourlyUpdate()
        end
    end

    self.weatherIntegration.currentTemp      = savedTemp
    self.weatherIntegration.hourlyRainAmount = savedRain

    print(string.format("Simulated %d-day heat wave. Check csStatus for field state.", days))
end


function CropStressManager:consoleConsultant()
    local shown = CsDialogLoader.show("CropConsultantDialog")
    if shown then
        print("CropStress: CropConsultant dialog opened")
    else
        print("CropStress: CropConsultant dialog failed to open — check log for CsDialogLoader errors")
    end
end

function CropStressManager:consoleToggleDebug()
    self.debugMode = not self.debugMode
    print(string.format("CropStress debug mode: %s", tostring(self.debugMode)))
end