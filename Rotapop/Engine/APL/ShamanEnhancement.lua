-- ShamanEnhancement.lua
-- Enhancement Shaman APL
-- Portiert von SimC: shaman_enhancement.simc (midnight branch)

local SE = Rotapop.SimEngine
local SC = Rotapop.StateCache

local SPELL = {
    WINDFURY_WEAPON     = 33757,
    FLAMETONGUE_WEAPON  = 318038,
    LIGHTNING_SHIELD    = 192106,
    STORMSTRIKE         = 17364,
    WINDSTRIKE          = 115356,
    LAVA_LASH           = 60103,
    CRASH_LIGHTNING     = 187874,
    FLAME_SHOCK         = 188389,
    LIGHTNING_BOLT      = 188196,
    CHAIN_LIGHTNING     = 188443,
    TEMPEST             = 452201,
    PRIMORDIAL_STORM    = 375986,
    ASCENDANCE          = 114051,
    DOOM_WINDS          = 384352,
    SUNDERING           = 197214,
    SURGING_TOTEM       = 444995,
    VOLTAIC_BLAZE       = 468283,
    BLOOD_FURY          = 20572,
    BERSERKING          = 26297,
    FIREBLOOD           = 265221,
    ANCESTRAL_CALL      = 274738,
}

local BUFF = {
    ASCENDANCE          = 114051,
    DOOM_WINDS          = 384352,
    MAELSTROM_WEAPON    = 344179,
    CRASH_LIGHTNING     = 333964,
    WHIRLING_AIR        = 455090,
    WHIRLING_FIRE       = 455089,
    WHIRLING_EARTH      = 455091,
    HOT_HAND            = 215785,
    CONVERGING_STORMS   = 198300,
    PRIMORDIAL_STORM    = 375986,
}

local DEBUFF = {
    FLAME_SHOCK         = 188389,
    LASHING_FLAMES      = 334168,
}

for _, id in pairs(SPELL) do
    SC:Track(id)
end

-- ============================================================
-- Hilfsfunktionen — robuste Version
-- ============================================================

--- Aura-Daten sicher abrufen.
-- Versucht C_UnitAuras.GetAuraDataBySpellID,
-- fällt zurück auf AuraUtil.FindAuraByName falls nötig.
-- @param unit    string
-- @param spellID number
-- @param filter  string "HELPFUL"|"HARMFUL"
-- @return table|nil  AuraData
local function getAuraData(unit, spellID, filter)
    -- C_UnitAuras.GetAuraDataBySpellID →
    -- https://warcraft.wiki.gg/wiki/API_C_UnitAuras.GetAuraDataBySpellID
    local ok, result = pcall(
        C_UnitAuras.GetAuraDataBySpellID, unit, spellID, filter
    )
    if ok then return result end
    return nil
end

--- Prüft ob ein Buff auf "player" aktiv ist.
local function hasBuff(buffID)
    return getAuraData("player", buffID, "HELPFUL") ~= nil
end

--- Prüft ob ein Debuff auf "target" aktiv ist.
local function targetHasDebuff(debuffID)
    return getAuraData("target", debuffID, "HARMFUL") ~= nil
end

--- Verbleibende Aura-Dauer in Sekunden.
-- @param spellID number
-- @param unit    string
-- @param filter  string
-- @return number  0 wenn nicht aktiv, math.huge wenn permanent
local function getAuraRemains(spellID, unit, filter)
    unit   = unit   or "player"
    filter = filter or "HELPFUL"
    local data = getAuraData(unit, spellID, filter)
    if not data then return 0 end
    if not data.expirationTime or data.expirationTime == 0 then
        return math.huge
    end
    return math.max(0, data.expirationTime - GetTime())
end

--- Maelstrom Weapon Stacks (Buff ID 344179).
local function getMaelstromStacks()
    local data = getAuraData("player", 344179, "HELPFUL")
    return data and (data.applications or 0) or 0
end

--- Verbleibende CD-Zeit in Sekunden.
local function getCDRemains(spellID)
    local cd = C_Spell.GetSpellCooldown(spellID)
    if not cd or not cd.startTime or cd.startTime == 0 then return 0 end
    if not cd.duration or cd.duration == 0 then return 0 end
    return math.max(0, (cd.startTime + cd.duration) - GetTime())
end

--- Charge-Bruchteil (z.B. 1.8 = fast 2 Charges).
local function getChargesFractional(spellID)
    local info = C_Spell.GetSpellCharges(spellID)
    if not info then return 1 end
    if info.currentCharges >= info.maxCharges then
        return info.maxCharges
    end
    if not info.cooldownStartTime or info.cooldownDuration == 0 then
        return info.currentCharges
    end
    local elapsed  = GetTime() - info.cooldownStartTime
    local fraction = math.min(1, elapsed / info.cooldownDuration)
    return info.currentCharges + fraction
end

--- Anzahl aktiver Feinde via Nameplates.
local function getActiveEnemies()
    local count = 0
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) and UnitCanAttack("player", unit) then
            count = count + 1
        end
    end
    return math.max(1, count)
end

--- Talent aktiv via IsSpellKnown.
local function hasTalent(spellID)
    local ok, result = pcall(IsSpellKnown, spellID)
    return ok and result or false
end

-- ============================================================
-- evalList — wertet eine APL-Liste aus
-- ============================================================
local function evalList(list, unitState)
    for _, entry in ipairs(list) do
        local spellID   = entry[1]
        local condition = entry[2]

        local ready = Rotapop.CooldownAdapter:IsReady(spellID)
        if ready then
            local condMet = true
            if condition then
                local ok, result = pcall(condition, unitState)
                condMet = ok and (result == true)
            end
            if condMet then
                return spellID
            end
        end
    end
    return nil
end

-- ============================================================
-- APL Listen
-- ============================================================
local APL = {}

APL.single_sb = {
    { SPELL.PRIMORDIAL_STORM, function()
        local mw = getMaelstromStacks()
        return mw >= 9
            or (getAuraRemains(BUFF.PRIMORDIAL_STORM, "player", "HELPFUL") <= 4
                and mw >= 5)
    end },
    { SPELL.VOLTAIC_BLAZE, function()
        return getAuraRemains(DEBUFF.FLAME_SHOCK, "target", "HARMFUL") == 0
    end },
    { SPELL.LAVA_LASH, function()
        return not targetHasDebuff(DEBUFF.LASHING_FLAMES)
    end },
    { SPELL.BLOOD_FURY, function()
        return hasBuff(BUFF.ASCENDANCE) or hasBuff(BUFF.DOOM_WINDS)
    end },
    { SPELL.BERSERKING, function()
        return hasBuff(BUFF.ASCENDANCE) or hasBuff(BUFF.DOOM_WINDS)
    end },
    { SPELL.SUNDERING, function()
        return hasTalent(SPELL.SURGING_TOTEM) or hasTalent(51533)
    end },
    { SPELL.DOOM_WINDS, nil },
    { SPELL.CRASH_LIGHTNING, function()
        return not hasBuff(BUFF.CRASH_LIGHTNING) or hasTalent(390352)
    end },
    { SPELL.WINDSTRIKE, function()
        return getMaelstromStacks() > 0 and hasTalent(384444)
    end },
    { SPELL.ASCENDANCE, nil },
    { SPELL.STORMSTRIKE, function()
        return hasBuff(BUFF.DOOM_WINDS) and hasTalent(384444)
    end },
    { SPELL.TEMPEST, function()
        return getMaelstromStacks() == 10
    end },
    { SPELL.LIGHTNING_BOLT, function()
        return getMaelstromStacks() == 10
    end },
    { SPELL.STORMSTRIKE, function()
        return getChargesFractional(SPELL.STORMSTRIKE) >= 1.8
    end },
    { SPELL.LAVA_LASH, nil },
    { SPELL.STORMSTRIKE, nil },
    { SPELL.VOLTAIC_BLAZE, nil },
    { SPELL.SUNDERING, nil },
    { SPELL.LIGHTNING_BOLT, function()
        return getMaelstromStacks() >= 8
    end },
    { SPELL.CRASH_LIGHTNING, nil },
    { SPELL.LIGHTNING_BOLT, function()
        return getMaelstromStacks() >= 5
    end },
}

APL.single_totemic = {
    { SPELL.VOLTAIC_BLAZE, function()
        return getAuraRemains(DEBUFF.FLAME_SHOCK, "target", "HARMFUL") == 0
    end },
    { SPELL.SURGING_TOTEM, nil },
    { SPELL.BLOOD_FURY, function()
        return hasBuff(BUFF.ASCENDANCE) or hasBuff(BUFF.DOOM_WINDS)
    end },
    { SPELL.BERSERKING, function()
        return hasBuff(BUFF.ASCENDANCE) or hasBuff(BUFF.DOOM_WINDS)
    end },
    { SPELL.LAVA_LASH, function()
        return hasBuff(BUFF.WHIRLING_FIRE) or hasBuff(BUFF.HOT_HAND)
    end },
    { SPELL.SUNDERING, function()
        return hasTalent(SPELL.SURGING_TOTEM)
            or hasBuff(BUFF.WHIRLING_EARTH)
            or hasTalent(51533)
    end },
    { SPELL.DOOM_WINDS, nil },
    { SPELL.CRASH_LIGHTNING, function()
        return not hasBuff(BUFF.CRASH_LIGHTNING) or hasTalent(390352)
    end },
    { SPELL.PRIMORDIAL_STORM, function()
        local mw = getMaelstromStacks()
        return mw >= 10
            or (getAuraRemains(BUFF.PRIMORDIAL_STORM, "player", "HELPFUL") < 3.5
                and mw >= 5)
    end },
    { SPELL.WINDSTRIKE, function()
        return hasTalent(384444) and hasBuff(BUFF.ASCENDANCE)
    end },
    { SPELL.ASCENDANCE, function()
        return hasTalent(384444) and not hasBuff(BUFF.ASCENDANCE)
    end },
    { SPELL.CRASH_LIGHTNING, function()
        return (hasTalent(384444) and hasBuff(BUFF.DOOM_WINDS))
            or hasBuff(BUFF.ASCENDANCE)
    end },
    { SPELL.STORMSTRIKE, function()
        return hasTalent(384444) and hasBuff(BUFF.DOOM_WINDS)
    end },
    { SPELL.LIGHTNING_BOLT, function()
        local mw = getMaelstromStacks()
        return mw >= 10
            or (mw >= 5 and getCDRemains(SPELL.LAVA_LASH) > 0)
    end },
    { SPELL.CRASH_LIGHTNING, function()
        return not hasBuff(BUFF.CRASH_LIGHTNING)
    end },
    { SPELL.LAVA_LASH, nil },
    { SPELL.SUNDERING, function()
        return getCDRemains(SPELL.SURGING_TOTEM) > 25
    end },
    { SPELL.STORMSTRIKE, nil },
    { SPELL.VOLTAIC_BLAZE, nil },
    { SPELL.CRASH_LIGHTNING, nil },
    { SPELL.LIGHTNING_BOLT, function()
        return getMaelstromStacks() >= 5
    end },
}

APL.aoe = {
    { SPELL.VOLTAIC_BLAZE, function()
        return hasTalent(SPELL.SURGING_TOTEM)
            and getAuraRemains(DEBUFF.FLAME_SHOCK, "target", "HARMFUL") == 0
    end },
    { SPELL.SURGING_TOTEM, nil },
    { SPELL.ASCENDANCE, function()
        return hasTalent(384444) and not hasBuff(BUFF.ASCENDANCE)
    end },
    { SPELL.BLOOD_FURY, function()
        return hasBuff(BUFF.ASCENDANCE) or hasBuff(BUFF.DOOM_WINDS)
    end },
    { SPELL.BERSERKING, function()
        return hasBuff(BUFF.ASCENDANCE) or hasBuff(BUFF.DOOM_WINDS)
    end },
    { SPELL.SUNDERING, function()
        return hasTalent(SPELL.SURGING_TOTEM) or hasBuff(BUFF.WHIRLING_EARTH)
    end },
    { SPELL.LAVA_LASH, function()
        return hasBuff(BUFF.WHIRLING_FIRE)
    end },
    { SPELL.DOOM_WINDS, nil },
    { SPELL.CRASH_LIGHTNING, function()
        return hasTalent(384444)
            and hasBuff(BUFF.WHIRLING_AIR)
            and (hasBuff(BUFF.DOOM_WINDS) or hasBuff(BUFF.ASCENDANCE))
    end },
    { SPELL.WINDSTRIKE, function()
        return hasTalent(384444)
            and hasBuff(BUFF.WHIRLING_AIR)
            and hasBuff(BUFF.ASCENDANCE)
    end },
    { SPELL.STORMSTRIKE, function()
        return hasTalent(384444)
            and hasBuff(BUFF.WHIRLING_AIR)
            and hasBuff(BUFF.DOOM_WINDS)
    end },
    { SPELL.LAVA_LASH, function()
        return hasTalent(382033) and hasBuff(BUFF.HOT_HAND)
    end },
    { SPELL.TEMPEST, function()
        local mw = getMaelstromStacks()
        return mw >= 10
            and (not hasBuff(BUFF.ASCENDANCE) or not hasBuff(BUFF.DOOM_WINDS))
    end },
    { SPELL.PRIMORDIAL_STORM, function()
        return getMaelstromStacks() >= 10
    end },
    { SPELL.VOLTAIC_BLAZE, function()
        return hasTalent(333974)
    end },
    { SPELL.CRASH_LIGHTNING, nil },
    { SPELL.WINDSTRIKE, nil },
    { SPELL.STORMSTRIKE, function()
        return hasBuff(BUFF.DOOM_WINDS)
    end },
    { SPELL.CHAIN_LIGHTNING, function()
        local threshold = hasTalent(SPELL.SURGING_TOTEM) and 10 or 9
        return getMaelstromStacks() >= threshold
    end },
    { SPELL.SUNDERING, function()
        return hasTalent(51533)
    end },
    { SPELL.VOLTAIC_BLAZE, nil },
    { SPELL.STORMSTRIKE, function()
        local cf = getChargesFractional(SPELL.STORMSTRIKE)
        local data = getAuraData("player", BUFF.CONVERGING_STORMS, "HELPFUL")
        local csMax   = data and (data.maxStacks or 6) or 6
        local csStack = data and (data.applications or 0) or 0
        return cf >= 1.8 or csStack == csMax
    end },
    { SPELL.SUNDERING, function()
        return getCDRemains(SPELL.SURGING_TOTEM) > 25
    end },
    { SPELL.STORMSTRIKE, function()
        return not hasTalent(SPELL.SURGING_TOTEM)
    end },
    { SPELL.LAVA_LASH, nil },
    { SPELL.STORMSTRIKE, nil },
    { SPELL.CHAIN_LIGHTNING, function()
        return getMaelstromStacks() >= 5
    end },
}

-- ============================================================
-- GetNextSpell Override
-- ============================================================
function SE:GetNextSpell(unitState)
    local enemies = getActiveEnemies()

    if enemies > 1 then
        return evalList(APL.aoe, unitState)
    end

    if hasTalent(SPELL.SURGING_TOTEM) then
        return evalList(APL.single_totemic, unitState)
    else
        return evalList(APL.single_sb, unitState)
    end
end
