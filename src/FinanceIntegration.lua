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
    if irrMgr == nil then return end

    for id, system in pairs(irrMgr.systems) do
        if system.isActive then
            local cost = system.operationalCostPerHour
            if self.usedPlusActive then
                -- Phase 4: verify exact UsedPlus API against source before enabling
                -- LUADOC NOTE: g_usedPlusManager:recordExpense() signature unconfirmed
                if g_usedPlusManager ~= nil and g_usedPlusManager.recordExpense ~= nil then
                    g_usedPlusManager:recordExpense("IRRIGATION", cost, {
                        description = string.format("Irrigation system %d", id),
                        category    = "OPERATIONAL",
                    })
                end
            else
                -- Correct FS25 call: updateFunds on the mission object directly.
                -- FundsReasonType.OTHER is nil-guarded — it may not be defined in all builds.
                -- We also obtain the correct farmId rather than defaulting to farm 0.
                if g_currentMission ~= nil then
                    local reasonType = (FundsReasonType ~= nil and FundsReasonType.OTHER) or 0
                    local farmId = (g_currentMission.player ~= nil and g_currentMission.player:getOwnerFarmId())
                        or AccessHandler.EVERYBODY
                    g_currentMission:updateFunds(farmId, -cost, reasonType, true)
                end
            end
        end
    end
end

function FinanceIntegration:getEquipmentWearLevel(vehicleId)
    -- Phase 4: query UsedPlus DNA reliability value
    return 0.0
end

function FinanceIntegration:delete()
    if self.manager ~= nil and self.manager.eventBus ~= nil then
        self.manager.eventBus.unsubscribeAll(self)
    end
    self.isInitialized = false
end