-- ============================================================
-- CropStressSettings.lua
-- Data model and persistence for mod settings.
-- Follows NPCFavor pattern: data model → ESC menu → multiplayer sync.
-- Settings live in a sidecar XML file per savegame.
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
-- CROP STRESS SETTINGS CLASS
-- ============================================================
CropStressSettings = {}
CropStressSettings.__index = CropStressSettings

-- Default values matching the current hardcoded constants
local DEFAULTS = {
    enabled = true,
    difficulty = "normal",
    hudVisible = true,
    evapotranspiration = "normal",
    maxYieldLoss = 0.60,
    criticalThreshold = 0.25,
    irrigationCosts = true,
    alertsEnabled = true,
    alertCooldown = 12,
    debugMode = false
}

-- Difficulty multipliers
local DIFFICULTY_MULTIPLIERS = {
    easy = { stress = 0.5, evap = 0.7 },
    normal = { stress = 1.0, evap = 1.0 },
    hard = { stress = 1.5, evap = 1.4 }
}

-- Validation ranges
local VALIDATION = {
    maxYieldLoss = { min = 0.30, max = 0.75 },
    criticalThreshold = { min = 0.15, max = 0.35 },
    alertCooldown = { min = 4, max = 24 }
}

function CropStressSettings.new()
    local self = setmetatable({}, CropStressSettings)
    
    -- Initialize with defaults
    self:resetToDefaults()
    
    return self
end

-- Reset all settings to defaults
function CropStressSettings:resetToDefaults()
    for key, value in pairs(DEFAULTS) do
        self[key] = value
    end
end

-- Load settings from savegame XML file
function CropStressSettings:load(missionInfo)
    if missionInfo == nil then
        csLog("WARNING: missionInfo is nil, using defaults")
        return
    end
    
    local savegameDir = missionInfo.savegameDirectory
    if savegameDir == nil then
        csLog("WARNING: savegameDirectory is nil, using defaults")
        return
    end
    
    local xmlPath = savegameDir .. "/cropStressSettings.xml"
    
    -- Check if file exists
    if not fileExists(xmlPath) then
        csLog("Settings file not found, using defaults")
        return
    end
    
    local xmlFile = XMLFile.load("CropStressSettings", xmlPath)
    if xmlFile == nil then
        csLog("WARNING: Failed to load settings XML, using defaults")
        return
    end
    
    -- Read all settings with type-appropriate getters
    self.enabled = xmlFile:getBool("cropStressSettings.enabled") or DEFAULTS.enabled
    self.difficulty = xmlFile:getString("cropStressSettings.difficulty") or DEFAULTS.difficulty
    self.hudVisible = xmlFile:getBool("cropStressSettings.hudVisible") or DEFAULTS.hudVisible
    self.evapotranspiration = xmlFile:getString("cropStressSettings.evapotranspiration") or DEFAULTS.evapotranspiration
    self.maxYieldLoss = xmlFile:getFloat("cropStressSettings.maxYieldLoss") or DEFAULTS.maxYieldLoss
    self.criticalThreshold = xmlFile:getFloat("cropStressSettings.criticalThreshold") or DEFAULTS.criticalThreshold
    self.irrigationCosts = xmlFile:getBool("cropStressSettings.irrigationCosts") or DEFAULTS.irrigationCosts
    self.alertsEnabled = xmlFile:getBool("cropStressSettings.alertsEnabled") or DEFAULTS.alertsEnabled
    self.alertCooldown = xmlFile:getInt("cropStressSettings.alertCooldown") or DEFAULTS.alertCooldown
    self.debugMode = xmlFile:getBool("cropStressSettings.debugMode") or DEFAULTS.debugMode
    
    xmlFile:delete()
    
    -- Validate and clamp values
    self:validateSettings()
    
    csLog("Settings loaded from " .. xmlPath)
end

-- Save settings to savegame XML file
function CropStressSettings:saveToXMLFile(missionInfo)
    if missionInfo == nil then
        csLog("WARNING: missionInfo is nil, cannot save settings")
        return
    end
    
    local savegameDir = missionInfo.savegameDirectory
    if savegameDir == nil then
        csLog("WARNING: savegameDirectory is nil, cannot save settings")
        return
    end
    
    local xmlPath = savegameDir .. "/cropStressSettings.xml"
    
    -- Create new XML file
    local xmlFile = XMLFile.create("CropStressSettings", xmlPath, "cropStressSettings")
    if xmlFile == nil then
        csLog("WARNING: Failed to create settings XML file")
        return
    end
    
    -- Write all settings with type-appropriate setters
    xmlFile:setBool("cropStressSettings.enabled", self.enabled)
    xmlFile:setString("cropStressSettings.difficulty", self.difficulty)
    xmlFile:setBool("cropStressSettings.hudVisible", self.hudVisible)
    xmlFile:setString("cropStressSettings.evapotranspiration", self.evapotranspiration)
    xmlFile:setFloat("cropStressSettings.maxYieldLoss", self.maxYieldLoss)
    xmlFile:setFloat("cropStressSettings.criticalThreshold", self.criticalThreshold)
    xmlFile:setBool("cropStressSettings.irrigationCosts", self.irrigationCosts)
    xmlFile:setBool("cropStressSettings.alertsEnabled", self.alertsEnabled)
    xmlFile:setInt("cropStressSettings.alertCooldown", self.alertCooldown)
    xmlFile:setBool("cropStressSettings.debugMode", self.debugMode)
    
    xmlFile:save()
    xmlFile:delete()
    
    csLog("Settings saved to " .. xmlPath)
end

-- Validate and clamp settings to valid ranges
function CropStressSettings:validateSettings()
    -- Validate difficulty
    if self.difficulty ~= "easy" and self.difficulty ~= "normal" and self.difficulty ~= "hard" then
        self.difficulty = DEFAULTS.difficulty
        csLog("Invalid difficulty, reset to 'normal'")
    end
    
    -- Validate evapotranspiration
    if self.evapotranspiration ~= "slow" and self.evapotranspiration ~= "normal" and self.evapotranspiration ~= "fast" then
        self.evapotranspiration = DEFAULTS.evapotranspiration
        csLog("Invalid evapotranspiration, reset to 'normal'")
    end
    
    -- Clamp maxYieldLoss
    if self.maxYieldLoss < VALIDATION.maxYieldLoss.min then
        self.maxYieldLoss = VALIDATION.maxYieldLoss.min
        csLog("maxYieldLoss too low, clamped to " .. self.maxYieldLoss)
    elseif self.maxYieldLoss > VALIDATION.maxYieldLoss.max then
        self.maxYieldLoss = VALIDATION.maxYieldLoss.max
        csLog("maxYieldLoss too high, clamped to " .. self.maxYieldLoss)
    end
    
    -- Clamp criticalThreshold
    if self.criticalThreshold < VALIDATION.criticalThreshold.min then
        self.criticalThreshold = VALIDATION.criticalThreshold.min
        csLog("criticalThreshold too low, clamped to " .. self.criticalThreshold)
    elseif self.criticalThreshold > VALIDATION.criticalThreshold.max then
        self.criticalThreshold = VALIDATION.criticalThreshold.max
        csLog("criticalThreshold too high, clamped to " .. self.criticalThreshold)
    end
    
    -- Clamp alertCooldown
    if self.alertCooldown < VALIDATION.alertCooldown.min then
        self.alertCooldown = VALIDATION.alertCooldown.min
        csLog("alertCooldown too low, clamped to " .. self.alertCooldown)
    elseif self.alertCooldown > VALIDATION.alertCooldown.max then
        self.alertCooldown = VALIDATION.alertCooldown.max
        csLog("alertCooldown too high, clamped to " .. self.alertCooldown)
    end
    
    -- Ensure boolean values are actually booleans
    self.enabled = not not self.enabled
    self.hudVisible = not not self.hudVisible
    self.irrigationCosts = not not self.irrigationCosts
    self.alertsEnabled = not not self.alertsEnabled
    self.debugMode = not not self.debugMode
end

-- Get stress rate multiplier based on difficulty
function CropStressSettings:getDifficultyStressMultiplier()
    local mult = DIFFICULTY_MULTIPLIERS[self.difficulty]
    return mult and mult.stress or 1.0
end

-- Get evapotranspiration multiplier based on difficulty
function CropStressSettings:getDifficultyEvapMultiplier()
    local mult = DIFFICULTY_MULTIPLIERS[self.difficulty]
    return mult and mult.evap or 1.0
end

-- Get evapotranspiration base multiplier based on setting
function CropStressSettings:getEvapBaseMultiplier()
    if self.evapotranspiration == "slow" then
        return 0.7
    elseif self.evapotranspiration == "fast" then
        return 1.4
    else
        return 1.0  -- normal
    end
end

-- Get combined evapotranspiration multiplier (base * difficulty)
function CropStressSettings:getTotalEvapMultiplier()
    return self:getEvapBaseMultiplier() * self:getDifficultyEvapMultiplier()
end

-- Debug: print current settings
function CropStressSettings:debugPrint()
    csLog("=== CropStress Settings ===")
    csLog("enabled: " .. tostring(self.enabled))
    csLog("difficulty: " .. self.difficulty)
    csLog("hudVisible: " .. tostring(self.hudVisible))
    csLog("evapotranspiration: " .. self.evapotranspiration)
    csLog("maxYieldLoss: " .. tostring(self.maxYieldLoss))
    csLog("criticalThreshold: " .. tostring(self.criticalThreshold))
    csLog("irrigationCosts: " .. tostring(self.irrigationCosts))
    csLog("alertsEnabled: " .. tostring(self.alertsEnabled))
    csLog("alertCooldown: " .. tostring(self.alertCooldown))
    csLog("debugMode: " .. tostring(self.debugMode))
    csLog("stressMultiplier: " .. tostring(self:getDifficultyStressMultiplier()))
    csLog("evapMultiplier: " .. tostring(self:getTotalEvapMultiplier()))
    csLog("=========================")
end