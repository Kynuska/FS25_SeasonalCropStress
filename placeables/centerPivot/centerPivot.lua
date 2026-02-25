-- ============================================================
-- centerPivot.lua
-- Center pivot irrigation system. Registers with IrrigationManager.
-- Animates arm when active.
-- E-key proximity interaction: opens IrrigationScheduleDialog when
-- player is within INTERACTION_RADIUS metres of the pivot centre.
-- ============================================================

IrrigationPivot = {}
local IrrigationPivot_mt = Class(IrrigationPivot, Placeable)

IrrigationPivot.INTERACTION_RADIUS = 8  -- metres; player must be within this to see prompt

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

function IrrigationPivot.new(isServer, isClient, customMt)
    local self = Placeable.new(customMt or IrrigationPivot_mt)
    self.isServer = isServer
    self.isClient = isClient

    self.irrigationManager = nil

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

    -- Proximity interaction state (client-side only)
    self.triggerNode             = nil
    self.playerInRange           = false
    self.actionEventId           = nil

    return self
end

function IrrigationPivot:onLoad(savegame)
    Placeable.onLoad(self, savegame)

    -- Read custom config from the placeable's XML file
    if self.xmlFile ~= nil then
        local base = self.baseKey .. ".irrigationConfig"
        local r  = getXMLFloat(self.xmlFile,  base .. "#radius")
        local fr = getXMLFloat(self.xmlFile,  base .. "#flowRatePerHour")
        local oc = getXMLFloat(self.xmlFile,  base .. "#operationalCostPerHour")
        local sh = getXMLInt(self.xmlFile,    base .. "#defaultStartHour")
        local eh = getXMLInt(self.xmlFile,    base .. "#defaultEndHour")
        if r  ~= nil then self.radius                 = r  end
        if fr ~= nil then self.flowRatePerHour        = fr end
        if oc ~= nil then self.operationalCostPerHour = oc end
        if sh ~= nil then self.defaultStartHour       = sh end
        if eh ~= nil then self.defaultEndHour         = eh end

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

    -- Find arm node in i3d
    if self.nodeId ~= nil then
        local armIdx = I3DUtil.getChildIndex(self.nodeId, "armNode")
        if armIdx ~= nil then
            self.armNode = getChildAt(self.nodeId, armIdx)
        end
    end

    -- Proximity trigger (client-only — no need to run on server)
    if self.isClient then
        self:createProximityTrigger()
    end

    -- Resolve IrrigationManager
    self.irrigationManager = g_cropStressManager and g_cropStressManager.irrigationManager or nil

    if self.irrigationManager ~= nil then
        self.irrigationManager:registerIrrigationSystem(self)
    else
        csLog("centerPivot: IrrigationManager not available at onLoad — pivot not registered")
    end
end

-- ============================================================
-- PROXIMITY TRIGGER
-- Creates a spherical trigger node attached to the pivot root.
-- FS25 trigger callbacks fire with (triggerId, otherId, onEnter, onLeave, onStay).
-- We check if the other node is the local player's root node.
-- ============================================================
function IrrigationPivot:createProximityTrigger()
    if self.nodeId == nil then return end

    -- Create a new transform group as a child of the root node
    self.triggerNode = createTransformGroup("irrigationPivotTrigger")
    if self.triggerNode == nil or self.triggerNode == 0 then
        self.triggerNode = nil
        return
    end

    link(self.nodeId, self.triggerNode)
    setTranslation(self.triggerNode, 0, 0, 0)

    -- Add a sphere collider for the trigger
    -- FS25 addSphere syntax: addSphere(node, radius, useForCollision, collisionMask, triggerMask)
    -- For a trigger volume, we need addTrigger instead
    local triggerRadius = IrrigationPivot.INTERACTION_RADIUS
    
    -- Use addTrigger(node, callbackName, target) — callbackName is a STRING, not a function/table.
    -- FS25 calls target[callbackName](target, triggerId, otherId, onEnter, onLeave, onStay).
    addTrigger(self.triggerNode, "onProximityTrigger", self)

    csLog(string.format("centerPivot %s: proximity trigger created (r=%.1fm)", tostring(self.id), triggerRadius))
end

-- Trigger callback — fires when any entity enters/leaves the sphere
function IrrigationPivot:onProximityTrigger(triggerId, otherId, onEnter, onLeave, onStay)
    -- Only care about the local player's root node
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
-- Registers the E-key action event when player enters range.
-- Uses the beginActionEventsModification / endActionEventsModification
-- pattern to avoid duplicate keybind registration.
-- ============================================================
function IrrigationPivot:registerInteractionAction()
    if self.actionEventId ~= nil then return end  -- already registered
    if g_inputBinding == nil then return end
    if InputAction == nil or InputAction.ACTIVATE_HANDTOOL == nil then return end

    -- ACTIVATE_HANDTOOL is the standard FS25 "E" interaction action
    local _, actionEventId = g_inputBinding:registerActionEvent(
        InputAction.ACTIVATE_HANDTOOL,
        self,
        IrrigationPivot.onInteractPressed,
        false,  -- triggerUp
        true,   -- triggerDown
        false,  -- triggerAlways
        true    -- startActive
    )
    self.actionEventId = actionEventId

    -- Show the interaction help text at the bottom of the screen
    if actionEventId ~= nil then
        g_inputBinding:setActionEventText(actionEventId, g_i18n:getText("cs_irr_open_schedule"))
        g_inputBinding:setActionEventActive(actionEventId, true)
        g_inputBinding:setActionEventTextVisibility(actionEventId, true)
    end
end

function IrrigationPivot:removeInteractionAction()
    if self.actionEventId == nil then return end
    if g_inputBinding ~= nil then
        g_inputBinding:removeActionEvent(self.actionEventId)
    end
    self.actionEventId = nil
end

-- Called when player presses E within range
function IrrigationPivot:onInteractPressed()
    if not self.playerInRange then return end

    local mgr = g_cropStressManager
    if mgr == nil then return end

    -- Open the irrigation schedule dialog for this system
    local dialog = g_gui:showDialog("IrrigationScheduleDialog")
    if dialog ~= nil and dialog.target ~= nil then
        dialog.target:onIrrigationDialogOpen(self.id)
    end

    -- Remove action event after opening so it doesn't double-fire
    self:removeInteractionAction()
end

-- ============================================================
-- UPDATE
-- ============================================================
function IrrigationPivot:onUpdate(dt)
    Placeable.onUpdate(self, dt)

    -- Sync active state from IrrigationManager
    local mgr = g_cropStressManager and g_cropStressManager.irrigationManager or nil
    local sys = mgr ~= nil and mgr.systems[self.id] or nil
    self.isActive = sys ~= nil and sys.isActive == true

    -- Arm animation: client-only, only when active and i3d node exists
    if self.isClient and self.isActive and self.armNode ~= nil then
        self.armRotation = self.armRotation + 0.5 * dt
        setRotation(self.armNode, 0, self.armRotation, 0)
    end

    -- Re-register interaction if player is in range but action was cleared
    -- (e.g. after dialog was closed)
    if self.isClient and self.playerInRange and self.actionEventId == nil then
        self:registerInteractionAction()
    end
end

-- ============================================================
-- DELETE
-- ============================================================
function IrrigationPivot:onDelete()
    -- Clean up interaction action event
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
function IrrigationPivot:onReadStream(streamId, connection)
    Placeable.onReadStream(self, streamId, connection)
    self.isActive = streamReadBool(streamId)
end

function IrrigationPivot:onWriteStream(streamId, connection)
    Placeable.onWriteStream(self, streamId, connection)
    streamWriteBool(streamId, self.isActive)
end