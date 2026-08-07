-- CombatLogFix (3.3.5)
--
-- Some private-server cores occasionally stop sending
-- COMBAT_LOG_EVENT_UNFILTERED part-way through a fight: the combat log
-- "hangs" and every addon relying on it (damage meters, boss mods, dot/hot
-- trackers, etc.) goes silent until the log is reset.
--
-- This watches event flow while the player is in combat. If nothing has
-- come through for STALL_THRESHOLD seconds despite active combat, it
-- toggles LoggingCombat off/on, which forces the client to re-subscribe
-- to the server's combat log stream and clears the stall.

local CHECK_INTERVAL  = 1  -- seconds between stall checks
local STALL_THRESHOLD = 8  -- seconds without a CLEU event, while in combat, before treating it as hung
local RESET_COOLDOWN  = 10 -- minimum seconds between resets

local lastEventTime = GetTime()
local lastResetTime = 0

local fixFrame = CreateFrame("Frame", "CombatLogFixFrame", UIParent)
fixFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
fixFrame:RegisterEvent("PLAYER_REGEN_DISABLED") -- entering combat: start the stall window fresh

fixFrame:SetScript("OnEvent", function()
    lastEventTime = GetTime()
end)

local elapsed = 0
fixFrame:SetScript("OnUpdate", function(self, delta)
    elapsed = elapsed + delta
    if elapsed < CHECK_INTERVAL then
        return
    end
    elapsed = 0

    if not UnitAffectingCombat("player") then
        return
    end

    local now = GetTime()
    if now - lastEventTime < STALL_THRESHOLD then
        return
    end
    if now - lastResetTime < RESET_COOLDOWN then
        return
    end

    -- Actively in combat, but nothing has come through in a while: reset the log.
    lastResetTime = now
    lastEventTime = now
    LoggingCombat(false)
    LoggingCombat(true)
end)
