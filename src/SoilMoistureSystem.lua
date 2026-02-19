-- ============================================================
-- SoilMoistureSystem.lua
-- Maintains a soil moisture value (0.0–1.0) for every field on
-- the map. Updated every in-game hour via CropStressManager's
-- hourly tick.
--
-- Moisture rises from:
--   • Rainfall (via WeatherIntegration poll)
--   • Irrigation (Phase 2 — IrrigationManager sets irrigationGainRate)
-- Moisture falls from:
--   • Evapotranspiration: base rate × temp modifier × season modifier × soil modifier
-- ============================================================

SoilMoistureSystem = {}
SoilMoistureSystem.__index = SoilMoistureSystem

-- Base evaporation per in-game hour (before modifiers).
-- At 1.0 modifier: 0.004 = 0.4% per hour → full evap in ~104 hours (~4 game days)
SoilMoistureSystem.BASE_EVAP_RATE = 0.004

-- Soil type evaporation modifiers and rain absorption coefficients
SoilMoistureSystem.SOIL_PARAMS = {
    sandy = { evapMod = 1.40, rainAbsorb = 0.90 },
    loamy = { evapMod = 1.00, rainAbsorb = 1.00 },
    clay  = { evapMod = 0.70, rainAbsorb = 0.80 },
}

-- Season-aware starting moisture (used when no saved state exists)
-- 0=spring, 1=summer, 2=autumn, 3=winter
SoilMoistureSystem.SEASON_START_MOISTURE = { [0]=0.60, [1]=0.40, [2]=0.55, [3]=0.70 }

-- Critical threshold — below this, fire CS_CRITICAL_THRESHOLD
SoilMoistureSystem.CRITICAL_MOISTURE = 0.25

function SoilMoistureSystem.new(manager)
    local self = setmetatable({}, SoilMoistureSystem)
    self.manager = manager

    -- keyed by fieldId (integer)
    -- Each entry:
    -- {
    --   fieldId         = number,
    --   moisture        = float (0.0-1.0),
    --   soilType        = string ("sandy"/"loamy"/"clay"),
    --   irrigationGain  = float (0.0 = none; set by IrrigationManager in Phase 2),
    -- }
    self.fieldData = {}

    self.irrigationGains = {}  -- fieldId -> total gain per hour

    -- Track which fields have already had a first-run HUD trigger
    self.criticalAlertCooldown = {}  -- fieldId → lastAlertHourKey

    self.isInitialized = false
    return self
end

function SoilMoistureSystem:initialize()
    if g_currentMission == nil or g_currentMission.fieldManager == nil then
        g_logManager:devInfo("[CropStress]", "SoilMoistureSystem: fieldManager unavailable at init")
        return
    end

    local season = 0
    if g_currentMission.environment ~= nil then
        season = g_currentMission.environment:currentSeason() or 0
    end
    local startMoisture = SoilMoistureSystem.SEASON_START_MOISTURE[season] or 0.50

    local fields = g_currentMission.fieldManager:getFields()
    local count = 0

    for _, field in pairs(fields) do
        local fid = field.fieldId
        if fid ~= nil then
            self.fieldData[fid] = {
                fieldId        = fid,
                moisture       = startMoisture,
                soilType       = self:detectSoilType(field),
                irrigationGain = 0.0,
            }
            count = count + 1
        end
    end

    -- Subscribe to irrigation events (once, here — never inside the hourly loop)
    if self.manager ~= nil and self.manager.eventBus ~= nil then
        self.manager.eventBus.subscribe("CS_IRRIGATION_STARTED", self.onIrrigationStarted, self)
        self.manager.eventBus.subscribe("CS_IRRIGATION_STOPPED", self.onIrrigationStopped, self)
    end

    self.isInitialized = true
    g_logManager:devInfo("[CropStress]", string.format(
        "SoilMoistureSystem initialized. %d fields tracked. Start moisture=%.0f%% (season %d)",
        count, startMoisture * 100, season
    ))
end

-- Called every in-game hour
function SoilMoistureSystem:hourlyUpdate(weather)
    if not self.isInitialized then return end
    if weather == nil then return end

    local evapMultiplier  = weather:getHourlyEvapMultiplier()
    local rainAmount      = weather:getHourlyRainAmount()

    local env = g_currentMission and g_currentMission.environment
    local hourKey = env and ((env.currentMonotonicDay or 0) * 24 + (env:getHour() or 0)) or 0

    for fieldId, data in pairs(self.fieldData) do
        local soilParams = SoilMoistureSystem.SOIL_PARAMS[data.soilType]
            or SoilMoistureSystem.SOIL_PARAMS.loamy

        -- Evapotranspiration loss this hour
        local evapLoss = SoilMoistureSystem.BASE_EVAP_RATE
            * evapMultiplier
            * soilParams.evapMod

        -- Rain gain (modulated by soil absorption)
        local rainGain = rainAmount * soilParams.rainAbsorb

        local irrigGain = self.irrigationGains[fieldId] or 0.0

        local prevMoisture = data.moisture
        data.moisture = math.max(0.0, math.min(1.0,
            data.moisture - evapLoss + rainGain + irrigGain))

        -- Fire event via CropEventBus
        if self.manager ~= nil and self.manager.eventBus ~= nil then
            self.manager.eventBus.publish("CS_MOISTURE_UPDATED", {
                fieldId  = fieldId,
                previous = prevMoisture,
                current  = data.moisture,
            })
        end

        -- Critical threshold check (with cooldown to avoid spam)
        if data.moisture <= SoilMoistureSystem.CRITICAL_MOISTURE then
            local lastAlert = self.criticalAlertCooldown[fieldId] or -999
            if (hourKey - lastAlert) >= 12 then
                self.criticalAlertCooldown[fieldId] = hourKey
                if self.manager ~= nil and self.manager.eventBus ~= nil then
                    self.manager.eventBus.publish("CS_CRITICAL_THRESHOLD", {
                        fieldId      = fieldId,
                        moistureLevel = data.moisture,
                    })
                end
            end
        end

        if self.manager.debugMode then
            g_logManager:devInfo("[CropStress]", string.format(
                "Field %d: %.1f%% → %.1f%% (evap=%.4f rain=%.4f irr=%.4f)",
                fieldId, prevMoisture * 100, data.moisture * 100,
                evapLoss, rainGain, irrigGain
            ))
        end
    end
end

-- Returns moisture (0.0–1.0) for a field, or nil if unknown
function SoilMoistureSystem:getMoisture(fieldId)
    local d = self.fieldData[fieldId]
    return d and d.moisture or nil
end

-- Force-set moisture (for debug console commands)
function SoilMoistureSystem:setMoisture(fieldId, value)
    if self.fieldData[fieldId] ~= nil then
        self.fieldData[fieldId].moisture = math.max(0.0, math.min(1.0, value))
        return true
    end
    return false
end

function SoilMoistureSystem:getFieldCount()
    local count = 0
    for _ in pairs(self.fieldData) do count = count + 1 end
    return count
end

-- Returns a sorted list of {fieldId, moisture, soilType} for HUD display
function SoilMoistureSystem:getFieldsSortedByMoisture()
    local list = {}
    for fieldId, data in pairs(self.fieldData) do
        table.insert(list, { fieldId = fieldId, moisture = data.moisture, soilType = data.soilType })
    end
    table.sort(list, function(a, b) return a.moisture < b.moisture end)
    return list
end

function SoilMoistureSystem:onIrrigationStarted(data)
    self.irrigationGains[data.fieldId] = (self.irrigationGains[data.fieldId] or 0) + data.ratePerHour
end

function SoilMoistureSystem:onIrrigationStopped(data)
    self.irrigationGains[data.fieldId] = (self.irrigationGains[data.fieldId] or 0) - data.ratePerHour
    if self.irrigationGains[data.fieldId] < 0.001 then
        self.irrigationGains[data.fieldId] = nil
    end
end

-- Detect soil type from FS25 map metadata.
-- FS25 maps vary widely in what metadata they expose.
-- This uses a best-effort hierarchy; defaults to "loamy".
function SoilMoistureSystem:detectSoilType(field)
    -- 1. Try field's custom attribute if map author set it
    if field.soilType ~= nil then
        local s = tostring(field.soilType):lower()
        if SoilMoistureSystem.SOIL_PARAMS[s] ~= nil then return s end
    end

    -- 2. Try terrain detail layer at field center
    -- (Requires map support — many vanilla maps don't expose this)
    -- NOTE: If FS25 LUADOC documents getTerrainAttributeAtWorldPos, implement here.

    -- 3. Heuristic: use field position's biome/map region if available
    -- (Placeholder for future map-specific support)

    -- 4. Default
    return "loamy"
end

function SoilMoistureSystem:delete()
    self.isInitialized = false
end
