-- ============================================================
-- CropConsultantDialog.lua
-- Phase 3 implementation.
--
-- Opened via CS_OPEN_CONSULTANT (Shift+C) or from the Crop Consultant
-- NPC if FS25_NPCFavor is active.
--
-- Standalone mode:
--   Shows agronomist report: top 5 fields by risk, current alerts,
--   recommended irrigation schedule for the next 3 days.
--
-- NPCFavor mode:
--   Also shows relationship level with Alex Chen and available favors.
--
-- Extends DialogElement per CLAUDE.md guidance.
-- NEVER name callbacks onClose/onOpen — they conflict with FS25 lifecycle.
-- ============================================================

CropConsultantDialog = {}
local CropConsultantDialog_mt = Class(CropConsultantDialog, DialogElement)

-- ============================================================
-- CONSTRUCTOR
-- ============================================================
function CropConsultantDialog.new(target, customMt)
    local self = DialogElement.new(target, customMt or CropConsultantDialog_mt)
    self.lastRefreshTime = 0
    return self
end

-- ============================================================
-- onCreate — wire up elements by ID
-- Called by FS25 GUI system after XML is parsed.
-- ============================================================
function CropConsultantDialog:onCreate()
    -- Header
    self.titleElement      = self:getDescendantByName("titleText")
    self.subtitleElement   = self:getDescendantByName("subtitleText")

    -- NPC relationship bar (hidden when NPCFavor not active)
    self.npcSection        = self:getDescendantByName("npcSection")
    self.npcRelLabel       = self:getDescendantByName("npcRelLabel")
    self.npcRelValue       = self:getDescendantByName("npcRelValue")

    -- Field list container (dynamic rows added in Lua)
    self.fieldContainer    = self:getDescendantByName("fieldListContainer")

    -- Forecast / recommendation section
    self.recommendTitle    = self:getDescendantByName("recommendTitle")
    self.recommendText     = self:getDescendantByName("recommendText")

    -- Buttons
    self.btnClose          = self:getDescendantByName("btnClose")
    self.btnOpenIrr        = self:getDescendantByName("btnOpenIrr")

    -- Hide NPC section by default (shown only if NPCFavor active)
    if self.npcSection ~= nil then
        self.npcSection:setVisible(false)
    end
end

-- ============================================================
-- onConsultantDialogOpen — called from main.lua action handler
-- ============================================================
function CropConsultantDialog:onConsultantDialogOpen()
    self:refreshContent()
end

-- ============================================================
-- REFRESH CONTENT
-- Rebuilds the field list, recommendations, and optional NPC panel.
-- ============================================================
function CropConsultantDialog:refreshContent()
    if g_cropStressManager == nil then return end

    -- Update title
    if self.titleElement ~= nil then
        local name = (g_i18n ~= nil and g_i18n:getText("cs_consultant_name")) or "Crop Consultant"
        self.titleElement:setText(name)
    end

    -- NPC section (only when NPCFavor active and NPC registered)
    if self.npcSection ~= nil then
        local npcActive = g_cropStressManager.npcIntegration ~= nil
            and g_cropStressManager.npcIntegration.isRegistered
        self.npcSection:setVisible(npcActive)

        if npcActive and self.npcRelValue ~= nil then
            local rel = g_cropStressManager.npcIntegration:getRelationshipLevel()
            self.npcRelValue:setText(string.format("%d / 100", rel))
        end
    end

    -- Build field list
    self:buildFieldList()

    -- Build recommendation text
    self:buildRecommendation()
end

-- ============================================================
-- BUILD FIELD LIST
-- Populates fieldContainer with up to 5 fields sorted by risk.
-- ============================================================
function CropConsultantDialog:buildFieldList()
    if self.fieldContainer == nil then return end

    -- Clear existing dynamic children
    local children = self.fieldContainer.elements
    if children ~= nil then
        for i = #children, 1, -1 do
            self.fieldContainer:removeElement(children[i])
        end
    end

    local soilSystem     = g_cropStressManager.soilSystem
    local stressModifier = g_cropStressManager.stressModifier
    if soilSystem == nil or soilSystem.fieldData == nil then return end

    -- Build risk score list: stress * 0.6 + (1-moisture) * 0.4
    local riskList = {}
    for fieldId, data in pairs(soilSystem.fieldData) do
        local stress   = stressModifier ~= nil and stressModifier:getStress(fieldId) or 0
        local moisture = data.moisture or 0.5
        local risk     = stress * 0.6 + (1 - moisture) * 0.4
        table.insert(riskList, { fieldId = fieldId, moisture = moisture, stress = stress, risk = risk })
    end
    table.sort(riskList, function(a, b) return a.risk > b.risk end)

    local y = 0
    for i = 1, math.min(5, #riskList) do
        local entry = riskList[i]

        local cropName = self:getCropName(entry.fieldId)
        local yieldImpact = stressModifier ~= nil
            and stressModifier:getYieldImpactString(entry.fieldId)
            or "0%"

        -- Severity label
        local severityStr
        if entry.moisture < 0.25 then
            severityStr = "[CRITICAL]"
        elseif entry.moisture < 0.40 then
            severityStr = "[WARNING]"
        else
            severityStr = "[OK]"
        end

        local labelStr = string.format(
            "Field %d · %s  %d%% moisture  Yield %s  %s",
            entry.fieldId,
            cropName,
            math.floor(entry.moisture * 100),
            yieldImpact,
            severityStr
        )

        local label = GuiElement.new(self.fieldContainer)
        label:setProfile("fs25_dialogText")
        label:setPosition(5, y)
        label:setText(labelStr)
        self.fieldContainer:addElement(label)
        y = y - 22
    end

    if #riskList == 0 then
        local noData = GuiElement.new(self.fieldContainer)
        noData:setProfile("fs25_dialogText")
        noData:setPosition(5, 0)
        noData:setText((g_i18n ~= nil and g_i18n:getText("cs_consultant_no_data")) or "No field data available.")
        self.fieldContainer:addElement(noData)
    end
end

-- ============================================================
-- BUILD RECOMMENDATION
-- Uses weather forecast + field state to suggest actions.
-- ============================================================
function CropConsultantDialog:buildRecommendation()
    if self.recommendText == nil then return end

    local soilSystem   = g_cropStressManager and g_cropStressManager.soilSystem
    local weatherInteg = g_cropStressManager and g_cropStressManager.weatherIntegration

    if soilSystem == nil or soilSystem.fieldData == nil then
        self.recommendText:setText("—")
        return
    end

    -- Find the highest-risk field
    local worst = nil
    for fieldId, data in pairs(soilSystem.fieldData) do
        if worst == nil or data.moisture < worst.moisture then
            worst = { fieldId = fieldId, moisture = data.moisture }
        end
    end

    if worst == nil then
        self.recommendText:setText("All fields appear healthy.")
        return
    end

    -- Generate a simple recommendation string
    local lines = {}

    if worst.moisture < 0.25 then
        table.insert(lines, string.format(
            "URGENT: Field %d at %.0f%% moisture — irrigate immediately!",
            worst.fieldId, worst.moisture * 100))
    elseif worst.moisture < 0.40 then
        table.insert(lines, string.format(
            "Field %d at %.0f%% moisture — irrigation recommended within 24h.",
            worst.fieldId, worst.moisture * 100))
    else
        table.insert(lines, "All fields within acceptable moisture range.")
    end

    -- 3-day forecast hint for worst field
    if weatherInteg ~= nil then
        local proj = weatherInteg:getMoistureForecast(worst.fieldId, 3)
        if proj ~= nil and #proj >= 3 then
            table.insert(lines, string.format(
                "Forecast: Day+1 %.0f%%  Day+2 %.0f%%  Day+3 %.0f%%",
                (proj[1] or 0) * 100,
                (proj[2] or 0) * 100,
                (proj[3] or 0) * 100
            ))
        end
    end

    -- Irrigation status hint
    local irrMgr = g_cropStressManager.irrigationManager
    if irrMgr ~= nil then
        local active = 0
        for _, sys in pairs(irrMgr.systems) do
            if sys.isActive then active = active + 1 end
        end
        if active > 0 then
            table.insert(lines, string.format("%d irrigation system(s) currently running.", active))
        else
            table.insert(lines, "No irrigation systems are currently active.")
        end
    end

    self.recommendText:setText(table.concat(lines, "\n"))
end

-- ============================================================
-- BUTTON HANDLERS
-- ============================================================
function CropConsultantDialog:onOpenIrrigationDialog()
    self:onConsultantDialogClose()
    -- Let CropStressManager open the irrigation dialog
    if g_cropStressManager ~= nil then
        g_cropStressManager:onOpenIrrigationDialog()
    end
end

-- ============================================================
-- HELPERS
-- ============================================================
function CropConsultantDialog:getCropName(fieldId)
    if g_currentMission == nil or g_currentMission.fieldManager == nil then return "?" end
    local field = nil
    if g_currentMission.fieldManager.getFieldByIndex ~= nil then
        field = g_currentMission.fieldManager:getFieldByIndex(fieldId)
    end
    if field == nil then return "?" end
    local ft = type(field.getFruitType) == "function"
        and field:getFruitType()
        or field.fruitType
    if ft ~= nil and ft.name ~= nil then
        return ft.name:sub(1,1):upper() .. ft.name:sub(2):lower()
    end
    return "?"
end

-- ============================================================
-- CLOSE
-- ============================================================
function CropConsultantDialog:onConsultantDialogClose()
    g_gui:closeDialog(self)
end