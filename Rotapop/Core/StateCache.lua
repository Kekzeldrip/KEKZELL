-- StateCache.lua
-- Event-driven Cache über CooldownAdapter.
-- Events:
--   SPELL_UPDATE_COOLDOWN → https://warcraft.wiki.gg/wiki/SPELL_UPDATE_COOLDOWN
--   SPELL_UPDATE_CHARGES  → https://warcraft.wiki.gg/wiki/SPELL_UPDATE_CHARGES

Rotapop = Rotapop or {}
Rotapop.StateCache = {}

local SC = Rotapop.StateCache
local EB = Rotapop.EventBus

local cache = {}

SC.trackedSpells = {}

--- Registriere eine SpellID für Tracking.
function SC:Track(spellID)
    self.trackedSpells[spellID] = true
end

local function refreshSpell(spellID)
    if SC.trackedSpells[spellID] then
        cache[spellID] = Rotapop.CooldownAdapter:GetSpellState(spellID)
    end
end

local function refreshAll()
    for spellID in pairs(SC.trackedSpells) do
        cache[spellID] = Rotapop.CooldownAdapter:GetSpellState(spellID)
    end
end

--- Gibt den gecachten State zurück.
-- @param spellID number
-- @return table|nil
function SC:GetState(spellID)
    if not cache[spellID] then
        cache[spellID] = Rotapop.CooldownAdapter:GetSpellState(spellID)
    end
    return cache[spellID]
end

--- Kompletten Cache leeren.
function SC:InvalidateAll()
    cache = {}
end

-- SPELL_UPDATE_COOLDOWN → Lookup rebuild + alle invalidieren
-- https://warcraft.wiki.gg/wiki/SPELL_UPDATE_COOLDOWN
EB:Subscribe("SPELL_UPDATE_COOLDOWN", function()
    Rotapop.CooldownAdapter:RebuildLookup()
    refreshAll()
end)

-- SPELL_UPDATE_CHARGES → betroffenen Spell aktualisieren
-- https://warcraft.wiki.gg/wiki/SPELL_UPDATE_CHARGES
EB:Subscribe("SPELL_UPDATE_CHARGES", function(_, spellID)
    if spellID then
        refreshSpell(spellID)
    else
        refreshAll()
    end
end)

-- Cast-Events → vollständiger Refresh
EB:Subscribe("UNIT_SPELLCAST_START", function(_, unit)
    if unit == "player" then refreshAll() end
end)

EB:Subscribe("UNIT_SPELLCAST_SUCCEEDED", function(_, unit)
    if unit == "player" then
        C_Timer.After(0.05, function()
            Rotapop.CooldownAdapter:RebuildLookup()
            refreshAll()
        end)
    end
end)

-- Ressource-Changes können Usability ändern
EB:Subscribe("UNIT_POWER_UPDATE", function(_, unit)
    if unit == "player" then refreshAll() end
end)
