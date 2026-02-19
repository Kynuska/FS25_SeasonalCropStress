-- ============================================================
-- waterPump.lua
-- Water pump placeable. Registers with IrrigationManager as a water source.
-- ============================================================

WaterPump = {}
local WaterPump_mt = Class(WaterPump, Placeable)

function WaterPump.new(isServer, isClient, customMt)
    local self = Placeable.new(isServer, isClient, customMt or WaterPump_mt)
    self.irrigationManager = g_cropStressManager and g_cropStressManager.irrigationManager
    return self
end

function WaterPump:onLoad(savegame)
    Placeable.onLoad(self, savegame)
    self.waterFlowCapacity = self.configurations and self.configurations.waterFlowCapacity or 1000
    if self.irrigationManager then
        self.irrigationManager:registerWaterSource(self)
    end
end

function WaterPump:onDelete()
    if self.irrigationManager then
        self.irrigationManager:deregisterWaterSource(self.id)
    end
    Placeable.onDelete(self)
end

function WaterPump:onReadStream(streamId, connection)
    Placeable.onReadStream(self, streamId, connection)
    -- Read any sync data if needed
end

function WaterPump:onWriteStream(streamId, connection)
    Placeable.onWriteStream(self, streamId, connection)
    -- Write sync data
end