-- ============================================================
-- CropStressModifier.lua
-- Tracks accumulated yield stress per field and hooks into the
-- harvesting pipeline to reduce yield proportionally.
--
-- Stress accumulates each in-game hour when:
--   • The field has a crop in a "critical growth window" AND
--   • Soil moisture is below the crop's criticalMoisture threshold
--
-- At harvest, yield is reduced by: stress * MAX_YIELD_LOSS (default 60%)
--
-- HARVEST HOOK IMPLEMENTATION NOTES:
--   Uses Utils.overwrittenFunction on HarvestingMachine.doGroundWorkArea.
--   This intercepts before+after fill levels and removes the stress
--   portion. If two mods both overwrite this function, the last one loaded
--   wins — flag this in modDesc.xml compatibility notes if needed.
--   Verify exact function signature against LUADOC before testing.
-- ============================================================

CropStressModifier = {}
CropStressModifier.__index = CropStressModifier

-- Maximum yield reduction at stress = 1.0 (full stress)
CropStressModifier.MAX_YIELD_LOSS = 0.60

-- Crop stress configuration (matches cropStressDefaults.xml)
-- key = lowercase fruit type name as returned by FS25 field:getFruitType().name
CropStressModifier.CROP_WINDOWS = {
    wheat      = { stages = {3,4},     criticalMoisture = 0.35, stressRatePerHour = 0.003 },
    barley     = { stages = {3,4},     criticalMoisture = 0.30, stressRatePerHour = 0.003 },
    corn       = { stages = {4,5},     criticalMoisture = 0.40, stressRatePerHour = 0.004 },
    canola     = { stages = {2,3},     criticalMoisture = 0.45, stressRatePerHour = 0.005 },
    sunflower  = { stages = {3,4},     criticalMoisture = 0.30, stressRatePerHour = 0.002 },
    soybeans   = { stages = {3,4},     criticalMoisture = 0.40, stressRatePerHour = 0.004 },
    sugarbeet  = { stages = {2,3,4},   criticalMoisture = 0.50, stressRatePerHour = 0.005 },
    potato     = { stages = {2,3,4},   criticalMoisture = 0.55, stressRatePerHour = 0.006 },
}

-- Whether the harvest hook has been installed (static flag, module-level)
CropStressModifier.harvestHookInstalled = false

-- ============================================================
-- LOGGING HELPER
-- g_logManager may be nil during early load; fall back to print().
-- ============================================================
local function csLog(msg)
    if g_logManager ~= nil then
        g_logManager:devInfo("[CropStress]", msg)
    else
        print("[CropStress] " .. tostring(msg))
    end
end

function CropStressModifier.new(manager)
    local self = setmetatable({}, CropStressModifier)
    self.manager = manager

    -- Per-field accumulated stress: fieldId → float (0.0–1.0)
    self.fieldStress = {}

    -- When FS25_RealisticWeather is present, its getHarvestScaleMultiplier hook
    -- handles the yield penalty. We skip our doGroundWorkArea reduction to avoid
    -- stacking, but still accumulate stress for HUD display.
    self.rwModeActive = false

    self.isInitialized = false
    return self
end

function CropStressModifier:initialize()
    self.isInitialized = true
end

-- ============================================================
-- HOURLY STRESS ACCUMULATION
-- Called by CropStressManager:onHourlyTick()
-- ============================================================
function CropStressModifier:hourlyUpdate()
    if not self.isInitialized then return end
    if g_currentMission == nil or g_currentMission.fieldManager == nil then return end

    local soilSystem = self.manager.soilSystem
    if soilSystem == nil then return end

    -- Use the manager's pre-built fieldId→field map (built in lateInitialize).
    -- Avoids rebuilding it every hour and eliminates the getFieldByIndex trap:
    -- getFieldByIndex(n) returns fields[n] (array index), NOT the field with fieldId==n.
    local fieldById = (self.manager ~= nil) and self.manager.fieldById or {}

    for fieldId, data in pairs(soilSystem.fieldData) do
        local field = fieldById[fieldId]
        if field ~= nil then
            self:processFieldStress(field, fieldId, data.moisture)
        end
        -- If field not in map this tick, skip silently — map will be rebuilt on next lateInitialize
    end
end

function CropStressModifier:processFieldStress(field, fieldId, moisture)
    -- Get fruit type name — FS25-native API first, legacy fallback second
    local cropName = nil

    -- FS25 primary: getFieldState() → fruitTypeIndex → g_fruitTypeManager lookup
    if type(field.getFieldState) == "function" then
        local ok, state = pcall(function() return field:getFieldState() end)
        if ok and state ~= nil and state.fruitTypeIndex ~= nil and state.fruitTypeIndex > 0 then
            if g_fruitTypeManager ~= nil then
                local ft = g_fruitTypeManager:getFruitTypeByIndex(state.fruitTypeIndex)
                if ft ~= nil and ft.name ~= nil then
                    cropName = ft.name:lower()
                end
            end
        end
    end

    -- Fallback: legacy getFruitType() (FS19/22 API present in many FS25 maps)
    if cropName == nil then
        local fruitType = nil
        if type(field.getFruitType) == "function" then
            fruitType = field:getFruitType()
        elseif field.fruitType ~= nil then
            fruitType = field.fruitType
        end
        if fruitType ~= nil and fruitType.name ~= nil then
            cropName = fruitType.name:lower()
        end
    end

    if cropName == nil then return end

    local window = CropStressModifier.CROP_WINDOWS[cropName]
    if window == nil then return end  -- Crop not in our config — no stress

    -- Get growth stage
    -- FS25: field:getGrowthState() or field.growthState or similar
    -- LUADOC NOTE: verify exact method name
    local growthStage = nil
    if type(field.getGrowthState) == "function" then
        growthStage = field:getGrowthState()
    elseif field.growthState ~= nil then
        growthStage = field.growthState
    end
    if growthStage == nil then return end

    -- Check if in a critical growth window
    local inCriticalWindow = false
    for _, s in ipairs(window.stages) do
        if growthStage == s then
            inCriticalWindow = true
            break
        end
    end
    if not inCriticalWindow then return end

    -- Below critical moisture threshold → accumulate stress
    if moisture < window.criticalMoisture then
        local deficit = window.criticalMoisture - moisture
        local deficitRatio = deficit / window.criticalMoisture  -- 0.0-1.0
        -- Apply the player-configured difficulty rate multiplier (1.0 = normal, 1.5 = hard, 0.5 = easy)
        local rateMultiplier = self.rateMultiplier or 1.0
        local stressIncrease = window.stressRatePerHour * deficitRatio * rateMultiplier

        local prev = self.fieldStress[fieldId] or 0.0
        self.fieldStress[fieldId] = math.min(1.0, prev + stressIncrease)

        if self.manager ~= nil and self.manager.debugMode then
            csLog(string.format(
                "Stress Field %d (%s stage %d): +%.4f → total %.3f (moisture %.1f%% < %.0f%%)",
                fieldId, cropName, growthStage, stressIncrease,
                self.fieldStress[fieldId], moisture * 100, window.criticalMoisture * 100
            ))
        end
    end
end

-- ============================================================
-- GETTERS
-- ============================================================
function CropStressModifier:getStress(fieldId)
    return self.fieldStress[fieldId] or 0.0
end

function CropStressModifier:resetStress(fieldId)
    self.fieldStress[fieldId] = 0.0
end

-- Returns estimated yield impact as a display string, e.g. "-18%".
-- Uses the instance method (not the class constant) so the player's
-- configured max yield loss setting is reflected in dialog display.
function CropStressModifier:getYieldImpactString(fieldId)
    local stress = self:getStress(fieldId)
    local loss = stress * self:getMaxYieldLoss() * 100
    if loss < 0.5 then return "0%" end
    return string.format("-%.0f%%", loss)
end

-- ============================================================
-- POSITION → FIELD ID HELPER
-- Used by the harvest hook to find which field is being harvested.
-- ============================================================
function CropStressModifier.getFieldIdAtPosition(x, z)
    if g_currentMission == nil or g_currentMission.fieldManager == nil then return nil end

    local ok, fields = pcall(function()
        return g_currentMission.fieldManager:getFields()
    end)
    if not ok or fields == nil then return nil end
    for _, field in pairs(fields) do
        -- Preferred: native containment check
        -- LUADOC: look for fieldManager:getFieldAtWorldPos(x, z) or field:containsPoint(x, z)
        if type(field.containsPoint) == "function" then
            if field:containsPoint(x, z) then
                return field.fieldId
            end
        else
            -- Fallback: bounding-circle estimate using field center + dimensions
            -- This is imprecise — upgrade when exact API is confirmed
            local cx = field.posX or (field.startX and (field.startX + (field.widthX or 0) * 0.5))
            local cz = field.posZ or (field.startZ and (field.startZ + (field.heightZ or 0) * 0.5))
            local r  = field.fieldRadius or 80  -- conservative radius estimate

            if cx ~= nil and cz ~= nil then
                local dx = x - cx
                local dz = z - cz
                if (dx * dx + dz * dz) <= (r * r) then
                    return field.fieldId
                end
            end
        end
    end
    return nil
end

-- ============================================================
-- HARVEST HOOK INSTALLATION
-- Called from main.lua at module-load time (before vehicles exist).
-- ============================================================
function CropStressModifier.installHarvestHook()
    if CropStressModifier.harvestHookInstalled then return end
    if HarvestingMachine == nil then
        csLog("HarvestingMachine not found — harvest hook skipped")
        return
    end
    if HarvestingMachine.doGroundWorkArea == nil then
        csLog("HarvestingMachine.doGroundWorkArea not found — hook skipped")
        return
    end

    -- Using overwrittenFunction for before+after fill level tracking.
    -- This gives us a superFunc trampoline, letting us measure the fill delta.
    -- COMPATIBILITY NOTE: If another mod also uses overwrittenFunction on this
    -- same function, load order in modDesc.xml determines precedence.
    HarvestingMachine.doGroundWorkArea = Utils.overwrittenFunction(
        HarvestingMachine.doGroundWorkArea,
        function(vehicle, superFunc, workArea, dt)
            -- Record fill levels BEFORE harvest
            local fillBefore = {}
            if vehicle.spec_fillUnit ~= nil and vehicle.spec_fillUnit.fillUnits ~= nil then
                for i, fu in ipairs(vehicle.spec_fillUnit.fillUnits) do
                    fillBefore[i] = fu.fillLevel or 0
                end
            end

            -- Run original harvest logic
            superFunc(vehicle, workArea, dt)

            -- Apply stress reduction if manager is active
            if g_cropStressManager == nil or not g_cropStressManager.isInitialized then return end
            if vehicle.spec_fillUnit == nil or vehicle.spec_fillUnit.fillUnits == nil then return end

            -- Find which field this is (using work area start position)
            local wx, _, wz = getWorldTranslation(workArea.start)
            local fieldId = CropStressModifier.getFieldIdAtPosition(wx, wz)
            if fieldId == nil then return end

            local stressModifier = g_cropStressManager.stressModifier
            local stress = stressModifier:getStress(fieldId)

            -- When RW is active its getHarvestScaleMultiplier hook handles yield.
            -- We reset our accumulated stress (clears HUD) but skip fill-level changes.
            if stressModifier.rwModeActive then
                if stress > 0.01 and g_cropStressManager.debugMode then
                    csLog(string.format(
                        "Harvest field %d: stress=%.2f display-only (RW handles yield)",
                        fieldId, stress
                    ))
                end
                stressModifier:resetStress(fieldId)
                return
            end

            if stress <= 0.01 then return end

            -- Calculate yield reduction factor using the player-configured max yield loss.
            -- Uses the instance method (which reads settings-adjusted value) rather than
            -- the class constant so difficulty/settings changes take effect at harvest.
            local maxLoss = stressModifier:getMaxYieldLoss()
            local reduction = stress * maxLoss
            local keepFactor = 1.0 - reduction

            -- Apply reduction to each fill unit that received grain this pass
            local farmId = vehicle:getOwnerFarmId()
            for i, fu in ipairs(vehicle.spec_fillUnit.fillUnits) do
                local prev = fillBefore[i] or 0
                local gained = (fu.fillLevel or 0) - prev
                if gained > 0 then
                    local targetLevel = prev + (gained * keepFactor)
                    -- setFillUnitFillLevel(farmId, fillUnitIndex, value, fillType, toolType, fillPositionData)
                    -- LUADOC NOTE: verify exact signature — second arg may be 1-based index
                    vehicle:setFillUnitFillLevel(farmId, i, targetLevel, fu.fillType, nil, nil)
                end
            end

            -- Log and reset stress for this field
            if g_cropStressManager.debugMode then
                csLog(string.format(
                    "Harvest field %d: stress=%.2f → yield reduced by %.0f%%",
                    fieldId, stress, reduction * 100
                ))
            end
            stressModifier:resetStress(fieldId)
        end
    )

    CropStressModifier.harvestHookInstalled = true
    csLog("Harvest yield hook installed on HarvestingMachine.doGroundWorkArea")
end

function CropStressModifier:delete()
    self.isInitialized = false
    -- Note: the harvest hook patch cannot be uninstalled without storing the original.
    -- On mod reload, the whole game restarts so this is not a concern.
end

-- Enable/disable RW integration mode (called by CropStressManager:detectOptionalMods)
function CropStressModifier:setRWMode(active)
    self.rwModeActive = active == true
    if self.rwModeActive then
        csLog("CropStressModifier: RW mode active — harvest yield penalty deferred to RW")
    end
end

-- Set stress rate multiplier from settings
function CropStressModifier:setRateMultiplier(multiplier)
    self.rateMultiplier = multiplier or 1.0
end

-- Set maximum yield loss from settings
function CropStressModifier:setMaxYieldLoss(loss)
    self.maxYieldLoss = math.max(0.30, math.min(0.75, loss or 0.60))
end

-- Override MAX_YIELD_LOSS for settings compatibility
function CropStressModifier:getMaxYieldLoss()
    return self.maxYieldLoss or CropStressModifier.MAX_YIELD_LOSS
end