-- ============================================================
-- FinanceIntegration.lua
-- PHASE 4 STUB — not yet implemented.
--
-- When implemented, this system will:
--   • Detect FS25_UsedPlus at runtime via g_usedPlusManager global
--   • Subscribe to CS_IRRIGATION_STARTED / CS_IRRIGATION_STOPPED events
--   • Charge hourly operational costs for active irrigation systems:
--       — Via g_usedPlusManager:recordExpense("IRRIGATION", cost, {...}) if UsedPlus active
--       — Via g_currentMission.missionInfo:updateFunds(-cost, "OTHER", true) if standalone
--   • Pull equipment wear levels from UsedPlus DNA to degrade irrigation flow rates
--     (worn pump = reduced flow → less moisture gain per hour)
--
-- Finance path for fund deductions (FS25 standard):
--   g_currentMission.missionInfo:updateFunds(amount, "OTHER", true)
--   amount is NEGATIVE for deductions. The third arg = true flags it as "other costs".
--
-- See Section 6.8 of FS25_SeasonalCropStress_ModPlan.md for full spec.
-- ============================================================

FinanceIntegration = {}
FinanceIntegration.__index = FinanceIntegration

function FinanceIntegration.new(manager)
    local self = setmetatable({}, FinanceIntegration)
    self.manager = manager
    self.usedPlusActive = false  -- set by CropStressManager:detectOptionalMods()
    self.isInitialized  = false
    return self
end

function FinanceIntegration:initialize()
    -- Phase 4: subscribe to irrigation events
    self.isInitialized = true
end

function FinanceIntegration:chargeHourlyCosts()
    -- Phase 4: iterate active irrigation systems, deduct operational costs
end

function FinanceIntegration:getEquipmentWearLevel(vehicleId)
    -- Phase 4: query UsedPlus DNA for pump wear, return 0.0-1.0
    return 0.0
end

function FinanceIntegration:delete()
    if self.manager ~= nil and self.manager.eventBus ~= nil then
        self.manager.eventBus.unsubscribeAll(self)
    end
    self.isInitialized = false
end
