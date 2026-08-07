local _collectgarbage = _G.collectgarbage

ZoomGCDB = ZoomGCDB or {}
if ZoomGCDB.silent == nil then
    ZoomGCDB.silent = false
end

-- Phase metrics
local metrics = {
    load = { start = GetTime(), gc_calls = 0, gc_kb = 0 },
    world = { gc_kb = 0 },
}

SLASH_ZOOMGC1 = "/zoomgc"
SlashCmdList["ZOOMGC"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "silent" then
        ZoomGCDB.silent = true
        print("|cff00ff00[GC]|r reports silenced. Use /zoomgc verbose to re-enable.")
    elseif msg == "verbose" then
        ZoomGCDB.silent = false
        print("|cff00ff00[GC]|r reports enabled.")
    elseif msg == "status" then
        print(("|cff00ff00[GC]|r reports are currently %s."):format(ZoomGCDB.silent and "silenced" or "enabled"))
        if metrics.load.loadTime then
            print(("|cff00ff00[GC]|r Last login: %.2f kb collected in %d passes, %.2fs login phase, %.2f kb on first world enter.")
                :format(metrics.load.gc_kb / 1024, metrics.load.gc_calls or 0, metrics.load.loadTime, metrics.world.gc_kb / 1024))
        else
            print("|cff00ff00[GC]|r No metrics recorded yet this session.")
        end
    else
        print("|cff00ff00[GC]|r usage: /zoomgc silent | /zoomgc verbose | /zoomgc status")
    end
end

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

-- Safety valve: with GC fully stopped, garbage from every addon's load
-- piles up uncollected with no bound until PLAYER_LOGIN. On a heavy addon
-- set that's an open-loop memory-growth risk on a 32-bit client. Cap it: if
-- accumulated memory crosses this threshold mid-load, force one incremental
-- collect instead of continuing to grow unbounded, then keep going.
local MEMORY_SAFETY_THRESHOLD_KB = 300 * 1024 -- 300 MB

local frame = CreateFrame("Frame")

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

frame:SetScript("OnEvent", function(self, event)
    if event == "ADDON_LOADED" then
        if _collectgarbage("count") > MEMORY_SAFETY_THRESHOLD_KB then
            DoGC("load", "collect")
        end
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("ADDON_LOADED")

        -- End of login phase: one GC pass and timing
        DoGC("load", "collect")

        metrics.load.loadTime = GetTime() - metrics.load.start

        if not ZoomGCDB.silent then
            ChatFrame1:AddMessage((
                "|cff00ff00[GC]|r |cffffff00Load|r: " ..
                "|cff00ffff%2.2f|r kb collected in |cffffd000%d|r passes, " ..
                "login phase took |cff00ffff%2.2f|r seconds"
            ):format(metrics.load.gc_kb / 1024, metrics.load.gc_calls or 0, metrics.load.loadTime))
        end

        -- Re‑enable automatic GC for normal gameplay
        _collectgarbage("restart")
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Optional: a final GC once the world is entered
        DoGC("world", "collect")
        local footprintKB = _collectgarbage("count")

        if not ZoomGCDB.silent then
            ChatFrame1:AddMessage((
                "|cff00ff00[GC]|r |cffffff00World|r: " ..
                "|cff00ffff%2.2f|r kb collected on first enter, " ..
                "current footprint |cff00ffff%2.2f|r mb"
            ):format(metrics.world.gc_kb / 1024, footprintKB / 1024))
        end

        self:SetScript("OnEvent", nil)
        self:UnregisterAllEvents()
    end
end)
