-- UI.lua
-- Minimal next-spell display and developer debug overlay for Rotapop.
--
-- Features:
--   1. Next-Spell Icon — shows the recommended spell icon with an optional
--      cooldown overlay (swipe animation).
--   2. Debug Overlay   — developer-only panel that dumps CooldownAdapter
--      outputs for all tracked spells.
--
-- No-Legacy Policy:
--   Uses only C_Spell.GetSpellTexture for icon retrieval.
--   Ref: https://warcraft.wiki.gg/wiki/API_C_Spell.GetSpellTexture
--
-- Cooldown overlay uses the standard Blizzard CooldownFrame API.
-- Ref: https://warcraft.wiki.gg/wiki/API_CooldownFrame_Set

local _, ns = ...

local UI = ns.UI
local SimEngine  = ns.SimEngine
local StateCache = ns.StateCache

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------

local ICON_SIZE        = 64
local ICON_PADDING     = 4
local DEBUG_LINE_HEIGHT = 14
local UPDATE_INTERVAL  = 0.1   -- seconds between recommendation refreshes

------------------------------------------------------------------------
-- Next-Spell Icon Frame
------------------------------------------------------------------------

local iconFrame     -- main icon button
local iconTexture   -- texture child
local iconCooldown  -- CooldownFrame child
local iconText      -- spell name FontString

--- Create the next-spell icon frame (called once on init).
local function CreateIconFrame()
    iconFrame = CreateFrame("Button", "RotapopNextSpellIcon", UIParent)
    iconFrame:SetSize(ICON_SIZE, ICON_SIZE)
    iconFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
    iconFrame:SetMovable(true)
    iconFrame:EnableMouse(true)
    iconFrame:RegisterForDrag("LeftButton")
    iconFrame:SetScript("OnDragStart", iconFrame.StartMoving)
    iconFrame:SetScript("OnDragStop", iconFrame.StopMovingOrSizing)
    iconFrame:SetClampedToScreen(true)

    -- Border
    iconFrame:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
    })

    -- Spell texture
    iconTexture = iconFrame:CreateTexture(nil, "ARTWORK")
    iconTexture:SetAllPoints()

    -- Cooldown swipe overlay
    -- Ref: https://warcraft.wiki.gg/wiki/API_CooldownFrame_Set
    iconCooldown = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
    iconCooldown:SetAllPoints()
    iconCooldown:SetDrawEdge(true)

    -- Spell name below icon
    iconText = iconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    iconText:SetPoint("TOP", iconFrame, "BOTTOM", 0, -2)
    iconText:SetWidth(ICON_SIZE * 2)
    iconText:SetText("")

    iconFrame:Hide()
end

--- Update the next-spell icon with a recommendation from SimEngine.
local function UpdateIcon()
    if not iconFrame then return end

    local rec = SimEngine:GetNextSpell()

    if not rec or not rec.spellID then
        iconFrame:Hide()
        return
    end

    -- Spell icon texture.
    -- Ref: https://warcraft.wiki.gg/wiki/API_C_Spell.GetSpellTexture
    local texture = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(rec.spellID)
    if texture then
        iconTexture:SetTexture(texture)
    else
        iconTexture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end

    -- Cooldown overlay.
    local spellState = StateCache:GetSpellState(rec.spellID)
    if spellState and spellState.cooldown and spellState.cooldown.start and spellState.cooldown.duration and spellState.cooldown.duration > 0 then
        -- Ref: https://warcraft.wiki.gg/wiki/API_CooldownFrame_Set
        CooldownFrame_Set(iconCooldown, spellState.cooldown.start, spellState.cooldown.duration, true)
    else
        CooldownFrame_Set(iconCooldown, 0, 0, false)
    end

    iconText:SetText(rec.name or "")
    iconFrame:Show()
end

------------------------------------------------------------------------
-- Debug Overlay
------------------------------------------------------------------------

local debugFrame    -- ScrollFrame container
local debugContent  -- child frame with text
local debugText     -- FontString for dump output
local debugVisible = false

--- Create the debug overlay frame (called once, lazy).
local function CreateDebugFrame()
    debugFrame = CreateFrame("ScrollFrame", "RotapopDebugOverlay", UIParent, "UIPanelScrollFrameTemplate")
    debugFrame:SetSize(420, 320)
    debugFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -80)
    debugFrame:SetMovable(true)
    debugFrame:EnableMouse(true)
    debugFrame:RegisterForDrag("LeftButton")
    debugFrame:SetScript("OnDragStart", debugFrame.StartMoving)
    debugFrame:SetScript("OnDragStop", debugFrame.StopMovingOrSizing)
    debugFrame:SetClampedToScreen(true)

    -- Background
    debugFrame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    debugFrame:SetBackdropColor(0, 0, 0, 0.85)

    -- Title
    local title = debugFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", debugFrame, "TOPLEFT", 10, -8)
    title:SetText("|cFF00FF00Rotapop|r Debug")

    -- Content child
    debugContent = CreateFrame("Frame", nil, debugFrame)
    debugContent:SetSize(400, 800)
    debugFrame:SetScrollChild(debugContent)

    debugText = debugContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    debugText:SetPoint("TOPLEFT", debugContent, "TOPLEFT", 4, -4)
    debugText:SetWidth(390)
    debugText:SetJustifyH("LEFT")
    debugText:SetText("")

    debugFrame:Hide()
end

--- Serialize a spell-state table into a human-readable string.
local function SerializeState(spellID, state)
    if not state then return tostring(spellID) .. ": <nil>\n" end

    local lines = { tostring(spellID) .. ":" }

    lines[#lines + 1] = "  isKnown=" .. tostring(state.isKnown)
    lines[#lines + 1] = "  isUsable=" .. tostring(state.isUsable)

    if state.charges then
        local c = state.charges
        lines[#lines + 1] = ("  charges: cur=%s max=%s start=%s dur=%s"):format(
            tostring(c.cur), tostring(c.max), tostring(c.start), tostring(c.duration)
        )
    end

    if state.cooldown then
        local cd = state.cooldown
        lines[#lines + 1] = ("  cooldown: start=%s dur=%s enabled=%s modRate=%s gcd=%s"):format(
            tostring(cd.start), tostring(cd.duration), tostring(cd.isEnabled),
            tostring(cd.modRate), tostring(cd.isOnGCDMaybe)
        )
    end

    if state.linkedSpells then
        lines[#lines + 1] = "  linkedSpells: (available)"
    end

    return table.concat(lines, "\n") .. "\n"
end

--- Refresh the debug overlay text with current StateCache data.
local function UpdateDebugOverlay()
    if not debugFrame or not debugVisible then return end

    local tracked = StateCache:GetTrackedSpells()
    local parts = { ("Last refresh: %.2f\n"):format(StateCache:GetLastRefreshTime()) }

    for spellID in pairs(tracked) do
        local state = StateCache:GetSpellState(spellID)
        parts[#parts + 1] = SerializeState(spellID, state)
    end

    -- Show next-spell recommendation.
    local rec = SimEngine:GetNextSpell()
    if rec then
        parts[#parts + 1] = "\n>> Next: " .. tostring(rec.name) .. " (" .. tostring(rec.spellID) .. ")"
    else
        parts[#parts + 1] = "\n>> Next: (none)"
    end

    debugText:SetText(table.concat(parts, "\n"))
end

------------------------------------------------------------------------
-- Periodic Update
------------------------------------------------------------------------

local ticker = CreateFrame("Frame")
local elapsed = 0

ticker:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + dt
    if elapsed < UPDATE_INTERVAL then return end
    elapsed = 0

    UpdateIcon()

    if debugVisible then
        UpdateDebugOverlay()
    end
end)

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------

--- Toggle the developer debug overlay.
function UI:ToggleDebugOverlay(enabled)
    if enabled == nil then
        debugVisible = not debugVisible
    else
        debugVisible = enabled
    end

    if not debugFrame then
        CreateDebugFrame()
    end

    if debugVisible then
        debugFrame:Show()
    else
        debugFrame:Hide()
    end
end

--- Initialize the UI module. Called after PLAYER_LOGIN.
function UI:Init()
    CreateIconFrame()

    -- Show debug overlay if saved preference says so.
    if ns.db and ns.db.debugOverlay then
        UI:ToggleDebugOverlay(true)
    end
end
