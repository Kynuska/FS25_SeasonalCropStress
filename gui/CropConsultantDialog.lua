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
-- Extends MessageDialog (NOT the deprecated DialogElement — see CLAUDE.md).
-- onOpen IS used as the FS25 lifecycle hook (calls superClass().onOpen for focus/input init).
-- Close buttons call self:close() to initiate the close sequence; the XML onClose attribute
-- points to onConsultantDialogClose() which is cleanup-only (do NOT call close() inside it).
-- ============================================================

CropConsultantDialog = {}
local CropConsultantDialog_mt = Class(CropConsultantDialog, MessageDialog)

-- ============================================================
-- CONSTRUCTOR
-- ============================================================
function CropConsultantDialog.new(target, customMt)
    -- Called by g_gui:loadGui() with no arguments — target and customMt will both be nil.
    -- Base class MUST be MessageDialog (not the deprecated DialogElement) so that
    -- focusElement is properly initialised during XML wiring and FocusManager:update()
    -- does not crash with "attempt to index nil with 'focusElement'" on the first frame.
    local self = MessageDialog.new(target, customMt or CropConsultantDialog_mt)
    return self
end

-- ============================================================
-- onOpen — called by FS25 GUI system when dialog becomes visible.
-- MUST call superClass().onOpen() to register focus/input handling.
-- ============================================================
function CropConsultantDialog:onOpen()
    CropConsultantDialog:superClass().onOpen(self)
end

-- Initiated by close buttons — triggers the close sequence.
function CropConsultantDialog:onCloseClicked()
    self:close()
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

    -- Recommendation text (populated by buildRecommendation)
    self.recommendText     = self:getDescendantByName("recommendText")

    -- Note: btnClose and btnOpenIrr are handled via XML onClick — no Lua ref needed

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

        -- TextElement is the correct FS25 class for dynamic text inside a dialog.
        -- GuiElement.new() does not expose setText() and setProfile() is not standard.
        local label = TextElement.new()
        if g_gui ~= nil then
            local prof = g_gui:getProfile("fs25_dialogText")
            if prof ~= nil then
                label:loadProfile(prof, true)
            end
        end
        label:setPosition(5, y)
        label:setText(labelStr)
        self.fieldContainer:addElement(label)
        label:onGuiSetupFinished()
        y = y - 22
    end

    if #riskList == 0 then
        local noData = TextElement.new()
        if g_gui ~= nil then
            local prof = g_gui:getProfile("fs25_dialogText")
            if prof ~= nil then
                noData:loadProfile(prof, true)
            end
        end
        noData:setPosition(5, 0)
        noData:setText((g_i18n ~= nil and g_i18n:getText("cs_consultant_no_data")) or "No field data available.")
        self.fieldContainer:addElement(noData)
        noData:onGuiSetupFinished()
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

    local function t(key, ...) return (g_i18n ~= nil and string.format(g_i18n:getText(key), ...)) or key end

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
        self.recommendText:setText(t("cs_rec_all_healthy"))
        return
    end

    -- Generate a localized recommendation string
    local lines = {}

    if worst.moisture < 0.25 then
        table.insert(lines, t("cs_rec_urgent",  worst.fieldId, worst.moisture * 100))
    elseif worst.moisture < 0.40 then
        table.insert(lines, t("cs_rec_warning", worst.fieldId, worst.moisture * 100))
    else
        table.insert(lines, t("cs_rec_ok"))
    end

    -- 3-day forecast hint for worst field
    if weatherInteg ~= nil then
        local proj = weatherInteg:getMoistureForecast(worst.fieldId, 3)
        if proj ~= nil and #proj >= 3 then
            table.insert(lines, t("cs_rec_forecast",
                (proj[1] or 0) * 100,
                (proj[2] or 0) * 100,
                (proj[3] or 0) * 100))
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
            table.insert(lines, t("cs_rec_systems_running", active))
        else
            table.insert(lines, t("cs_rec_no_systems"))
        end
    end

    self.recommendText:setText(table.concat(lines, "\n"))
end

-- ============================================================
-- BUTTON HANDLERS
-- ============================================================
function CropConsultantDialog:onOpenIrrigationDialog()
    self:close()
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
    -- Fallback: iterate all fields (needed on maps where getFieldByIndex returns nil)
    if field == nil then
        local fields = g_currentMission.fieldManager:getFields()
        for _, f in pairs(fields) do
            if f.fieldId == fieldId then field = f; break end
        end
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
-- Called by FS25 GUI system AFTER the dialog has been closed (cleanup only).
-- Do NOT call self:close() or g_gui:closeDialog() here.
-- ============================================================
function CropConsultantDialog:onConsultantDialogClose()
    CropConsultantDialog:superClass().onClose(self)
end