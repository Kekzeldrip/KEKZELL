-- DefaultPriority.lua
-- Beispiel-APL für Fury Warrior (Platzhalter).
-- Ersetze spellIDs und Conditions mit den jeweiligen Klassen-APLs.
-- SimC-Prioritäten direkt abbilden.

local SE = Rotapop.SimEngine

-- Fury Warrior – vereinfachte Beispiel-Priorität
-- spellIDs sind Platzhalter; mit echten IDs aus WoW ersetzen.

-- 1. Recklessness (Cooldown)
SE:RegisterAction(1719, function(unitState, _)
    -- Bedingung: Berserking oder Raid-Burst-Fenster aktiv (Placeholder)
    return true
end, 10)

-- 2. Rampage (Rage-Dump, verhindert Rage-Cap)
SE:RegisterAction(184367, function(unitState, _)
    return (unitState.resources.rage or 0) >= 85
end, 20)

-- 3. Bloodthirst
SE:RegisterAction(23881, function(_, _)
    return true
end, 30)

-- 4. Whirlwind (Filler)
SE:RegisterAction(190411, function(_, _)
    return true
end, 40)
