-- ============================================================
-- WeatherIntegration.lua
-- Bridges FS25's environment/weather API to the moisture system.
-- Polled every in-game hour by CropStressManager:onHourlyTick().
--
-- Does NOT subscribe to MessageType events (FS25 event IDs are
-- integer-mapped and may differ by version). Instead, polls the
-- weather state directly — reliable and version-agnostic.
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

    self.isInitialized = false
    return self
end

function WeatherIntegration:initialize()
    if g_currentMission == nil then
        csLog("WeatherIntegration: g_currentMission nil at init")
        return
    end

    -- Do an immediate poll to populate cached values
    self:update()
    self.isInitialized = true
    csLog(string.format(
        "WeatherIntegration initialized. Season=%s Temp=%.1f°C Rain=%s",
        WeatherIntegration.SEASON_NAMES[self.currentSeason] or "?",
        self.currentTemp,
        tostring(self.isRaining)
    ))
end

-- Called every in-game hour by CropStressManager:onHourlyTick()
function WeatherIntegration:update()
    if g_currentMission == nil then return end
    local env = g_currentMission.environment
    if env == nil then return end

    -- Season: direct property access, not a method call
    self.currentSeason = env.currentSeason or WeatherIntegration.SEASON_SPRING

    -- Temperature
    -- Try multiple access paths for compatibility across patch versions
    local temp = 15.0
    if env.weather ~= nil then
        if env.weather.temperature ~= nil then
            temp = env.weather.temperature
        elseif type(env.weather.getCurrentTemperature) == "function" then
            temp = env.weather:getCurrentTemperature() or 15.0
        end
    end
    self.currentTemp = temp

    -- Humidity (optional — used for extended forecast; fall back gracefully)
    if env.weather ~= nil and env.weather.relativeHumidity ~= nil then
        self.currentHumidity = env.weather.relativeHumidity
    end

    -- Rain intensity
    -- FS25: env.weather.rainScale is a 0.0-1.0 normalized rain amount
    self.rainScale = 0.0
    if env.weather ~= nil then
        if env.weather.rainScale ~= nil then
            self.rainScale = env.weather.rainScale or 0.0
        elseif type(env.weather.getRainFallScale) == "function" then
            self.rainScale = env.weather:getRainFallScale() or 0.0
        end
    end
    self.isRaining = self.rainScale > 0.01

    -- Translate rain scale to moisture gain per hour.
    -- Base: 0.012 moisture fraction per hour at rainScale=1.0
    -- Heavy rain (scale ~1.5) gives 0.018/hr; drizzle (0.3) gives 0.0036/hr
    self.hourlyRainAmount = self.isRaining and (0.012 * self.rainScale) or 0.0
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