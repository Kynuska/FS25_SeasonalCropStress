-- ============================================================
-- HUDOverlay.lua
-- Renders the field moisture panel in the lower-left corner.
-- Uses FS25 immediate-mode render functions (renderText, renderOverlay, setOverlayColor).
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
HUDOverlay.COLOR_EDIT_BORDER = {1.00, 0.60, 0.10, 0.90}  -- orange — edit mode indicator
HUDOverlay.EDIT_BORDER_W     = 0.002

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
    self.rebuildTimer   = 0   -- throttles row rebuilds

    -- Click detection: track previous left-mouse button state for row selection.
    -- (FS25 Lua: getMouseButtonState(1) = LMB poll)
    -- RMB edit mode and drag are handled via addModEventListener mouseEvent (button 3/1).
    self.prevMouseDown  = false

    -- Panel position — initialized from class constants, overridable via drag in edit mode
    self.panelX         = HUDOverlay.PANEL_X
    self.panelY         = HUDOverlay.PANEL_Y
    self.lastResolution = {g_screenWidth or 1920, g_screenHeight or 1080}

    -- Edit mode / drag state (mirrors NPCFavorHUD pattern)
    self.editMode       = false
    self.dragging       = false
    self.dragOffsetX    = 0
    self.dragOffsetY    = 0

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

    -- Single shared overlay handle used for every filled-rect draw call.
    -- "dataS/menu/base/graph_pixel.dds" is a 1×1 white pixel in FS25 game data —
    -- tinted at draw time via setOverlayColor(handle, r, g, b, a).
    -- Guard: createImageOverlay is always available in FS25 PC/Console builds, but
    -- we check defensively so a missing function doesn't crash at draw time (see draw()).
    if createImageOverlay ~= nil then
        self.fillOverlay = createImageOverlay("dataS/menu/base/graph_pixel.dds")
    else
        csLog("WARNING: createImageOverlay not available — HUD rect rendering disabled")
    end

    self.isInitialized = true
    csLog("HUDOverlay initialized (Phase 3 — with forecast strip)")
end

-- ============================================================
-- UPDATE  (called every frame by CropStressManager:update())
-- ============================================================
function HUDOverlay:update(dt)
    if not self.isInitialized then return end
    if not self.isVisible then return end

    -- Detect resolution changes and recalculate coordinates
    local currentResolution = { g_screenWidth, g_screenHeight }
    if self.lastResolution[1] ~= currentResolution[1] or self.lastResolution[2] ~= currentResolution[2] then
        self.lastResolution = currentResolution
        self:recalculateCoordinates()
    end

    -- LMB row click detection (rising-edge poll — must run every frame)
    self:detectRowClick()

    -- Throttle row rebuilds to once per second to avoid per-frame cost
    self.rebuildTimer = self.rebuildTimer + dt
    if self.rebuildTimer >= 1.0 then
        self.rebuildTimer = 0
        self:rebuildDisplayRows()
    end

    -- Rebuild forecast when selection changes or moisture is updated.
    -- Runs after rebuildDisplayRows so selectedFieldId is always up-to-date.
    if self.forecastDirty then
        self.forecastDirty = false
        self:rebuildForecast()
    end

    -- Auto-hide countdown: tick down and hide when the timer expires.
    -- Set by onCriticalThreshold() to auto-dismiss after a critical alert.
    if self.autoShowActive and self.autoHideTimer > 0 then
        self.autoHideTimer = self.autoHideTimer - dt
        if self.autoHideTimer <= 0 then
            self.autoHideTimer  = 0
            self.autoShowActive = false
            self.isVisible      = false
        end
    end
end

-- Recalculate panel position from saved relative coordinates when resolution changes.
-- Position is stored as normalized fractions in settings so it survives resolution changes.
function HUDOverlay:recalculateCoordinates()
    local settings = self.manager and self.manager.settings
    if settings == nil then return end
    self.panelX = settings.hudPanelX or HUDOverlay.PANEL_X
    self.panelY = settings.hudPanelY or HUDOverlay.PANEL_Y
end

-- ============================================================
-- CLICK DETECTION (LMB row selection — polling)
-- LMB rising-edge via getMouseButtonState(1).
-- RMB reposition is handled by onMouseEvent() via addModEventListener.
-- ============================================================
function HUDOverlay:detectRowClick()
    -- Suppress row selection while in edit/drag mode
    if self.editMode then return end

    local lmbDown = false
    if type(getMouseButtonState) == "function" then
        local ok, val = pcall(getMouseButtonState, 1)
        if ok then lmbDown = val end
    end
    local lmbClicked   = lmbDown and not self.prevMouseDown
    self.prevMouseDown = lmbDown

    if not lmbClicked then return end

    -- Get mouse position (FS25 normalized: 0-1 from bottom-left)
    local mx, my = 0, 0
    if type(getMousePosition) == "function" then
        local ok, x, y = pcall(getMousePosition)
        if ok then mx, my = x or 0, y or 0 end
    end

    local numRows = math.min(#self.displayRows, HUDOverlay.MAX_FIELDS)
    local panelH  = self:calcPanelHeight(numRows)
    local px      = self.panelX
    local py      = self.panelY

    for i = 1, numRows do
        local rowY = py + panelH - HUDOverlay.HEADER_H - (i * HUDOverlay.ROW_H)
        if mx >= px and mx <= px + HUDOverlay.PANEL_W
        and my >= rowY and my <= rowY + HUDOverlay.ROW_H then
            local newId = self.displayRows[i].fieldId
            if self.selectedFieldId == newId then
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
-- MOUSE EVENT — edit mode + drag reposition
-- Called from main.lua addModEventListener mouseEvent handler.
-- FS25 button numbers: 1=left, 3=right, 2=middle.
--
-- IMPORTANT: In FS25 gameplay mode, the cursor is captured for
-- camera control. mouseEvent fires ONLY on button state changes
-- (down/up) — NOT for intermediate mouse movement. This means
-- continuous drag tracking is impossible. We use the NPCFavor
-- pattern: record position on LMB down, apply the full delta
-- (release - click) on LMB up. One-shot repositioning.
--
-- Flow:
--   RMB down → toggle edit mode (orange border = edit active)
--   LMB down (in edit mode) → record click position + HUD origin
--   LMB up (in edit mode)   → apply DOWN→UP delta to HUD position
-- ============================================================
function HUDOverlay:onMouseEvent(posX, posY, isDown, isUp, button)
    if not self.isVisible then return end

    -- ── RMB: toggle edit mode ─────────────────────────────
    if isDown and button == 3 then
        self.editMode = not self.editMode
        if not self.editMode then
            self.dragging = false
            -- Persist new position to settings so it survives reload.
            if self.manager ~= nil and self.manager.settings ~= nil then
                self.manager.settings.hudPanelX = self.panelX
                self.manager.settings.hudPanelY = self.panelY
            end
            csLog("HUD edit mode OFF — position saved")
        else
            csLog("HUD edit mode ON — LMB click+release to reposition")
        end
        return
    end

    if not self.editMode then return end

    -- ── LMB down: record drag start ───────────────────────
    if isDown and button == 1 then
        self.dragging   = true
        self.dragStartX = posX
        self.dragStartY = posY
        self.hudStartX  = self.panelX
        self.hudStartY  = self.panelY
        return
    end

    -- ── LMB up: apply full DOWN→UP delta ──────────────────
    -- No intermediate movement events fire in FS25 gameplay mode,
    -- so we apply the entire delta from click to release at once.
    if isUp and button == 1 and self.dragging then
        local dx = posX - self.dragStartX
        local dy = posY - self.dragStartY
        self.panelX = math.max(0.0, math.min(1.0 - HUDOverlay.PANEL_W, self.hudStartX + dx))
        self.panelY = math.max(0.05, math.min(0.95, self.hudStartY + dy))
        self.dragging = false
        -- Persist immediately
        if self.manager ~= nil and self.manager.settings ~= nil then
            self.manager.settings.hudPanelX = self.panelX
            self.manager.settings.hudPanelY = self.panelY
        end
        csLog(string.format("HUD repositioned to %.3f,%.3f (delta: %+.3f,%+.3f)", self.panelX, self.panelY, dx, dy))
        return
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

    -- Request FORECAST_COLS-1 projected days: the first display column is "Now"
    -- (current moisture from soilSystem), so we only need 4 future projections
    -- to fill the remaining 4 columns.
    local projections = self.manager.weatherIntegration:getMoistureForecast(
        self.selectedFieldId, HUDOverlay.FORECAST_COLS - 1)

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
    -- Hide while any full-screen GUI (InGameMenu, dialogs) is open.
    if g_gui ~= nil and g_gui:getIsGuiVisible() then return end
    -- fillOverlay is nil only if createImageOverlay was unavailable at init (extremely rare).
    -- Bail out rather than spam nil-handle errors every frame.
    if self.fillOverlay == nil then return end

    local numRows = math.min(#self.displayRows, HUDOverlay.MAX_FIELDS)

    -- Use 1 placeholder row height when there are no fields so the panel
    -- always renders visibly after Shift+M — gives the player feedback that
    -- the toggle worked even on maps with no enumerated fields.
    local showEmpty   = (numRows == 0)
    local panelH      = self:calcPanelHeight(showEmpty and 1 or numRows)
    local px          = self.panelX
    local py          = self.panelY

    -- Draw forecast strip BELOW the main panel (lower Y values)
    if self.forecastCache ~= nil then
        self:drawForecastStrip(px, py - HUDOverlay.FORECAST_H - HUDOverlay.PADDING)
    end

    -- Background panel
    setOverlayColor(self.fillOverlay, unpack(HUDOverlay.COLOR_BG))
    renderOverlay(self.fillOverlay, px, py, HUDOverlay.PANEL_W, panelH)

    -- Header bar
    setOverlayColor(self.fillOverlay, unpack(HUDOverlay.COLOR_HEADER_BG))
    renderOverlay(self.fillOverlay, px, py + panelH - HUDOverlay.HEADER_H, HUDOverlay.PANEL_W, HUDOverlay.HEADER_H)

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

    -- Empty state: no fields tracked on this map
    if showEmpty then
        setTextColor(unpack(HUDOverlay.COLOR_DIM_TEXT))
        renderText(
            px + HUDOverlay.PADDING,
            py + HUDOverlay.PADDING + (HUDOverlay.ROW_H - HUDOverlay.TEXT_SIZE) * 0.5,
            HUDOverlay.TEXT_SIZE,
            (g_i18n ~= nil and g_i18n:getText("cs_hud_no_crop")) or "No field data"
        )
        return
    end

    -- Field rows
    for i = 1, numRows do
        local row  = self.displayRows[i]
        local rowY = py + panelH - HUDOverlay.HEADER_H - (i * HUDOverlay.ROW_H)

        -- Selection highlight background
        if row.fieldId == self.selectedFieldId then
            setOverlayColor(self.fillOverlay, unpack(HUDOverlay.COLOR_ROW_HOVER))
            renderOverlay(self.fillOverlay, px, rowY, HUDOverlay.PANEL_W, HUDOverlay.ROW_H)
            -- Selection border (left edge stripe)
            setOverlayColor(self.fillOverlay, unpack(HUDOverlay.COLOR_SELECTED_BDR))
            renderOverlay(self.fillOverlay, px, rowY, HUDOverlay.SELECTED_BORDER_W, HUDOverlay.ROW_H)
        end

        self:drawFieldRow(row, px, rowY)
    end

    -- Hint text at bottom of panel if no field selected
    if self.selectedFieldId == nil and not self.editMode then
        setTextColor(unpack(HUDOverlay.COLOR_DIM_TEXT))
        renderText(
            px + HUDOverlay.PADDING,
            py + HUDOverlay.PADDING,
            0.010,
            (g_i18n ~= nil and g_i18n:getText("cs_hud_click_forecast")) or "Click row for 5-day forecast"
        )
    end

    -- Edit mode: orange border + hint text replacing the normal footer
    if self.editMode then
        local bw = HUDOverlay.EDIT_BORDER_W
        setOverlayColor(self.fillOverlay, unpack(HUDOverlay.COLOR_EDIT_BORDER))
        renderOverlay(self.fillOverlay, px,                      py + panelH - bw, HUDOverlay.PANEL_W, bw)  -- top
        renderOverlay(self.fillOverlay, px,                      py,               HUDOverlay.PANEL_W, bw)  -- bottom
        renderOverlay(self.fillOverlay, px,                      py,               bw,                 panelH)  -- left
        renderOverlay(self.fillOverlay, px + HUDOverlay.PANEL_W - bw, py,          bw,                 panelH)  -- right

        setTextColor(unpack(HUDOverlay.COLOR_EDIT_BORDER))
        renderText(
            px + HUDOverlay.PADDING,
            py + HUDOverlay.PADDING,
            0.010,
            "LMB click+release to move  |  RMB to exit"
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
    setOverlayColor(self.fillOverlay, unpack(HUDOverlay.COLOR_BAR_BG))
    renderOverlay(self.fillOverlay, barX, barY, HUDOverlay.BAR_W, HUDOverlay.BAR_H)

    -- Moisture bar fill
    local barColor = self:getMoistureColor(moisture)
    setOverlayColor(self.fillOverlay, unpack(barColor))
    renderOverlay(self.fillOverlay, barX, barY, HUDOverlay.BAR_W * moisture, HUDOverlay.BAR_H)

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
    setOverlayColor(self.fillOverlay, unpack(HUDOverlay.COLOR_FORECAST_BG))
    renderOverlay(self.fillOverlay, px, py, HUDOverlay.PANEL_W, fH)

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
        setOverlayColor(self.fillOverlay, unpack(HUDOverlay.COLOR_BAR_BG))
        renderOverlay(self.fillOverlay, cx, barBaseY, bw, barMaxH)

        -- Bar fill
        local fillH = barMaxH * val
        setOverlayColor(self.fillOverlay, unpack(self:getMoistureColor(val)))
        renderOverlay(self.fillOverlay, cx, barBaseY, bw, fillH)

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

function HUDOverlay:resolveCropName(field)
    if field == nil then return "?" end

    local ft = nil

    -- FS25 primary: field.currentFruitTypeIndex (engine-written property)
    local fti = field.currentFruitTypeIndex
    if fti ~= nil and fti > 0 and g_fruitTypeManager ~= nil then
        ft = g_fruitTypeManager:getFruitTypeByIndex(fti)
    end

    -- Legacy fallback: getFruitType() / fruitType (FS22-era field API)
    if ft == nil then
        if type(field.getFruitType) == "function" then
            local ok, result = pcall(function() return field:getFruitType() end)
            if ok then ft = result end
        end
        if ft == nil then ft = field.fruitType end
    end

    if ft ~= nil and ft.name ~= nil then
        local name = ft.name:lower()
        if name == "grass" or name == "drygrass" or name == "weed"
        or name == "stone" or name == "meadow" then
            return "Fallow"
        end
        return ft.name:sub(1,1):upper() .. ft.name:sub(2):lower()
    end
    return "Fallow"
end

function HUDOverlay:rebuildDisplayRows()
    self.displayRows = {}
    if self.manager == nil or self.manager.soilSystem == nil then return end

    local sortedFields = self.manager.soilSystem:getFieldsSortedByMoisture()
    if sortedFields == nil then return end

    -- Use the manager's pre-built fieldId→field map (O(1) per lookup, correct on all maps).
    -- getFieldByIndex(n) returns fields[n] by array position, NOT the field with fieldId==n
    -- — silently wrong on custom maps, renumbered fields, or non-sequential farmlands.
    local fieldById = (self.manager ~= nil) and self.manager.fieldById or {}

    for _, entry in ipairs(sortedFields) do
        if #self.displayRows >= HUDOverlay.MAX_FIELDS then break end

        local stress      = 0
        local cropName    = nil
        local growthStage = nil

        if self.manager.stressModifier ~= nil then
            stress = self.manager.stressModifier:getStress(entry.fieldId)
        end

        local field = fieldById[entry.fieldId]
        if field ~= nil then
            -- FS25-native crop resolution: getFieldState() → fruitTypeIndex
            cropName = self:resolveCropName(field)

            -- Growth stage
            if type(field.getGrowthState) == "function" then
                local ok2, result = pcall(function() return field:getGrowthState() end)
                if ok2 then growthStage = result end
            elseif field.growthState ~= nil then
                growthStage = field.growthState
            end
        end

        -- Final fallback: field not in map yet (enumeration race on slow-loading map)
        if cropName == nil then cropName = "?" end

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

    if self.isVisible then
        if not self.firstRunShown then
            self.firstRunShown = true
        end

        -- Rebuild display rows immediately so auto-select below has data.
        -- (update() normally rebuilds rows, but it runs next frame — after toggle() returns.)
        self:rebuildDisplayRows()

        self:rebuildDisplayRows()

        -- FIX: soilSystem may not have its moisture table yet on first open.
        -- Build stub rows from fieldById so the panel is never blank.
        if #self.displayRows == 0 then
            local fieldById = (self.manager ~= nil) and self.manager.fieldById or {}
            local count = 0
            for fid, field in pairs(fieldById) do
                if count >= HUDOverlay.MAX_FIELDS then break end
                local stress = 0
                if self.manager ~= nil and self.manager.stressModifier ~= nil then
                    stress = self.manager.stressModifier:getStress(fid) or 0
                end
                local growthStage = nil
                if type(field.getGrowthState) == "function" then
                    local ok, result = pcall(function() return field:getGrowthState() end)
                    if ok then growthStage = result end
                elseif field.growthState ~= nil then
                    growthStage = field.growthState
                end
                table.insert(self.displayRows, {
                    fieldId     = fid,
                    moisture    = 0,
                    stress      = stress,
                    cropName    = self:resolveCropName(field),
                    growthStage = growthStage,
                })
                count = count + 1
            end
        end
        
        -- Auto-select driest field when opening
        if self.selectedFieldId == nil and #self.displayRows > 0 then
            self.selectedFieldId = self.displayRows[1].fieldId
            self.forecastDirty   = true
        end
    else
        -- Exit edit mode when hiding — orange border should not persist invisibly
        if self.editMode then
            self.editMode = false
            self.dragging = false
            -- Persist position so the drag position is saved even if they hid mid-edit
            if self.manager ~= nil and self.manager.settings ~= nil then
                self.manager.settings.hudPanelX = self.panelX
                self.manager.settings.hudPanelY = self.panelY
            end
        end
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
    if self.fillOverlay ~= nil and delete ~= nil then
        delete(self.fillOverlay)
        self.fillOverlay = nil
    end
    self.forecastCache   = nil
    self.selectedFieldId = nil
    self.isInitialized   = false
end