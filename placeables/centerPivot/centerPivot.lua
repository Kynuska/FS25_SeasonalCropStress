-- ============================================================
-- centerPivot.lua
-- Center pivot irrigation system. Registers with IrrigationManager.
-- Animates arm when active.
-- ============================================================

IrrigationPivot = {}
local IrrigationPivot_mt = Class(IrrigationPivot, Placeable)

function IrrigationPivot.new(isServer, isClient, customMt)
    -- Placeable.new() takes only the metatable in FS25
    local self = Placeable.new(customMt or IrrigationPivot_mt)
    self.isServer = isServer
    self.isClient = isClient

    -- irrigationManager must NOT be read here — g_cropStressManager doesn't exist yet.
    -- Looked up in onLoad instead.
    self.irrigationManager = nil

    self.radius = 200
    self.flowRatePerHour = 0.018
    self.operationalCostPerHour = 15
    self.defaultStartHour = 6
    self.defaultEndHour = 10
    self.defaultActiveDays = {true, true, true, true, true, false, false}
    self.armNode = nil      -- set from i3d in onLoad
    self.armRotation = 0
    self.irrigationType = "pivot"
    self.isActive = false   -- explicit init — onUpdate reads this before any stream
    return self
end

function IrrigationPivot:onLoad(savegame)
    Placeable.onLoad(self, savegame)

    -- Read custom config from the placeable's XML file
    -- xmlFile and baseKey are available via self.xmlFile / self.baseKey after Placeable.onLoad
    if self.xmlFile ~= nil then
        local base = self.baseKey .. ".irrigationConfig"
        local r  = getXMLFloat(self.xmlFile, base .. "#radius")
        local fr = getXMLFloat(self.xmlFile, base .. "#flowRatePerHour")
        local oc = getXMLFloat(self.xmlFile, base .. "#operationalCostPerHour")
        local sh = getXMLInt(self.xmlFile,   base .. "#defaultStartHour")
        local eh = getXMLInt(self.xmlFile,   base .. "#defaultEndHour")
        if r  ~= nil then self.radius                  = r  end
        if fr ~= nil then self.flowRatePerHour         = fr end
        if oc ~= nil then self.operationalCostPerHour  = oc end
        if sh ~= nil then self.defaultStartHour        = sh end
        if eh ~= nil then self.defaultEndHour          = eh end

        local daysStr = getXMLString(self.xmlFile, base .. "#defaultActiveDays")
        if daysStr ~= nil then
            local days = {}
            for v in string.gmatch(daysStr, "[^,]+") do
                table.insert(days, tonumber(v) ~= 0)
            end
            if #days == 7 then
                self.defaultActiveDays = days
            end
        end
    end

    -- Find arm node in i3d via the root component node
    -- getChildByName() walks immediate children; falls back to nil safely
    if self.nodeId ~= nil then
        local armIdx = I3DUtil.getChildIndex(self.nodeId, "armNode")
        if armIdx ~= nil then
            self.armNode = getChildAt(self.nodeId, armIdx)
        end
    end

    -- Resolve IrrigationManager now that the mission is loaded
    self.irrigationManager = g_cropStressManager and g_cropStressManager.irrigationManager or nil

    if self.irrigationManager ~= nil then
        self.irrigationManager:registerIrrigationSystem(self)
    else
        print("[CropStress] centerPivot: IrrigationManager not available at onLoad — pivot not registered")
    end
end

function IrrigationPivot:onDelete()
    if self.irrigationManager ~= nil then
        self.irrigationManager:deregisterIrrigationSystem(self.id)
    end
    Placeable.onDelete(self)
end

function IrrigationPivot:onUpdate(dt)
    Placeable.onUpdate(self, dt)

    -- Sync active state from IrrigationManager (manager owns canonical state)
    local mgr = g_cropStressManager and g_cropStressManager.irrigationManager or nil
    local sys = mgr ~= nil and mgr.systems[self.id] or nil
    self.isActive = sys ~= nil and sys.isActive == true

    -- Arm animation: client-only, only when active and i3d node exists
    if self.isClient and self.isActive and self.armNode ~= nil then
        self.armRotation = self.armRotation + 0.5 * dt
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