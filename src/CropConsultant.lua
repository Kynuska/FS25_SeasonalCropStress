-- ============================================================
-- CropConsultant.lua
-- PHASE 3 STUB — not yet implemented.
--
-- When implemented, this system will:
--   • Subscribe to CS_CRITICAL_THRESHOLD events
--   • Generate player-facing alert notifications at 3 severity levels
--   • Enforce per-field alert cooldowns (12 in-game hours)
--   • In standalone mode: show blinking HUD warnings
--   • When FS25_NPCFavor is active: delegate alerts to NPCIntegration
--     which presents them as NPC dialog from "Alex Chen, Agronomist"
--
-- Alert severity levels:
--   INFO     (40-50% moisture)  — "Field X getting dry — monitor conditions."
--   WARNING  (25-40% moisture)  — "Field X moisture low — irrigation recommended."
--   CRITICAL (<25% moisture)    — "Field X at drought stress threshold — irrigate NOW!"
--
-- See Section 6.6 of FS25_SeasonalCropStress_ModPlan.md for full spec.
-- ============================================================

CropConsultant = {}
CropConsultant.__index = CropConsultant

function CropConsultant.new(manager)
    local self = setmetatable({}, CropConsultant)
    self.manager = manager
    self.alertCooldowns = {}  -- fieldId → lastAlertHourKey
    self.isInitialized = false
    return self
end

function CropConsultant:initialize()
    -- Phase 3: subscribe to events and optionally register NPC
    self.isInitialized = true
end

function CropConsultant:onCriticalThreshold(data)
    -- Phase 3: generate alerts
end

function CropConsultant:delete()
    if self.manager ~= nil and self.manager.eventBus ~= nil then
        self.manager.eventBus.unsubscribeAll(self)
    end
    self.isInitialized = false
end
