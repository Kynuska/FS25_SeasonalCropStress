-- ============================================================
-- NPCIntegration.lua
-- Phase 3 implementation.
--
-- Detects FS25_NPCFavor at runtime and registers "Alex Chen,
-- Agronomist" as an external NPC. When active, consultant alerts
-- are forwarded here to generate NPC dialog and favor quests.
--
-- IMPORTANT: All g_NPCSystem calls are nil-guarded because
-- the NPCFavor API is verified against a specific mod version.
-- If the API differs, integration fails SILENTLY — the standalone
-- consultant alerts in CropConsultant.lua continue to work.
--
-- NPCFavor exports the global g_NPCSystem (set in NPCFavor/main.lua).
--
-- LUADOC NOTE: The following NPCFavor API calls need verification
-- against FS25_NPCFavor source before shipping:
--   • g_NPCSystem:registerExternalNPC(config)
--   • g_NPCSystem:generateFavor(npcId, favorType, data)
--   • g_NPCSystem:getRelationshipLevel(npcId)
--   • g_NPCSystem:sendNPCDialog(npcId, text, duration)
-- ============================================================

NPCIntegration = {}
NPCIntegration.__index = NPCIntegration

-- NPC configuration for Alex Chen
NPCIntegration.NPC_ID   = "cs_alex_chen"
NPCIntegration.NPC_NAME = "cs_consultant_name"  -- i18n key

-- Favor type identifiers (must match keys expected by NPCFavor)
NPCIntegration.FAVOR_SOIL_SAMPLE      = "SOIL_SAMPLE"
NPCIntegration.FAVOR_IRRIGATION_CHECK = "IRRIGATION_CHECK"
NPCIntegration.FAVOR_EMERGENCY_WATER  = "EMERGENCY_WATER"
NPCIntegration.FAVOR_SEASONAL_PLAN    = "SEASONAL_PLAN"

-- Relationship threshold required to unlock each favor type
-- LUADOC NOTE: verify NPCFavor's relationship scale (likely 0-100)
NPCIntegration.REL_THRESHOLD_BASIC    = 0    -- always available
NPCIntegration.REL_THRESHOLD_ADVANCED = 30   -- requires some relationship
NPCIntegration.REL_THRESHOLD_EXPERT   = 60   -- requires strong relationship

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
function NPCIntegration.new(manager)
    local self = setmetatable({}, NPCIntegration)
    self.manager = manager

    self.npcFavorActive  = false   -- set by CropStressManager:detectOptionalMods()
    self.consultantNPCId = nil     -- returned by registerExternalNPC()
    self.isRegistered    = false   -- true once NPC is registered with NPCFavor
    self.isInitialized   = false

    -- Queue of alerts received before NPC is registered (replayed on registration)
    self.pendingAlerts   = {}

    return self
end

-- ============================================================
-- INITIALIZE
-- Called by CropStressManager:initialize().
-- If npcFavorActive was set by detectOptionalMods(), attempts NPC registration.
-- ============================================================
function NPCIntegration:initialize()
    if not self.npcFavorActive then
        self.isInitialized = true
        csLog("NPCIntegration: FS25_NPCFavor not detected — running without NPC integration")
        return
    end

    self:registerConsultantNPC()
    self.isInitialized = true
end

-- ============================================================
-- REGISTER CONSULTANT NPC
-- Registers Alex Chen with the NPCFavor system.
-- All calls are nil-guarded and wrapped in pcall for safety.
-- ============================================================
function NPCIntegration:registerConsultantNPC()
    if g_NPCSystem == nil then
        csLog("NPCIntegration: g_NPCSystem nil at registration — skipping")
        return
    end

    -- LUADOC NOTE: Verify registerExternalNPC signature against FS25_NPCFavor v1.2+.
    -- Expected: registerExternalNPC(config) → npcId string | nil
    -- Config fields: id, name (i18n key), relationship (starting value), favors (table)
    if type(g_NPCSystem.registerExternalNPC) ~= "function" then
        csLog("NPCIntegration: registerExternalNPC API not found — version mismatch?")
        return
    end

    local npcConfig = {
        id           = NPCIntegration.NPC_ID,
        name         = (g_i18n ~= nil) and g_i18n:getText(NPCIntegration.NPC_NAME) or "Alex Chen",
        relationship = 10,  -- start at a small positive value so player isn't cold
        favors       = self:buildFavorConfigs(),
    }

    local ok, result = pcall(function()
        return g_NPCSystem:registerExternalNPC(npcConfig)
    end)

    if ok and result ~= nil then
        self.consultantNPCId = result
        self.isRegistered    = true
        csLog(string.format("NPCIntegration: Alex Chen registered (npcId=%s)", tostring(result)))

        -- Replay any alerts that arrived before registration
        for _, alertData in ipairs(self.pendingAlerts) do
            self:forwardAlertToNPC(alertData)
        end
        self.pendingAlerts = {}
    else
        csLog(string.format("NPCIntegration: NPC registration failed — %s", tostring(result)))
    end
end

-- ============================================================
-- BUILD FAVOR CONFIGS
-- Returns a table of favor configuration objects for all 4 favor types.
-- LUADOC NOTE: Verify favor config schema against FS25_NPCFavor source.
-- ============================================================
function NPCIntegration:buildFavorConfigs()
    return {
        {
            type             = NPCIntegration.FAVOR_SOIL_SAMPLE,
            relThreshold     = NPCIntegration.REL_THRESHOLD_BASIC,
            -- Callback name called by NPCFavor when player accepts the favor
            -- LUADOC NOTE: verify whether NPCFavor calls a global or passes a callback
            onAccept         = "cs_favor_onSoilSample",
            onComplete       = "cs_favor_onSoilSampleDone",
        },
        {
            type             = NPCIntegration.FAVOR_IRRIGATION_CHECK,
            relThreshold     = NPCIntegration.REL_THRESHOLD_ADVANCED,
            onAccept         = "cs_favor_onIrrigationCheck",
            onComplete       = "cs_favor_onIrrigationCheckDone",
        },
        {
            type             = NPCIntegration.FAVOR_EMERGENCY_WATER,
            relThreshold     = NPCIntegration.REL_THRESHOLD_BASIC,
            onAccept         = "cs_favor_onEmergencyWater",
            onComplete       = "cs_favor_onEmergencyWaterDone",
        },
        {
            type             = NPCIntegration.FAVOR_SEASONAL_PLAN,
            relThreshold     = NPCIntegration.REL_THRESHOLD_EXPERT,
            onAccept         = "cs_favor_onSeasonalPlan",
            onComplete       = "cs_favor_onSeasonalPlanDone",
        },
    }
end

-- ============================================================
-- SEND CONSULTANT ALERT
-- Called by CropConsultant:showAlert() when in NPCFavor mode.
-- Routes the alert to NPC dialog and generates a favor quest.
-- ============================================================
function NPCIntegration:sendConsultantAlert(data)
    if not self.isInitialized then return end
    if data == nil or data.fieldId == nil then return end

    if not self.isRegistered then
        -- Queue for replay once NPC is registered
        table.insert(self.pendingAlerts, data)
        return
    end

    self:forwardAlertToNPC(data)
end

function NPCIntegration:forwardAlertToNPC(data)
    if g_NPCSystem == nil then return end
    if not self.isRegistered or self.consultantNPCId == nil then return end

    -- Build dialog text from severity
    local severity = data.severity or "WARNING"
    local msgKey   = "cs_alert_warning"
    if severity == "CRITICAL" then msgKey = "cs_alert_critical"
    elseif severity == "INFO"  then msgKey = "cs_alert_info" end

    local template = (g_i18n ~= nil) and g_i18n:getText(msgKey) or msgKey
    local dialogText = string.format(template, data.fieldId, data.cropName or "?")

    -- Show NPC dialog message
    -- LUADOC NOTE: verify sendNPCDialog signature — (npcId, text, durationMs)
    if type(g_NPCSystem.sendNPCDialog) == "function" then
        local ok = pcall(function()
            g_NPCSystem:sendNPCDialog(self.consultantNPCId, dialogText, 8000)
        end)
        if not ok then
            csLog("NPCIntegration: sendNPCDialog call failed")
        end
    end

    -- Generate a favor quest for CRITICAL alerts
    if severity == "CRITICAL" then
        self:generateFavor(NPCIntegration.FAVOR_EMERGENCY_WATER, {
            fieldId = data.fieldId,
            urgency = "high",
        })
    elseif severity == "WARNING" then
        self:generateFavor(NPCIntegration.FAVOR_IRRIGATION_CHECK, {
            fieldId = data.fieldId,
            urgency = "normal",
        })
    end
end

-- ============================================================
-- GENERATE FAVOR
-- Asks NPCFavor to create a new favor quest for the player.
-- LUADOC NOTE: verify generateFavor(npcId, favorType, data) signature.
-- ============================================================
function NPCIntegration:generateFavor(favorType, favorData)
    if g_NPCSystem == nil then return end
    if not self.isRegistered or self.consultantNPCId == nil then return end

    -- LUADOC NOTE: verify exact method name — may be createFavor() or addFavor()
    if type(g_NPCSystem.generateFavor) ~= "function" then return end

    local ok, err = pcall(function()
        g_NPCSystem:generateFavor(self.consultantNPCId, favorType, favorData)
    end)
    if not ok then
        csLog(string.format("NPCIntegration: generateFavor(%s) failed — %s",
            favorType, tostring(err)))
    else
        csLog(string.format("NPCIntegration: favor generated [%s] for field %s",
            favorType, tostring(favorData and favorData.fieldId or "?")))
    end
end

-- ============================================================
-- GET RELATIONSHIP LEVEL
-- Returns the player's relationship level with Alex Chen.
-- Returns 0 if NPCFavor is not active or API differs.
-- ============================================================
function NPCIntegration:getRelationshipLevel()
    if g_NPCSystem == nil then return 0 end
    if not self.isRegistered or self.consultantNPCId == nil then return 0 end

    -- LUADOC NOTE: verify getRelationshipLevel(npcId) returns a number (0-100 scale)
    if type(g_NPCSystem.getRelationshipLevel) ~= "function" then return 0 end

    local ok, level = pcall(function()
        return g_NPCSystem:getRelationshipLevel(self.consultantNPCId)
    end)
    if ok then return level or 0 end
    return 0
end

-- ============================================================
-- CLEANUP
-- ============================================================
function NPCIntegration:delete()
    -- Deregister NPC from NPCFavor if registered
    if g_NPCSystem ~= nil
    and self.isRegistered
    and self.consultantNPCId ~= nil then
        -- LUADOC NOTE: verify deregisterExternalNPC(npcId) exists
        if type(g_NPCSystem.deregisterExternalNPC) == "function" then
            pcall(function()
                g_NPCSystem:deregisterExternalNPC(self.consultantNPCId)
            end)
        end
    end

    self.pendingAlerts   = {}
    self.isRegistered    = false
    self.consultantNPCId = nil
    self.isInitialized   = false
end