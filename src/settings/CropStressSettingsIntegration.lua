-- ============================================================
-- CropStressSettingsIntegration.lua
-- ESC menu integration for mod settings.
-- Mirrors NPCSettingsIntegration.lua pattern exactly.
-- Injects "Seasonal Crop Stress" section into InGameMenuSettingsFrame.
-- ============================================================

-- ============================================================
-- LOGGING HELPER
-- ============================================================
local function csLog(msg)
    if g_logManager ~= nil then
        g_logManager:devInfo("[CropStress]", msg)
    else
        print("[CropStress] " .. tostring(msg))
    end
end

-- ============================================================
-- GLOBAL FLAG TO PREVENT DOUBLE-INIT
-- ============================================================
local cs_initDone = false

-- ============================================================
-- ESC MENU INTEGRATION
-- ============================================================
local function onFrameOpen(self)
    if cs_initDone then return end
    cs_initDone = true
    
    -- Only inject if we have a manager and settings
    if g_cropStressManager == nil or g_cropStressManager.settings == nil then
        csLog("WARNING: CropStressManager or settings not available, skipping ESC menu injection")
        return
    end
    
    addSettingsElements(self)
    updateSettingsUI(self)
end

-- ============================================================
-- UI ELEMENT CREATION
-- ============================================================
local function addSectionHeader(frame, text)
    local header = frame:createElement("CropStressHeader")
    header:setText(text)
    header:setColor(1, 1, 1, 1)
    header:setFontSize(24)
    header:setAlignment(AlignmentType.CENTER)
    header:setPadding(0, 10, 0, 10)
    frame.gameSettingsLayout:addElement(header)
end

local function addBinaryOption(frame, callbackName, shortText, longText)
    local option = frame:createElement("CropStressBinaryOption")
    option:setText(shortText)
    option:setTooltip(longText)
    option:setCallback(callbackName)
    option:setWidth(1.0)
    option:setHeight(0.05)
    frame.gameSettingsLayout:addElement(option)
    return option
end

local function addMultiTextOption(frame, callbackName, textsArray, shortText, longText)
    local option = frame:createElement("CropStressMultiTextOption")
    option:setText(shortText)
    option:setTooltip(longText)
    option:setCallback(callbackName)
    option:setWidth(1.0)
    option:setHeight(0.05)
    option:setTexts(textsArray)
    frame.gameSettingsLayout:addElement(option)
    return option
end

-- ============================================================
-- SETTINGS ELEMENTS
-- ============================================================
local settingsElements = {}

local function addSettingsElements(frame)
    addSectionHeader(frame, g_i18n:getText("cs_settings_section"))
    
    -- Enable Mod
    settingsElements.enabled = addBinaryOption(
        frame,
        "onEnabledChanged",
        g_i18n:getText("cs_settings_enabled_short"),
        g_i18n:getText("cs_settings_enabled_long")
    )
    
    -- Difficulty
    settingsElements.difficulty = addMultiTextOption(
        frame,
        "onDifficultyChanged",
        { "Easy", "Normal", "Hard" },
        g_i18n:getText("cs_settings_difficulty_short"),
        g_i18n:getText("cs_settings_difficulty_long")
    )
    
    -- HUD Visible
    settingsElements.hudVisible = addBinaryOption(
        frame,
        "onHudVisibleChanged",
        g_i18n:getText("cs_settings_hud_short"),
        g_i18n:getText("cs_settings_hud_long")
    )
    
    -- Evapotranspiration
    settingsElements.evapotranspiration = addMultiTextOption(
        frame,
        "onEvapotranspirationChanged",
        { "Slow", "Normal", "Fast" },
        g_i18n:getText("cs_settings_evap_short"),
        g_i18n:getText("cs_settings_evap_long")
    )
    
    -- Max Yield Loss
    settingsElements.maxYieldLoss = addMultiTextOption(
        frame,
        "onMaxYieldLossChanged",
        { "30%", "45%", "60%", "75%" },
        g_i18n:getText("cs_settings_yield_loss_short"),
        g_i18n:getText("cs_settings_yield_loss_long")
    )
    
    -- Critical Threshold
    settingsElements.criticalThreshold = addMultiTextOption(
        frame,
        "onCriticalThresholdChanged",
        { "15%", "25%", "35%" },
        g_i18n:getText("cs_settings_threshold_short"),
        g_i18n:getText("cs_settings_threshold_long")
    )
    
    -- Irrigation Costs
    settingsElements.irrigationCosts = addBinaryOption(
        frame,
        "onIrrigationCostsChanged",
        g_i18n:getText("cs_settings_irr_costs_short"),
        g_i18n:getText("cs_settings_irr_costs_long")
    )
    
    -- Alerts Enabled
    settingsElements.alertsEnabled = addBinaryOption(
        frame,
        "onAlertsEnabledChanged",
        g_i18n:getText("cs_settings_alerts_short"),
        g_i18n:getText("cs_settings_alerts_long")
    )
    
    -- Alert Cooldown
    settingsElements.alertCooldown = addMultiTextOption(
        frame,
        "onAlertCooldownChanged",
        { "4h", "8h", "12h", "24h" },
        g_i18n:getText("cs_settings_cooldown_short"),
        g_i18n:getText("cs_settings_cooldown_long")
    )
    
    -- Debug Mode
    settingsElements.debugMode = addBinaryOption(
        frame,
        "onDebugModeChanged",
        g_i18n:getText("cs_settings_debug_short"),
        g_i18n:getText("cs_settings_debug_long")
    )
end

-- ============================================================
-- UI UPDATE
-- ============================================================
local function updateSettingsUI(frame)
    if g_cropStressManager == nil or g_cropStressManager.settings == nil then return end
    
    local settings = g_cropStressManager.settings
    
    -- Update binary options
    if settingsElements.enabled then
        settingsElements.enabled:setState(settings.enabled)
    end
    
    if settingsElements.hudVisible then
        settingsElements.hudVisible:setState(settings.hudVisible)
    end
    
    if settingsElements.irrigationCosts then
        settingsElements.irrigationCosts:setState(settings.irrigationCosts)
    end
    
    if settingsElements.alertsEnabled then
        settingsElements.alertsEnabled:setState(settings.alertsEnabled)
    end
    
    if settingsElements.debugMode then
        settingsElements.debugMode:setState(settings.debugMode)
    end
    
    -- Update multi-text options
    if settingsElements.difficulty then
        local index = 2  -- default to Normal
        if settings.difficulty == "easy" then index = 1
        elseif settings.difficulty == "hard" then index = 3 end
        settingsElements.difficulty:setState(index)
    end
    
    if settingsElements.evapotranspiration then
        local index = 2  -- default to Normal
        if settings.evapotranspiration == "slow" then index = 1
        elseif settings.evapotranspiration == "fast" then index = 3 end
        settingsElements.evapotranspiration:setState(index)
    end
    
    if settingsElements.maxYieldLoss then
        local index = 3  -- default to 60%
        if settings.maxYieldLoss == 0.30 then index = 1
        elseif settings.maxYieldLoss == 0.45 then index = 2
        elseif settings.maxYieldLoss == 0.75 then index = 4 end
        settingsElements.maxYieldLoss:setState(index)
    end
    
    if settingsElements.criticalThreshold then
        local index = 2  -- default to 25%
        if settings.criticalThreshold == 0.15 then index = 1
        elseif settings.criticalThreshold == 0.35 then index = 3 end
        settingsElements.criticalThreshold:setState(index)
    end
    
    if settingsElements.alertCooldown then
        local index = 3  -- default to 12h
        if settings.alertCooldown == 4 then index = 1
        elseif settings.alertCooldown == 8 then index = 2
        elseif settings.alertCooldown == 24 then index = 4 end
        settingsElements.alertCooldown:setState(index)
    end
end

-- ============================================================
-- CALLBACK HANDLERS
-- ============================================================
local function applySetting(key, value)
    if g_server ~= nil then
        -- Server-authoritative: apply locally and broadcast to all clients
        g_cropStressManager.settings[key] = value
        g_cropStressManager.settings:validateSettings()
        g_cropStressManager:applySettings()
        g_server:broadcastEvent(CropStressSettingsSyncEvent.newSingle(key, value), false)
    else
        -- Client: send to server
        CropStressSettingsSyncEvent.sendSingleToServer(key, value)
    end
end

-- Binary option callbacks
function onEnabledChanged(self, state)
    applySetting("enabled", state)
end

function onHudVisibleChanged(self, state)
    applySetting("hudVisible", state)
end

function onIrrigationCostsChanged(self, state)
    applySetting("irrigationCosts", state)
end

function onAlertsEnabledChanged(self, state)
    applySetting("alertsEnabled", state)
end

function onDebugModeChanged(self, state)
    applySetting("debugMode", state)
end

-- Multi-text option callbacks
function onDifficultyChanged(self, index)
    local difficulty = "normal"
    if index == 1 then difficulty = "easy"
    elseif index == 3 then difficulty = "hard" end
    applySetting("difficulty", difficulty)
end

function onEvapotranspirationChanged(self, index)
    local evap = "normal"
    if index == 1 then evap = "slow"
    elseif index == 3 then evap = "fast" end
    applySetting("evapotranspiration", evap)
end

function onMaxYieldLossChanged(self, index)
    local loss = 0.60
    if index == 1 then loss = 0.30
    elseif index == 2 then loss = 0.45
    elseif index == 4 then loss = 0.75 end
    applySetting("maxYieldLoss", loss)
end

function onCriticalThresholdChanged(self, index)
    local threshold = 0.25
    if index == 1 then threshold = 0.15
    elseif index == 3 then threshold = 0.35 end
    applySetting("criticalThreshold", threshold)
end

function onAlertCooldownChanged(self, index)
    local cooldown = 12
    if index == 1 then cooldown = 4
    elseif index == 2 then cooldown = 8
    elseif index == 4 then cooldown = 24 end
    applySetting("alertCooldown", cooldown)
end

-- ============================================================
-- INITIALIZATION
-- ============================================================
local function initHooks()
    -- Hook into InGameMenuSettingsFrame.onFrameOpen
    if InGameMenuSettingsFrame ~= nil and InGameMenuSettingsFrame.onFrameOpen ~= nil then
        InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(InGameMenuSettingsFrame.onFrameOpen, onFrameOpen)
        csLog("ESC menu hook installed")
    else
        csLog("WARNING: InGameMenuSettingsFrame.onFrameOpen not found, ESC menu integration skipped")
    end
end

-- Initialize hooks at file load time
initHooks()