-- Rotapop.lua
-- Main addon initialization & namespace setup
-- No legacy global API dependencies. All state sourced via C_* namespaces.

local addonName, ns = ...

------------------------------------------------------------------------
-- Addon Namespace
------------------------------------------------------------------------
Rotapop = Rotapop or {}
Rotapop.ns = ns

ns.addonName = addonName
ns.version = C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version") or "dev"

------------------------------------------------------------------------
-- Build Information
-- https://warcraft.wiki.gg/wiki/API_GetBuildInfo
------------------------------------------------------------------------
local buildStr, _, _, buildNum = GetBuildInfo()
ns.buildStr = buildStr
ns.buildNum = buildNum

------------------------------------------------------------------------
-- Sub-module placeholders (populated by their respective files)
------------------------------------------------------------------------
ns.CooldownAdapter = {}  -- CooldownAdapter.lua
ns.StateCache      = {}  -- StateCache.lua
ns.SimEngine       = {}  -- SimEngine.lua
ns.UI              = {}  -- UI.lua

------------------------------------------------------------------------
-- Saved-variable defaults
------------------------------------------------------------------------
local defaults = {
    global = {
        debugOverlay = false,  -- Developer debug overlay toggle
    },
}

------------------------------------------------------------------------
-- Initialization
-- Fires once when the addon is loaded by the WoW client.
------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")

initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        -- Initialise saved variables with defaults.
        RotapopDB = RotapopDB or {}
        for k, v in pairs(defaults.global) do
            if RotapopDB[k] == nil then
                RotapopDB[k] = v
            end
        end

        ns.db = RotapopDB

        -- Initialise sub-modules that need early setup.
        if ns.CooldownAdapter.Init then
            ns.CooldownAdapter:Init()
        end

        if ns.StateCache.Init then
            ns.StateCache:Init()
        end

        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        -- Modules that depend on the player being fully loaded.
        if ns.SimEngine.Init then
            ns.SimEngine:Init()
        end

        if ns.UI.Init then
            ns.UI:Init()
        end

        -- Start the event-driven state cache listeners.
        if ns.StateCache.RegisterEvents then
            ns.StateCache:RegisterEvents()
        end

        self:UnregisterEvent("PLAYER_LOGIN")

        -- Print a short load confirmation.
        -- Using print() is safe; no legacy API.
        print("|cFF00FF00Rotapop|r v" .. ns.version .. " loaded.")
    end
end)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
SLASH_ROTAPOP1 = "/rotapop"
SLASH_ROTAPOP2 = "/rp"

SlashCmdList["ROTAPOP"] = function(msg)
    local cmd = (msg or ""):lower():trim()

    if cmd == "debug" then
        ns.db.debugOverlay = not ns.db.debugOverlay
        if ns.UI.ToggleDebugOverlay then
            ns.UI:ToggleDebugOverlay(ns.db.debugOverlay)
        end
        print("|cFF00FF00Rotapop|r debug overlay: " .. (ns.db.debugOverlay and "ON" or "OFF"))

    elseif cmd == "test" then
        -- Quick developer test: print next-spell recommendation.
        if ns.SimEngine.GetNextSpell then
            local spell = ns.SimEngine:GetNextSpell()
            if spell then
                print("|cFF00FF00Rotapop|r next spell: " .. tostring(spell.name or spell.spellID))
            else
                print("|cFF00FF00Rotapop|r no recommendation available.")
            end
        end

    else
        print("|cFF00FF00Rotapop|r commands:")
        print("  /rotapop debug  — toggle debug overlay")
        print("  /rotapop test   — print next-spell recommendation")
    end
end
