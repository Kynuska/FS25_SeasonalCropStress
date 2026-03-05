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
    --   centerX         = float (world X of field centre, used for RW cell sampling),
    --   centerZ         = float (world Z of field centre, used for RW cell sampling),
    -- }
    self.fieldData = {}

    -- When FS25_RealisticWeather is present this is g_currentMission.moistureSystem.
    -- hourlyUpdate() reads RW cells instead of running our own evap/rain simulation.
    self.rwMoistureSystem = nil

    self.irrigationGains = {}  -- fieldId -> total gain per hour

    -- Per-field cooldown to avoid spamming CS_CRITICAL_THRESHOLD
    self.criticalAlertCooldown = {}  -- fieldId → lastAlertHourKey

    self.isInitialized = false
    return self
end

function SoilMoistureSystem:initialize()
    -- Subscribe to irrigation events immediately (don't depend on fieldManager being ready)
    if self.manager ~= nil and self.manager.eventBus ~= nil then
        self.manager.eventBus.subscribe("CS_IRRIGATION_STARTED", self.onIrrigationStarted, self)
        self.manager.eventBus.subscribe("CS_IRRIGATION_STOPPED", self.onIrrigationStopped, self)
    end

    self.isInitialized = true
end

-- Populate fieldData for every field on the map.
-- Uses g_fieldManager.fields directly (NPCFavor pattern) — more reliable than
-- g_currentMission.fieldManager:getFields() which can be nil until well after
-- isMissionStarted fires. Safe to call multiple times — skips fields already
-- in fieldData to preserve any save data loaded earlier.
-- Returns the number of NEW fields added.
function SoilMoistureSystem:enumerateFields()
    if g_fieldManager == nil or g_fieldManager.fields == nil then
        csLog("SoilMoistureSystem: g_fieldManager unavailable — field enumeration deferred")
        return 0
    end

    -- currentSeason is a direct property on the environment object, not a method call.
    -- Normalise to 0-based (spring=0) — some FS25 builds return 1-based (1–4).
    local season = 0
    if g_currentMission ~= nil and g_currentMission.environment ~= nil then
        local rawSeason = g_currentMission.environment.currentSeason or 0
        if rawSeason >= 1 and rawSeason <= 4 then
            rawSeason = rawSeason - 1
        end
        season = rawSeason
    end
    local startMoisture = SoilMoistureSystem.SEASON_START_MOISTURE[season] or 0.50

    local count = 0
    for _, field in pairs(g_fieldManager.fields) do
        -- FS25: fields are identified by farmland ID. field.fieldId does not exist.
        local fid = field.farmland and field.farmland.id
        if fid ~= nil and self.fieldData[fid] == nil then
            -- field.posX/posZ are confirmed FS25 properties (set from polygon centroid in Field:load).
            -- field:getCenterOfFieldWorldPosition() returns the same values and is also valid.
            local cx = field.posX or 0
            local cz = field.posZ or 0
            self.fieldData[fid] = {
                fieldId        = fid,
                moisture       = startMoisture,
                soilType       = self:detectSoilType(field),
                irrigationGain = 0.0,
                centerX        = cx,
                centerZ        = cz,
            }
            count = count + 1
        end
    end

    if count > 0 then
        csLog(string.format(
            "SoilMoistureSystem: %d fields enumerated (season %d, start moisture=%.0f%%)",
            count, season, startMoisture * 100
        ))
    end
    return count
end

-- Called every in-game hour
function SoilMoistureSystem:hourlyUpdate(weather)
    if not self.isInitialized then return end
    if weather == nil then return end

    -- FS25_RealisticWeather integration: read moisture from RW cells instead of
    -- simulating our own evap/rain. We still apply irrigation gains on top and
    -- write them back to RW's system so it stays in sync.
    if self.rwMoistureSystem ~= nil then
        self:_syncFromRW()
        return
    end

    local evapMultiplier = weather:getHourlyEvapMultiplier()
    local rainAmount     = weather:getHourlyRainAmount()

    -- currentHour is a direct property on the environment object, not a method call
    local env     = g_currentMission and g_currentMission.environment
    local hourKey = 0
    if env ~= nil then
        hourKey = (env.currentMonotonicDay or 0) * 24 + (env.currentHour or 0)
    end

    -- Hoist SoilFertilizer integration reference outside the field loop — it is
    -- constant for the entire tick and resolving it per-field is wasteful.
    local settingsEvapMult = self.evapMultiplier or 1.0
    local sfInteg = self.manager and self.manager.soilFertilizerIntegration
    local sfHasEvap   = sfInteg ~= nil and type(sfInteg.getFieldEvapMod)   == "function"
    local sfHasStress = sfInteg ~= nil and type(sfInteg.getFieldStressMod) == "function"

    for fieldId, data in pairs(self.fieldData) do
        local soilParams = SoilMoistureSystem.SOIL_PARAMS[data.soilType]
            or SoilMoistureSystem.SOIL_PARAMS.loamy

        -- Evapotranspiration loss this hour.
        -- evapMultiplier   = weather-based (temperature + season) from WeatherIntegration
        -- settingsEvapMult = player-configured multiplier (difficulty × evap rate setting)
        -- sfEvapMod        = per-field organic matter modifier from FS25_SoilFertilizer (if present)
        --                    High OM (>5%) lowers evap; poor OM (<1%) raises it. Default 1.0.
        local sfEvapMod = sfHasEvap and sfInteg:getFieldEvapMod(fieldId) or 1.0
        local evapLoss = SoilMoistureSystem.BASE_EVAP_RATE
            * evapMultiplier
            * soilParams.evapMod
            * settingsEvapMult
            * sfEvapMod

        -- Rain gain (modulated by soil absorption)
        local rainGain  = rainAmount * soilParams.rainAbsorb
        local irrigGain = self.irrigationGains[fieldId] or 0.0

        local prevMoisture = data.moisture
        data.moisture = math.max(0.0, math.min(1.0,
            data.moisture - evapLoss + rainGain + irrigGain))

        -- Publish moisture update event
        if self.manager ~= nil and self.manager.eventBus ~= nil then
            self.manager.eventBus.publish("CS_MOISTURE_UPDATED", {
                fieldId  = fieldId,
                previous = prevMoisture,
                current  = data.moisture,
            })
        end

        -- Critical threshold check (12-hour cooldown per field to avoid spam).
        -- Use getCriticalMoisture() so the player's settings value is honoured;
        -- falls back to the class constant if applySettings() hasn't run yet.
        -- SoilFertilizer pH modifier raises the threshold for acid/alkaline fields
        -- (crops become moisture-stressed at a higher moisture level when pH is poor).
        local sfStressMod = sfHasStress and sfInteg:getFieldStressMod(fieldId) or 0.0
        if data.moisture <= (self:getCriticalMoisture() + sfStressMod) then
            local lastAlert = self.criticalAlertCooldown[fieldId] or -999
            if (hourKey - lastAlert) >= 12 then
                self.criticalAlertCooldown[fieldId] = hourKey
                if self.manager ~= nil and self.manager.eventBus ~= nil then
                    self.manager.eventBus.publish("CS_CRITICAL_THRESHOLD", {
                        fieldId       = fieldId,
                        moistureLevel = data.moisture,
                    })
                end
            end
        end

        if self.manager ~= nil and self.manager.debugMode then
            csLog(string.format(
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
    -- math.max ensures the gain never goes negative on a rate mismatch
    -- (e.g. if stopped fires twice or the rate differs from what was added).
    local remaining = math.max(0, (self.irrigationGains[data.fieldId] or 0) - data.ratePerHour)
    self.irrigationGains[data.fieldId] = (remaining > 0.001) and remaining or nil
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

-- ============================================================
-- RW MOISTURE INTEGRATION
-- ============================================================

-- Wire up (or clear) the RealisticWeather MoistureSystem reference.
-- Called by CropStressManager:detectOptionalMods() when RW is detected.
function SoilMoistureSystem:setRWMoistureSystem(rwSystem)
    self.rwMoistureSystem = rwSystem
    if rwSystem ~= nil then
        csLog("SoilMoistureSystem: RW MoistureSystem wired — own simulation disabled")
    end
end

-- Hourly sync when FS25_RealisticWeather is active.
-- Reads per-cell moisture from RW at each field's centre coordinate,
-- applies our irrigation gains on top, and writes that delta back to
-- RW so its state stays accurate for future reads and its own yield hook.
function SoilMoistureSystem:_syncFromRW()
    local env     = g_currentMission and g_currentMission.environment
    local hourKey = 0
    if env ~= nil then
        hourKey = (env.currentMonotonicDay or 0) * 24 + (env.currentHour or 0)
    end

    local sfInteg     = self.manager and self.manager.soilFertilizerIntegration
    local sfHasStress = sfInteg ~= nil and type(sfInteg.getFieldStressMod) == "function"

    for fieldId, data in pairs(self.fieldData) do
        -- Sample RW's cell at this field's world-space centre
        local rwValues   = self.rwMoistureSystem:getValuesAtCoords(
            data.centerX, data.centerZ, {"moisture"})
        local rwMoisture = rwValues and rwValues.moisture

        -- RW returns nil for out-of-bounds cells; keep current value as fallback
        if rwMoisture == nil then
            rwMoisture = data.moisture
        end

        -- Our irrigation gain adds on top of RW's rain/evap simulation
        local irrigGain  = self.irrigationGains[fieldId] or 0.0
        local newMoisture = math.max(0.0, math.min(1.0, rwMoisture + irrigGain))

        -- Write the irrigation delta back to RW so its future reads
        -- include our infrastructure contribution.  addToPendingSync=false:
        -- we don't need MP re-broadcast (RW handles its own MP sync).
        if irrigGain > 0.0 then
            self.rwMoistureSystem:setValuesAtCoords(
                data.centerX, data.centerZ, {moisture = irrigGain}, false)
        end

        local prevMoisture = data.moisture
        data.moisture      = newMoisture

        -- Publish moisture update event so HUD and consultant still work
        if self.manager ~= nil and self.manager.eventBus ~= nil then
            self.manager.eventBus.publish("CS_MOISTURE_UPDATED", {
                fieldId  = fieldId,
                previous = prevMoisture,
                current  = data.moisture,
            })
        end

        -- Critical threshold alert (12-hour cooldown, same as own-sim path)
        local sfStressMod = sfHasStress and sfInteg:getFieldStressMod(fieldId) or 0.0
        if data.moisture <= (self:getCriticalMoisture() + sfStressMod) then
            local lastAlert = self.criticalAlertCooldown[fieldId] or -999
            if (hourKey - lastAlert) >= 12 then
                self.criticalAlertCooldown[fieldId] = hourKey
                if self.manager ~= nil and self.manager.eventBus ~= nil then
                    self.manager.eventBus.publish("CS_CRITICAL_THRESHOLD", {
                        fieldId       = fieldId,
                        moistureLevel = data.moisture,
                    })
                end
            end
        end

        if self.manager ~= nil and self.manager.debugMode then
            csLog(string.format(
                "Field %d [RW]: %.1f%% → %.1f%% (rw=%.1f%% irr=%.4f)",
                fieldId, prevMoisture * 100, data.moisture * 100,
                rwMoisture * 100, irrigGain
            ))
        end
    end
end

function SoilMoistureSystem:delete()
    self.isInitialized = false
end

-- Set evapotranspiration multiplier from settings
function SoilMoistureSystem:setEvapMultiplier(multiplier)
    self.evapMultiplier = multiplier or 1.0
end

-- Set critical moisture threshold from settings
function SoilMoistureSystem:setCriticalThreshold(threshold)
    self.criticalMoisture = math.max(0.15, math.min(0.35, threshold or 0.25))
end

-- Override CRITICAL_MOISTURE for settings compatibility
function SoilMoistureSystem:getCriticalMoisture()
    return self.criticalMoisture or SoilMoistureSystem.CRITICAL_MOISTURE
end

-- (field enumeration is now handled by CropStressManager's addUpdateable init pattern)