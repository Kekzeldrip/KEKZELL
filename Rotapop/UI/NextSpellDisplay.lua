-- NextSpellDisplay.lua
Rotapop = Rotapop or {}
Rotapop.UI = Rotapop.UI or {}

local Display = {}
Rotapop.UI.NextSpellDisplay = Display

local frame = CreateFrame("Frame", "RotapopNextSpellFrame", UIParent)
frame:SetSize(64, 64)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

local icon = frame:CreateTexture(nil, "BACKGROUND")
icon:SetAllPoints()
icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

local cdOverlay = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
cdOverlay:SetAllPoints()

local border = frame:CreateTexture(nil, "OVERLAY")
border:SetAllPoints()
border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
border:SetBlendMode("ADD")

local function getUnitState()
    return {
        resources = {
            mana   = UnitPower("player", Enum.PowerType.Mana)   or 0,
            rage   = UnitPower("player", Enum.PowerType.Rage)   or 0,
            energy = UnitPower("player", Enum.PowerType.Energy) or 0,
        },
        buffs   = {},
        debuffs = {},
    }
end

function Display:Update()
    local ok, nextSpell = pcall(
        Rotapop.SimEngine.GetNextSpell,
        Rotapop.SimEngine,
        getUnitState()
    )

    if not ok or not nextSpell then
        icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        cdOverlay:Clear()
        return
    end

    -- Icon
    -- C_Spell.GetSpellInfo → https://warcraft.wiki.gg/wiki/API_C_Spell.GetSpellInfo
    local spellInfo = C_Spell.GetSpellInfo(nextSpell)
    if spellInfo and spellInfo.iconID then
        icon:SetTexture(spellInfo.iconID)
    end

    -- Cooldown Overlay
    local state = Rotapop.StateCache:GetState(nextSpell)
    if state
        and state.cooldown.start
        and state.cooldown.duration
        and state.cooldown.duration > 1.5  -- kein GCD-Overlay
    then
        cdOverlay:SetCooldown(state.cooldown.start, state.cooldown.duration)
    else
        cdOverlay:Clear()
    end
end

-- Ticker alle 0.1s
C_Timer.NewTicker(0.1, function()
    Display:Update()
end)

-- Nach Cast sofort updaten
-- UNIT_SPELLCAST_SUCCEEDED → https://warcraft.wiki.gg/wiki/UNIT_SPELLCAST_SUCCEEDED
Rotapop.EventBus:Subscribe("UNIT_SPELLCAST_SUCCEEDED", function(_, unit)
    if unit == "player" then
        -- Kurze Verzögerung damit CD-APIs bereits den neuen State haben
        C_Timer.After(0.05, function()
            Display:Update()
        end)
    end
end)
