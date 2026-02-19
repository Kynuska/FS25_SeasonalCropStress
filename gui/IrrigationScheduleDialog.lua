-- ============================================================
-- IrrigationScheduleDialog.lua
-- Dialog for editing irrigation system schedule and manual control.
-- ============================================================

IrrigationScheduleDialog = {}
local IrrigationScheduleDialog_mt = Class(IrrigationScheduleDialog, MessageDialog)

function IrrigationScheduleDialog.new(target, customMt)
    local self = MessageDialog.new(target, customMt or IrrigationScheduleDialog_mt)
    self.systemId = nil
    return self
end

function IrrigationScheduleDialog:onCreate()
    -- Find UI elements
    self.titleElement = self:getElement("title")
    self.waterSourceValue = self:getElement("waterSourceValue")
    self.startHourDropdown = self:getElement("startHour")
    self.endHourDropdown = self:getElement("endHour")
    self.flowRateText = self:getElement("flowRate")
    self.efficiencyText = self:getElement("efficiency")
    self.costText = self:getElement("cost")
    self.wearText = self:getElement("wear")
    self.coveredFieldsContainer = self:getElement("coveredFieldsContainer")
    self.btnIrrigateNow = self:getElement("btnIrrigateNow")
    self.btnSave = self:getElement("btnSave")
    self.btnClose = self:getElement("btnClose")
    self.dayButtonsContainer = self:getElement("dayButtonsContainer")

    -- Initialize time dropdowns with hours 0-23
    local hours = {}
    for h = 0, 23 do
        table.insert(hours, string.format("%02d:00", h))
    end
    if self.startHourDropdown then
        self.startHourDropdown:setTexts(hours)
    end
    if self.endHourDropdown then
        self.endHourDropdown:setTexts(hours)
    end
end

function IrrigationScheduleDialog:onDialogOpen(systemId)
    self.systemId = systemId
    local system = self:getCurrentSystem()
    if not system then
        self:onDialogClose()
        return
    end

    -- Set title
    local typeName = system.type == "pivot" and g_i18n:getText("cs_irr_pivot") or g_i18n:getText("cs_irr_drip")
    self.titleElement:setText(string.format(g_i18n:getText("cs_irr_title"), typeName))

    -- Water source status
    if system.waterSourceId then
        self.waterSourceValue:setText(g_i18n:getText("cs_irr_connected"))
    else
        self.waterSourceValue:setText(g_i18n:getText("cs_irr_disconnected"))
    end

    -- Create day buttons (if not already created)
    self:createDayButtons(system)

    -- Set time dropdowns
    if self.startHourDropdown then
        self.startHourDropdown:setState(system.schedule.startHour)
    end
    if self.endHourDropdown then
        self.endHourDropdown:setState(system.schedule.endHour)
    end

    -- Update performance texts
    self:updatePerformance(system)

    -- Populate covered fields list
    self:updateCoveredFields(system)
end

function IrrigationScheduleDialog:createDayButtons(system)
    -- Clear any existing buttons
    self.dayButtonsContainer:removeAllChildren()
    self.dayButtons = {}

    local dayNames = {g_i18n:getText("cs_day_mon"), g_i18n:getText("cs_day_tue"),
                      g_i18n:getText("cs_day_wed"), g_i18n:getText("cs_day_thu"),
                      g_i18n:getText("cs_day_fri"), g_i18n:getText("cs_day_sat"),
                      g_i18n:getText("cs_day_sun")}
    local x = 0
    for i = 1, 7 do
        local bg = Overlay:new("fs25_buttonBg", self.dayButtonsContainer)
        bg:setPosition(x, 0)
        bg:setSize(30, 30)
        bg:setVisible(true)

        local hit = Button:new(self.dayButtonsContainer)
        hit:setProfile("fs25_buttonHit")
        hit:setPosition(x, 0)
        hit:setSize(30, 30)
        hit:setVisible(true)
        hit:setCallback("onClick", function()
            self:onDayToggle(i, not hit:getSelected())
        end)

        local text = Text:new(self.dayButtonsContainer)
        text:setProfile("fs25_buttonText")
        text:setPosition(x + 5, 5)
        text:setText(dayNames[i])
        text:setVisible(true)

        hit:setSelected(system.schedule.activeDays[i])
        table.insert(self.dayButtons, {hit = hit, text = text, bg = bg})
        x = x + 35
    end
end

function IrrigationScheduleDialog:onDayToggle(dayIndex, state)
    local system = self:getCurrentSystem()
    if system then
        system.schedule.activeDays[dayIndex] = state
        self.dayButtons[dayIndex].hit:setSelected(state)
    end
end

function IrrigationScheduleDialog:onStartHourChanged(state)
    local system = self:getCurrentSystem()
    if system then
        system.schedule.startHour = state
    end
end

function IrrigationScheduleDialog:onEndHourChanged(state)
    local system = self:getCurrentSystem()
    if system then
        system.schedule.endHour = state
    end
end

function IrrigationScheduleDialog:updatePerformance(system)
    local effectiveRate = system.flowRatePerHour * system.pressureMultiplier * (1.0 - system.wearLevel * 0.3)
    local efficiency = math.floor(system.pressureMultiplier * 100)
    self.flowRateText:setText(string.format("Flow Rate: %.3f/hr", effectiveRate))
    self.efficiencyText:setText(string.format("Efficiency: %d%%", efficiency))
    self.costText:setText(string.format("Est. Cost: $%d/hr", system.operationalCostPerHour))
    self.wearText:setText(string.format("Wear Level: %d%%", math.floor(system.wearLevel * 100)))
end

function IrrigationScheduleDialog:updateCoveredFields(system)
    self.coveredFieldsContainer:removeAllChildren()
    local y = 0
    for _, fieldId in ipairs(system.coveredFields) do
        local moisture = g_cropStressManager.soilSystem:getMoisture(fieldId) or 0
        local stress = g_cropStressManager.stressModifier:getStress(fieldId) or 0
        local cropName = self:getCropName(fieldId)
        local text = string.format("Field %d · %s  %d%%", fieldId, cropName, math.floor(moisture * 100))
        if stress > 0.2 then
            text = text .. " ⚠"
        end
        local label = Text:new(self.coveredFieldsContainer)
        label:setProfile("fs25_dialogText")
        label:setPosition(5, y)
        label:setText(text)
        y = y - 20
    end
end

function IrrigationScheduleDialog:getCropName(fieldId)
    -- Simplified: try to get from field object
    if g_currentMission and g_currentMission.fieldManager then
        local field = g_currentMission.fieldManager:getFieldByIndex(fieldId)
        if field then
            local ft = field:getFruitType()
            if ft and ft.name then
                return ft.name:sub(1,1):upper() .. ft.name:sub(2):lower()
            end
        end
    end
    return "?"
end

function IrrigationScheduleDialog:onIrrigateNow()
    local system = self:getCurrentSystem()
    if system and not system.isActive then
        g_cropStressManager.irrigationManager:activateSystem(self.systemId)
        g_currentMission:showBlinkingWarning("Irrigation started", 3000)
    end
    self:onDialogClose()
end

function IrrigationScheduleDialog:onSaveSchedule()
    -- Schedule is already live in IrrigationManager; it persists on the next game save.
    g_currentMission:showBlinkingWarning("Schedule saved", 2000)
    self:onDialogClose()
end

function IrrigationScheduleDialog:getCurrentSystem()
    return g_cropStressManager and g_cropStressManager.irrigationManager and
           g_cropStressManager.irrigationManager.systems[self.systemId]
end

function IrrigationScheduleDialog:onDialogClose()
    self:close()
end