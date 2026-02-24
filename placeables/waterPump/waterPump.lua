-- ============================================================
-- waterPump.lua
-- Water pump placeable. Registers with IrrigationManager as a water source.
-- ============================================================

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

WaterPump = {}
local WaterPump_mt = Class(WaterPump, Placeable)

function WaterPump.new(isServer, isClient, customMt)
    -- Placeable.new() takes only the metatable in FS25
    local self = Placeable.new(customMt or WaterPump_mt)
    self.isServer = isServer
    self.isClient = isClient

    -- irrigationManager must NOT be read here — g_cropStressManager doesn't exist yet.
    -- Looked up in onLoad instead.
    self.irrigationManager = nil
    self.waterFlowCapacity = 1000  -- default; overwritten in onLoad from XML
    return self
end

function WaterPump:onLoad(savegame)
    Placeable.onLoad(self, savegame)

    -- Read custom config from the placeable's XML file
    if self.xmlFile ~= nil then
        local base = self.baseKey .. ".pumpConfig"
        local wfc = getXMLFloat(self.xmlFile, base .. "#waterFlowCapacity")
        if wfc ~= nil then
            self.waterFlowCapacity = wfc
        end
    end

    -- Resolve IrrigationManager now that the mission is loaded
    self.irrigationManager = g_cropStressManager and g_cropStressManager.irrigationManager or nil

    -- waterFlowCapacity must be set BEFORE registerWaterSource so the
    -- manager records the correct capacity on first registration
    if self.irrigationManager ~= nil then
        self.irrigationManager:registerWaterSource(self)
    else
        csLog("waterPump: IrrigationManager not available at onLoad — pump not registered")
    end
end

function WaterPump:onDelete()
    if self.irrigationManager ~= nil then
        self.irrigationManager:deregisterWaterSource(self.id)
    end
    Placeable.onDelete(self)
end

function WaterPump:onReadStream(streamId, connection)
    Placeable.onReadStream(self, streamId, connection)
    -- No additional state to sync for Phase 2
end

function WaterPump:onWriteStream(streamId, connection)
    Placeable.onWriteStream(self, streamId, connection)
    -- No additional state to sync for Phase 2
end