-- ============================================================
-- SaveLoadHandler.lua
-- Handles reading and writing all persistent mod state.
--
-- Storage strategy:
--   • Sidecar file: {savegameDirectory}/cropStressData.xml
--     — per-field moisture, stress accumulation
--   • Player config: {savegameDirectory}/cropStressConfig.xml
--     — HUD preferences, difficulty settings (Phase 2)
--
-- CONSOLE COMPATIBILITY NOTE:
--   On Xbox/PS5, file system access is restricted. All save/load
--   MUST use the xmlFile handle provided by the game's save callbacks,
--   OR write to the savegame's own XML via setXMLInt/Float/String.
--   Never use io.open() for persistent data.
--
-- For Phase 1, we write our data block inside the career savegame XML.
-- Phase 2 will migrate large data to a sidecar file once tested on PC.
-- ============================================================

SaveLoadHandler = {}
SaveLoadHandler.__index = SaveLoadHandler

-- XML key prefix inside the career savegame file
SaveLoadHandler.XML_ROOT_KEY = "careerSavegame.cropStress"

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
-- SAVE — called from FSCareerMissionInfo.saveToXMLFile hook
-- ============================================================
function SaveLoadHandler:saveToXMLFile(xmlFile)
    if xmlFile == nil then
        g_logManager:devInfo("[CropStress]", "SaveLoad: xmlFile is nil — save skipped")
        return
    end

    local root = SaveLoadHandler.XML_ROOT_KEY

    -- Write schema version
    setXMLInt(xmlFile, root .. "#version", 1)

    -- Save per-field moisture state
    local soilSystem = self.manager.soilSystem
    if soilSystem ~= nil and soilSystem.fieldData ~= nil then
        local i = 0
        for fieldId, data in pairs(soilSystem.fieldData) do
            local key = string.format("%s.field(%d)", root, i)
            setXMLInt(xmlFile,    key .. "#id",       fieldId)
            setXMLFloat(xmlFile,  key .. "#moisture",  data.moisture)
            setXMLString(xmlFile, key .. "#soilType",  data.soilType or "loamy")
            i = i + 1
        end
        g_logManager:devInfo("[CropStress]", string.format("Saved moisture for %d fields", i))
    end

    -- Save per-field stress accumulation
    local stressModifier = self.manager.stressModifier
    if stressModifier ~= nil and stressModifier.fieldStress ~= nil then
        local i = 0
        for fieldId, stress in pairs(stressModifier.fieldStress) do
            if stress > 0.001 then  -- skip zero entries
                local key = string.format("%s.stress(%d)", root, i)
                setXMLInt(xmlFile,   key .. "#id",    fieldId)
                setXMLFloat(xmlFile, key .. "#value", stress)
                i = i + 1
            end
        end
        g_logManager:devInfo("[CropStress]", string.format("Saved stress for %d fields", i))
    end

    -- Save HUD state
    local hud = self.manager.hudOverlay
    if hud ~= nil then
        local hudKey = root .. ".hud"
        setXMLBool(xmlFile, hudKey .. "#visible",      hud.isVisible)
        setXMLBool(xmlFile, hudKey .. "#firstRunShown", hud.firstRunShown)
    end

    g_logManager:devInfo("[CropStress]", "Save complete")
end

-- ============================================================
-- LOAD — called from Mission00.onStartMission hook
-- ============================================================
function SaveLoadHandler:loadFromXMLFile()
    if g_currentMission == nil then return end
    local savegameDir = g_currentMission.missionInfo
        and g_currentMission.missionInfo.savegameDirectory

    if savegameDir == nil then
        g_logManager:devInfo("[CropStress]", "SaveLoad: no savegame directory — using defaults")
        return
    end

    -- Build path to career savegame XML
    local savePath = savegameDir .. "/careerSavegame.xml"

    -- loadXMLFile returns handle or nil
    local xmlFile = loadXMLFile("cropStressSave", savePath)
    if xmlFile == nil then
        g_logManager:devInfo("[CropStress]", "SaveLoad: careerSavegame.xml not found — fresh start")
        return
    end

    local root = SaveLoadHandler.XML_ROOT_KEY

    -- Check version
    local version = getXMLInt(xmlFile, root .. "#version") or 0
    if version < 1 then
        g_logManager:devInfo("[CropStress]", "SaveLoad: no cropStress data in save — using defaults")
        delete(xmlFile)
        return
    end

    -- Load moisture per field
    local soilSystem = self.manager.soilSystem
    local loadedMoistureCount = 0
    if soilSystem ~= nil and soilSystem.fieldData ~= nil then
        local i = 0
        while true do
            local key = string.format("%s.field(%d)", root, i)
            local fieldId = getXMLInt(xmlFile, key .. "#id")
            if fieldId == nil then break end

            local moisture = getXMLFloat(xmlFile,  key .. "#moisture")  or 0.5
            local soilType = getXMLString(xmlFile, key .. "#soilType")  or "loamy"

            if soilSystem.fieldData[fieldId] ~= nil then
                soilSystem.fieldData[fieldId].moisture = math.max(0.0, math.min(1.0, moisture))
                soilSystem.fieldData[fieldId].soilType = soilType
                loadedMoistureCount = loadedMoistureCount + 1
            end
            i = i + 1
        end
    end

    -- Load stress per field
    local stressModifier = self.manager.stressModifier
    local loadedStressCount = 0
    if stressModifier ~= nil then
        local i = 0
        while true do
            local key = string.format("%s.stress(%d)", root, i)
            local fieldId = getXMLInt(xmlFile, key .. "#id")
            if fieldId == nil then break end

            local stress = getXMLFloat(xmlFile, key .. "#value") or 0.0
            stressModifier.fieldStress[fieldId] = math.max(0.0, math.min(1.0, stress))
            loadedStressCount = loadedStressCount + 1
            i = i + 1
        end
    end

    -- Load HUD state
    local hud = self.manager.hudOverlay
    if hud ~= nil then
        local hudKey = root .. ".hud"
        local savedVisible = getXMLBool(xmlFile, hudKey .. "#visible")
        if savedVisible ~= nil then hud.isVisible = savedVisible end

        local savedFirstRun = getXMLBool(xmlFile, hudKey .. "#firstRunShown")
        if savedFirstRun ~= nil then hud.firstRunShown = savedFirstRun end
    end

    delete(xmlFile)
    g_logManager:devInfo("[CropStress]", string.format(
        "Load complete. Moisture: %d fields, Stress: %d fields",
        loadedMoistureCount, loadedStressCount
    ))
end

function SaveLoadHandler:delete()
    self.isInitialized = false
end
