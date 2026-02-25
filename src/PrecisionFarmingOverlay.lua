-- ============================================================
-- PrecisionFarmingOverlay.lua
-- Phase 4: Integrates with Precision Farming DLC to display
-- soil moisture overlay on the PF soil analysis map screen.
-- ============================================================

local function csLog(msg)
    if g_logManager ~= nil then g_logManager:devInfo("[CropStress]", msg)
    else print("[CropStress] " .. tostring(msg)) end
end

PrecisionFarmingOverlay = {}
PrecisionFarmingOverlay.__index = PrecisionFarmingOverlay

function PrecisionFarmingOverlay.new(manager)
    local self = setmetatable({}, PrecisionFarmingOverlay)
    self.manager = manager
    self.pfActive = false
    self.isInitialized = false
    return self
end

function PrecisionFarmingOverlay:initialize()
    self.isInitialized = true
    csLog("PrecisionFarmingOverlay initialized")
end

-- Enable Precision Farming mode - called by CropStressManager after detection
function PrecisionFarmingOverlay:enablePrecisionFarmingMode()
    self.pfActive = true
    self:registerMoistureOverlay()
    csLog("PrecisionFarmingOverlay: Precision Farming integration enabled")
end

-- Register moisture overlay with Precision Farming DLC
function PrecisionFarmingOverlay:registerMoistureOverlay()
    if not self.pfActive then return end
    if g_precisionFarming == nil or g_precisionFarming.registerOverlay == nil then return end

    local overlayConfig = {
        name = "CropStress_Moisture",
        displayName = (g_i18n ~= nil) and g_i18n:getText("cs_pf_moisture_overlay")      or "Soil Moisture",
        description = (g_i18n ~= nil) and g_i18n:getText("cs_pf_moisture_overlay_desc") or "",
        category = "IRRIGATION",
        -- Color gradient: dry (red) -> optimal (green) -> saturated (blue)
        colorMap = {
            { value = 0.0,  color = {1.0, 0.0, 0.0} },  -- Red (dry)
            { value = 0.3,  color = {1.0, 0.5, 0.0} },  -- Orange
            { value = 0.5,  color = {0.0, 1.0, 0.0} },  -- Green (optimal)
            { value = 0.8,  color = {0.0, 0.5, 1.0} },  -- Light blue
            { value = 1.0,  color = {0.0, 0.0, 1.0} }   -- Blue (saturated)
        },
        minValue = 0.0,
        maxValue = 1.0,
        -- Callback to get moisture data for a world position
        getValueAtPosition = function(x, z)
            return self:getMoistureAtPosition(x, z)
        end,
        -- Optional: Get soil type from PF if available
        getSoilTypeAtPosition = function(x, z)
            return self:getSoilTypeAtPosition(x, z)
        end
    }

    g_precisionFarming:registerOverlay(overlayConfig)
    csLog("Registered soil moisture overlay with Precision Farming DLC")
end

-- Get moisture value at world position
function PrecisionFarmingOverlay:getMoistureAtPosition(x, z)
    if not self.pfActive then return 0.5 end

    local soilSystem = self.manager and self.manager.soilSystem
    if soilSystem == nil then return 0.5 end

    -- Find the field that contains this position
    local fieldId = self:getFieldIdAtPosition(x, z)
    if fieldId == nil then return 0.5 end

    return soilSystem:getMoisture(fieldId) or 0.5
end

-- Get soil type at world position (if PF provides it)
function PrecisionFarmingOverlay:getSoilTypeAtPosition(x, z)
    if not self.pfActive then return "loamy" end

    -- Try to get soil type from PF first
    if g_precisionFarming ~= nil and g_precisionFarming.getSoilTypeAtPosition ~= nil then
        local pfSoilType = g_precisionFarming:getSoilTypeAtPosition(x, z)
        if pfSoilType ~= nil then
            return pfSoilType
        end
    end

    -- Fall back to our own soil type detection
    local soilSystem = self.manager and self.manager.soilSystem
    if soilSystem == nil then return "loamy" end

    local fieldId = self:getFieldIdAtPosition(x, z)
    if fieldId == nil then return "loamy" end

    local fieldData = soilSystem.fieldData and soilSystem.fieldData[fieldId]
    return fieldData and fieldData.soilType or "loamy"
end

-- Find field ID at world position
function PrecisionFarmingOverlay:getFieldIdAtPosition(x, z)
    if g_currentMission == nil or g_currentMission.fieldManager == nil then return nil end

    local fields = g_currentMission.fieldManager:getFields()
    for _, field in pairs(fields) do
        if self:positionInField(field, x, z) then
            return field.fieldId
        end
    end
    return nil
end

-- Check if position is within field bounds
function PrecisionFarmingOverlay:positionInField(field, x, z)
    local minX, maxX, minZ, maxZ
    if field.minX ~= nil then
        minX, maxX, minZ, maxZ = field.minX, field.maxX, field.minZ, field.maxZ
    else
        -- Fallback to bounding box approximation
        local fx = field.posX or (field.startX and (field.startX + (field.widthX  or 0) * 0.5)) or x
        local fz = field.posZ or (field.startZ and (field.startZ + (field.heightZ or 0) * 0.5)) or z
        local fr = field.fieldRadius or 50
        minX, maxX = fx - fr, fx + fr
        minZ, maxZ = fz - fr, fz + fr
    end

    return (x >= minX and x <= maxX and z >= minZ and z <= maxZ)
end

function PrecisionFarmingOverlay:delete()
    self.isInitialized = false
end