-- ============================================================
-- CropConsultant.lua
-- Phase 3 implementation.
--
-- Subscribes to CS_CRITICAL_THRESHOLD events and generates
-- player-facing alerts at three severity levels.
-- Enforces a 12-in-game-hour cooldown per field to prevent spam.
--
-- In standalone mode:  shows blinkingWarning notifications.
-- With FS25_NPCFavor:  forwards alerts to NPCIntegration which
--                      presents them as NPC dialog from Alex Chen.
--
-- Alert severity levels:
--   INFO     (40-50% moisture) — "monitor conditions"          4s
--   WARNING  (25-40% moisture) — "irrigation recommended"      6s
--   CRITICAL (<25% moisture)  — "irrigate NOW!"               10s + auto-show HUD
-- ============================================================

CropConsultant = {}
CropConsultant.__index = CropConsultant

-- Severity thresholds (moisture fractions)
CropConsultant.SEVERITY_INFO_MAX     = 0.50   -- 40-50%: monitor
CropConsultant.SEVERITY_WARNING_MAX  = 0.40   -- 25-40%: recommend
CropConsultant.SEVERITY_CRITICAL_MAX = 0.25   -- <25%:   emergency

-- Alert display durations (milliseconds)
CropConsultant.DURATION_INFO     = 4000
CropConsultant.DURATION_WARNING  = 6000
CropConsultant.DURATION_CRITICAL = 10000

-- Cooldown: minimum in-game hours between alerts for the same field
CropConsultant.COOLDOWN_HOURS = 12

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
-- CONSTRUCTOR
-- ============================================================
function CropConsultant.new(manager)
    local self = setmetatable({}, CropConsultant)
    self.manager = manager

    -- fieldId_type → last alert hourKey (monotonic day * 24 + hour)
    self.alertCooldowns = {}

    -- Whether NPCFavor integration is delegating our alerts
    self.npcFavorMode = false

    self.isInitialized = false
    return self
end

-- ============================================================
-- INITIALIZE
-- Called by CropStressManager:initialize() after all subsystems exist.
-- ============================================================
function CropConsultant:initialize()
    if self.manager == nil or self.manager.eventBus == nil then
        csLog("CropConsultant: eventBus unavailable at init")
        self.isInitialized = true
        return
    end

    -- Subscribe to critical threshold events from SoilMoistureSystem
    self.manager.eventBus.subscribe("CS_CRITICAL_THRESHOLD", self.onCriticalThreshold, self)

    -- Subscribe to moisture updates for WARNING-level band-crossing detection
    self.manager.eventBus.subscribe("CS_MOISTURE_UPDATED", self.onMoistureUpdated, self)

    self.isInitialized = true
    csLog("CropConsultant initialized (standalone mode)")
end

-- ============================================================
-- ENABLE NPC FAVOR MODE
-- Called by CropStressManager:detectOptionalMods() when NPCFavor is present.
-- ============================================================
function CropConsultant:enableNPCFavorMode()
    self.npcFavorMode = true
    csLog("CropConsultant: NPCFavor mode enabled — alerts will route through Alex Chen")
end

-- ============================================================
-- HOURLY EVALUATE
-- Called by CropStressManager:onHourlyTick().
-- Proactively checks fields for INFO-level alerts (40-50% moisture
-- while a crop is in its critical window). CS_CRITICAL_THRESHOLD
-- only fires below 0.25, so this fills the gap.
-- ============================================================
function CropConsultant:hourlyEvaluate()
    if not self.isInitialized then return end
    if self.manager == nil or self.manager.soilSystem == nil then return end

    local env     = g_currentMission and g_currentMission.environment
    local hourKey = 0
    if env ~= nil then
        hourKey = (env.currentMonotonicDay or 0) * 24 + (env.currentHour or 0)
    end

    for fieldId, data in pairs(self.manager.soilSystem.fieldData) do
        local moisture = data.moisture

        -- Only evaluate INFO range here (WARNING covered by band-crossing in onMoistureUpdated)
        if moisture >= CropConsultant.SEVERITY_WARNING_MAX
        and moisture <= CropConsultant.SEVERITY_INFO_MAX then
            -- Only alert if stress is actively accumulating (crop in critical window)
            local stress = 0
            if self.manager.stressModifier ~= nil then
                stress = self.manager.stressModifier:getStress(fieldId)
            end

            if stress > 0.01 then
                local cooldownKey = fieldId .. "_info"
                local lastAlert   = self.alertCooldowns[cooldownKey] or -999
                if (hourKey - lastAlert) >= CropConsultant.COOLDOWN_HOURS then
                    self.alertCooldowns[cooldownKey] = hourKey
                    local cropName = self:getCropName(fieldId)
                    self:showAlert(fieldId, moisture, "INFO", cropName)
                end
            end
        end
    end
end

-- ============================================================
-- EVENT HANDLER: CS_CRITICAL_THRESHOLD
-- Fires when moisture drops to or below 0.25.
-- ============================================================
function CropConsultant:onCriticalThreshold(data)
    if not self.isInitialized then return end
    if data == nil or data.fieldId == nil then return end

    local fieldId = data.fieldId
    local env     = g_currentMission and g_currentMission.environment
    local hourKey = 0
    if env ~= nil then
        hourKey = (env.currentMonotonicDay or 0) * 24 + (env.currentHour or 0)
    end

    local cooldownKey = fieldId .. "_critical"
    local lastAlert   = self.alertCooldowns[cooldownKey] or -999
    if (hourKey - lastAlert) < CropConsultant.COOLDOWN_HOURS then return end

    self.alertCooldowns[cooldownKey] = hourKey

    local moisture = data.moistureLevel or 0
    local cropName = self:getCropName(fieldId)
    self:showAlert(fieldId, moisture, "CRITICAL", cropName)
end

-- ============================================================
-- EVENT HANDLER: CS_MOISTURE_UPDATED
-- Watches for moisture entering the WARNING band from above.
-- ============================================================
function CropConsultant:onMoistureUpdated(data)
    if not self.isInitialized then return end
    if data == nil then return end

    local fieldId  = data.fieldId
    local previous = data.previous or 1.0
    local current  = data.current  or 1.0

    -- Trigger when crossing INTO the warning band from healthy
    if previous >= CropConsultant.SEVERITY_WARNING_MAX
    and current  < CropConsultant.SEVERITY_WARNING_MAX
    and current  >= CropConsultant.SEVERITY_CRITICAL_MAX then
        local env     = g_currentMission and g_currentMission.environment
        local hourKey = 0
        if env ~= nil then
            hourKey = (env.currentMonotonicDay or 0) * 24 + (env.currentHour or 0)
        end

        local cooldownKey = fieldId .. "_warning"
        local lastAlert   = self.alertCooldowns[cooldownKey] or -999
        if (hourKey - lastAlert) < CropConsultant.COOLDOWN_HOURS then return end
        self.alertCooldowns[cooldownKey] = hourKey

        local cropName = self:getCropName(fieldId)
        self:showAlert(fieldId, current, "WARNING", cropName)
    end
end

-- ============================================================
-- SHOW ALERT
-- Builds i18n message, shows blinking warning, optionally
-- forwards to NPCIntegration.
-- ============================================================
function CropConsultant:showAlert(fieldId, moisture, severity, cropName)
    if g_currentMission == nil then return end

    local msgKey   = "cs_alert_info"
    local duration = CropConsultant.DURATION_INFO

    if severity == "CRITICAL" then
        msgKey   = "cs_alert_critical"
        duration = CropConsultant.DURATION_CRITICAL
    elseif severity == "WARNING" then
        msgKey   = "cs_alert_warning"
        duration = CropConsultant.DURATION_WARNING
    end

    local template = (g_i18n ~= nil) and g_i18n:getText(msgKey) or msgKey
    local msg = string.format(template, fieldId, cropName or "?")

    g_currentMission:showBlinkingWarning(msg, duration)

    csLog(string.format("CropConsultant [%s] Field %d (%.0f%%): %s",
        severity, fieldId, moisture * 100, msg))

    -- Forward to NPC integration for dialog / favor generation
    if self.npcFavorMode
    and self.manager ~= nil
    and self.manager.npcIntegration ~= nil then
        self.manager.npcIntegration:sendConsultantAlert({
            fieldId  = fieldId,
            moisture = moisture,
            severity = severity,
            cropName = cropName,
        })
    end
end

-- ============================================================
-- HELPERS
-- ============================================================
function CropConsultant:getCropName(fieldId)
    if g_currentMission == nil or g_currentMission.fieldManager == nil then return "?" end
    local field = nil
    if g_currentMission.fieldManager.getFieldByIndex ~= nil then
        field = g_currentMission.fieldManager:getFieldByIndex(fieldId)
    end
    if field == nil then
        local fields = g_currentMission.fieldManager:getFields()
        for _, f in pairs(fields) do
            if f.fieldId == fieldId then field = f; break end
        end
    end
    if field == nil then return "?" end

    local ft = type(field.getFruitType) == "function"
        and field:getFruitType()
        or field.fruitType
    if ft ~= nil and ft.name ~= nil then
        return ft.name:sub(1,1):upper() .. ft.name:sub(2):lower()
    end
    return "?"
end

-- ============================================================
-- CLEANUP
-- ============================================================
function CropConsultant:delete()
    if self.manager ~= nil and self.manager.eventBus ~= nil then
        self.manager.eventBus.unsubscribeAll(self)
    end
    self.alertCooldowns = {}
    self.isInitialized  = false
end

-- Set alerts enabled flag from settings
function CropConsultant:setAlertsEnabled(enabled)
    self.alertsEnabled = not not enabled
end

-- Set alert cooldown from settings
function CropConsultant:setAlertCooldown(hours)
    self.alertCooldown = math.max(4, math.min(24, hours or 12))
end
