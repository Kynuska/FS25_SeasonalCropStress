-- ============================================================
-- IrrigationScheduleDialog.lua
-- Dialog for editing irrigation system schedule and manual control.
-- ============================================================

IrrigationScheduleDialog = {}
local IrrigationScheduleDialog_mt = Class(IrrigationScheduleDialog, MessageDialog)

function IrrigationScheduleDialog.new(target, customMt)
    -- Called by g_gui:loadGui() with no arguments — target and customMt will both be nil.
    -- Base class MUST be MessageDialog (not the deprecated DialogElement) so that
    -- focusElement is properly initialised during XML wiring and FocusManager:update()
    -- does not crash with "attempt to index nil with 'focusElement'" on the first frame.
    local self = MessageDialog.new(target, customMt or IrrigationScheduleDialog_mt)
    self.systemId    = nil
    self.daySelected = {false, false, false, false, false, false, false}
    return self
end

function IrrigationScheduleDialog:onCreate()
    -- FS25: elements wired by name via getDescendantByName()
    self.titleElement          = self:getDescendantByName("title")
    self.waterSourceValue      = self:getDescendantByName("waterSourceValue")
    self.startHourDropdown     = self:getDescendantByName("startHour")
    self.endHourDropdown       = self:getDescendantByName("endHour")
    self.flowRateText          = self:getDescendantByName("flowRate")
    self.efficiencyText        = self:getDescendantByName("efficiency")
    self.costText              = self:getDescendantByName("cost")
    self.wearText              = self:getDescendantByName("wear")
    self.coveredFieldsContainer = self:getDescendantByName("coveredFieldsContainer")
    self.btnIrrigateNow        = self:getDescendantByName("btnIrrigateNow")
    self.btnSave               = self:getDescendantByName("btnSave")
    self.btnClose              = self:getDescendantByName("btnClose")
    self.dayButtonsContainer   = self:getDescendantByName("dayButtonsContainer")

    -- Day toggle buttons looked up by name (declared in XML as btn_day_1 .. btn_day_7)
    self.dayButtons = {}
    for i = 1, 7 do
        local btn = self:getDescendantByName("btn_day_" .. i)
        if btn ~= nil then
            self.dayButtons[i] = btn
        end
    end

    -- Initialize time dropdowns with hours 0-23
    local hours = {}
    for h = 0, 23 do
        table.insert(hours, string.format("%02d:00", h))
    end
    if self.startHourDropdown ~= nil then
        self.startHourDropdown:setTexts(hours)
    end
    if self.endHourDropdown ~= nil then
        self.endHourDropdown:setTexts(hours)
    end
end

function IrrigationScheduleDialog:onIrrigationDialogOpen(systemId)
    self.systemId = systemId
    local system = self:getCurrentSystem()
    if system == nil then
        self:onIrrigationDialogClose()
        return
    end

    -- Set title
    local typeName = system.type == "pivot" and g_i18n:getText("cs_irr_pivot") or g_i18n:getText("cs_irr_drip")
    if self.titleElement ~= nil then
        self.titleElement:setText(string.format(g_i18n:getText("cs_irr_title"), typeName))
    end

    -- Water source status
    if self.waterSourceValue ~= nil then
        if system.waterSourceId ~= nil then
            self.waterSourceValue:setText(g_i18n:getText("cs_irr_connected"))
        else
            self.waterSourceValue:setText(g_i18n:getText("cs_irr_disconnected"))
        end
    end

    -- Sync day button visual state from schedule
    self:syncDayButtons(system)

    -- Set time dropdowns (setState takes index + silent flag)
    if self.startHourDropdown ~= nil then
        self.startHourDropdown:setState(system.schedule.startHour, true)
    end
    if self.endHourDropdown ~= nil then
        self.endHourDropdown:setState(system.schedule.endHour, true)
    end

    -- Update performance texts
    self:updatePerformance(system)

    -- Populate covered fields list
    self:updateCoveredFields(system)
end

-- Sync day button selected state from system schedule (no Button.getSelected needed)
function IrrigationScheduleDialog:syncDayButtons(system)
    for i = 1, 7 do
        self.daySelected[i] = system.schedule.activeDays[i] == true
        if self.dayButtons[i] ~= nil then
            self.dayButtons[i]:setSelected(self.daySelected[i])
        end
    end
end

-- Called from XML onClick on each day button.
-- FS25 GUI XML onClick does not support passing arguments inline, so each
-- day button binds its own numbered wrapper that forwards to the shared impl.
function IrrigationScheduleDialog:onDayToggle1() self:_toggleDay(1) end
function IrrigationScheduleDialog:onDayToggle2() self:_toggleDay(2) end
function IrrigationScheduleDialog:onDayToggle3() self:_toggleDay(3) end
function IrrigationScheduleDialog:onDayToggle4() self:_toggleDay(4) end
function IrrigationScheduleDialog:onDayToggle5() self:_toggleDay(5) end
function IrrigationScheduleDialog:onDayToggle6() self:_toggleDay(6) end
function IrrigationScheduleDialog:onDayToggle7() self:_toggleDay(7) end

function IrrigationScheduleDialog:_toggleDay(idx)
    if idx == nil or idx < 1 or idx > 7 then return end

    local system = self:getCurrentSystem()
    if system == nil then return end

    self.daySelected[idx] = not self.daySelected[idx]
    system.schedule.activeDays[idx] = self.daySelected[idx]

    if self.dayButtons[idx] ~= nil then
        self.dayButtons[idx]:setSelected(self.daySelected[idx])
    end
end

function IrrigationScheduleDialog:onStartHourChanged(state)
    local system = self:getCurrentSystem()
    if system ~= nil then
        system.schedule.startHour = state
    end
end

function IrrigationScheduleDialog:onEndHourChanged(state)
    local system = self:getCurrentSystem()
    if system ~= nil then
        system.schedule.endHour = state
    end
end

function IrrigationScheduleDialog:updatePerformance(system)
    local effectiveRate = system.flowRatePerHour * system.pressureMultiplier * (1.0 - system.wearLevel * 0.3)
    local efficiency    = math.floor(system.pressureMultiplier * 100)
    if self.flowRateText  ~= nil then self.flowRateText:setText(string.format("Flow Rate: %.3f/hr", effectiveRate)) end
    if self.efficiencyText ~= nil then self.efficiencyText:setText(string.format("Efficiency: %d%%", efficiency)) end
    if self.costText      ~= nil then self.costText:setText(string.format("Est. Cost: $%d/hr", system.operationalCostPerHour)) end
    if self.wearText      ~= nil then self.wearText:setText(string.format("Wear Level: %d%%", math.floor(system.wearLevel * 100))) end
end

function IrrigationScheduleDialog:updateCoveredFields(system)
    -- Remove existing dynamic children
    if self.coveredFieldsContainer ~= nil then
        local children = self.coveredFieldsContainer.elements
        if children ~= nil then
            for i = #children, 1, -1 do
                self.coveredFieldsContainer:removeElement(children[i])
            end
        end
    end

    if self.coveredFieldsContainer == nil then return end

    local y = 0
    for _, fieldId in ipairs(system.coveredFields) do
        local moisture = 0
        local stress   = 0
        if g_cropStressManager ~= nil then
            if g_cropStressManager.soilSystem   ~= nil then moisture = g_cropStressManager.soilSystem:getMoisture(fieldId) or 0 end
            if g_cropStressManager.stressModifier ~= nil then stress = g_cropStressManager.stressModifier:getStress(fieldId) or 0 end
        end

        local cropName = self:getCropName(fieldId)
        local labelStr = string.format("Field %d · %s  %d%%", fieldId, cropName, math.floor(moisture * 100))
        if stress > 0.2 then
            labelStr = labelStr .. " !"  -- unicode warning char can be unreliable in FS25 font atlas
        end

        local label = GuiElement.new(self.coveredFieldsContainer)
        label:setProfile("fs25_dialogText")
        label:setPosition(5, y)
        label:setText(labelStr)
        self.coveredFieldsContainer:addElement(label)
        y = y - 20
    end
end

function IrrigationScheduleDialog:getCropName(fieldId)
    if g_currentMission ~= nil and g_currentMission.fieldManager ~= nil then
        local field = nil
        if g_currentMission.fieldManager.getFieldByIndex ~= nil then
            field = g_currentMission.fieldManager:getFieldByIndex(fieldId)
        end
        if field ~= nil then
            local ft = nil
            if type(field.getFruitType) == "function" then
                ft = field:getFruitType()
            elseif field.fruitType ~= nil then
                ft = field.fruitType
            end
            if ft ~= nil and ft.name ~= nil then
                return ft.name:sub(1,1):upper() .. ft.name:sub(2):lower()
            end
        end
    end
    return "?"
end

function IrrigationScheduleDialog:onIrrigateNow()
    local system = self:getCurrentSystem()
    if system ~= nil and not system.isActive then
        if g_cropStressManager ~= nil and g_cropStressManager.irrigationManager ~= nil then
            g_cropStressManager.irrigationManager:activateSystem(self.systemId)
        end
        if g_currentMission ~= nil then
            g_currentMission:showBlinkingWarning(g_i18n:getText("cs_irr_started"), 3000)
        end
    end
    self:onIrrigationDialogClose()
end

function IrrigationScheduleDialog:onSaveSchedule()
    -- Schedule is already live in IrrigationManager; it persists on the next game save.
    if g_currentMission ~= nil then
        g_currentMission:showBlinkingWarning(g_i18n:getText("cs_schedule_saved"), 2000)
    end
    self:onIrrigationDialogClose()
end

function IrrigationScheduleDialog:getCurrentSystem()
    if g_cropStressManager == nil then return nil end
    if g_cropStressManager.irrigationManager == nil then return nil end
    return g_cropStressManager.irrigationManager.systems[self.systemId]
end

function IrrigationScheduleDialog:onIrrigationDialogClose()
    g_gui:closeDialog(self)
end