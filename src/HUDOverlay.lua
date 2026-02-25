-- ============================================================
-- HUDOverlay.lua
-- Renders the field moisture panel in the lower-left corner.
-- Uses FS25 immediate-mode render functions (renderText, drawFilledRect).
--
-- Phase 1: Basic moisture bars with auto-show/auto-hide
-- Phase 3: +Forecast strip for selected field, +click-based row selection
--
-- Layout (bottom-left, above minimap):
-- ┌─────────────────────────────────────────────┐
-- │  CROP MOISTURE MONITOR               [M]    │
-- │  Field 7 · Wheat S4    ████████░░ 78%  [SEL]│
-- │  Field 3 · Corn  S5 !  ███░░░░░░░ 32%       │
-- │  Field 5 · Corn  S3    ██████████ 80%       │
-- ├─────────────────────────────────────────────┤
-- │  5-DAY FORECAST — Field 7                   │
-- │  Today  D+1   D+2   D+3   D+4               │
-- │   78%    72%   65%   58%   52%               │
-- └─────────────────────────────────────────────┘
--
-- HUD coordinates: bottom-left origin. Y=0 at BOTTOM, increases UP.
-- All values are normalized screen fractions (0.0–1.0).
-- ============================================================

HUDOverlay = {}
HUDOverlay.__index = HUDOverlay

-- ── Main panel layout ──────────────────────────────────────
HUDOverlay.PANEL_X          = 0.010
HUDOverlay.PANEL_Y          = 0.175
HUDOverlay.PANEL_W          = 0.230
HUDOverlay.ROW_H            = 0.024
HUDOverlay.HEADER_H         = 0.028
HUDOverlay.PADDING          = 0.004
HUDOverlay.BAR_W            = 0.080
HUDOverlay.BAR_H            = 0.012
HUDOverlay.TEXT_SIZE         = 0.013
HUDOverlay.HEADER_TEXT_SIZE  = 0.014
HUDOverlay.MAX_FIELDS        = 6

-- ── Forecast strip layout ──────────────────────────────────
HUDOverlay.FORECAST_H        = 0.068   -- total height of the forecast panel
HUDOverlay.FORECAST_HEADER_H = 0.022
HUDOverlay.FORECAST_ROW_H    = 0.020
HUDOverlay.FORECAST_COLS     = 5
HUDOverlay.FORECAST_COL_W    = 0.040   -- width per forecast column
HUDOverlay.FORECAST_BAR_H    = 0.010
HUDOverlay.FORECAST_TEXT_SZ  = 0.011

-- ── Selection highlight ────────────────────────────────────
-- A thin colored border is drawn on the selected row
HUDOverlay.SELECTED_BORDER_W  = 0.003
HUDOverlay.COLOR_SELECTED_BDR = {0.40, 0.80, 1.00, 0.90}  -- light blue

-- ── Colors ─────────────────────────────────────────────────
HUDOverlay.COLOR_BG          = {0.05, 0.05, 0.05, 0.78}
HUDOverlay.COLOR_HEADER_BG   = {0.10, 0.10, 0.10, 0.85}
HUDOverlay.COLOR_ROW_HOVER   = {0.15, 0.15, 0.15, 0.60}  -- subtle row highlight
HUDOverlay.COLOR_TEXT         = {0.90, 0.90, 0.90, 1.00}
HUDOverlay.COLOR_HEADER_TEXT  = {1.00, 1.00, 1.00, 1.00}
HUDOverlay.COLOR_BAR_BG      = {0.20, 0.20, 0.20, 0.80}
HUDOverlay.COLOR_HEALTHY     = {0.20, 0.75, 0.20, 1.00}  -- green  >60%
HUDOverlay.COLOR_WARNING     = {0.85, 0.70, 0.10, 1.00}  -- yellow 30-60%
HUDOverlay.COLOR_CRITICAL    = {0.85, 0.20, 0.10, 1.00}  -- red    <30%
HUDOverlay.COLOR_FORECAST_BG = {0.08, 0.08, 0.12, 0.82}
HUDOverlay.COLOR_DIM_TEXT    = {0.60, 0.60, 0.60, 1.00}

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

-- ============================================================
-- CONSTRUCTOR
-- ============================================================
function HUDOverlay.new(manager)
    local self = setmetatable({}, HUDOverlay)
    self.manager        = manager
    self.isVisible      = false
    self.firstRunShown  = false

    -- Display rows rebuilt each frame
    self.displayRows    = {}

    -- Phase 3: selected field for forecast strip
    self.selectedFieldId   = nil
    self.forecastCache     = nil   -- cached {fieldId, projections[5]} — rebuilt when selection changes
    self.forecastDirty     = true

    -- Auto-show / auto-hide state
    self.autoShowActive = false
    self.autoHideTimer  = 0   -- real-time seconds; 0 = no auto-hide

    -- Click detection: track previous left-mouse button state
    -- (FS25 Lua: getMouseButtonState(1) returns true if LMB held)
    self.prevMouseDown  = false

    self.isInitialized  = false
    return self
end

-- ============================================================
-- INITIALIZE
-- ============================================================
function HUDOverlay:initialize()
    if self.manager ~= nil and self.manager.eventBus ~= nil then
        self.manager.eventBus.subscribe("CS_MOISTURE_UPDATED",   self.onMoistureUpdated,   self)
        self.manager.eventBus.subscribe("CS_CRITICAL_THRESHOLD", self.onCriticalThreshold, self)
    end

    self.isInitialized = true
    csLog("HUDOverlay initialized (Phase 3 — with forecast strip)")
end

-- ============================================================
-- UPDATE  (called every frame by CropStressManager:update())
-- ============================================================
function HUDOverlay:update(dt)
    if not self.isInitialized then return end

    -- Auto-hide countdown
    if self.autoHideTimer > 0 then
        self.autoHideTimer = self.autoHideTimer - dt
        if self.autoHideTimer <= 0 then
            self.autoHideTimer = 0
            if self.autoShowActive then
                self.autoShowActive = false
                self.isVisible      = false
            end
        end
    end

    -- Rebuild display rows only while visible — no need to pay the field lookup
    -- cost every frame when the HUD is hidden.
    if self.isVisible then
        self:rebuildDisplayRows()
        self:detectRowClick()
    end

    -- Rebuild forecast when selected field changes or data is dirty
    if self.forecastDirty and self.selectedFieldId ~= nil then
        self:rebuildForecast()
        self.forecastDirty = false
    end
end

-- ============================================================
-- CLICK DETECTION
-- Checks if the player clicks within any field row's bounds.
-- Uses getMouseButtonState(1) for LMB — rising-edge trigger.
-- ============================================================
function HUDOverlay:detectRowClick()
    local lmbDown = false

    -- LUADOC NOTE: getMouseButtonState(1) is the FS25 LMB query.
    -- Guard with pcall in case the function is unavailable.
    if type(getMouseButtonState) == "function" then
        local ok, val = pcall(getMouseButtonState, 1)
        if ok then lmbDown = val end
    end

    -- Rising edge: click started this frame
    local clicked = lmbDown and not self.prevMouseDown
    self.prevMouseDown = lmbDown

    if not clicked then return end

    -- Get mouse position (FS25 normalized: getMousePosition → x, y, 0-1 from bottom-left)
    local mx, my = 0, 0
    if type(getMousePosition) == "function" then
        local ok, x, y = pcall(getMousePosition)
        if ok then mx, my = x or 0, y or 0 end
    end

    -- Test each row's bounding box
    local numRows = math.min(#self.displayRows, HUDOverlay.MAX_FIELDS)
    local panelH  = self:calcPanelHeight(numRows)
    local px      = HUDOverlay.PANEL_X
    local py      = HUDOverlay.PANEL_Y

    for i = 1, numRows do
        local rowY = py + panelH - HUDOverlay.HEADER_H - (i * HUDOverlay.ROW_H)
        if mx >= px and mx <= px + HUDOverlay.PANEL_W
        and my >= rowY and my <= rowY + HUDOverlay.ROW_H then
            local newId = self.displayRows[i].fieldId
            if self.selectedFieldId == newId then
                -- Clicking selected row again deselects
                self.selectedFieldId = nil
                self.forecastCache   = nil
            else
                self.selectedFieldId = newId
                self.forecastDirty   = true
            end
            break
        end
    end
end

-- ============================================================
-- REBUILD FORECAST
-- Requests a 5-day moisture projection from WeatherIntegration
-- for the currently selected field.
-- ============================================================
function HUDOverlay:rebuildForecast()
    if self.selectedFieldId == nil then
        self.forecastCache = nil
        return
    end
    if self.manager == nil or self.manager.weatherIntegration == nil then return end

    local projections = self.manager.weatherIntegration:getMoistureForecast(
        self.selectedFieldId, HUDOverlay.FORECAST_COLS)

    self.forecastCache = {
        fieldId     = self.selectedFieldId,
        projections = projections,
    }
end

-- ============================================================
-- CALC PANEL HEIGHT (pure function, used in update + draw)
-- ============================================================
function HUDOverlay:calcPanelHeight(numRows)
    return HUDOverlay.HEADER_H
        + (numRows * HUDOverlay.ROW_H)
        + HUDOverlay.PADDING * 2
end

-- ============================================================
-- DRAW  (called every frame by CropStressManager:draw())
-- ============================================================
function HUDOverlay:draw()
    if not self.isInitialized or not self.isVisible then return end
    if g_currentMission == nil then return end

    local numRows = math.min(#self.displayRows, HUDOverlay.MAX_FIELDS)
    if numRows == 0 then return end

    local panelH = self:calcPanelHeight(numRows)
    local px     = HUDOverlay.PANEL_X
    local py     = HUDOverlay.PANEL_Y

    -- Draw forecast strip BELOW the main panel (lower Y values)
    local forecastBottomY = py
    if self.forecastCache ~= nil then
        forecastBottomY = py - HUDOverlay.FORECAST_H - HUDOverlay.PADDING
        self:drawForecastStrip(px, forecastBottomY)
    end

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
        (g_i18n ~= nil and g_i18n:getText("cs_hud_title")) or "CROP MOISTURE"
    )
    -- Key hint (right side of header)
    renderText(
        px + HUDOverlay.PANEL_W - 0.028,
        py + panelH - HUDOverlay.HEADER_H + HUDOverlay.PADDING,
        HUDOverlay.TEXT_SIZE,
        "[M]"
    )
    setTextBold(false)

    -- Field rows
    for i = 1, numRows do
        local row  = self.displayRows[i]
        local rowY = py + panelH - HUDOverlay.HEADER_H - (i * HUDOverlay.ROW_H)

        -- Selection highlight background
        if row.fieldId == self.selectedFieldId then
            setTextColor(unpack(HUDOverlay.COLOR_ROW_HOVER))
            drawFilledRect(px, rowY, HUDOverlay.PANEL_W, HUDOverlay.ROW_H)
            -- Selection border (left edge stripe)
            setTextColor(unpack(HUDOverlay.COLOR_SELECTED_BDR))
            drawFilledRect(px, rowY, HUDOverlay.SELECTED_BORDER_W, HUDOverlay.ROW_H)
        end

        self:drawFieldRow(row, px, rowY)
    end

    -- Hint text at bottom of panel if no field selected
    if self.selectedFieldId == nil and numRows > 0 then
        setTextColor(unpack(HUDOverlay.COLOR_DIM_TEXT))
        renderText(
            px + HUDOverlay.PADDING,
            py + HUDOverlay.PADDING,
            0.010,
            "click row for 5-day forecast"
        )
    end
end

-- ============================================================
-- DRAW FIELD ROW
-- ============================================================
function HUDOverlay:drawFieldRow(row, px, rowY)
    local moisture = row.moisture or 0
    local stress   = row.stress   or 0

    local cropLabel   = row.cropName or "?"
    local stageStr    = row.growthStage and (" S" .. tostring(row.growthStage)) or ""
    local label       = string.format("F%d · %s%s", row.fieldId, cropLabel, stageStr)
    local stressStr   = stress > 0.15 and " !" or ""

    setTextColor(unpack(HUDOverlay.COLOR_TEXT))
    renderText(
        px + HUDOverlay.PADDING + HUDOverlay.SELECTED_BORDER_W,
        rowY + HUDOverlay.PADDING,
        HUDOverlay.TEXT_SIZE,
        label .. stressStr
    )

    -- Moisture bar background
    local barX = px + HUDOverlay.PANEL_W - HUDOverlay.BAR_W - HUDOverlay.PADDING * 2
    local barY = rowY + (HUDOverlay.ROW_H - HUDOverlay.BAR_H) * 0.5
    setTextColor(unpack(HUDOverlay.COLOR_BAR_BG))
    drawFilledRect(barX, barY, HUDOverlay.BAR_W, HUDOverlay.BAR_H)

    -- Moisture bar fill
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

-- ============================================================
-- DRAW FORECAST STRIP
-- Renders a 5-column bar-chart below the main panel.
-- ============================================================
function HUDOverlay:drawForecastStrip(px, py)
    if self.forecastCache == nil then return end

    local projections = self.forecastCache.projections
    local fieldId     = self.forecastCache.fieldId
    local fH          = HUDOverlay.FORECAST_H

    -- Background
    setTextColor(unpack(HUDOverlay.COLOR_FORECAST_BG))
    drawFilledRect(px, py, HUDOverlay.PANEL_W, fH)

    -- Header
    setTextColor(unpack(HUDOverlay.COLOR_HEADER_TEXT))
    setTextBold(true)
    local titleText = string.format("%s — F%d",
        (g_i18n ~= nil and g_i18n:getText("cs_hud_forecast")) or "5-Day Forecast",
        fieldId)
    renderText(
        px + HUDOverlay.PADDING,
        py + fH - HUDOverlay.FORECAST_HEADER_H + HUDOverlay.PADDING,
        HUDOverlay.FORECAST_TEXT_SZ,
        titleText
    )
    setTextBold(false)

    -- Column labels and bars
    -- projections[1..5] are day+1 through day+5 from WeatherIntegration:getMoistureForecast().
    -- We show current moisture as the first "Now" column directly from soilSystem,
    -- then the five projected days.  Shift projections into display slots 2-5 and
    -- insert current moisture as slot 1.
    local colLabels   = {"Now", "D+1", "D+2", "D+3", "D+4"}
    local currentMoisture = 0
    if self.manager ~= nil and self.manager.soilSystem ~= nil then
        currentMoisture = self.manager.soilSystem:getMoisture(fieldId) or 0
    end
    -- Build display values: [current, proj[1], proj[2], proj[3], proj[4]]
    local displayVals = {
        currentMoisture,
        projections[1] or currentMoisture,
        projections[2] or currentMoisture,
        projections[3] or currentMoisture,
        projections[4] or currentMoisture,
    }
    local colStartX   = px + HUDOverlay.PADDING
    local colGap      = (HUDOverlay.PANEL_W - HUDOverlay.PADDING * 2) / HUDOverlay.FORECAST_COLS
    local barAreaH    = fH - HUDOverlay.FORECAST_HEADER_H - HUDOverlay.PADDING * 2
    local barMaxH     = barAreaH - HUDOverlay.FORECAST_ROW_H  -- reserve space for pct text
    local barBaseY    = py + HUDOverlay.PADDING + HUDOverlay.FORECAST_ROW_H

    for i = 1, HUDOverlay.FORECAST_COLS do
        local val = displayVals[i] or 0
        local cx  = colStartX + (i - 1) * colGap + HUDOverlay.PADDING

        -- Column label (day label, small, dimmed)
        setTextColor(unpack(HUDOverlay.COLOR_DIM_TEXT))
        renderText(cx, barBaseY + barMaxH + HUDOverlay.PADDING, HUDOverlay.FORECAST_TEXT_SZ,
            colLabels[i] or "?")

        -- Bar background
        local bw = HUDOverlay.FORECAST_COL_W - HUDOverlay.PADDING
        setTextColor(unpack(HUDOverlay.COLOR_BAR_BG))
        drawFilledRect(cx, barBaseY, bw, barMaxH)

        -- Bar fill
        local fillH = barMaxH * val
        setTextColor(unpack(self:getMoistureColor(val)))
        drawFilledRect(cx, barBaseY, bw, fillH)

        -- Percentage text below bar
        setTextColor(unpack(HUDOverlay.COLOR_TEXT))
        renderText(cx, py + HUDOverlay.PADDING, HUDOverlay.FORECAST_TEXT_SZ,
            string.format("%d%%", math.floor(val * 100 + 0.5)))
    end
end

-- ============================================================
-- MOISTURE COLOR
-- ============================================================
function HUDOverlay:getMoistureColor(moisture)
    if moisture >= 0.60 then return HUDOverlay.COLOR_HEALTHY
    elseif moisture >= 0.30 then return HUDOverlay.COLOR_WARNING
    else return HUDOverlay.COLOR_CRITICAL end
end

-- ============================================================
-- REBUILD DISPLAY ROWS
-- ============================================================
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

        if g_currentMission ~= nil and g_currentMission.fieldManager ~= nil then
            local field = nil
            if g_currentMission.fieldManager.getFieldByIndex ~= nil then
                field = g_currentMission.fieldManager:getFieldByIndex(entry.fieldId)
            end
            if field ~= nil then
                local ft = type(field.getFruitType) == "function"
                    and field:getFruitType()
                    or field.fruitType
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

    -- If selected field is no longer in the display list, mark forecast dirty
    if self.selectedFieldId ~= nil then
        local found = false
        for _, row in ipairs(self.displayRows) do
            if row.fieldId == self.selectedFieldId then found = true; break end
        end
        if not found then
            -- Reselect top (driest) field if previous selected fell off the list
            if #self.displayRows > 0 then
                local newId = self.displayRows[1].fieldId
                if self.selectedFieldId ~= newId then
                    self.selectedFieldId = newId
                    self.forecastDirty   = true
                end
            else
                self.selectedFieldId = nil
                self.forecastCache   = nil
            end
        end
    end
end

-- ============================================================
-- TOGGLE (bound to CS_TOGGLE_HUD)
-- ============================================================
function HUDOverlay:toggle()
    self.isVisible      = not self.isVisible
    self.autoShowActive = false
    self.autoHideTimer  = 0

    if self.isVisible and not self.firstRunShown then
        self.firstRunShown = true
    end

    -- Auto-select driest field when opening
    if self.isVisible and self.selectedFieldId == nil and #self.displayRows > 0 then
        self.selectedFieldId = self.displayRows[1].fieldId
        self.forecastDirty   = true
    end

    csLog("HUD toggled: " .. tostring(self.isVisible))
end

-- ============================================================
-- EVENT: CS_CRITICAL_THRESHOLD
-- ============================================================
function HUDOverlay:onCriticalThreshold(data)
    if not self.isInitialized then return end

    if not self.isVisible then
        self.isVisible      = true
        self.autoShowActive = true
        self.autoHideTimer  = 120

        -- Auto-select the critical field
        if data ~= nil and data.fieldId ~= nil then
            self.selectedFieldId = data.fieldId
            self.forecastDirty   = true
        end
    end

    -- First-run tooltip (once)
    if not self.firstRunShown then
        self.firstRunShown = true
        if g_currentMission ~= nil then
            local msg = (g_i18n ~= nil and g_i18n:getText("cs_hud_first_run"))
                or "Crop Moisture Monitor active. Press Shift+M to toggle the HUD."
            g_currentMission:showBlinkingWarning(msg, 6000)
        end
    end
end

-- ============================================================
-- EVENT: CS_MOISTURE_UPDATED
-- Marks forecast dirty so it gets recalculated next frame.
-- ============================================================
function HUDOverlay:onMoistureUpdated(data)
    if data ~= nil and data.fieldId == self.selectedFieldId then
        self.forecastDirty = true
    end
end

-- ============================================================
-- CLEANUP
-- ============================================================
function HUDOverlay:delete()
    if self.manager ~= nil and self.manager.eventBus ~= nil then
        self.manager.eventBus.unsubscribeAll(self)
    end
    self.forecastCache   = nil
    self.selectedFieldId = nil
    self.isInitialized   = false
end