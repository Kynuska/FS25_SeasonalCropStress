-- ============================================================
-- dripLine.lua
-- Drip irrigation line system. Registers with IrrigationManager.
-- Uses linear coverage (start/end markers) instead of circular.
-- E-key proximity interaction: opens IrrigationScheduleDialog when
-- player is within INTERACTION_RADIUS metres of the line.
-- ============================================================

DripIrrigationLine = {}
local DripIrrigationLine_mt = Class(DripIrrigationLine, Placeable)

DripIrrigationLine.INTERACTION_RADIUS = 8  -- metres

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

function DripIrrigationLine.new(isServer, isClient, customMt)
    local self = Placeable.new(customMt or DripIrrigationLine_mt)
    self.isServer = isServer
    self.isClient = isClient

    self.irrigationManager = nil

    -- Drip line parameters
    self.lineLength         = 100    -- metres
    self.lineSpacing        = 0.8    -- metres between lines
    self.flowRatePerHour   = 0.012  -- moisture gain per hour
    self.operationalCostPerHour = 8
    self.defaultStartHour   = 6
    self.defaultEndHour    = 10
    self.defaultActiveDays  = {true, true, true, true, true, false, false}
    self.irrigationType    = "drip"
    self.isActive          = false

    -- Start/end positions for linear coverage
    self.startX = 0
    self.startZ = 0
    self.endX   = 0
    self.endZ   = 0

    -- Coverage area (calculated from start/end)
    self.coverageMinX = 0
    self.coverageMaxX = 0
    self.coverageMinZ = 0
    self.coverageMaxZ = 0

    -- Proximity interaction state
    self.triggerNode        = nil
    self.playerInRange      = false
    self.actionEventId      = nil

    return self
end

function DripIrrigationLine:onLoad(savegame)
    Placeable.onLoad(self, savegame)

    -- Read custom config from the placeable's XML file
    if self.xmlFile ~= nil then
        local base = self.baseKey .. ".dripConfig"
        local ll = getXMLFloat(self.xmlFile, base .. "#lineLength")
        local ls = getXMLFloat(self.xmlFile, base .. "#lineSpacing")
        local fr = getXMLFloat(self.xmlFile, base .. "#flowRatePerHour")
        local oc = getXMLFloat(self.xmlFile, base .. "#operationalCostPerHour")
        local sh = getXMLInt(self.xmlFile,   base .. "#defaultStartHour")
        local eh = getXMLInt(self.xmlFile,   base .. "#defaultEndHour")

        if ll ~= nil then self.lineLength          = ll end
        if ls ~= nil then self.lineSpacing         = ls end
        if fr ~= nil then self.flowRatePerHour     = fr end
        if oc ~= nil then self.operationalCostPerHour = oc end
        if sh ~= nil then self.defaultStartHour    = sh end
        if eh ~= nil then self.defaultEndHour      = eh end

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

    -- Get position from root node
    local x, y, z = getWorldTranslation(self.nodeId)
    self.startX = x
    self.startZ = z
    self.endX   = x + self.lineLength
    self.endZ   = z

    -- Calculate coverage bounding box
    self.coverageMinX = math.min(self.startX, self.endX)
    self.coverageMaxX = math.max(self.startX, self.endX)
    self.coverageMinZ = math.min(self.startZ, self.endZ) - self.lineSpacing * 0.5
    self.coverageMaxZ = math.max(self.startZ, self.endZ) + self.lineSpacing * 0.5

    -- Proximity trigger (client-only)
    if self.isClient then
        self:createProximityTrigger()
    end

    -- Resolve IrrigationManager
    self.irrigationManager = g_cropStressManager and g_cropStressManager.irrigationManager or nil

    if self.irrigationManager ~= nil then
        self.irrigationManager:registerIrrigationSystem(self)
    else
        csLog("dripLine: IrrigationManager not available at onLoad — drip line not registered")
    end
end

-- ============================================================
-- PROXIMITY TRIGGER
-- ============================================================
function DripIrrigationLine:createProximityTrigger()
    if self.nodeId == nil then return end

    self.triggerNode = createTransformGroup("dripLineTrigger")
    if self.triggerNode == nil or self.triggerNode == 0 then
        self.triggerNode = nil
        return
    end

    link(self.nodeId, self.triggerNode)
    setTranslation(self.triggerNode, 0, 0, 0)

    addTrigger(self.triggerNode, self)

    csLog(string.format("dripLine %s: proximity trigger created (r=%.1fm)", tostring(self.id), DripIrrigationLine.INTERACTION_RADIUS))
end

function DripIrrigationLine:onProximityTrigger(triggerId, otherId, onEnter, onLeave, onStay)
    local player = g_localPlayer
    if player == nil then return end

    local playerNode = player.rootNode or player.nodeId
    if playerNode == nil or otherId ~= playerNode then return end

    if onEnter then
        self.playerInRange = true
        self:registerInteractionAction()
    elseif onLeave then
        self.playerInRange = false
        self:removeInteractionAction()
    end
end

-- ============================================================
-- INPUT ACTION REGISTRATION
-- ============================================================
function DripIrrigationLine:registerInteractionAction()
    if self.actionEventId ~= nil then return end
    if g_inputBinding == nil then return end
    if InputAction == nil or InputAction.ACTIVATE_HANDTOOL == nil then return end

    local _, actionEventId = g_inputBinding:registerActionEvent(
        InputAction.ACTIVATE_HANDTOOL,
        self,
        DripIrrigationLine.onInteractPressed,
        false,  -- triggerUp
        true,   -- triggerDown
        false,  -- triggerAlways
        true    -- startActive
    )
    self.actionEventId = actionEventId

    if actionEventId ~= nil then
        g_inputBinding:setActionEventText(actionEventId, g_i18n:getText("cs_irr_open_schedule"))
        g_inputBinding:setActionEventActive(actionEventId, true)
        g_inputBinding:setActionEventTextVisibility(actionEventId, true)
    end
end

function DripIrrigationLine:removeInteractionAction()
    if self.actionEventId == nil then return end
    if g_inputBinding ~= nil then
        g_inputBinding:removeActionEvent(self.actionEventId)
    end
    self.actionEventId = nil
end

function DripIrrigationLine:onInteractPressed()
    if not self.playerInRange then return end

    local mgr = g_cropStressManager
    if mgr == nil then return end

    local dialog = g_gui:showDialog("IrrigationScheduleDialog")
    if dialog ~= nil and dialog.target ~= nil then
        dialog.target:onIrrigationDialogOpen(self.id)
    end

    self:removeInteractionAction()
end

-- ============================================================
-- UPDATE
-- ============================================================
function DripIrrigationLine:onUpdate(dt)
    Placeable.onUpdate(self, dt)

    -- Sync active state from IrrigationManager
    local mgr = g_cropStressManager and g_cropStressManager.irrigationManager or nil
    local sys = mgr ~= nil and mgr.systems[self.id] or nil
    self.isActive = sys ~= nil and sys.isActive == true

    -- Re-register interaction if player is in range but action was cleared
    if self.isClient and self.playerInRange and self.actionEventId == nil then
        self:registerInteractionAction()
    end
end

-- ============================================================
-- DELETE
-- ============================================================
function DripIrrigationLine:onDelete()
    if self.isClient then
        self:removeInteractionAction()
        if self.triggerNode ~= nil and self.triggerNode ~= 0 then
            removeTrigger(self.triggerNode)
            delete(self.triggerNode)
            self.triggerNode = nil
        end
    end

    if self.irrigationManager ~= nil then
        self.irrigationManager:deregisterIrrigationSystem(self.id)
    end
    Placeable.onDelete(self)
end

-- ============================================================
-- MULTIPLAYER STREAM
-- ============================================================
function DripIrrigationLine:onReadStream(streamId, connection)
    Placeable.onReadStream(self, streamId, connection)
    self.isActive = streamReadBool(streamId)
end

function DripIrrigationLine:onWriteStream(streamId, connection)
    Placeable.onWriteStream(self, streamId, connection)
    streamWriteBool(streamId, self.isActive)
end
