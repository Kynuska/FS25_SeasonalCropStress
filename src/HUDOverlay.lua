-- ============================================================
-- HUDOverlay.lua
-- Renders the field moisture panel in the lower-left corner of
-- the screen using FS25's immediate-mode render functions.
--
-- Phase 1: Direct draw rendering (no XML dialog — simple and reliable)
-- Phase 2+: Upgrade to a proper GuiElement / XML dialog for better theming
--
-- Layout (bottom-left, above minimap):
-- ┌────────────────────────────────────────────┐
-- │  CROP MOISTURE MONITOR              [M]    │
-- │                                            │
-- │  Field 7 · Wheat (Stage 4)    ██████░░ 78%│
-- │  Field 3 · Corn  (Stage 5) ⚠  ███░░░░░ 32%│
-- │  Field 5 · Corn  (Stage 3)    ████████ 80%│
-- └────────────────────────────────────────────┘
--
-- HUD coordinates are normalized: 0.0–1.0 (bottom-left origin).
-- Y=0 is BOTTOM of screen. Text and rect calls use this space.
-- ============================================================

HUDOverlay = {}
HUDOverlay.__index = HUDOverlay

-- Panel layout constants (normalized screen coordinates)
HUDOverlay.PANEL_X         = 0.010   -- left edge
HUDOverlay.PANEL_Y         = 0.175   -- bottom edge of panel
HUDOverlay.PANEL_W         = 0.220   -- panel width
HUDOverlay.ROW_H           = 0.024   -- height per field row
HUDOverlay.HEADER_H        = 0.028   -- header row height
HUDOverlay.PADDING         = 0.004
HUDOverlay.BAR_W           = 0.080   -- moisture bar width
HUDOverlay.BAR_H           = 0.012
HUDOverlay.TEXT_SIZE        = 0.013
HUDOverlay.HEADER_TEXT_SIZE = 0.014
HUDOverlay.MAX_FIELDS       = 6      -- max rows shown

-- Colors (r, g, b, a)
HUDOverlay.COLOR_BG         = {0.05, 0.05, 0.05, 0.78}
HUDOverlay.COLOR_HEADER_BG  = {0.10, 0.10, 0.10, 0.85}
HUDOverlay.COLOR_TEXT        = {0.90, 0.90, 0.90, 1.00}
HUDOverlay.COLOR_HEADER_TEXT = {1.00, 1.00, 1.00, 1.00}
HUDOverlay.COLOR_BAR_BG     = {0.20, 0.20, 0.20, 0.80}
HUDOverlay.COLOR_HEALTHY    = {0.20, 0.75, 0.20, 1.00}  -- green  >60%
HUDOverlay.COLOR_WARNING    = {0.85, 0.70, 0.10, 1.00}  -- yellow 30-60%
HUDOverlay.COLOR_CRITICAL   = {0.85, 0.20, 0.10, 1.00}  -- red    <30%
HUDOverlay.COLOR_STRESS_IND = {0.90, 0.35, 0.10, 1.00}  -- orange stress indicator

-- First-run auto-show: show panel automatically when a field first hits warning
HUDOverlay.FIRST_RUN_MOISTURE_TRIGGER = 0.50

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

function HUDOverlay.new(manager)
    local self = setmetatable({}, HUDOverlay)
    self.manager = manager
    self.isVisible = false
    self.firstRunShown = false

    -- List of {fieldId, moisture, stress, cropName, growthStage} for current frame
    self.displayRows = {}

    -- Auto-show state
    self.autoShowActive = false
    self.autoHideTimer  = 0   -- countdown in seconds (real time); 0 = don't auto-hide

    self.isInitialized = false
    return self
end

function HUDOverlay:initialize()
    -- Subscribe to events via CropEventBus
    if self.manager ~= nil and self.manager.eventBus ~= nil then
        self.manager.eventBus.subscribe("CS_MOISTURE_UPDATED",   self.onMoistureUpdated,   self)
        self.manager.eventBus.subscribe("CS_CRITICAL_THRESHOLD", self.onCriticalThreshold, self)
    end

    self.isInitialized = true
    csLog("HUDOverlay initialized")
end

-- Called per frame by CropStressManager:update()
function HUDOverlay:update(dt)
    if not self.isInitialized then return end

    -- Auto-hide countdown (real seconds)
    if self.autoHideTimer > 0 then
        self.autoHideTimer = self.autoHideTimer - dt
        if self.autoHideTimer <= 0 then
            self.autoHideTimer = 0
            -- Only auto-hide if user hasn't manually shown it
            if self.autoShowActive then
                self.autoShowActive = false
                self.isVisible = false
            end
        end
    end

    -- Rebuild display rows each frame from current system state
    self:rebuildDisplayRows()
end

-- Called per frame draw by CropStressManager:draw()
function HUDOverlay:draw()
    if not self.isInitialized or not self.isVisible then return end
    if g_currentMission == nil then return end

    local numRows = math.min(#self.displayRows, HUDOverlay.MAX_FIELDS)
    if numRows == 0 then return end

    local panelH = HUDOverlay.HEADER_H
        + (numRows * HUDOverlay.ROW_H)
        + HUDOverlay.PADDING * 2

    local px = HUDOverlay.PANEL_X
    local py = HUDOverlay.PANEL_Y

    -- Background panel
    setTextColor(unpack(HUDOverlay.COLOR_BG))
    drawFilledRect(px, py, HUDOverlay.PANEL_W, panelH)

    -- Header bar
    setTextColor(unpack(HUDOverlay.COLOR_HEADER_BG))
    drawFilledRect(px, py + panelH - HUDOverlay.HEADER_H, HUDOverlay.PANEL_W, HUDOverlay.HEADER_H)

    -- Header text
    setTextColor(unpack(HUDOverlay.COLOR_HEADER_TEXT))
    setTextBold(true)
    renderText(
        px + HUDOverlay.PADDING,
        py + panelH - HUDOverlay.HEADER_H + HUDOverlay.PADDING,
        HUDOverlay.HEADER_TEXT_SIZE,
        g_i18n:getText("cs_hud_title") or "CROP MOISTURE"
    )
    -- Key hint on the right
    renderText(
        px + HUDOverlay.PANEL_W - 0.030,
        py + panelH - HUDOverlay.HEADER_H + HUDOverlay.PADDING,
        HUDOverlay.TEXT_SIZE,
        "[M]"
    )
    setTextBold(false)

    -- Field rows (lowest moisture first)
    for i = 1, numRows do
        local row = self.displayRows[i]
        local rowY = py + panelH - HUDOverlay.HEADER_H - (i * HUDOverlay.ROW_H)
        self:drawFieldRow(row, px, rowY)
    end
end

function HUDOverlay:drawFieldRow(row, px, rowY)
    local moisture = row.moisture or 0
    local stress   = row.stress   or 0

    -- Row label: "Field 7 · Wheat"
    local cropLabel = row.cropName or "?"
    local stageStr  = row.growthStage and (" S" .. tostring(row.growthStage)) or ""
    local label = string.format("F%d · %s%s", row.fieldId, cropLabel, stageStr)

    -- Stress indicator
    local indicatorStr = ""
    if stress > 0.15 then
        indicatorStr = " !"
    end

    setTextColor(unpack(HUDOverlay.COLOR_TEXT))
    renderText(
        px + HUDOverlay.PADDING,
        rowY + HUDOverlay.PADDING,
        HUDOverlay.TEXT_SIZE,
        label .. indicatorStr
    )

    -- Moisture bar background
    local barX = px + HUDOverlay.PANEL_W - HUDOverlay.BAR_W - HUDOverlay.PADDING * 2
    local barY = rowY + (HUDOverlay.ROW_H - HUDOverlay.BAR_H) * 0.5
    setTextColor(unpack(HUDOverlay.COLOR_BAR_BG))
    drawFilledRect(barX, barY, HUDOverlay.BAR_W, HUDOverlay.BAR_H)

    -- Moisture bar fill — call on self, not on the class table
    local barColor = self:getMoistureColor(moisture)
    setTextColor(unpack(barColor))
    drawFilledRect(barX, barY, HUDOverlay.BAR_W * moisture, HUDOverlay.BAR_H)

    -- Percentage text
    setTextColor(unpack(HUDOverlay.COLOR_TEXT))
    renderText(
        barX + HUDOverlay.BAR_W + HUDOverlay.PADDING,
        rowY + HUDOverlay.PADDING,
        HUDOverlay.TEXT_SIZE,
        string.format("%d%%", math.floor(moisture * 100 + 0.5))
    )
end

function HUDOverlay:getMoistureColor(moisture)
    if moisture >= 0.60 then
        return HUDOverlay.COLOR_HEALTHY
    elseif moisture >= 0.30 then
        return HUDOverlay.COLOR_WARNING
    else
        return HUDOverlay.COLOR_CRITICAL
    end
end

-- Rebuild the display rows list from current soil + stress state
function HUDOverlay:rebuildDisplayRows()
    self.displayRows = {}

    if self.manager == nil or self.manager.soilSystem == nil then return end

    local sortedFields = self.manager.soilSystem:getFieldsSortedByMoisture()
    if sortedFields == nil then return end

    for _, entry in ipairs(sortedFields) do
        if #self.displayRows >= HUDOverlay.MAX_FIELDS then break end

        local stress      = 0
        local cropName    = "?"
        local growthStage = nil

        if self.manager.stressModifier ~= nil then
            stress = self.manager.stressModifier:getStress(entry.fieldId)
        end

        -- Try to get crop info from the field object
        if g_currentMission ~= nil and g_currentMission.fieldManager ~= nil then
            local field = nil
            if g_currentMission.fieldManager.getFieldByIndex ~= nil then
                field = g_currentMission.fieldManager:getFieldByIndex(entry.fieldId)
            end
            if field ~= nil then
                local ft = type(field.getFruitType) == "function" and field:getFruitType() or field.fruitType
                if ft ~= nil and ft.name ~= nil then
                    cropName = ft.name:sub(1,1):upper() .. ft.name:sub(2):lower()
                end
                if type(field.getGrowthState) == "function" then
                    growthStage = field:getGrowthState()
                elseif field.growthState ~= nil then
                    growthStage = field.growthState
                end
            end
        end

        table.insert(self.displayRows, {
            fieldId     = entry.fieldId,
            moisture    = entry.moisture,
            stress      = stress,
            cropName    = cropName,
            growthStage = growthStage,
        })
    end
end

-- Toggle visibility (bound to CS_TOGGLE_HUD input action)
function HUDOverlay:toggle()
    self.isVisible = not self.isVisible
    self.autoShowActive = false
    self.autoHideTimer  = 0

    if self.isVisible and not self.firstRunShown then
        self.firstRunShown = true
    end

    csLog("HUD toggled: " .. tostring(self.isVisible))
end

-- Auto-show when a critical threshold fires (if not already visible)
function HUDOverlay:onCriticalThreshold(data)
    if not self.isInitialized then return end
    if not self.isVisible then
        self.isVisible      = true
        self.autoShowActive = true
        self.autoHideTimer  = 120  -- auto-hide after 120 real seconds if not interacted with
    end

    -- First-run explanation (show once)
    if not self.firstRunShown then
        self.firstRunShown = true
        if g_currentMission ~= nil then
            g_currentMission:showBlinkingWarning(
                (g_i18n:getText("cs_hud_first_run") or
                 "Crop Moisture Monitor active. Press Shift+M to toggle the HUD."),
                6000
            )
        end
    end
end

function HUDOverlay:onMoistureUpdated(data)
    -- No per-event work needed — we rebuild each frame from current state
end

function HUDOverlay:delete()
    if self.manager ~= nil and self.manager.eventBus ~= nil then
        self.manager.eventBus.unsubscribeAll(self)
    end
    self.isInitialized = false
end