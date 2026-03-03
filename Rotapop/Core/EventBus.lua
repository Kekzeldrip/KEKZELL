-- EventBus.lua
-- Zentrale Event-Registrierung und Dispatching.
-- Entkoppelt Module voneinander; jedes Modul abonniert Events
-- über EventBus:Subscribe statt eigene Frames zu registrieren.

Rotapop = Rotapop or {}
Rotapop.EventBus = {}

local EB = Rotapop.EventBus
local subscribers = {} -- { eventName = { callback, ... } }
local frame = CreateFrame("Frame", "RotapopEventBusFrame")

--- Abonniere ein WoW-Event.
-- @param event  string   WoW-Event-Name
-- @param callback function  Wird mit (event, ...) aufgerufen
function EB:Subscribe(event, callback)
    if not subscribers[event] then
        subscribers[event] = {}
        frame:RegisterEvent(event)
    end
    table.insert(subscribers[event], callback)
end

frame:SetScript("OnEvent", function(_, event, ...)
    if subscribers[event] then
        for _, cb in ipairs(subscribers[event]) do
            cb(event, ...)
        end
    end
end)
