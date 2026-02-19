-- ============================================================
-- SaveLoadHandler.lua
-- Handles reading and writing all persistent mod state.
--
-- Storage strategy:
--   • Phase 1: writes a <cropStress> block inside the career savegame XML,
--     using the xmlFile handle supplied by the game's save/load callbacks.
--   • Phase 2 will migrate large field data to a sidecar file once tested.
--
-- CONSOLE COMPATIBILITY NOTE:
--   On Xbox/PS5, file system access is restricted. All save/load
--   MUST use the xmlFile handle provided by the game's save callbacks.
--   Never use io.open() for persistent data.
--
-- HOOK WIRING (in main.lua):
--   SAVE: FSCareerMissionInfo.saveToXMLFile  — receives xmlFile handle
--   LOAD: FSCareerMissionInfo.loadFromXMLFile — receives xmlFile handle
--         (NOT Mission00.onStartMission — that fires too late and has no handle)
-- ============================================================

SaveLoadHandler = {}
SaveLoadHandler.__index = SaveLoadHandler

-- XML key prefix inside the career savegame file
SaveLoadHandler.XML_ROOT_KEY = "careerSavegame.cropStress"

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
-- SAVE — called from FSCareerMissionInfo.saveToXMLFile hook
-- xmlFile handle is provided by the game — do NOT open/close it here.
-- ============================================================
function SaveLoadHandler:saveToXMLFile(xmlFile)
    if xmlFile == nil then
        csLog("SaveLoad: xmlFile is nil — save skipped")
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
            setXMLInt(xmlFile,    key .. "#id",      fieldId)
            setXMLFloat(xmlFile,  key .. "#moisture", data.moisture)
            setXMLString(xmlFile, key .. "#soilType", data.soilType or "loamy")
            i = i + 1
        end
        csLog(string.format("Saved moisture for %d fields", i))
    end

    -- Save per-field stress accumulation (skip near-zero entries)
    local stressModifier = self.manager.stressModifier
    if stressModifier ~= nil and stressModifier.fieldStress ~= nil then
        local i = 0
        for fieldId, stress in pairs(stressModifier.fieldStress) do
            if stress > 0.001 then
                local key = string.format("%s.stress(%d)", root, i)
                setXMLInt(xmlFile,   key .. "#id",    fieldId)
                setXMLFloat(xmlFile, key .. "#value", stress)
                i = i + 1
            end
        end
        csLog(string.format("Saved stress for %d fields", i))
    end

    -- Save HUD state
    local hud = self.manager.hudOverlay
    if hud ~= nil then
        local hudKey = root .. ".hud"
        setXMLBool(xmlFile, hudKey .. "#visible",       hud.isVisible)
        setXMLBool(xmlFile, hudKey .. "#firstRunShown", hud.firstRunShown)
    end

    csLog("Save complete")
end

-- ============================================================
-- LOAD — called from FSCareerMissionInfo.loadFromXMLFile hook.
-- The game supplies the xmlFile handle — do NOT open/close it here.
--
-- NOTE: main.lua must hook FSCareerMissionInfo.loadFromXMLFile
-- (not Mission00.onStartMission) so that the xmlFile handle is available.
-- ============================================================
function SaveLoadHandler:loadFromXMLFile(xmlFile)
    if xmlFile == nil then
        csLog("SaveLoad: xmlFile is nil — using defaults")
        return
    end

    local root = SaveLoadHandler.XML_ROOT_KEY

    -- Check schema version
    local version = getXMLInt(xmlFile, root .. "#version") or 0
    if version < 1 then
        csLog("SaveLoad: no cropStress data in save — using defaults")
        return
    end

    -- Load moisture per field
    local soilSystem = self.manager.soilSystem
    local loadedMoistureCount = 0
    if soilSystem ~= nil and soilSystem.fieldData ~= nil then
        local i = 0
        while true do
            local key     = string.format("%s.field(%d)", root, i)
            local fieldId = getXMLInt(xmlFile, key .. "#id")
            if fieldId == nil then break end

            local moisture = getXMLFloat(xmlFile,  key .. "#moisture") or 0.5
            local soilType = getXMLString(xmlFile, key .. "#soilType") or "loamy"

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
            local key     = string.format("%s.stress(%d)", root, i)
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
        local savedVisible  = getXMLBool(xmlFile, hudKey .. "#visible")
        local savedFirstRun = getXMLBool(xmlFile, hudKey .. "#firstRunShown")
        if savedVisible  ~= nil then hud.isVisible      = savedVisible  end
        if savedFirstRun ~= nil then hud.firstRunShown  = savedFirstRun end
    end

    csLog(string.format(
        "Load complete. Moisture: %d fields, Stress: %d fields",
        loadedMoistureCount, loadedStressCount
    ))
end

function SaveLoadHandler:delete()
    self.isInitialized = false
end