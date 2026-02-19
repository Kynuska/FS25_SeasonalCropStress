-- ============================================================
-- NPCIntegration.lua
-- PHASE 3 STUB — not yet implemented.
--
-- When implemented, this system will:
--   • Detect FS25_NPCFavor at runtime via g_npcFavorSystem global
--   • Register "Alex Chen, Agronomist" as an external NPC via NPCFavor API
--   • Generate consultant-specific favor types:
--       SOIL_SAMPLE      — visit a field that hasn't been inspected in 10+ days
--       IRRIGATION_CHECK — inspect an offline irrigation system
--       EMERGENCY_WATER  — irrigate a critically stressed field before sundown
--       SEASONAL_PLAN    — open the seasonal planning dialog (Phase 3+)
--
-- Integration point:
--   The global g_npcFavorSystem is set by FS25_NPCFavor v1.2+.
--   Check g_npcFavorSystem.registerExternalNPC for the registration API.
--
-- See Section 6.7 of FS25_SeasonalCropStress_ModPlan.md for full spec.
-- ============================================================

NPCIntegration = {}
NPCIntegration.__index = NPCIntegration

function NPCIntegration.new(manager)
    local self = setmetatable({}, NPCIntegration)
    self.manager = manager
    self.npcFavorActive  = false  -- set by CropStressManager:detectOptionalMods()
    self.consultantNPCId = nil
    self.isInitialized   = false
    return self
end

function NPCIntegration:initialize()
    if not self.npcFavorActive then
        self.isInitialized = true
        return
    end
    -- Phase 3: register consultant NPC via g_npcFavorSystem API
    self.isInitialized = true
end

function NPCIntegration:sendConsultantAlert(data)
    -- Phase 3: forward alert to NPC dialog system
end

function NPCIntegration:delete()
    self.isInitialized = false
end
