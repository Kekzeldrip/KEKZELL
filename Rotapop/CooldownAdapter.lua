-- CooldownAdapter.lua
-- Normalized spell-state retrieval using exclusively C_Spell.* APIs.
--
-- No-Legacy Policy:
--   This module does NOT call any legacy global APIs (GetSpellCooldown, etc.).
--   All data is sourced from the documented C_Spell namespace introduced/updated
--   in Patch 11.1.5+ and the SpellCooldownInfo struct.
--
-- API References:
--   C_Spell.GetSpellCooldown  — https://warcraft.wiki.gg/wiki/API_C_Spell.GetSpellCooldown
--   C_Spell.GetSpellCharges   — https://warcraft.wiki.gg/wiki/API_C_Spell.GetSpellCharges
--   C_Spell.IsSpellUsable     — https://warcraft.wiki.gg/wiki/API_C_Spell.IsSpellUsable
--   C_Spell.GetSpellInfo      — https://warcraft.wiki.gg/wiki/API_C_Spell.GetSpellInfo
--   SpellCooldownInfo struct   — https://warcraft.wiki.gg/wiki/Struct_SpellCooldownInfo
--   C_CooldownViewer.*        — https://warcraft.wiki.gg/wiki/Category:API_C_CooldownViewer
--                                (Optional; see note below on verification.)

local _, ns = ...

local CooldownAdapter = ns.CooldownAdapter

------------------------------------------------------------------------
-- Internal helpers
------------------------------------------------------------------------

--- Safely query C_Spell.GetSpellCooldown and return a normalized table.
-- Returns structured SpellCooldownInfo fields.
-- Ref: https://warcraft.wiki.gg/wiki/API_C_Spell.GetSpellCooldown
-- Ref: https://warcraft.wiki.gg/wiki/Struct_SpellCooldownInfo
--
-- SpellCooldownInfo fields (confirmed):
--   .startTime   (number)  — GetTime()-based start of the cooldown.
--   .duration    (number)  — Full duration of the cooldown in seconds.
--   .isEnabled   (boolean) — Whether the cooldown is actively counting.
--   .modRate     (number)  — Haste modifier on the cooldown (1 = normal).
--
-- Context-sensitive field (mark as "context sensitive"):
--   .isOnGCD     (boolean|nil) — May be present; indicates if the spell
--                                 is currently on the GCD. Reliable when
--                                 consumed together with SPELL_UPDATE_COOLDOWN.
local function QuerySpellCooldown(spellID)
    if not C_Spell or not C_Spell.GetSpellCooldown then return nil end
    local info = C_Spell.GetSpellCooldown(spellID)
    if not info then return nil end
    return {
        start     = info.startTime,
        duration  = info.duration,
        isEnabled = info.isEnabled,
        modRate   = info.modRate,
        -- "context sensitive": isOnGCD may not be populated in every context.
        -- Ref: https://warcraft.wiki.gg/wiki/Struct_SpellCooldownInfo
        isOnGCDMaybe = info.isOnGCD,
    }
end

--- Safely query C_Spell.GetSpellCharges and return a normalized table.
-- Ref: https://warcraft.wiki.gg/wiki/API_C_Spell.GetSpellCharges
--
-- Returns structured SpellChargeInfo fields:
--   .currentCharges   (number)
--   .maxCharges       (number)
--   .cooldownStartTime (number)
--   .cooldownDuration  (number)
--   .chargeModRate     (number)
local function QuerySpellCharges(spellID)
    if not C_Spell or not C_Spell.GetSpellCharges then return nil end
    local info = C_Spell.GetSpellCharges(spellID)
    if not info then return nil end
    return {
        cur      = info.currentCharges,
        max      = info.maxCharges,
        start    = info.cooldownStartTime,
        duration = info.cooldownDuration,
        modRate  = info.chargeModRate,
    }
end

--- Query whether the spell can currently be cast.
-- Ref: https://warcraft.wiki.gg/wiki/API_C_Spell.IsSpellUsable
local function QueryIsSpellUsable(spellID)
    if not C_Spell or not C_Spell.IsSpellUsable then return false end
    local usable, noMana = C_Spell.IsSpellUsable(spellID)
    return usable == true, noMana == true
end

--- Query whether the spell is known / exists in the spellbook.
-- Uses C_Spell.GetSpellInfo which returns nil for unknown spells.
-- Ref: https://warcraft.wiki.gg/wiki/API_C_Spell.GetSpellInfo
local function QueryIsSpellKnown(spellID)
    if not C_Spell or not C_Spell.GetSpellInfo then return false end
    local info = C_Spell.GetSpellInfo(spellID)
    return info ~= nil
end

------------------------------------------------------------------------
-- Optional: C_CooldownViewer integration stub
-- Ref: https://warcraft.wiki.gg/wiki/API_C_CooldownViewer.GetCooldownViewerCooldownInfo
--
-- C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID) is listed in
-- the 11.1.5 API diffs. Whether it returns meaningful values in every
-- addon context is an implementation variable and must be verified in-game
-- before being used as a production data source.
--
-- Fallback design:
--   If C_CooldownViewer data is unavailable or returns nil, we fall back
--   to the C_Spell.* queries above. This is documented as an intentional
--   fallback. Verification of C_CooldownViewer is a separate step and is
--   NOT part of this initial implementation.
------------------------------------------------------------------------

--- Attempt to retrieve linked/shared cooldown info via C_CooldownViewer.
-- Returns a list of linked spell entries or nil.
local function QueryLinkedSpells(spellID)
    -- Stub: requires in-game verification before activation.
    -- Ref: https://warcraft.wiki.gg/wiki/API_C_CooldownViewer.GetCooldownViewerCooldownInfo
    --
    -- Example future implementation:
    --   local viewerInfo = C_CooldownViewer.GetCooldownViewerCooldownInfo(spellID)
    --   if viewerInfo and viewerInfo.linkedSpells then
    --       return viewerInfo.linkedSpells
    --   end
    return nil
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------

--- GetSpellState(spellID) → normalized spell-state object.
--
-- Returns:
-- {
--   isKnown     = bool,
--   isUsable    = bool,
--   noMana      = bool,
--   charges     = { cur, max, start, duration [, modRate] } | nil,
--   cooldown    = { start, duration, isEnabled, modRate, isOnGCDMaybe } | nil,
--   linkedSpells = { ... } | nil,  -- when C_CooldownViewer data is available
-- }
--
-- All fields are sourced exclusively from C_Spell.* APIs.
-- linkedSpells may additionally use C_CooldownViewer.* after verification.
function CooldownAdapter:GetSpellState(spellID)
    if not spellID then return nil end

    local isKnown = QueryIsSpellKnown(spellID)
    local isUsable, noMana = QueryIsSpellUsable(spellID)
    local charges = QuerySpellCharges(spellID)
    local cooldown = QuerySpellCooldown(spellID)
    local linkedSpells = QueryLinkedSpells(spellID)

    return {
        isKnown      = isKnown,
        isUsable     = isUsable,
        noMana       = noMana,
        charges      = charges,      -- nil if spell has no charge mechanic
        cooldown     = cooldown,     -- nil if API unavailable
        linkedSpells = linkedSpells, -- nil until C_CooldownViewer is verified
    }
end

------------------------------------------------------------------------
-- Initialization
------------------------------------------------------------------------

function CooldownAdapter:Init()
    -- Nothing required at init time; all queries are on-demand.
    -- Future: pre-warm caches for known rotation spells if needed.
end
