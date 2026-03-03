-- CooldownAdapter.lua
-- Verwendet den neuen C_CooldownViewer Cooldown Manager als primäre State-Quelle.
-- Eingeführt in Patch 11.1.5:
-- https://warcraft.wiki.gg/wiki/API_C_CooldownViewer.GetCooldownViewerCooldownInfo
-- https://warcraft.wiki.gg/wiki/Category:API_C_CooldownViewer

Rotapop = Rotapop or {}
Rotapop.CooldownAdapter = {}

local CA = Rotapop.CooldownAdapter

-- Lookup-Tabelle: spellID → cooldownID
local spellToCooldownID = {}
local cooldownIDToInfo  = {}

-- Maximale Kategorie-ID die wir scannen
local MAX_CATEGORY = 20

--- Baut die Lookup-Tabelle spellID → cooldownID auf.
local function buildLookupTable()
    spellToCooldownID = {}
    cooldownIDToInfo  = {}

    for category = 1, MAX_CATEGORY do
        local set = C_CooldownViewer.GetCooldownViewerCategorySet(
            category, true
        )
        if set then
            for _, cooldownID in pairs(set) do
                local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(
                    cooldownID
                )
                if info and info.spellID then
                    spellToCooldownID[info.spellID] = cooldownID
                    cooldownIDToInfo[cooldownID]    = info

                    if info.overrideSpellID
                        and info.overrideSpellID ~= info.spellID
                    then
                        spellToCooldownID[info.overrideSpellID] = cooldownID
                    end

                    if info.linkedSpellIDs then
                        for _, linkedID in pairs(info.linkedSpellIDs) do
                            if linkedID and linkedID ~= 0 then
                                spellToCooldownID[linkedID] = cooldownID
                            end
                        end
                    end
                end
            end
        end
    end
end

--- Gibt die CooldownID für eine SpellID zurück.
local function getCooldownID(spellID)
    if not next(spellToCooldownID) then
        buildLookupTable()
    end
    return spellToCooldownID[spellID]
end

--- Gibt den rohen CooldownViewer-Info für eine SpellID zurück.
local function getRawCooldownInfo(spellID)
    local cooldownID = getCooldownID(spellID)
    if not cooldownID then return nil end
    return C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
end

-- ============================================================
-- Öffentliche API
-- ============================================================

--- Gibt den normalisierten Spell-State zurück.
-- @param spellID number
-- @return table|nil
function CA:GetSpellState(spellID)
    local spellInfo = C_Spell.GetSpellInfo(spellID)
    if not spellInfo then return nil end

    -- C_Spell.IsSpellUsable → https://warcraft.wiki.gg/wiki/API_C_Spell.IsSpellUsable
    local isUsable, _ = C_Spell.IsSpellUsable(spellID)

    local cvInfo = getRawCooldownInfo(spellID)

    -- Charges
    -- C_Spell.GetSpellCharges → https://warcraft.wiki.gg/wiki/API_C_Spell.GetSpellCharges
    local chargesInfo = C_Spell.GetSpellCharges(spellID)
    local charges
    if chargesInfo then
        charges = {
            cur      = chargesInfo.currentCharges,
            max      = chargesInfo.maxCharges,
            start    = chargesInfo.cooldownStartTime,
            duration = chargesInfo.cooldownDuration,
        }
    else
        charges = { cur = 1, max = 1, start = nil, duration = nil }
    end

    -- Cooldown
    local cooldown
    if cvInfo then
        cooldown = {
            start        = cvInfo.startTime,
            duration     = cvInfo.duration,
            isEnabled    = cvInfo.isKnown,
            isOnGCDMaybe = (
                cvInfo.startTime
                and cvInfo.startTime > 0
                and cvInfo.duration
                and cvInfo.duration <= 1.5
            ) or false,
        }
    else
        -- Fallback: C_Spell.GetSpellCooldown
        -- https://warcraft.wiki.gg/wiki/API_C_Spell.GetSpellCooldown
        local cd = C_Spell.GetSpellCooldown(spellID)
        cooldown = {
            start        = cd and cd.startTime or nil,
            duration     = cd and cd.duration  or nil,
            isEnabled    = cd and cd.isEnabled or nil,
            isOnGCDMaybe = (
                cd
                and cd.startTime
                and cd.startTime > 0
                and cd.duration
                and cd.duration <= 1.5
            ) or false,
        }
    end

    return {
        isKnown  = true,
        isUsable = isUsable or false,
        charges  = charges,
        cooldown = cooldown,
        cvInfo   = cvInfo,
    }
end

--- Ist der Spell gerade castbar?
-- @param spellID number
-- @return bool
function CA:IsReady(spellID)
    local now = GetTime()

    -- 0. Ist der Spell überhaupt castbar?
    -- C_Spell.IsSpellUsable → https://warcraft.wiki.gg/wiki/API_C_Spell.IsSpellUsable
    local isUsable, _ = C_Spell.IsSpellUsable(spellID)
    if not isUsable then return false end

    -- 1. Charges haben Vorrang
    -- C_Spell.GetSpellCharges → https://warcraft.wiki.gg/wiki/API_C_Spell.GetSpellCharges
    local chargesInfo = C_Spell.GetSpellCharges(spellID)
    if chargesInfo then
        return chargesInfo.currentCharges >= 1
    end

    -- 2. C_CooldownViewer — primäre CD-Quelle
    local cvInfo = getRawCooldownInfo(spellID)
    if cvInfo then
        if not cvInfo.isKnown then return false end
        if not cvInfo.startTime or cvInfo.startTime == 0 then return true end
        if not cvInfo.duration  or cvInfo.duration  == 0 then return true end
        -- [context sensitive] GCD ignorieren
        if cvInfo.duration <= 1.5 then return true end
        return (cvInfo.startTime + cvInfo.duration) <= now
    end

    -- 3. Fallback: C_Spell.GetSpellCooldown
    -- https://warcraft.wiki.gg/wiki/API_C_Spell.GetSpellCooldown
    local cd = C_Spell.GetSpellCooldown(spellID)
    if not cd then return false end
    if cd.isEnabled == false then return false end
    if not cd.startTime or cd.startTime == 0 then return true end
    if not cd.duration  or cd.duration  == 0 then return true end
    if cd.duration <= 1.5 then return true end

    return (cd.startTime + cd.duration) <= now
end

--- Rebuild Lookup-Tabelle.
function CA:RebuildLookup()
    buildLookupTable()
end

--- Debug: Gibt alle bekannten spellID → cooldownID Mappings zurück.
function CA:GetLookupTable()
    return spellToCooldownID
end
