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
            -- Deduct operational cost via vanilla FS25 fund system.
            -- UsedPlus public API (UsedPlusAPI) does not expose recordExpense() —
            -- confirmed against UsedPlusAPI wiki. Costs always go through vanilla updateFunds.
            self:deductFundsVanilla(system.operationalCostPerHour)

            -- Update wear level from UsedPlus DNA (if UsedPlus active).
            -- Placeables typically have no DNA entry, so this usually returns 0.0.
            -- IrrigationManager:activateSystem() scales flow by (1 - wearLevel * 0.3).
            if self.usedPlusActive then
                local wearLevel = self:getEquipmentWearLevel(id)
                irrMgr:updateSystemWearLevel(id, wearLevel)
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
    if not self.usedPlusActive then return 0.0 end

    -- Try UsedPlusAPI (confirmed public static interface) then g_usedPlusManager (legacy).
    -- UsedPlusAPI.getVehicleDNA(entity) is a static call; g_usedPlusManager:getVehicleDNA()
    -- is a method call — both wrapped in pcall to handle either convention safely.
    -- Note: UsedPlus DNA tracks vehicles (tractors, combines). Irrigation systems are
    -- placeables and typically have no DNA entry, so dna will be nil → returns 0.0.
    local dna = nil
    if UsedPlusAPI ~= nil and UsedPlusAPI.getVehicleDNA ~= nil then
        local ok, result = pcall(UsedPlusAPI.getVehicleDNA, vehicleId)
        if ok then dna = result end
    elseif g_usedPlusManager ~= nil and g_usedPlusManager.getVehicleDNA ~= nil then
        local ok, result = pcall(function() return g_usedPlusManager:getVehicleDNA(vehicleId) end)
        if ok then dna = result end
    end
    if dna == nil then return 0.0 end

    -- DNA reliability range: 0.6 (heavily worn) → 1.4 (new)
    -- Converted to wear level: 0.0 (new) → 1.0 (at limit)
    local reliability = dna.reliability
    if reliability == nil then return 0.0 end
    return math.max(0.0, math.min(1.0, (1.4 - reliability) / 0.8))
end

-- Enable UsedPlus mode - called by CropStressManager after detection.
-- With UsedPlus active: DNA wear tracking enabled (affects flow rate).
-- Operational costs always go through vanilla updateFunds (recordExpense not in public API).
function FinanceIntegration:enableUsedPlusMode()
    self.usedPlusActive = true
    csLog("FinanceIntegration: UsedPlus active — DNA wear tracking enabled")
end

function FinanceIntegration:delete()
    if self.manager ~= nil and self.manager.eventBus ~= nil then
        self.manager.eventBus.unsubscribeAll(self)
    end
    self.isInitialized = false
end