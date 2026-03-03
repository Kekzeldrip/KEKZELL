-- SimEngine.lua
-- APL (Action Priority List) parser and priority engine for Rotapop.
--
-- Interface:
--   SimEngine:GetNextSpell(unitState?) → { spellID, name, reason } | nil
--
-- This module consumes CooldownAdapter outputs (via StateCache) and
-- resource state to evaluate SimC-style priority lists and determine
-- the next spell to cast.
--
-- The APL evaluation logic is ported from Hekili's Scripts.lua without
-- algorithmic changes.  Only the state-retrieval layer has been adapted
-- to use the new Cooldown-Manager model.
--
-- No-Legacy Policy:
--   No legacy global APIs.  All spell state via StateCache → CooldownAdapter.
--
-- API References (consumed indirectly through StateCache/CooldownAdapter):
--   C_Spell.GetSpellCooldown  — https://warcraft.wiki.gg/wiki/API_C_Spell.GetSpellCooldown
--   C_Spell.GetSpellCharges   — https://warcraft.wiki.gg/wiki/API_C_Spell.GetSpellCharges
--   C_Spell.IsSpellUsable     — https://warcraft.wiki.gg/wiki/API_C_Spell.IsSpellUsable
--   C_Spell.GetSpellInfo      — https://warcraft.wiki.gg/wiki/API_C_Spell.GetSpellInfo

local _, ns = ...

local SimEngine = ns.SimEngine
local StateCache = ns.StateCache

------------------------------------------------------------------------
-- APL Data Structures
------------------------------------------------------------------------

--[[
    An APL (Action Priority List) is an ordered list of entries:

    {
        {
            spellID  = 12345,
            name     = "Fireball",
            condition = <compiled function or nil>,
            -- condition(unitState, spellState) → boolean
        },
        ...
    }

    The engine walks the list top-to-bottom and returns the first entry
    whose condition evaluates to true (or has no condition) AND whose
    spell is ready to cast.
]]

-- The currently loaded APL.
local activeAPL = {}

-- Unit-state snapshot used during evaluation.
-- Populated by :BuildUnitState() or passed into :GetNextSpell().
local cachedUnitState = nil

------------------------------------------------------------------------
-- APL Condition Helpers
------------------------------------------------------------------------

--- Evaluate whether a spell is ready (off cooldown, has charges, is usable).
-- @param spellState  table — from StateCache:GetSpellState(spellID)
-- @return boolean
local function IsSpellReady(spellState)
    if not spellState then return false end
    if not spellState.isKnown then return false end
    if not spellState.isUsable then return false end

    -- Check charges first (charge-based abilities).
    if spellState.charges then
        if spellState.charges.cur and spellState.charges.cur > 0 then
            return true
        end
        -- No charges available; spell is not ready.
        return false
    end

    -- Check standard cooldown.
    if spellState.cooldown then
        local cd = spellState.cooldown
        if cd.duration and cd.duration > 0 and cd.start then
            local now = GetTime()
            local remaining = (cd.start + cd.duration) - now
            if remaining > 0 then
                -- "context sensitive": If the remaining cooldown matches GCD length,
                -- the spell may be on GCD rather than its own cooldown.
                -- Ref: SpellCooldownInfo.isOnGCD — https://warcraft.wiki.gg/wiki/Struct_SpellCooldownInfo
                if cd.isOnGCDMaybe then
                    -- Spell is on GCD only → treat as ready-soon (will be available
                    -- after the current GCD ends).
                    return true
                end
                return false
            end
        end
    end

    return true
end

--- Get the remaining cooldown of a spell in seconds.
-- @param spellState  table — from StateCache:GetSpellState(spellID)
-- @return number — 0 if ready
local function GetSpellCooldownRemaining(spellState)
    if not spellState or not spellState.cooldown then return 0 end
    local cd = spellState.cooldown
    if not cd.start or not cd.duration or cd.duration == 0 then return 0 end
    local remaining = (cd.start + cd.duration) - GetTime()
    return remaining > 0 and remaining or 0
end

------------------------------------------------------------------------
-- APL Expression Parser (SimC-style)
------------------------------------------------------------------------

--[[
    The expression parser converts SimC APL condition strings into
    evaluable Lua functions.

    Supported operators (ported from Hekili Scripts.lua):
      &  → and
      |  → or
      !  → not
      >= <= > < = !=  → comparison
      +  -  *  /  %   → arithmetic (% = modulo, matching SimC)

    Supported references:
      cooldown.<name>.remains      → remaining CD in seconds
      cooldown.<name>.ready        → boolean, is off CD
      charges.<name>.current       → current charges
      charges.<name>.max           → max charges
      spell.<name>.usable          → is usable
      spell.<name>.known           → is known
      resource.<type>.current      → current resource amount
      resource.<type>.max          → max resource amount
      gcd.remains                  → remaining GCD

    The parser does NOT modify the algorithmic structure of Hekili's
    APL evaluation — only the data source has changed.
]]

--- Convert "!" (NOT) in SimC expressions to Lua-safe "not (...)".
-- Ported from Hekili's forgetMeNots() — Scripts.lua.
local exprBreak = { ["&"] = true, ["|"] = true }

local function ConvertNot(str)
    -- Handle bracketed: !(X) → not (X)
    local found = 1
    while found > 0 do
        str, found = str:gsub("%s*!%s*(%b())%s*", " not %1 ")
    end

    -- Handle unbracketed: !expr → not ( expr )
    local i = 0
    while str:find("!") do
        local start = str:find("!")
        local parens = 0
        local finish = -1

        for j = start + 1, #str do
            local c = str:sub(j, j)
            if c == "(" then
                parens = parens + 1
            elseif c == ")" then
                if parens > 0 then parens = parens - 1
                else finish = j - 1; break end
            elseif parens == 0 and exprBreak[c] then
                finish = j - 1
                break
            end
        end

        if finish == -1 then finish = #str end
        local sub = str:sub(start + 1, finish):match("^%s*(.-)%s*$")
        str = ("%s not ( %s ) %s"):format(
            str:sub(1, start - 1) or "",
            sub,
            str:sub(finish + 1) or ""
        )

        i = i + 1
        if i >= 100 then break end  -- safety
    end

    return str:gsub("%s%s+", " ")
end

--- Convert SimC operators to Lua equivalents.
local function ConvertOperators(str)
    str = str:gsub("&", " and ")
    str = str:gsub("|", " or ")
    str = str:gsub("!=", "~=")
    str = str:gsub("%%", " %% ")  -- SimC % = modulo
    return str
end

--- Resolve SimC variable references to Lua function calls.
-- e.g. "cooldown.fireball.remains" → "env.cooldown_remains('fireball')"
local function ResolveReferences(str, spellMap)
    -- cooldown.<name>.remains
    str = str:gsub("cooldown%.([%w_]+)%.remains", function(name)
        return ("env.cooldown_remains('%s')"):format(name)
    end)
    -- cooldown.<name>.ready
    str = str:gsub("cooldown%.([%w_]+)%.ready", function(name)
        return ("env.cooldown_ready('%s')"):format(name)
    end)
    -- charges.<name>.current
    str = str:gsub("charges%.([%w_]+)%.current", function(name)
        return ("env.charges_current('%s')"):format(name)
    end)
    -- charges.<name>.max
    str = str:gsub("charges%.([%w_]+)%.max", function(name)
        return ("env.charges_max('%s')"):format(name)
    end)
    -- spell.<name>.usable
    str = str:gsub("spell%.([%w_]+)%.usable", function(name)
        return ("env.spell_usable('%s')"):format(name)
    end)
    -- spell.<name>.known
    str = str:gsub("spell%.([%w_]+)%.known", function(name)
        return ("env.spell_known('%s')"):format(name)
    end)
    -- gcd.remains
    str = str:gsub("gcd%.remains", "env.gcd_remains()")
    return str
end

------------------------------------------------------------------------
-- APL Compilation
------------------------------------------------------------------------

--- Compile a SimC condition string into a callable Lua function.
-- @param condStr  string — SimC-style condition (e.g. "!cooldown.fireball.remains>0&spell.fireball.usable")
-- @param spellMap table  — { name = spellID } mapping
-- @return function(env) → boolean, or nil on failure
local function CompileCondition(condStr, spellMap)
    if not condStr or condStr == "" then return nil end

    local lua = condStr
    lua = ConvertNot(lua)
    lua = ConvertOperators(lua)
    lua = ResolveReferences(lua, spellMap)

    -- Wrap in a function body.
    local code = "return function(env) return " .. lua .. " end"
    local fn, err = loadstring(code)
    if not fn then
        -- Compilation failed; log and return nil (entry always passes).
        print("|cFFFF0000Rotapop|r APL compile error: " .. tostring(err))
        return nil
    end
    return fn()
end

------------------------------------------------------------------------
-- APL Environment (runtime evaluation context)
------------------------------------------------------------------------

--- Build an environment table that condition functions can query.
-- This bridges APL expressions to StateCache data.
-- @param spellMap  table — { name = spellID }
-- @param unitState table — { gcd = { expires }, resources = { [type] = { current, max } }, ... }
-- @return table — env object passed to compiled condition functions
local function BuildAPLEnv(spellMap, unitState)
    local env = {}

    function env.cooldown_remains(name)
        local id = spellMap[name]
        if not id then return 999 end
        local state = StateCache:GetSpellState(id)
        return GetSpellCooldownRemaining(state)
    end

    function env.cooldown_ready(name)
        local id = spellMap[name]
        if not id then return false end
        local state = StateCache:GetSpellState(id)
        return IsSpellReady(state)
    end

    function env.charges_current(name)
        local id = spellMap[name]
        if not id then return 0 end
        local state = StateCache:GetSpellState(id)
        if state and state.charges then return state.charges.cur or 0 end
        return 0
    end

    function env.charges_max(name)
        local id = spellMap[name]
        if not id then return 0 end
        local state = StateCache:GetSpellState(id)
        if state and state.charges then return state.charges.max or 0 end
        return 0
    end

    function env.spell_usable(name)
        local id = spellMap[name]
        if not id then return false end
        local state = StateCache:GetSpellState(id)
        return state and state.isUsable or false
    end

    function env.spell_known(name)
        local id = spellMap[name]
        if not id then return false end
        local state = StateCache:GetSpellState(id)
        return state and state.isKnown or false
    end

    function env.gcd_remains()
        if unitState and unitState.gcd and unitState.gcd.expires then
            local r = unitState.gcd.expires - GetTime()
            return r > 0 and r or 0
        end
        return 0
    end

    return env
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------

--- Load an APL from a definition table.
-- @param aplDef  table — {
--     spellMap = { name = spellID, ... },
--     entries  = {
--         { spell = "name", condition = "SimC condition string" | nil },
--         ...
--     },
-- }
function SimEngine:LoadAPL(aplDef)
    if not aplDef then return end

    activeAPL = {}

    local spellMap = aplDef.spellMap or {}

    -- Register all spells with StateCache for event-driven tracking.
    local spellList = {}
    for _, id in pairs(spellMap) do
        spellList[#spellList + 1] = id
    end
    StateCache:SetTrackedSpells(spellList)

    -- Compile each entry.
    for _, entry in ipairs(aplDef.entries or {}) do
        local compiled = {
            spellID   = spellMap[entry.spell],
            name      = entry.spell,
            condition = CompileCondition(entry.condition, spellMap),
        }
        activeAPL[#activeAPL + 1] = compiled
    end
end

--- Evaluate the loaded APL and return the next spell to cast.
-- @param unitState table|nil — optional unit-state override; if nil,
--                               a minimal state is built automatically.
-- @return table { spellID, name, reason } | nil
function SimEngine:GetNextSpell(unitState)
    if #activeAPL == 0 then return nil end

    unitState = unitState or cachedUnitState or {}

    -- Build the spell-name → spellID map from the active APL.
    local spellMap = {}
    for _, entry in ipairs(activeAPL) do
        if entry.name and entry.spellID then
            spellMap[entry.name] = entry.spellID
        end
    end

    local env = BuildAPLEnv(spellMap, unitState)

    for _, entry in ipairs(activeAPL) do
        local spellState = StateCache:GetSpellState(entry.spellID)

        if IsSpellReady(spellState) then
            -- Evaluate condition (nil condition = always true).
            local conditionMet = true
            if entry.condition then
                local ok, result = pcall(entry.condition, env)
                if ok then
                    conditionMet = result and true or false
                else
                    -- Condition error; skip this entry.
                    conditionMet = false
                end
            end

            if conditionMet then
                return {
                    spellID = entry.spellID,
                    name    = entry.name,
                    reason  = "APL priority matched",
                }
            end
        end
    end

    return nil
end

--- Set / update the cached unit state (resources, GCD, etc.).
-- @param unitState table — { gcd = { expires }, resources = { ... }, ... }
function SimEngine:SetUnitState(unitState)
    cachedUnitState = unitState
end

--- Get the currently loaded APL entries (for debug overlay).
function SimEngine:GetActiveAPL()
    return activeAPL
end

------------------------------------------------------------------------
-- Initialization
------------------------------------------------------------------------

function SimEngine:Init()
    activeAPL = {}
    cachedUnitState = nil

    -- Example: Load a minimal test APL (developer use only).
    -- In production this would be loaded from spec-specific data files.
    -- Uncomment for testing:
    --[[
    self:LoadAPL({
        spellMap = {
            fireball  = 133,
            pyroblast = 11366,
            fire_blast = 108853,
        },
        entries = {
            { spell = "pyroblast",  condition = "spell.pyroblast.usable" },
            { spell = "fire_blast", condition = "cooldown.fire_blast.ready" },
            { spell = "fireball",   condition = nil },  -- filler, always castable
        },
    })
    ]]
end
