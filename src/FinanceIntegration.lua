-- ============================================================
-- FinanceIntegration.lua
-- Handles operational costs for irrigation.
-- Phase 2: simple fund deduction via updateFunds.
-- Phase 4: will integrate with UsedPlus.
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
    self.isInitialized = true
end

function FinanceIntegration:chargeHourlyCosts()
    if not self.isInitialized then return end
    local irrMgr = self.manager.irrigationManager
    if not irrMgr then return end

    for id, system in pairs(irrMgr.systems) do
        if system.isActive then
            local cost = system.operationalCostPerHour
            if self.usedPlusActive then
                -- Phase 4: use UsedPlus
                if g_usedPlusManager and g_usedPlusManager.recordExpense then
                    g_usedPlusManager:recordExpense("IRRIGATION", cost, {
                        description = string.format("Irrigation system %d", id),
                        category    = "OPERATIONAL",
                    })
                end
            else
                g_currentMission.missionInfo:updateFunds(-cost, "OTHER", true)
            end
        end
    end
end

function FinanceIntegration:getEquipmentWearLevel(vehicleId)
    -- Phase 4: query UsedPlus DNA
    return 0.0
end

function FinanceIntegration:delete()
    if self.manager and self.manager.eventBus then
        self.manager.eventBus.unsubscribeAll(self)
    end
    self.isInitialized = false
end
