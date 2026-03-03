-- StateCache.lua
-- Event-driven state cache for Rotapop.
--
-- Listens to WoW events that indicate spell/cooldown state changes and
-- invalidates or refreshes the cached spell-state via CooldownAdapter.
--
-- No-Legacy Policy:
--   Only documented C_* APIs and standard WoW events are used.
--
-- Registered Events:
--   SPELL_UPDATE_COOLDOWN    — https://warcraft.wiki.gg/wiki/SPELL_UPDATE_COOLDOWN
--   SPELL_UPDATE_CHARGES     — https://warcraft.wiki.gg/wiki/SPELL_UPDATE_CHARGES
--   UNIT_SPELLCAST_START     — https://warcraft.wiki.gg/wiki/UNIT_SPELLCAST_START
--   UNIT_SPELLCAST_SUCCEEDED — https://warcraft.wiki.gg/wiki/UNIT_SPELLCAST_SUCCEEDED
--   UNIT_POWER_UPDATE        — https://warcraft.wiki.gg/wiki/UNIT_POWER_UPDATE

local _, ns = ...

local StateCache = ns.StateCache
local CooldownAdapter = ns.CooldownAdapter

------------------------------------------------------------------------
-- Cache storage
------------------------------------------------------------------------

-- spellCache[spellID] = result of CooldownAdapter:GetSpellState(spellID)
local spellCache = {}

-- Set of spellIDs that the rotation actively tracks.
-- Populated by SimEngine when a priority list is loaded.
local trackedSpells = {}

-- Timestamp of last full cache refresh (GetTime()-based).
local lastFullRefresh = 0

------------------------------------------------------------------------
-- Internal helpers
------------------------------------------------------------------------

--- Invalidate a single spell's cached state, forcing a re-query on next access.
local function InvalidateSpell(spellID)
    spellCache[spellID] = nil
end

--- Refresh a single spell's cached state from CooldownAdapter.
local function RefreshSpell(spellID)
    if not CooldownAdapter.GetSpellState then return end
    spellCache[spellID] = CooldownAdapter:GetSpellState(spellID)
end

--- Invalidate and re-query all tracked spells.
local function RefreshAllTracked()
    for spellID in pairs(trackedSpells) do
        RefreshSpell(spellID)
    end
    lastFullRefresh = GetTime()
end

------------------------------------------------------------------------
-- Event handler
------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")

local eventHandlers = {}

--- SPELL_UPDATE_COOLDOWN
-- Fired when any spell cooldown state changes.
-- Ref: https://warcraft.wiki.gg/wiki/SPELL_UPDATE_COOLDOWN
eventHandlers["SPELL_UPDATE_COOLDOWN"] = function()
    -- Batch-refresh all tracked spells; the event does not carry a spellID.
    RefreshAllTracked()
end

--- SPELL_UPDATE_CHARGES
-- Fired when a spell's charge count changes.
-- Ref: https://warcraft.wiki.gg/wiki/SPELL_UPDATE_CHARGES
eventHandlers["SPELL_UPDATE_CHARGES"] = function()
    RefreshAllTracked()
end

--- UNIT_SPELLCAST_START
-- Fired when a unit begins casting a spell.
-- Ref: https://warcraft.wiki.gg/wiki/UNIT_SPELLCAST_START
eventHandlers["UNIT_SPELLCAST_START"] = function(unit, _, spellID)
    if unit ~= "player" then return end
    if spellID and trackedSpells[spellID] then
        RefreshSpell(spellID)
    end
end

--- UNIT_SPELLCAST_SUCCEEDED
-- Fired when a spell cast completes successfully.
-- Ref: https://warcraft.wiki.gg/wiki/UNIT_SPELLCAST_SUCCEEDED
eventHandlers["UNIT_SPELLCAST_SUCCEEDED"] = function(unit, _, spellID)
    if unit ~= "player" then return end
    -- After a successful cast, refresh all tracked spells since shared
    -- cooldowns may have triggered.
    RefreshAllTracked()
end

--- UNIT_POWER_UPDATE
-- Fired when a unit's power (mana, energy, rage, etc.) changes.
-- Ref: https://warcraft.wiki.gg/wiki/UNIT_POWER_UPDATE
eventHandlers["UNIT_POWER_UPDATE"] = function(unit)
    if unit ~= "player" then return end
    -- Power changes may affect spell usability (noMana flag).
    RefreshAllTracked()
end

--- Dispatch events to their handlers.
local function OnEvent(self, event, ...)
    local handler = eventHandlers[event]
    if handler then
        handler(...)
    end
end

eventFrame:SetScript("OnEvent", OnEvent)

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------

--- Register all events. Called once after PLAYER_LOGIN.
function StateCache:RegisterEvents()
    eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_START")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    eventFrame:RegisterEvent("UNIT_POWER_UPDATE")
end

--- Unregister all events (e.g., when the addon is disabled).
function StateCache:UnregisterEvents()
    eventFrame:UnregisterAllEvents()
end

--- Mark a spellID as tracked by the rotation.
-- SimEngine calls this when building a priority list.
function StateCache:TrackSpell(spellID)
    if not spellID then return end
    trackedSpells[spellID] = true
end

--- Remove a spellID from tracking.
function StateCache:UntrackSpell(spellID)
    if not spellID then return end
    trackedSpells[spellID] = nil
    spellCache[spellID] = nil
end

--- Bulk-set tracked spells from a list.
-- @param spellList  table — array of spellIDs, e.g. {12345, 67890, ...}
function StateCache:SetTrackedSpells(spellList)
    -- Clear only entries that are no longer needed; repopulate in one pass.
    local newTracked = {}
    if spellList then
        for _, id in ipairs(spellList) do
            newTracked[id] = true
        end
    end

    -- Remove cache entries for spells no longer tracked.
    for id in pairs(trackedSpells) do
        if not newTracked[id] then
            spellCache[id] = nil
        end
    end

    trackedSpells = newTracked
    RefreshAllTracked()
end

--- Get the cached state for a spell (lazy-refresh if missing).
-- @param spellID  number
-- @return table — same shape as CooldownAdapter:GetSpellState()
function StateCache:GetSpellState(spellID)
    if not spellID then return nil end
    if not spellCache[spellID] then
        RefreshSpell(spellID)
    end
    return spellCache[spellID]
end

--- Force a full refresh of all tracked spells.
function StateCache:ForceRefresh()
    RefreshAllTracked()
end

--- Get the set of currently tracked spellIDs (read-only view).
function StateCache:GetTrackedSpells()
    return trackedSpells
end

--- Get the timestamp of the last full cache refresh.
function StateCache:GetLastRefreshTime()
    return lastFullRefresh
end

------------------------------------------------------------------------
-- Initialization
------------------------------------------------------------------------

function StateCache:Init()
    -- Clear caches on init.
    wipe(spellCache)
    wipe(trackedSpells)
    lastFullRefresh = 0
end
