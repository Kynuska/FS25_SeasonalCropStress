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
-- local to this placeable module — not shared with src/ logging
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
        if armIdx ~= nil and armIdx >= 0 then  -- getChildIndex returns -1 (not nil) when node not found
            self.armNode = getChildAt(self.nodeId, armIdx)
        end
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
        local label = (g_i18n ~= nil and g_i18n:getText("cs_irr_open_schedule")) or "Open Irrigation Schedule"
        g_inputBinding:setActionEventText(actionEventId, label)
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

    -- Arm animation: client-only, only when active and i3d node exists.
    -- Modulo 2π keeps the value in [0, 2π) to prevent floating-point precision
    -- drift during long play sessions.
    if self.isClient and self.isActive and self.armNode ~= nil then
        self.armRotation = (self.armRotation + 0.5 * dt) % (math.pi * 2)
        setRotation(self.armNode, 0, self.armRotation, 0)
    end

    -- Distance poll for proximity interaction (client-only).
    -- Replaces the physics-trigger approach which requires collider shapes in the i3d.
    -- Runs every frame; cost is two getWorldTranslation calls + one distance check.
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