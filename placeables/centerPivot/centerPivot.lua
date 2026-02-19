-- ============================================================
-- centerPivot.lua
-- Center pivot irrigation system. Registers with IrrigationManager.
-- Animates arm when active.
-- ============================================================

IrrigationPivot = {}
local IrrigationPivot_mt = Class(IrrigationPivot, Placeable)

function IrrigationPivot.new(isServer, isClient, customMt)
    local self = Placeable.new(isServer, isClient, customMt or IrrigationPivot_mt)
    self.irrigationManager = g_cropStressManager and g_cropStressManager.irrigationManager
    self.radius = 200
    self.flowRatePerHour = 0.018
    self.operationalCostPerHour = 15
    self.defaultStartHour = 6
    self.defaultEndHour = 10
    self.defaultActiveDays = {true, true, true, true, true, false, false}
    self.armNode = nil  -- will be set from i3d
    self.armRotation = 0
    self.irrigationType = "pivot"
    return self
end

function IrrigationPivot:onLoad(savegame)
    Placeable.onLoad(self, savegame)

    -- Load custom config from XML
    local config = self.configurations and self.configurations.irrigationConfig
    if config then
        self.radius = config.radius or self.radius
        self.flowRatePerHour = config.flowRatePerHour or self.flowRatePerHour
        self.operationalCostPerHour = config.operationalCostPerHour or self.operationalCostPerHour
        self.defaultStartHour = config.defaultStartHour or self.defaultStartHour
        self.defaultEndHour = config.defaultEndHour or self.defaultEndHour
        if config.defaultActiveDays then
            local days = {}
            for v in string.gmatch(config.defaultActiveDays, "[^,]+") do
                table.insert(days, tonumber(v) ~= 0)
            end
            self.defaultActiveDays = days
        end
    end

    -- Find arm node in i3d
    self.armNode = self:getNodeFromComponent("armNode")  -- need to define in i3d

    if self.irrigationManager then
        self.irrigationManager:registerIrrigationSystem(self)
    end
end

function IrrigationPivot:onDelete()
    if self.irrigationManager then
        self.irrigationManager:deregisterIrrigationSystem(self.id)
    end
    Placeable.onDelete(self)
end

function IrrigationPivot:onUpdate(dt)
    Placeable.onUpdate(self, dt)
    -- Sync active state from IrrigationManager (manager owns the canonical state)
    local mgr = g_cropStressManager and g_cropStressManager.irrigationManager
    local sys = mgr and mgr.systems[self.id]
    self.isActive = sys and sys.isActive or false
    if self.isActive and self.armNode then
        self.armRotation = self.armRotation + 0.5 * dt  -- rotate slowly
        setRotation(self.armNode, 0, self.armRotation, 0)
    end
end

function IrrigationPivot:onReadStream(streamId, connection)
    Placeable.onReadStream(self, streamId, connection)
    self.isActive = streamReadBool(streamId)
end

function IrrigationPivot:onWriteStream(streamId, connection)
    Placeable.onWriteStream(self, streamId, connection)
    streamWriteBool(streamId, self.isActive)
end