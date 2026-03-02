-- ============================================================
-- SaveLoadHandler.lua
-- Handles persistence of mod state into the FS25 career savegame.
--
-- FS25 API NOTE:
--   The xmlFile handle passed to FSCareerMissionInfo.saveToXMLFile is an
--   XMLFile OBJECT (FS25 OOP style). Use method calls:
--     xmlFile:setInt(key, val)    xmlFile:getInt(key)
--     xmlFile:setFloat(key, val)  xmlFile:getFloat(key)
--     xmlFile:setBool(key, val)   xmlFile:getBool(key)
--     xmlFile:setString(key, val) xmlFile:getString(key)
--   NOT the legacy globals setXMLInt / getXMLInt etc.
--
-- Save layout inside careerSavegame XML:
--   <cropStress>
--     <fields>
--       <field id="1" moisture="0.62" stress="0.00"/>
--       ...
--     </fields>
--     <hud visible="true" firstRunShown="true"/>
--     <irrigation>
--       <system id="42" startHour="6" endHour="10" isActive="false"
--               activeDays="1,1,1,1,1,0,0"/>
--       ...
--     </irrigation>
--   </cropStress>
-- ============================================================

SaveLoadHandler = {}
SaveLoadHandler.__index = SaveLoadHandler

local function csLog(msg)
    if g_logManager ~= nil then g_logManager:devInfo("[CropStress]", msg)
    else print("[CropStress] " .. tostring(msg)) end
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
-- xmlFile is the XMLFile OBJECT provided by FS25 (method API, not globals).
-- ============================================================
function SaveLoadHandler:saveToXMLFile(xmlFile)
    if not self.isInitialized then return end
    if xmlFile == nil then return end

    local root = "careerSavegame.cropStress"

    -- Field moisture & stress
    local soilSystem = self.manager.soilSystem
    if soilSystem ~= nil then
        local i = 0
        for fieldId, data in pairs(soilSystem.fieldData) do
            local key = string.format("%s.fields.field(%d)", root, i)
            xmlFile:setInt(   key .. "#id",       fieldId)
            xmlFile:setFloat( key .. "#moisture", data.moisture)
            xmlFile:setFloat( key .. "#stress",   self.manager.stressModifier:getStress(fieldId))
            i = i + 1
        end
    end

    -- HUD state
    local hud = self.manager.hudOverlay
    if hud ~= nil then
        xmlFile:setBool(root .. ".hud#visible",       hud.isVisible or false)
        xmlFile:setBool(root .. ".hud#firstRunShown", hud.firstRunShown or false)
    end

    -- Irrigation schedules
    local irrMgr = self.manager.irrigationManager
    if irrMgr ~= nil then
        local i = 0
        for sysId, system in pairs(irrMgr.systems) do
            local key = string.format("%s.irrigation.system(%d)", root, i)
            xmlFile:setInt(   key .. "#id",        sysId)
            xmlFile:setInt(   key .. "#startHour", system.schedule.startHour)
            xmlFile:setInt(   key .. "#endHour",   system.schedule.endHour)
            xmlFile:setBool(  key .. "#isActive",  system.isActive or false)
            local dayStrs = {}
            for _, v in ipairs(system.schedule.activeDays) do
                table.insert(dayStrs, v and "1" or "0")
            end
            xmlFile:setString(key .. "#activeDays", table.concat(dayStrs, ","))
            i = i + 1
        end
    end

    csLog("SaveLoadHandler: state saved")
end

-- ============================================================
-- LOAD
-- xmlFile is the XMLFile OBJECT on missionInfo (method API, not globals).
-- ============================================================
function SaveLoadHandler:loadFromXMLFile()
    if not self.isInitialized then return end

    local xmlFile = nil
    if g_currentMission ~= nil and g_currentMission.missionInfo ~= nil then
        xmlFile = g_currentMission.missionInfo.xmlFile
    end
    if xmlFile == nil then
        csLog("SaveLoadHandler: no xmlFile available — skipping load (fresh game)")
        return
    end

    local root = "careerSavegame.cropStress"

    -- readBool helper: nil (key absent) returns default; preserves explicit false
    local function readBool(key, default)
        local v = xmlFile:getBool(key)
        if v == nil then return default end
        return v
    end

    -- Field moisture & stress
    local soilSystem     = self.manager.soilSystem
    local stressModifier = self.manager.stressModifier
    if soilSystem ~= nil then
        local i = 0
        while true do
            local key     = string.format("%s.fields.field(%d)", root, i)
            local fieldId = xmlFile:getInt(key .. "#id")
            if fieldId == nil then break end
            local moisture = xmlFile:getFloat(key .. "#moisture") or 0.50
            local stress   = xmlFile:getFloat(key .. "#stress")   or 0.0
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

    -- HUD state
    local hud = self.manager.hudOverlay
    if hud ~= nil then
        hud.isVisible     = readBool(root .. ".hud#visible",       false)
        hud.firstRunShown = readBool(root .. ".hud#firstRunShown", false)
    end

    -- Irrigation schedules
    local irrMgr = self.manager.irrigationManager
    if irrMgr ~= nil then
        local i = 0
        local restored = 0
        while true do
            local key   = string.format("%s.irrigation.system(%d)", root, i)
            local sysId = xmlFile:getInt(key .. "#id")
            if sysId == nil then break end
            local system = irrMgr.systems[sysId]
            if system ~= nil then
                system.schedule.startHour = xmlFile:getInt(key .. "#startHour") or system.schedule.startHour
                system.schedule.endHour   = xmlFile:getInt(key .. "#endHour")   or system.schedule.endHour
                local daysStr = xmlFile:getString(key .. "#activeDays")
                if daysStr ~= nil then
                    local days = {}
                    for v in string.gmatch(daysStr, "[^,]+") do
                        table.insert(days, tonumber(v) ~= 0)
                    end
                    if #days == 7 then system.schedule.activeDays = days end
                end
                local wasActive = readBool(key .. "#isActive", false)
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