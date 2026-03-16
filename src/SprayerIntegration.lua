-- ============================================================
-- SprayerIntegration.lua
-- Detects when a vehicle-based sprayer applies water to a field.
-- Intercepts Sprayer:processSprayerArea to add moisture.
-- ============================================================

SprayerIntegration = {}
SprayerIntegration.__index = SprayerIntegration

-- Scaling factor: how much 1 liter of water adds to 1 sqm of moisture fraction.
-- 1mm of water = 1 liter/sqm.
-- If 1mm = 0.0024 moisture fraction (from rain balance), then:
SprayerIntegration.MOISTURE_PER_LITER_PER_SQM = 0.0024

function SprayerIntegration.new(manager)
    local self = setmetatable({}, SprayerIntegration)
    self.manager = manager
    self.isInitialized = false
    return self
end

function SprayerIntegration:initialize()
    if self.isInitialized then return end

    -- Hook into Sprayer:processSprayerArea to intercept water application
    if Sprayer ~= nil and type(Sprayer.processSprayerArea) == "function" then
        Sprayer.processSprayerArea = Utils.overwrittenFunction(Sprayer.processSprayerArea, SprayerIntegration.overwrittenProcessSprayerArea)
        print("[CropStress] SprayerIntegration: Hooked Sprayer.processSprayerArea")
    end

    self.isInitialized = true
end

function SprayerIntegration.overwrittenProcessSprayerArea(self, superFunc, workArea, dt)
    -- Run original function and capture area changed
    local changedArea, totalArea = superFunc(self, workArea, dt)

    -- If no area was changed or we're not the server, nothing more to do
    if changedArea <= 0 or not self.isServer then
        return changedArea, totalArea
    end

    local spec = self.spec_sprayer
    if spec == nil or spec.workAreaParameters == nil then
        return changedArea, totalArea
    end

    -- Check if we are spraying WATER
    local fillType = spec.workAreaParameters.sprayFillType
    if fillType == nil or fillType == FillType.UNKNOWN then
        return changedArea, totalArea
    end

    -- Ensure we have the WATER fill type index. Cache it for performance.
    if SprayerIntegration.WATER_FILL_TYPE == nil then
        SprayerIntegration.WATER_FILL_TYPE = g_fillTypeManager:getFillTypeIndexByName("WATER")
    end

    if fillType == SprayerIntegration.WATER_FILL_TYPE then
        -- Calculate moisture gain based on usage
        -- usage is in liters per dt
        local usage = spec.workAreaParameters.usage or 0
        if usage > 0 then
            -- Determine field at the start point of the work area
            local sx, _, sz = getWorldTranslation(workArea.start)
            local farmland = g_farmlandManager:getFarmlandAtWorldPosition(sx, sz)
            if farmland ~= nil then
                local fieldId = farmland.id
                local soilSystem = g_cropStressManager and g_cropStressManager.soilSystem
                if soilSystem ~= nil then
                    -- How much moisture to add?
                    -- 1 liter over 'totalArea' sqm.
                    -- Gain = (usage / totalArea) * MOISTURE_PER_LITER_PER_SQM
                    -- But wait, changedArea is better for actual application.
                    local area = math.max(1.0, totalArea) -- avoid div by zero
                    local gain = (usage / area) * SprayerIntegration.MOISTURE_PER_LITER_PER_SQM

                    -- Scale it up to make it a viable alternative (e.g. 5x more effective for gameplay)
                    gain = gain * 5.0

                    local current = soilSystem:getMoisture(fieldId)
                    if current ~= nil then
                        local newMoisture = math.min(1.0, current + gain)
                        soilSystem:setMoisture(fieldId, newMoisture)

                        -- If Realistic Weather is active, sync it back
                        if soilSystem.rwMoistureSystem ~= nil then
                            soilSystem.rwMoistureSystem:setValuesAtCoords(sx, sz, {moisture = gain}, false)
                        end

                        if g_cropStressManager.debugMode then
                            print(string.format("[CropStress] Sprayer water applied to Field %d: +%.4f moisture (usage=%.2f area=%.1f)", fieldId, gain, usage, area))
                        end
                    end
                end
            end
        end
    end

    return changedArea, totalArea
end

function SprayerIntegration:delete()
    -- Note: Overwritten functions cannot be easily "un-overwritten" without
    -- storing the original, which Utils.overwrittenFunction doesn't return
    -- to us. But we don't need to as the mod is being destroyed.
    self.isInitialized = false
end
