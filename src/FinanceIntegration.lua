-- ============================================================
-- FinanceIntegration.lua
-- Handles operational costs for irrigation.
-- Phase 2: simple fund deduction via updateFunds.
-- Phase 4: will integrate with UsedPlus.
-- ============================================================

local function csLog(msg)
    if g_logManager ~= nil then g_logManager:devInfo("[CropStress]", msg)
    else print("[CropStress] " .. tostring(msg)) end
end

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

    -- Respect the irrigation costs setting (costsEnabled == false means player disabled costs)
    -- nil means the flag was never set (default = costs enabled); only skip on explicit false.
    if irrMgr.costsEnabled == false then return end

    for id, system in pairs(irrMgr.systems) do
        if system.isActive then
            local cost = system.operationalCostPerHour
            if self.usedPlusActive then
                -- Forward expense to UsedPlus for budget tracking.
                -- LUADOC NOTE: g_usedPlusManager:recordExpense() signature unconfirmed.
                if g_usedPlusManager ~= nil and g_usedPlusManager.recordExpense ~= nil then
                    local ok, err = pcall(function()
                        g_usedPlusManager:recordExpense("IRRIGATION", cost, {
                            description = string.format("Irrigation system %d", id),
                            category    = "OPERATIONAL",
                        })
                    end)
                    if not ok then
                        -- UsedPlus API mismatch — fall through to vanilla fund deduction
                        self:deductFundsVanilla(cost)
                    end
                end

                -- Update wear level for this system from UsedPlus DNA.
                -- IrrigationManager.activateSystem() already scales effectiveRate by
                -- (1 - wearLevel * 0.3), so a wear of 1.0 means 30% reduced flow.
                -- LUADOC NOTE: placeables use entity IDs, so this assumes UsedPlus
                -- tracks placeables by the same ID — verify against UsedPlus source.
                local wearLevel = self:getEquipmentWearLevel(id)
                irrMgr:updateSystemWearLevel(id, wearLevel)
            else
                self:deductFundsVanilla(cost)
            end
        end
    end
end

-- Deduct operational cost via the vanilla FS25 fund system.
function FinanceIntegration:deductFundsVanilla(cost)
    if g_currentMission == nil then return end
    local reasonType = (FundsReasonType ~= nil and FundsReasonType.OTHER) or 0
    -- AccessHandler.EVERYBODY may be nil on some builds/platforms; fall back to
    -- farm 0 (spectator/server farm — effectively "all farms").
    local everybody = (AccessHandler ~= nil and AccessHandler.EVERYBODY) or 0
    local farmId = (g_currentMission.player ~= nil and g_currentMission.player:getOwnerFarmId())
        or everybody
    g_currentMission:updateFunds(farmId, -cost, reasonType, true)
end

function FinanceIntegration:getEquipmentWearLevel(vehicleId)
    -- Phase 4: query UsedPlus DNA reliability value
    if not self.usedPlusActive then return 0.0 end
    if g_usedPlusManager == nil or g_usedPlusManager.getVehicleDNA == nil then return 0.0 end

    local dna = g_usedPlusManager:getVehicleDNA(vehicleId)
    if dna == nil then return 0.0 end

    -- UsedPlus DNA reliability: 0.6–1.4 multiplier
    -- reliability 0.6 = 40% worn, reliability 1.4 = 0% worn
    -- Convert to wear level 0.0 (new) to 1.0 (broken)
    local wearLevel = math.max(0.0, (1.4 - dna.reliability) / 0.8)
    return math.min(1.0, wearLevel)
end

-- Enable UsedPlus mode - called by CropStressManager after detection
function FinanceIntegration:enableUsedPlusMode()
    self.usedPlusActive = true
    csLog("FinanceIntegration: UsedPlus integration enabled")
end

function FinanceIntegration:delete()
    if self.manager ~= nil and self.manager.eventBus ~= nil then
        self.manager.eventBus.unsubscribeAll(self)
    end
    self.isInitialized = false
end