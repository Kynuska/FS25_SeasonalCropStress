-- ============================================================
-- CropConsultantDialog.lua
-- Agronomist consultation panel.
--
-- Pattern: CsDialogLoader / NPCFavor confirmed pattern (FS25 v1.16)
--   • CsDialogLoader creates instance + calls g_gui:loadGui()
--   • onCreate() ONLY calls superClass().onCreate(self) in pcall
--     → FS25 auto-wires all elements by id into self.*
--   • onOpen() calls superClass().onOpen(self) then calls refreshContent()
--   • onClose() calls superClass().onClose(self) for cleanup
--
-- Auto-wired element names (must match id= in CropConsultantDialog.xml):
--   self.titleText, self.subtitleText
--   self.npcSection, self.npcRelLabel, self.npcRelValue
--   self.fieldListContainer, self.recommendText
--
-- Opened via CS_OPEN_CONSULTANT (Shift+C) or from Crop Consultant NPC
-- (FS25_NPCFavor integration). Reads live field/stress/moisture data on open.
-- ============================================================

CropConsultantDialog = {}
local CropConsultantDialog_mt = Class(CropConsultantDialog, MessageDialog)

-- ============================================================
-- CONSTRUCTOR
-- ============================================================

function CropConsultantDialog.new(target, customMt)
    local self = MessageDialog.new(target, customMt or CropConsultantDialog_mt)
    return self
end

-- ============================================================
-- LIFECYCLE
-- ============================================================

-- Called by FS25 GUI system after XML is parsed (via g_gui:loadGui).
-- ONLY calls superClass().onCreate(self) — triggers FS25 auto-wiring of
-- all XML elements with id= attributes into self.*.
function CropConsultantDialog:onCreate()
    local ok, err = pcall(function()
        CropConsultantDialog:superClass().onCreate(self)
    end)
    if not ok then
        print("[CropStress] CropConsultantDialog:onCreate() superClass FAILED: " .. tostring(err))
    end
end

-- Called by FS25 GUI system each time the dialog becomes visible.
-- superClass().onOpen() registers focus/input handling (Escape key, etc.).
function CropConsultantDialog:onOpen()
    local ok, err = pcall(function()
        CropConsultantDialog:superClass().onOpen(self)
    end)
    if not ok then
        print("[CropStress] CropConsultantDialog:onOpen() superClass FAILED: " .. tostring(err))
        return
    end
    self:refreshContent()
end

-- Called by FS25 GUI system after the dialog has fully closed (cleanup only).
-- XML onClose="onClose" points here. Do NOT call self:close() from here.
function CropConsultantDialog:onClose()
    CropConsultantDialog:superClass().onClose(self)
end

-- Initiated by close button — triggers the FS25 close sequence.
function CropConsultantDialog:onCloseClicked()
    self:close()
end

-- ============================================================
-- REFRESH CONTENT
-- Rebuilds the field risk list, recommendations, and optional NPC panel.
-- ============================================================

function CropConsultantDialog:refreshContent()
    if g_cropStressManager == nil then return end

    -- Title
    if self.titleText ~= nil then
        local name = (g_i18n ~= nil and g_i18n:getText("cs_consultant_name")) or "Crop Consultant"
        self.titleText:setText(name)
    end

    -- NPC section (only when FS25_NPCFavor is active and NPC registered)
    if self.npcSection ~= nil then
        local npcActive = g_cropStressManager.npcIntegration ~= nil
            and g_cropStressManager.npcIntegration.isRegistered
        self.npcSection:setVisible(npcActive)

        if npcActive and self.npcRelValue ~= nil then
            local rel = g_cropStressManager.npcIntegration:getRelationshipLevel()
            self.npcRelValue:setText(string.format("%d / 100", rel))
        end
    end

    self:buildFieldList()
    self:buildRecommendation()
end

-- ============================================================
-- BUILD FIELD LIST
-- Populates fieldListContainer with up to 5 fields sorted by risk.
-- ============================================================

function CropConsultantDialog:buildFieldList()
    if self.fieldListContainer == nil then return end

    -- Clear existing dynamic children
    local children = self.fieldListContainer.elements
    if children ~= nil then
        for i = #children, 1, -1 do
            self.fieldListContainer:removeElement(children[i])
        end
    end

    local soilSystem     = g_cropStressManager.soilSystem
    local stressModifier = g_cropStressManager.stressModifier
    if soilSystem == nil or soilSystem.fieldData == nil then return end

    -- Build risk score list: stress * 0.6 + (1 - moisture) * 0.4
    local riskList = {}
    for fieldId, data in pairs(soilSystem.fieldData) do
        local stress   = stressModifier ~= nil and stressModifier:getStress(fieldId) or 0
        local moisture = data.moisture or 0.5
        local risk     = stress * 0.6 + (1 - moisture) * 0.4
        table.insert(riskList, { fieldId = fieldId, moisture = moisture, stress = stress, risk = risk })
    end
    table.sort(riskList, function(a, b) return a.risk > b.risk end)

    local function addRow(text, yPos)
        local label = TextElement.new()
        if g_gui ~= nil then
            local prof = g_gui:getProfile("fs25_dialogText")
            if prof ~= nil then label:loadProfile(prof, true) end
        end
        label:setPosition(5, yPos)
        label:setText(text)
        self.fieldListContainer:addElement(label)
        label:onGuiSetupFinished()
    end

    if #riskList == 0 then
        addRow((g_i18n ~= nil and g_i18n:getText("cs_consultant_no_data")) or "No field data available.", 0)
        return
    end

    local y = 0
    for i = 1, math.min(5, #riskList) do
        local entry = riskList[i]
        local cropName    = self:getCropName(entry.fieldId)
        local yieldImpact = stressModifier ~= nil and stressModifier:getYieldImpactString(entry.fieldId) or "0%"

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
            entry.fieldId, cropName,
            math.floor(entry.moisture * 100),
            yieldImpact, severityStr
        )
        addRow(labelStr, y)
        y = y - 22
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

    -- Find the highest-risk (lowest moisture) field
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
                (proj[1] or 0) * 100, (proj[2] or 0) * 100, (proj[3] or 0) * 100))
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
    -- Delegate to CropStressManager which uses CsDialogLoader
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
    local ft = type(field.getFruitType) == "function" and field:getFruitType() or field.fruitType
    if ft ~= nil and ft.name ~= nil then
        return ft.name:sub(1,1):upper() .. ft.name:sub(2):lower()
    end
    return "?"
end
