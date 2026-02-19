-- ============================================================
-- IrrigationManager.lua
-- PHASE 2 STUB — not yet implemented.
--
-- When implemented, this system will:
--   • Track all placed irrigation placeables (center-pivot, drip, pump)
--   • Calculate which fields each system covers
--   • Run a scheduling engine (per-day start/end hours, active days)
--   • Set irrigationGain on covered fields in SoilMoistureSystem
--   • Publish CS_IRRIGATION_STARTED / CS_IRRIGATION_STOPPED events
--
-- See Section 6.2 of FS25_SeasonalCropStress_ModPlan.md for full spec.
-- ============================================================

IrrigationManager = {}
IrrigationManager.__index = IrrigationManager

function IrrigationManager.new(manager)
    local self = setmetatable({}, IrrigationManager)
    self.manager = manager
    self.irrigationSystems = {}  -- placeableId → system data table
    self.isInitialized = false
    return self
end

function IrrigationManager:initialize()
    -- Phase 2: enumerate existing placeables and register any irrigation systems
    self.isInitialized = true
end

function IrrigationManager:hourlyScheduleCheck()
    -- Phase 2: activate/deactivate irrigation systems per schedule
end

function IrrigationManager:registerIrrigationSystem(placeable)
    -- Phase 2: called from placeable onPostLoad
end

function IrrigationManager:deregisterIrrigationSystem(placeableId)
    -- Phase 2: called from placeable onDelete
end

function IrrigationManager:delete()
    self.isInitialized = false
end
