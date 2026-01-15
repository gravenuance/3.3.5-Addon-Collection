local _collectgarbage = _G.collectgarbage

-- Phase metrics
local metrics = {
    load = { start = GetTime(), gc_calls = 0, gc_kb = 0 },
    world = { gc_kb = 0 },
}

-- Helper: safe GC wrapper we call explicitly
local function DoGC(phase, what, arg)
    metrics[phase].gc_calls = (metrics[phase].gc_calls or 0) + 1
    local before = _collectgarbage("count")
    local result = _collectgarbage(what, arg)
    local after = _collectgarbage("count")
    metrics[phase].gc_kb = metrics[phase].gc_kb + (before - after)
    return result
end

-- Disable automatic GC during load, but do not override _G.collectgarbage
_collectgarbage("stop")

local frame = CreateFrame("Frame")

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- End of login phase: one GC pass and timing
        DoGC("load", "collect")

        local loadTime = GetTime() - metrics.load.start
        local loadKB = metrics.load.gc_kb / 1024

        ChatFrame1:AddMessage((
            "|cff00ff00[GC]|r |cffffff00Load|r: " ..
            "|cff00ffff%2.2f|r kb collected in |cffffd000%d|r passes, " ..
            "login phase took |cff00ffff%2.2f|r seconds"
        ):format(loadKB, metrics.load.gc_calls or 0, loadTime))

        -- Re‑enable automatic GC for normal gameplay
        _collectgarbage("restart")
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Optional: a final GC once the world is entered
        local before = _collectgarbage("count")
        _collectgarbage("collect")
        local after = _collectgarbage("count")

        metrics.world.gc_kb = (before - after)

        ChatFrame1:AddMessage((
            "|cff00ff00[GC]|r |cffffff00World|r: " ..
            "|cff00ffff%2.2f|r kb collected on first enter, " ..
            "current footprint |cff00ffff%2.2f|r mb"
        ):format(metrics.world.gc_kb / 1024, after / 1024))

        self:SetScript("OnEvent", nil)
        self:UnregisterAllEvents()
    end
end)
