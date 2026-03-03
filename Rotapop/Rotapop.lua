-- Rotapop.lua
-- Entry Point.

-- Dev-Flag: auf true setzen für DebugOverlay
ROTAPOP_DEBUG = false

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    -- Lookup-Tabelle initial aufbauen
    Rotapop.CooldownAdapter:RebuildLookup()

    -- Debug: Zeige wie viele Spells gemappt wurden
    if ROTAPOP_DEBUG then
        local count = 0
        for _ in pairs(Rotapop.CooldownAdapter:GetLookupTable()) do
            count = count + 1
        end
        print("|cff00ff00Rotapop|r CooldownViewer gemappt: "
            .. count .. " Spells")
    end

    print("|cff00ff00Rotapop|r loaded. Debug=" .. tostring(ROTAPOP_DEBUG))
end)
