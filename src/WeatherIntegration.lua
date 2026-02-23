-- ============================================================
-- WeatherIntegration.lua
-- Bridges FS25's environment/weather API to the moisture system.
-- Polled every in-game hour by CropStressManager:onHourlyTick().
--
-- Does NOT subscribe to MessageType events (FS25 event IDs are
-- integer-mapped and may differ by version). Instead, polls the
-- weather state directly — reliable and version-agnostic.
--
-- OPTIONAL MOD INTEGRATION:
-- - FS25_RealisticWeather: Detected at runtime, uses enhanced temperature/rain if present
-- ============================================================

WeatherIntegration = {}
WeatherIntegration.__index = WeatherIntegration

-- Season indices (matches g_currentMission.environment.currentSeason)
WeatherIntegration.SEASON_SPRING = 0
WeatherIntegration.SEASON_SUMMER = 1
WeatherIntegration.SEASON_AUTUMN = 2
WeatherIntegration.SEASON_WINTER = 3

-- Season display names (English — UI uses i18n keys)
WeatherIntegration.SEASON_NAMES = { [0]="Spring", [1]="Summer", [2]="Autumn", [3]="Winter" }

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

function WeatherIntegration.new(manager)
    local self = setmetatable({}, WeatherIntegration)
    self.manager = manager

    -- Cached state (updated each hourly poll)
    self.currentTemp     = 15.0   -- degrees Celsius
    self.currentSeason   = WeatherIntegration.SEASON_SPRING
    self.currentHumidity = 0.5    -- 0.0-1.0

    -- Rain state: rainScale is the FS25 normalized rain intensity (0.0-1.0)
    self.rainScale        = 0.0
    self.isRaining        = false

    -- Accumulated rain for the current hour (in moisture fraction units)
    -- Calculated from rainScale * absorption coefficient
    self.hourlyRainAmount = 0.0

    -- Optional mod integration flags
    self.realisticWeatherActive = false

    self.isInitialized = false
    return self
end

function WeatherIntegration:initialize()
    if g_currentMission == nil then
        csLog("WeatherIntegration: g_currentMission nil at init")
        return
    end

    -- Detect optional mods
    self:detectOptionalMods()

    -- Do an immediate poll to populate cached values
    self:update()
    self.isInitialized = true
    csLog(string.format(
        "WeatherIntegration initialized. Season=%s Temp=%.1f°C Rain=%s%s",
        WeatherIntegration.SEASON_NAMES[self.currentSeason] or "?",
        self.currentTemp,
        tostring(self.isRaining),
        self.realisticWeatherActive and " (RealisticWeather)" or ""
    ))
end

-- ============================================================
-- OPTIONAL MOD DETECTION
-- ============================================================
function WeatherIntegration:detectOptionalMods()
    -- FS25_RealisticWeather detection
    -- This mod exposes g_realisticWeather global with enhanced weather data
    if getfenv(0)["g_realisticWeather"] ~= nil then
        self.realisticWeatherActive = true
        csLog("FS25_RealisticWeather detected — using enhanced weather data")
    elseif getfenv(0)["g_weatherSystem"] ~= nil then
        -- Alternative global name some weather mods use
        self.realisticWeatherActive = true
        csLog("Weather mod detected (g_weatherSystem) — using enhanced weather data")
    end
end

-- Called every in-game hour by CropStressManager:onHourlyTick()
function WeatherIntegration:update()
    if g_currentMission == nil then return end
    local env = g_currentMission.environment
    if env == nil then return end

    -- Season: direct property access, not a method call
    self.currentSeason = env.currentSeason or WeatherIntegration.SEASON_SPRING

    -- Temperature - check RealisticWeather first, then fall back to vanilla
    self.currentTemp = self:getTemperatureFromWeather()

    -- Humidity (optional — used for extended forecast; fall back gracefully)
    self.currentHumidity = self:getHumidity()

    -- Rain intensity
    self.rainScale, self.isRaining = self:getRainFromWeather()

    -- Translate rain scale to moisture gain per hour.
    -- Base: 0.012 moisture fraction per hour at rainScale=1.0
    -- Heavy rain (scale ~1.5) gives 0.018/hr; drizzle (0.3) gives 0.0036/hr
    self.hourlyRainAmount = self.isRaining and (0.012 * self.rainScale) or 0.0
end

-- ============================================================
-- WEATHER DATA ACCESSORS (with RealisticWeather support)
-- ============================================================
function WeatherIntegration:getTemperatureFromWeather()
    local temp = 15.0

    -- Try RealisticWeather first if active
    if self.realisticWeatherActive then
        local rw = g_realisticWeather or g_weatherSystem
        if rw ~= nil then
            -- RealisticWeather typically exposes these methods
            if type(rw.getTemperature) == "function" then
                temp = rw:getTemperature() or 15.0
            elseif type(rw.getCurrentTemperature) == "function" then
                temp = rw:getCurrentTemperature() or 15.0
            elseif rw.temperature ~= nil then
                temp = rw.temperature
            elseif rw.currentTemp ~= nil then
                temp = rw.currentTemp
            end
            -- Return early if we got a valid temperature from RW
            if temp ~= 15.0 then
                return temp
            end
        end
    end

    -- Fall back to vanilla FS25 weather
    local env = g_currentMission.environment
    if env ~= nil and env.weather ~= nil then
        if env.weather.temperature ~= nil then
            temp = env.weather.temperature
        elseif type(env.weather.getCurrentTemperature) == "function" then
            temp = env.weather:getCurrentTemperature() or 15.0
        end
    end

    return temp
end

function WeatherIntegration:getHumidity()
    local humidity = 0.5

    -- Try RealisticWeather first if active
    if self.realisticWeatherActive then
        local rw = g_realisticWeather or g_weatherSystem
        if rw ~= nil then
            if type(rw.getHumidity) == "function" then
                humidity = rw:getHumidity() or 0.5
            elseif rw.humidity ~= nil then
                humidity = rw.humidity
            elseif rw.relativeHumidity ~= nil then
                humidity = rw.relativeHumidity
            end
            if humidity ~= 0.5 then
                return humidity
            end
        end
    end

    -- Fall back to vanilla
    local env = g_currentMission.environment
    if env ~= nil and env.weather ~= nil and env.weather.relativeHumidity ~= nil then
        humidity = env.weather.relativeHumidity
    end

    return humidity
end

function WeatherIntegration:getRainFromWeather()
    local rainScale = 0.0
    local isRaining = false

    -- Try RealisticWeather first if active
    if self.realisticWeatherActive then
        local rw = g_realisticWeather or g_weatherSystem
        if rw ~= nil then
            -- RealisticWeather rain methods - check multiple possible APIs
            if type(rw.getRainIntensity) == "function" then
                rainScale = rw:getRainIntensity() or 0.0
            elseif type(rw.getRainScale) == "function" then
                rainScale = rw:getRainScale() or 0.0
            elseif type(rw.getRainFallScale) == "function" then
                rainScale = rw:getRainFallScale() or 0.0
            elseif rw.rainIntensity ~= nil then
                rainScale = rw.rainIntensity
            elseif rw.rainScale ~= nil then
                rainScale = rw.rainScale
            end
            isRaining = rainScale > 0.01
            if isRaining then
                return rainScale, isRaining
            end
        end
    end

    -- Fall back to vanilla FS25 weather
    local env = g_currentMission.environment
    if env ~= nil and env.weather ~= nil then
        if env.weather.rainScale ~= nil then
            rainScale = env.weather.rainScale or 0.0
        elseif type(env.weather.getRainFallScale) == "function" then
            rainScale = env.weather:getRainFallScale() or 0.0
        end
    end
    isRaining = rainScale > 0.01

    return rainScale, isRaining
end

-- Evaporation multiplier for the current hour, combining temperature and season.
-- Returns a float (typically 0.2 – 2.5). Used by SoilMoistureSystem.
function WeatherIntegration:getHourlyEvapMultiplier()
    -- Temperature component: +3% per °C above 15°C
    local tempMod = 1.0 + math.max(0.0, (self.currentTemp - 15.0) * 0.03)

    -- Season component
    local seasonMods = { [0]=0.80, [1]=1.40, [2]=0.90, [3]=0.20 }
    local seasonMod  = seasonMods[self.currentSeason] or 1.0

    return tempMod * seasonMod
end

-- Returns the moisture gain per hour from current rainfall.
function WeatherIntegration:getHourlyRainAmount()
    return self.hourlyRainAmount
end

function WeatherIntegration:getCurrentSeason()
    return self.currentSeason
end

function WeatherIntegration:getCurrentTemp()
    return self.currentTemp
end

function WeatherIntegration:delete()
    -- No subscriptions to clean up (we poll instead)
    self.isInitialized = false
end
-- ============================================================
-- 5-DAY MOISTURE FORECAST
-- Projects moisture for a field over the next N in-game days
-- based on current weather state (linear extrapolation).
--
-- LUADOC NOTE: Upgrade to use g_currentMission.environment.weather:getForecast()
-- if/when that API is confirmed available in FS25.
-- ============================================================
function WeatherIntegration:getMoistureForecast(fieldId, days)
    days = days or 5

    local soilSystem = self.manager and self.manager.soilSystem
    if soilSystem == nil then
        local t = {}
        for i = 1, days do t[i] = 0.5 end
        return t
    end

    local current = soilSystem:getMoisture(fieldId) or 0.5

    local soilType = "loamy"
    if soilSystem.fieldData ~= nil and soilSystem.fieldData[fieldId] ~= nil then
        soilType = soilSystem.fieldData[fieldId].soilType or "loamy"
    end
    local soilParams = SoilMoistureSystem.SOIL_PARAMS[soilType]
        or SoilMoistureSystem.SOIL_PARAMS.loamy

    local evapPerHour  = SoilMoistureSystem.BASE_EVAP_RATE
        * self:getHourlyEvapMultiplier()
        * soilParams.evapMod
    local rainPerHour  = self:getHourlyRainAmount() * soilParams.rainAbsorb
    local irrigPerHour = 0.0
    if self.manager ~= nil and self.manager.irrigationManager ~= nil then
        irrigPerHour = self.manager.irrigationManager:getIrrigationRateForField(fieldId)
    end

    local netHourly = rainPerHour + irrigPerHour - evapPerHour

    local projections = {}
    local moisture    = current
    for day = 1, days do
        moisture = math.max(0.0, math.min(1.0, moisture + netHourly * 24))
        projections[day] = moisture
    end

    return projections
end