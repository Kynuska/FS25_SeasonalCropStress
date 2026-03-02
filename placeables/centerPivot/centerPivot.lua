-- ============================================================
-- centerPivot.lua
-- Center pivot irrigation system — FS25 specialization pattern.
-- Registers with IrrigationManager. Animates arm when active.
-- E-key proximity interaction: opens IrrigationScheduleDialog when
-- player is within INTERACTION_RADIUS metres of the pivot centre.
-- ============================================================

IrrigationPivot = {}
IrrigationPivot.MOD_NAME = g_currentModName
IrrigationPivot.INTERACTION_RADIUS = 8  -- metres

local function csLog(msg)
    if g_logManager ~= nil then
        g_logManager:devInfo("[CropStress]", msg)
    else
        print("[CropStress] " .. tostring(msg))
    end
end

-- ============================================================
-- SPECIALIZATION REGISTRATION
-- ============================================================
function IrrigationPivot.prerequisitesPresent(specializations)
    return true
end

function IrrigationPivot.registerFunctions(placeableType)
    SpecializationUtil.registerFunction(placeableType, "registerInteractionAction", IrrigationPivot.registerInteractionAction)
    SpecializationUtil.registerFunction(placeableType, "removeInteractionAction",   IrrigationPivot.removeInteractionAction)
    SpecializationUtil.registerFunction(placeableType, "onInteractPressed",         IrrigationPivot.onInteractPressed)
end

function IrrigationPivot.registerEventListeners(placeableType)
    SpecializationUtil.registerEventListener(placeableType, "onLoad",        IrrigationPivot)
    SpecializationUtil.registerEventListener(placeableType, "onUpdate",      IrrigationPivot)
    SpecializationUtil.registerEventListener(placeableType, "onDelete",      IrrigationPivot)
    SpecializationUtil.registerEventListener(placeableType, "onReadStream",  IrrigationPivot)
    SpecializationUtil.registerEventListener(placeableType, "onWriteStream", IrrigationPivot)
end

-- ============================================================
-- LIFECYCLE
-- ============================================================
function IrrigationPivot.onLoad(self, savegame)
    -- Initialise custom fields (replaces new() in standalone-class pattern)
    self.irrigationManager       = nil
    self.radius                  = 200
    self.flowRatePerHour         = 0.018
    self.operationalCostPerHour  = 15
    self.defaultStartHour        = 6
    self.defaultEndHour          = 10
    self.defaultActiveDays       = {true, true, true, true, true, false, false}
    self.armNode                 = nil
    self.armRotation             = 0
    self.irrigationType          = "pivot"
    self.isActive                = false
    self.playerInRange           = false
    self.actionEventId           = nil

    -- Read custom config from the placeable XML (self.xmlFile is an XMLFile object in FS25)
    if self.xmlFile ~= nil then
        local base = "placeable.irrigationConfig"
        self.radius                 = self.xmlFile:getFloat(base .. "#radius",                 self.radius)
        self.flowRatePerHour        = self.xmlFile:getFloat(base .. "#flowRatePerHour",        self.flowRatePerHour)
        self.operationalCostPerHour = self.xmlFile:getFloat(base .. "#operationalCostPerHour", self.operationalCostPerHour)
        self.defaultStartHour       = self.xmlFile:getInt(  base .. "#defaultStartHour",       self.defaultStartHour)
        self.defaultEndHour         = self.xmlFile:getInt(  base .. "#defaultEndHour",         self.defaultEndHour)

        local daysStr = self.xmlFile:getString(base .. "#defaultActiveDays", nil)
        if daysStr ~= nil then
            local days = {}
            for v in string.gmatch(daysStr, "[^,]+") do
                table.insert(days, tonumber(v) ~= 0)
            end
            if #days == 7 then self.defaultActiveDays = days end
        end
    end

    -- Find arm node in i3d
    if self.nodeId ~= nil then
        local armIdx = I3DUtil.getChildIndex(self.nodeId, "armNode")
        if armIdx ~= nil and armIdx >= 0 then
            self.armNode = getChildAt(self.nodeId, armIdx)
        end
    end

    -- Register with IrrigationManager
    self.irrigationManager = g_cropStressManager and g_cropStressManager.irrigationManager or nil
    if self.irrigationManager ~= nil then
        self.irrigationManager:registerIrrigationSystem(self)
    else
        csLog("centerPivot: IrrigationManager not available at onLoad — pivot not registered")
    end
end

function IrrigationPivot.onUpdate(self, dt)
    -- Sync active state from IrrigationManager
    local mgr = g_cropStressManager and g_cropStressManager.irrigationManager or nil
    local sys = mgr ~= nil and mgr.systems[self.id] or nil
    self.isActive = sys ~= nil and sys.isActive == true

    -- Arm animation: client-only, when active and i3d node exists
    if self.isClient and self.isActive and self.armNode ~= nil then
        self.armRotation = (self.armRotation + 0.5 * dt) % (math.pi * 2)
        setRotation(self.armNode, 0, self.armRotation, 0)
    end

    -- Distance poll for proximity interaction (client-only)
    if self.isClient and self.nodeId ~= nil then
        local player = g_localPlayer
        if player ~= nil then
            local px, _, pz = getWorldTranslation(player.rootNode or player.nodeId)
            local sx, _, sz = getWorldTranslation(self.nodeId)
            local r = IrrigationPivot.INTERACTION_RADIUS
            local inRange = (px-sx)*(px-sx) + (pz-sz)*(pz-sz) <= r*r
            if inRange and not self.playerInRange then
                self.playerInRange = true
                self:registerInteractionAction()
            elseif not inRange and self.playerInRange then
                self.playerInRange = false
                self:removeInteractionAction()
            end
        end
    end

    -- Re-register if player is in range but action was cleared (e.g. after dialog closed)
    if self.isClient and self.playerInRange and self.actionEventId == nil then
        self:registerInteractionAction()
    end
end

function IrrigationPivot.onDelete(self)
    if self.isClient then
        self:removeInteractionAction()
    end
    if self.irrigationManager ~= nil then
        self.irrigationManager:deregisterIrrigationSystem(self.id)
    end
end

function IrrigationPivot.onReadStream(self, streamId, connection)
    self.isActive = streamReadBool(streamId)
end

function IrrigationPivot.onWriteStream(self, streamId, connection)
    streamWriteBool(streamId, self.isActive or false)
end

-- ============================================================
-- INPUT ACTION REGISTRATION
-- ============================================================
function IrrigationPivot.registerInteractionAction(self)
    if self.actionEventId ~= nil then return end
    if g_inputBinding == nil then return end
    if InputAction == nil or InputAction.ACTIVATE_HANDTOOL == nil then return end

    local _, actionEventId = g_inputBinding:registerActionEvent(
        InputAction.ACTIVATE_HANDTOOL, self, IrrigationPivot.onInteractPressed,
        false, true, false, true
    )
    self.actionEventId = actionEventId

    if actionEventId ~= nil then
        local label = (g_i18n ~= nil and g_i18n:getText("cs_irr_open_schedule")) or "Open Irrigation Schedule"
        g_inputBinding:setActionEventText(actionEventId, label)
        g_inputBinding:setActionEventActive(actionEventId, true)
        g_inputBinding:setActionEventTextVisibility(actionEventId, true)
    end
end

function IrrigationPivot.removeInteractionAction(self)
    if self.actionEventId == nil then return end
    if g_inputBinding ~= nil then
        g_inputBinding:removeActionEvent(self.actionEventId)
    end
    self.actionEventId = nil
end

function IrrigationPivot.onInteractPressed(self)
    if not self.playerInRange then return end
    if g_cropStressManager == nil then return end

    local dialog = g_gui:showDialog("IrrigationScheduleDialog")
    if dialog ~= nil then
        dialog:onIrrigationDialogOpen(self.id)
    end

    self:removeInteractionAction()
end
