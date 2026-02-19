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
IrrigationManager.PRESSURE_FALLOFF = 0.3   -- 30% loss at max distance

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
    g_logManager:devInfo("[CropStress]", "IrrigationManager initialized")
end

-- ============================================================
-- Water Source Registration
-- ============================================================
function IrrigationManager:registerWaterSource(placeable)
    local x, _, z = placeable:getPosition()
    self.waterSources[placeable.id] = {
        id = placeable.id,
        x = x,
        z = z,
        hasWater = true,  -- Phase 2: always true; Phase 4: could be finite
        flowCapacity = placeable.waterFlowCapacity or 1000, -- not used yet
    }
    g_logManager:devInfo("[CropStress]", string.format("Water source %d registered at (%.1f, %.1f)", placeable.id, x, z))
end

function IrrigationManager:deregisterWaterSource(placeableId)
    self.waterSources[placeableId] = nil
    -- Any irrigation systems that depended on this source should be deactivated
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
    local x, _, z = placeable:getPosition()
    local coveredFields = self:detectCoveredFields(placeable, x, z)

    -- Find nearest water source within range
    local waterSourceId, distance = self:findNearestWaterSource(x, z)
    local pressureMultiplier = 0
    if waterSourceId then
        pressureMultiplier = self:calculatePressureMultiplier(distance)
    end

    local system = {
        id = placeable.id,
        type = placeable.irrigationType or "pivot",  -- "pivot" or "drip"
        x = x,
        z = z,
        coveredFields = coveredFields,
        waterSourceId = waterSourceId,
        distanceToSource = distance,
        pressureMultiplier = pressureMultiplier,
        flowRatePerHour = placeable.flowRatePerHour or 0.018,  -- moisture fraction per hour
        operationalCostPerHour = placeable.operationalCostPerHour or 15,
        wearLevel = 0,  -- Phase 4
        schedule = {
            startHour = placeable.defaultStartHour or 6,
            endHour = placeable.defaultEndHour or 10,
            activeDays = placeable.defaultActiveDays or {true, true, true, true, true, false, false}
        },
        isActive = false,
        effectiveRatePerField = {},  -- fieldId -> rate
    }

    self.systems[placeable.id] = system

    g_logManager:devInfo("[CropStress]", string.format(
        "Irrigation system %d (%s) registered, covers %d fields, water source %s (distance %.1f m, pressure %.0f%%)",
        placeable.id, system.type, #coveredFields,
        waterSourceId and tostring(waterSourceId) or "none",
        distance or 0, (pressureMultiplier or 0) * 100
    ))
end

function IrrigationManager:deregisterIrrigationSystem(placeableId)
    -- Deactivate first to clean up events
    if self.systems[placeableId] and self.systems[placeableId].isActive then
        self:deactivateSystem(placeableId)
    end
    self.systems[placeableId] = nil
end

-- ============================================================
-- Field Coverage Detection
-- ============================================================
function IrrigationManager:detectCoveredFields(placeable, cx, cz)
    local radius = placeable.radius or 200  -- default for pivot; drip lines will override
    local covered = {}

    -- For drip lines, we'd use a different method (line-polygon intersection)
    -- For Phase 2, we support only circular coverage (pivot)
    if placeable.irrigationType ~= "pivot" then
        -- Stub for other types
        return covered
    end

    local fields = g_currentMission.fieldManager:getFields()
    for _, field in pairs(fields) do
        if self:fieldIntersectsCircle(field, cx, cz, radius) then
            table.insert(covered, field.fieldId)
        end
    end
    return covered
end

-- Circle vs. field polygon intersection (simplified bounding box check)
function IrrigationManager:fieldIntersectsCircle(field, cx, cz, radius)
    -- Get field bounding box (assume field has minX, maxX, minZ, maxZ)
    -- If not, we can approximate from field dimensions.
    local minX, maxX, minZ, maxZ
    if field.minX then
        minX, maxX, minZ, maxZ = field.minX, field.maxX, field.minZ, field.maxZ
    else
        -- Fallback: use field center and radius
        local fx = field.posX or (field.startX and (field.startX + (field.widthX or 0) * 0.5)) or cx
        local fz = field.posZ or (field.startZ and (field.startZ + (field.heightZ or 0) * 0.5)) or cz
        local fr = field.fieldRadius or 50
        minX, maxX = fx - fr, fx + fr
        minZ, maxZ = fz - fr, fz + fr
    end

    -- Find closest point on AABB to circle center
    local closestX = math.max(minX, math.min(cx, maxX))
    local closestZ = math.max(minZ, math.min(cz, maxZ))
    local dx = cx - closestX
    local dz = cz - closestZ
    return (dx*dx + dz*dz) <= radius*radius
end

-- ============================================================
-- Water Source Lookup
-- ============================================================
function IrrigationManager:findNearestWaterSource(x, z)
    local nearestId = nil
    local minDist = math.huge

    for id, source in pairs(self.waterSources) do
        if source.hasWater then
            local dx = source.x - x
            local dz = source.z - z
            local dist = math.sqrt(dx*dx + dz*dz)
            if dist <= IrrigationManager.MAX_PUMP_DISTANCE and dist < minDist then
                minDist = dist
                nearestId = id
            end
        end
    end

    if nearestId then
        return nearestId, minDist
    else
        return nil, nil
    end
end

function IrrigationManager:calculatePressureMultiplier(distance)
    if distance > IrrigationManager.MAX_PUMP_DISTANCE then return 0 end
    -- Linear: 1.0 at 0m, (1 - PRESSURE_FALLOFF) at max distance
    return 1.0 - (distance / IrrigationManager.MAX_PUMP_DISTANCE) * IrrigationManager.PRESSURE_FALLOFF
end

-- ============================================================
-- Hourly Schedule Check
-- ============================================================
function IrrigationManager:hourlyScheduleCheck()
    if not self.isInitialized then return end
    local env = g_currentMission.environment
    if not env then return end

    local hour = env:getHour() or 0
    local dayOfWeek = env:getDayOfWeek() or 1  -- 1..7

    for id, system in pairs(self.systems) do
        -- Check if water source is still valid
        if system.waterSourceId and not self.waterSources[system.waterSourceId] then
            -- Source disappeared; deactivate
            if system.isActive then self:deactivateSystem(id) end
            system.waterSourceId = nil
            system.pressureMultiplier = 0
        end

        local shouldBeActive = false
        if system.waterSourceId and system.pressureMultiplier > 0 then
            local sched = system.schedule
            shouldBeActive = sched.activeDays[dayOfWeek] and
                             hour >= sched.startHour and
                             hour < sched.endHour
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
    if not system or system.isActive then return end

    -- Recalculate effective rate based on current pressure and wear
    local wearFactor = 1.0 - system.wearLevel * 0.3  -- worn pump reduces flow
    local effectiveRate = system.flowRatePerHour * system.pressureMultiplier * wearFactor

    system.effectiveRatePerField = {}
    for _, fieldId in ipairs(system.coveredFields) do
        system.effectiveRatePerField[fieldId] = effectiveRate
        -- Publish event
        if self.manager and self.manager.eventBus then
            self.manager.eventBus.publish("CS_IRRIGATION_STARTED", {
                placeableId = id,
                fieldId = fieldId,
                ratePerHour = effectiveRate,
            })
        end
    end

    system.isActive = true
    g_logManager:devInfo("[CropStress]", string.format("Irrigation system %d activated, rate=%.4f", id, effectiveRate))
end

function IrrigationManager:deactivateSystem(id)
    local system = self.systems[id]
    if not system or not system.isActive then return end

    for _, fieldId in ipairs(system.coveredFields) do
        local rate = system.effectiveRatePerField[fieldId] or 0
        if self.manager and self.manager.eventBus then
            self.manager.eventBus.publish("CS_IRRIGATION_STOPPED", {
                placeableId = id,
                fieldId = fieldId,
                ratePerHour = rate,
            })
        end
    end

    system.effectiveRatePerField = {}
    system.isActive = false
    g_logManager:devInfo("[CropStress]", string.format("Irrigation system %d deactivated", id))
end

-- ============================================================
-- Get Irrigation Rate for a Field (sum of active systems)
-- ============================================================
function IrrigationManager:getIrrigationRateForField(fieldId)
    local total = 0
    for _, system in pairs(self.systems) do
        if system.isActive and system.effectiveRatePerField[fieldId] then
            total = total + system.effectiveRatePerField[fieldId]
        end
    end
    return total
end

-- ============================================================
-- Cleanup
-- ============================================================
function IrrigationManager:delete()
    for id, _ in pairs(self.systems) do
        if self.systems[id].isActive then
            self:deactivateSystem(id)
        end
    end
    self.systems = {}
    self.waterSources = {}
    self.isInitialized = false
end
