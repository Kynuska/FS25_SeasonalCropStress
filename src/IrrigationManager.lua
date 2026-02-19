-- ============================================================
-- IrrigationManager.lua
-- Tracks all placed irrigation systems and water sources.
-- Handles registration, coverage detection, scheduling,
-- activation, and publishes irrigation gain events.
-- ============================================================

IrrigationManager = {}
IrrigationManager.__index = IrrigationManager

-- Constants
IrrigationManager.MAX_PUMP_DISTANCE = 500  -- meters
IrrigationManager.PRESSURE_FALLOFF  = 0.3  -- 30% loss at max distance

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
-- POSITION HELPER
-- FS25 placeables have no getPosition() method.
-- Position is read via Giants engine getWorldTranslation() on the root node.
-- ============================================================
local function getPlaceablePosition(placeable)
    local node = placeable.rootNode or placeable.nodeId
    if node ~= nil then
        return getWorldTranslation(node)
    end
    -- Final fallback — placeable may store position directly on some versions
    return placeable.posX or 0, 0, placeable.posZ or 0
end

function IrrigationManager.new(manager)
    local self = setmetatable({}, IrrigationManager)
    self.manager = manager

    -- Systems keyed by placeableId
    self.systems = {}
    -- Water sources (pumps) keyed by placeableId
    self.waterSources = {}

    self.isInitialized = false
    return self
end

function IrrigationManager:initialize()
    self.isInitialized = true
    csLog("IrrigationManager initialized")
end

-- ============================================================
-- Water Source Registration
-- ============================================================
function IrrigationManager:registerWaterSource(placeable)
    local x, _, z = getPlaceablePosition(placeable)
    self.waterSources[placeable.id] = {
        id           = placeable.id,
        x            = x,
        z            = z,
        hasWater     = true,  -- Phase 2: always true; Phase 4: could be finite
        flowCapacity = placeable.waterFlowCapacity or 1000,
    }
    csLog(string.format("Water source %d registered at (%.1f, %.1f)", placeable.id, x, z))
end

function IrrigationManager:deregisterWaterSource(placeableId)
    self.waterSources[placeableId] = nil
    -- Deactivate any irrigation systems that depended on this source
    for sysId, sys in pairs(self.systems) do
        if sys.waterSourceId == placeableId then
            self:deactivateSystem(sysId)
            sys.waterSourceId = nil
        end
    end
end

-- ============================================================
-- Irrigation System Registration
-- ============================================================
function IrrigationManager:registerIrrigationSystem(placeable)
    local x, _, z = getPlaceablePosition(placeable)
    local coveredFields = self:detectCoveredFields(placeable, x, z)

    -- Find nearest water source within range
    local waterSourceId, distance = self:findNearestWaterSource(x, z)
    local pressureMultiplier = 0
    if waterSourceId ~= nil then
        pressureMultiplier = self:calculatePressureMultiplier(distance)
    end

    local system = {
        id                     = placeable.id,
        type                   = placeable.irrigationType or "pivot",
        x                      = x,
        z                      = z,
        coveredFields          = coveredFields,
        waterSourceId          = waterSourceId,
        distanceToSource       = distance,
        pressureMultiplier     = pressureMultiplier,
        flowRatePerHour        = placeable.flowRatePerHour or 0.018,
        operationalCostPerHour = placeable.operationalCostPerHour or 15,
        wearLevel              = 0,  -- Phase 4
        schedule = {
            startHour  = placeable.defaultStartHour or 6,
            endHour    = placeable.defaultEndHour   or 10,
            activeDays = placeable.defaultActiveDays or {true, true, true, true, true, false, false},
        },
        isActive             = false,
        effectiveRatePerField = {},
    }

    self.systems[placeable.id] = system

    csLog(string.format(
        "Irrigation system %d (%s) registered, covers %d fields, water source %s (distance %.1f m, pressure %.0f%%)",
        placeable.id, system.type, #coveredFields,
        waterSourceId ~= nil and tostring(waterSourceId) or "none",
        distance or 0, (pressureMultiplier or 0) * 100
    ))
end

function IrrigationManager:deregisterIrrigationSystem(placeableId)
    if self.systems[placeableId] ~= nil and self.systems[placeableId].isActive then
        self:deactivateSystem(placeableId)
    end
    self.systems[placeableId] = nil
end

-- ============================================================
-- Field Coverage Detection
-- ============================================================
function IrrigationManager:detectCoveredFields(placeable, cx, cz)
    local radius  = placeable.radius or 200
    local covered = {}

    if placeable.irrigationType ~= "pivot" then
        -- Drip line coverage stubbed for Phase 4
        return covered
    end

    if g_currentMission == nil or g_currentMission.fieldManager == nil then return covered end

    local fields = g_currentMission.fieldManager:getFields()
    for _, field in pairs(fields) do
        if self:fieldIntersectsCircle(field, cx, cz, radius) then
            table.insert(covered, field.fieldId)
        end
    end
    return covered
end

-- Circle vs. field polygon intersection (simplified AABB check)
function IrrigationManager:fieldIntersectsCircle(field, cx, cz, radius)
    local minX, maxX, minZ, maxZ
    if field.minX ~= nil then
        minX, maxX, minZ, maxZ = field.minX, field.maxX, field.minZ, field.maxZ
    else
        local fx = field.posX or (field.startX and (field.startX + (field.widthX  or 0) * 0.5)) or cx
        local fz = field.posZ or (field.startZ and (field.startZ + (field.heightZ or 0) * 0.5)) or cz
        local fr = field.fieldRadius or 50
        minX, maxX = fx - fr, fx + fr
        minZ, maxZ = fz - fr, fz + fr
    end

    local closestX = math.max(minX, math.min(cx, maxX))
    local closestZ = math.max(minZ, math.min(cz, maxZ))
    local dx = cx - closestX
    local dz = cz - closestZ
    return (dx * dx + dz * dz) <= (radius * radius)
end

-- ============================================================
-- Water Source Lookup
-- ============================================================
function IrrigationManager:findNearestWaterSource(x, z)
    local nearestId = nil
    local minDist   = math.huge

    for id, source in pairs(self.waterSources) do
        if source.hasWater then
            local dx   = source.x - x
            local dz   = source.z - z
            local dist = math.sqrt(dx * dx + dz * dz)
            if dist <= IrrigationManager.MAX_PUMP_DISTANCE and dist < minDist then
                minDist   = dist
                nearestId = id
            end
        end
    end

    if nearestId ~= nil then
        return nearestId, minDist
    end
    return nil, nil
end

function IrrigationManager:calculatePressureMultiplier(distance)
    if distance > IrrigationManager.MAX_PUMP_DISTANCE then return 0 end
    return 1.0 - (distance / IrrigationManager.MAX_PUMP_DISTANCE) * IrrigationManager.PRESSURE_FALLOFF
end

-- ============================================================
-- Hourly Schedule Check
-- ============================================================
function IrrigationManager:hourlyScheduleCheck()
    if not self.isInitialized then return end
    if g_currentMission == nil then return end

    local env = g_currentMission.environment
    if env == nil then return end

    -- env.currentHour and env.currentDayInPeriod are direct properties in FS25.
    -- currentDayInPeriod is 1–7 within the current growth period (matches schedule activeDays).
    local hour      = env.currentHour         or 0
    local dayOfWeek = env.currentDayInPeriod   or 1

    for id, system in pairs(self.systems) do
        -- Check if water source is still valid
        if system.waterSourceId ~= nil and self.waterSources[system.waterSourceId] == nil then
            if system.isActive then self:deactivateSystem(id) end
            system.waterSourceId      = nil
            system.pressureMultiplier = 0
        end

        local shouldBeActive = false
        if system.waterSourceId ~= nil and system.pressureMultiplier > 0 then
            local sched = system.schedule
            shouldBeActive = sched.activeDays[dayOfWeek] == true
                and hour >= sched.startHour
                and hour <  sched.endHour
        end

        if shouldBeActive and not system.isActive then
            self:activateSystem(id)
        elseif not shouldBeActive and system.isActive then
            self:deactivateSystem(id)
        end
    end
end

-- ============================================================
-- Activation / Deactivation
-- ============================================================
function IrrigationManager:activateSystem(id)
    local system = self.systems[id]
    if system == nil or system.isActive then return end

    local wearFactor    = 1.0 - system.wearLevel * 0.3
    local effectiveRate = system.flowRatePerHour * system.pressureMultiplier * wearFactor

    system.effectiveRatePerField = {}
    for _, fieldId in ipairs(system.coveredFields) do
        system.effectiveRatePerField[fieldId] = effectiveRate
        if self.manager ~= nil and self.manager.eventBus ~= nil then
            self.manager.eventBus.publish("CS_IRRIGATION_STARTED", {
                placeableId = id,
                fieldId     = fieldId,
                ratePerHour = effectiveRate,
            })
        end
    end

    system.isActive = true
    csLog(string.format("Irrigation system %d activated, rate=%.4f", id, effectiveRate))
end

function IrrigationManager:deactivateSystem(id)
    local system = self.systems[id]
    if system == nil or not system.isActive then return end

    for _, fieldId in ipairs(system.coveredFields) do
        if self.manager ~= nil and self.manager.eventBus ~= nil then
            self.manager.eventBus.publish("CS_IRRIGATION_STOPPED", {
                placeableId = id,
                fieldId     = fieldId,
                ratePerHour = system.effectiveRatePerField[fieldId] or 0,
            })
        end
    end

    system.effectiveRatePerField = {}
    system.isActive = false
    csLog(string.format("Irrigation system %d deactivated", id))
end

-- ============================================================
-- Get Irrigation Rate for a Field (sum of all active systems)
-- ============================================================
function IrrigationManager:getIrrigationRateForField(fieldId)
    local total = 0
    for _, system in pairs(self.systems) do
        if system.isActive and system.effectiveRatePerField[fieldId] ~= nil then
            total = total + system.effectiveRatePerField[fieldId]
        end
    end
    return total
end

-- ============================================================
-- Cleanup
-- ============================================================
function IrrigationManager:delete()
    for id, system in pairs(self.systems) do
        if system.isActive then
            self:deactivateSystem(id)
        end
    end
    self.systems      = {}
    self.waterSources = {}
    self.isInitialized = false
end