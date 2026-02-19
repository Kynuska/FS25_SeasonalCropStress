-- ============================================================
-- SaveLoadHandler.lua
-- Handles persistence of mod state into the FS25 career savegame.
--
-- Save layout inside careerSavegame XML:
--   <cropStress>
--     <fields>
--       <field id="1" moisture="0.62" stress="0.00" estimated="false"/>
--       ...
--     </fields>
--     <hud visible="true" firstRunShown="true"/>
--     <irrigation>                          ← Phase 2 addition
--       <system id="42" startHour="6" endHour="10" isActive="false"
--               activeDays="1,1,1,1,1,0,0"/>
--       ...
--     </irrigation>
--   </cropStress>
-- ============================================================

SaveLoadHandler = {}
SaveLoadHandler.__index = SaveLoadHandler

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

function SaveLoadHandler.new(manager)
    local self = setmetatable({}, SaveLoadHandler)
    self.manager = manager
    self.isInitialized = false
    return self
end

function SaveLoadHandler:initialize()
    self.isInitialized = true
end

-- ============================================================
-- SAVE
-- Called from FSCareerMissionInfo.saveToXMLFile hook.
-- xmlFile is the handle provided by FS25 — never nil here.
-- ============================================================
function SaveLoadHandler:saveToXMLFile(xmlFile)
    if not self.isInitialized then return end
    if xmlFile == nil then return end

    local root = "careerSavegame.cropStress"

    -- ── Field moisture & stress ──────────────────────────────
    local soilSystem = self.manager.soilSystem
    if soilSystem ~= nil then
        local i = 0
        for fieldId, data in pairs(soilSystem.fieldData) do
            local key = string.format("%s.fields.field(%d)", root, i)
            setXMLInt(xmlFile,    key .. "#id",        fieldId)
            setXMLFloat(xmlFile,  key .. "#moisture",  data.moisture)
            setXMLFloat(xmlFile,  key .. "#stress",    self.manager.stressModifier:getStress(fieldId))
            setXMLBool(xmlFile,   key .. "#estimated", false)
            i = i + 1
        end
    end

    -- ── HUD state ────────────────────────────────────────────
    local hud = self.manager.hudOverlay
    if hud ~= nil then
        setXMLBool(xmlFile,  root .. ".hud#visible",       hud.isVisible)
        setXMLBool(xmlFile,  root .. ".hud#firstRunShown", hud.firstRunShown)
    end

    -- ── Irrigation schedules (Phase 2) ───────────────────────
    local irrMgr = self.manager.irrigationManager
    if irrMgr ~= nil then
        local i = 0
        for sysId, system in pairs(irrMgr.systems) do
            local key = string.format("%s.irrigation.system(%d)", root, i)

            setXMLInt(xmlFile,    key .. "#id",        sysId)
            setXMLInt(xmlFile,    key .. "#startHour", system.schedule.startHour)
            setXMLInt(xmlFile,    key .. "#endHour",   system.schedule.endHour)
            setXMLBool(xmlFile,   key .. "#isActive",  system.isActive)

            -- activeDays: encode as "1,0,1,..." string
            local dayStrs = {}
            for _, v in ipairs(system.schedule.activeDays) do
                table.insert(dayStrs, v and "1" or "0")
            end
            setXMLString(xmlFile, key .. "#activeDays", table.concat(dayStrs, ","))

            i = i + 1
        end
    end

    csLog("SaveLoadHandler: state saved")
end

-- ============================================================
-- LOAD
-- Called from Mission00.onStartMission hook, after fields are populated.
-- Missing keys fall back gracefully — safe on a fresh save.
-- ============================================================
function SaveLoadHandler:loadFromXMLFile()
    if not self.isInitialized then return end

    -- Resolve the career savegame XML file handle
    local xmlFile = nil
    if g_currentMission ~= nil and g_currentMission.missionInfo ~= nil then
        xmlFile = g_currentMission.missionInfo.xmlFile
    end
    if xmlFile == nil then
        csLog("SaveLoadHandler: no xmlFile available — skipping load (fresh game)")
        return
    end

    local root = "careerSavegame.cropStress"

    -- ── Field moisture & stress ──────────────────────────────
    local soilSystem     = self.manager.soilSystem
    local stressModifier = self.manager.stressModifier

    if soilSystem ~= nil then
        local i = 0
        while true do
            local key = string.format("%s.fields.field(%d)", root, i)
            local fieldId = getXMLInt(xmlFile, key .. "#id")
            if fieldId == nil then break end

            local moisture = getXMLFloat(xmlFile,  key .. "#moisture") or 0.50
            local stress   = getXMLFloat(xmlFile,  key .. "#stress")   or 0.0

            -- Only restore if field is tracked (handles map changes gracefully)
            if soilSystem.fieldData[fieldId] ~= nil then
                soilSystem.fieldData[fieldId].moisture = math.max(0.0, math.min(1.0, moisture))
                if stressModifier ~= nil then
                    stressModifier.fieldStress[fieldId] = math.max(0.0, math.min(1.0, stress))
                end
            end
            i = i + 1
        end
        csLog(string.format("SaveLoadHandler: loaded moisture/stress for %d fields", i))
    end

    -- ── HUD state ────────────────────────────────────────────
    local hud = self.manager.hudOverlay
    if hud ~= nil then
        hud.isVisible      = getXMLBool(xmlFile, root .. ".hud#visible")       or false
        hud.firstRunShown  = getXMLBool(xmlFile, root .. ".hud#firstRunShown") or false
    end

    -- ── Irrigation schedules (Phase 2) ───────────────────────
    local irrMgr = self.manager.irrigationManager
    if irrMgr ~= nil then
        local i = 0
        local restored = 0
        while true do
            local key    = string.format("%s.irrigation.system(%d)", root, i)
            local sysId  = getXMLInt(xmlFile, key .. "#id")
            if sysId == nil then break end

            local system = irrMgr.systems[sysId]
            if system ~= nil then
                -- Restore schedule
                local startHour = getXMLInt(xmlFile,    key .. "#startHour") or system.schedule.startHour
                local endHour   = getXMLInt(xmlFile,    key .. "#endHour")   or system.schedule.endHour
                local daysStr   = getXMLString(xmlFile, key .. "#activeDays")
                local wasActive = getXMLBool(xmlFile,   key .. "#isActive")  or false

                system.schedule.startHour = startHour
                system.schedule.endHour   = endHour

                if daysStr ~= nil then
                    local days = {}
                    for v in string.gmatch(daysStr, "[^,]+") do
                        table.insert(days, tonumber(v) ~= 0)
                    end
                    if #days == 7 then
                        system.schedule.activeDays = days
                    end
                end

                -- Re-activate if it was active when saved
                -- (hourlyScheduleCheck will take over on next tick,
                --  but we restore the isActive flag immediately so
                --  the HUD and dialog show correct state on load)
                if wasActive and not system.isActive then
                    irrMgr:activateSystem(sysId)
                end

                restored = restored + 1
            end
            i = i + 1
        end
        csLog(string.format("SaveLoadHandler: restored schedules for %d/%d irrigation systems", restored, i))
    end
end

function SaveLoadHandler:delete()
    self.isInitialized = false
end