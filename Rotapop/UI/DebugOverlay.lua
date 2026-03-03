-- DebugOverlay.lua
-- [DEV ONLY] Zeigt CooldownAdapter-Outputs für alle getrackten Spells.
-- Nur für Development; in Release deaktivieren via ROTAPOP_DEBUG = false.

Rotapop = Rotapop or {}
Rotapop.UI = Rotapop.UI or {}

ROTAPOP_DEBUG = ROTAPOP_DEBUG or false

local DebugOverlay = {}
Rotapop.UI.DebugOverlay = DebugOverlay

if not ROTAPOP_DEBUG then return end

local frame = CreateFrame("Frame", "RotapopDebugFrame", UIParent)
frame:SetSize(320, 400)
frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -200)
frame:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    edgeSize = 8,
    insets   = { left = 4, right = 4, top = 4, bottom = 4 },
})

local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
text:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
text:SetWidth(304)
text:SetJustifyH("LEFT")

local function formatState(spellID, state)
    if not state then
        return string.format("[%d] NOT FOUND\n", spellID)
    end
    return string.format(
        "[%d] usable=%s charges=%d/%d cdStart=%.2f cdDur=%.2f isOnGCD?=%s\n",
        spellID,
        tostring(state.isUsable),
        state.charges.cur or 0,
        state.charges.max or 0,
        state.cooldown.start    or 0,
        state.cooldown.duration or 0,
        -- [context sensitive] isOnGCDMaybe ist eine Heuristik, kein verlässliches Flag
        tostring(state.cooldown.isOnGCDMaybe)
    )
end

C_Timer.NewTicker(0.25, function()
    local lines = "=== Rotapop Debug ===\n"
    for spellID in pairs(Rotapop.StateCache.trackedSpells) do
        local state = Rotapop.StateCache:GetState(spellID)
        lines = lines .. formatState(spellID, state)
    end
    text:SetText(lines)
end)
