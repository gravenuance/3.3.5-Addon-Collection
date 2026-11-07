----------------------------------------------------
-- Interrupt Bar by Kollektiv (refactored)
----------------------------------------------------

-- SavedVariables
InterruptBarDB = InterruptBarDB or {
    scale  = 1,
    hidden = false,
    lock   = false,
}

----------------------------------------------------
-- Locals & upvalues
----------------------------------------------------

local GetTime       = GetTime
local GetSpellInfo  = GetSpellInfo
local floor         = floor
local band          = bit.band
local ipairs        = ipairs
local pairs         = pairs
local tinsert       = tinsert
local gmatch        = string.gmatch

local frame
local bar

local BUTTON_SIZE   = 30
local BUTTON_SPACING = 30
local BUTTON_START_X -- computed below, once the number of tracked abilities is known
local UPDATE_INTERVAL = 0.25

-- spellID -> cooldown
local spellDurations = {
    [72]    = 12,  -- Shield Bash
    [6552]  = 10,  -- Pummel
    [2139]  = 24,  -- Counterspell
    [19647] = 24,  -- Spell Lock
    [16979] = 15,  -- Feral Charge
    [1766]  = 10,  -- Kick
    [47528] = 10,  -- Mind Freeze
    [5211]  = 60,  -- Bash
    [15487] = 45,  -- Silence
    [64044] = 120, -- Psychic Horror
    [34490] = 20,  -- Silencing Shot
    [47476] = 120, -- Strangulate
    [20066] = 60,  -- Repentance
    [853]   = 60,  -- Hammer of Justice
}

local abilities = {}

-- Order is expressed as spellIDs first, then resolved to localized names
local order = {
    72, 6552, 2139, 19647,
    1766, 47528, 16979, 5211,
    64044, 15487, 34490, 47476,
    20066, 853,
}

----------------------------------------------------
-- Ability data initialization
----------------------------------------------------

do
    for spellID, duration in pairs(spellDurations) do
        local name, _, icon = GetSpellInfo(spellID)
        if name then
            abilities[name] = {
                icon     = icon,
                duration = duration,
            }
        end
    end

    local resolvedOrder = {}
    for _, spellID in ipairs(order) do
        local spellName = GetSpellInfo(spellID)
        if spellName then
            tinsert(resolvedOrder, spellName)
        end
    end
    order = resolvedOrder

    -- Center the icon row on the bar and size the bar to match, so the
    -- whole visible row (not just its leftmost few icons) is draggable.
    BUTTON_START_X = -(#order - 1) * BUTTON_SPACING / 2
end

----------------------------------------------------
-- Active timers
----------------------------------------------------

local activetimers = {}
local timerCount   = 0

local function ReanchorActiveTimers()
    if not InterruptBarDB.hidden then
        return
    end

    local x = BUTTON_START_X
    for _, ref in pairs(activetimers) do
        ref:SetPoint("CENTER", bar, "CENTER", x, 0)
        x = x + BUTTON_SPACING
    end
end

----------------------------------------------------
-- UI creation
----------------------------------------------------

local function InterruptBar_AddIcons()
    local x = BUTTON_START_X

    for _, abilityName in ipairs(order) do
        local info = abilities[abilityName]
        if info then
            local btn = CreateFrame("Frame", nil, bar)
            btn:SetWidth(BUTTON_SIZE)
            btn:SetHeight(BUTTON_SIZE)
            btn:SetPoint("CENTER", bar, "CENTER", x, 0)
            btn:SetFrameStrata("LOW")

            local cd = CreateFrame("Cooldown", nil, btn)
            cd.noomnicc        = true
            cd.noCooldownCount = true
            cd:SetAllPoints(true)
            cd:SetFrameStrata("MEDIUM")
            cd:Hide()

            local texture = btn:CreateTexture(nil, "BACKGROUND")
            texture:SetAllPoints(true)
            texture:SetTexture(info.icon)
            texture:SetTexCoord(0.07, 0.9, 0.07, 0.90)

            local text = cd:CreateFontString(nil, "ARTWORK")
            text:SetFont(STANDARD_TEXT_FONT, 18, "OUTLINE")
            text:SetTextColor(1, 1, 0, 1)
            text:SetPoint("LEFT", btn, "LEFT", 2, 0)

            btn.texture  = texture
            btn.text     = text
            btn.duration = info.duration
            btn.cd       = cd
            btn.homeX    = x

            bar[abilityName] = btn
            x = x + BUTTON_SPACING
        end
    end
end

local function InterruptBar_SavePosition()
    local point, _, relativePoint, xOfs, yOfs = bar:GetPoint()
    InterruptBarDB.Position = InterruptBarDB.Position or {}
    InterruptBarDB.Position.point         = point
    InterruptBarDB.Position.relativePoint = relativePoint
    InterruptBarDB.Position.xOfs          = xOfs
    InterruptBarDB.Position.yOfs          = yOfs
end

local function InterruptBar_LoadPosition()
    bar:ClearAllPoints()
    if InterruptBarDB.Position then
        bar:SetPoint(
            InterruptBarDB.Position.point,
            UIParent,
            InterruptBarDB.Position.relativePoint,
            InterruptBarDB.Position.xOfs,
            InterruptBarDB.Position.yOfs
        )
    else
        bar:SetPoint("CENTER", UIParent, "CENTER")
    end
end

local function InterruptBar_UpdateBar()
    bar:SetScale(InterruptBarDB.scale or 1)

    if InterruptBarDB.hidden then
        for _, abilityName in ipairs(order) do
            local btn = bar[abilityName]
            if btn then
                if activetimers[abilityName] then btn:Show() else btn:Hide() end
            end
        end
        ReanchorActiveTimers()
    else
        for _, abilityName in ipairs(order) do
            local btn = bar[abilityName]
            if btn then
                btn:Show()
                btn:SetPoint("CENTER", bar, "CENTER", btn.homeX, 0)
            end
        end
    end

    bar:EnableMouse(not InterruptBarDB.lock)
end

local function InterruptBar_CreateBar()
    bar = CreateFrame("Frame", nil, UIParent)
    bar:SetMovable(true)
    bar:SetWidth(BUTTON_SPACING * #order)
    bar:SetHeight(BUTTON_SIZE)
    bar:SetClampedToScreen(true)

    bar:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and not InterruptBarDB.lock then
            self:StartMoving()
        end
    end)

    bar:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            self:StopMovingOrSizing()
            InterruptBar_SavePosition()
        end
    end)

    bar:Show()

    InterruptBar_AddIcons()
    InterruptBar_UpdateBar()
    InterruptBar_LoadPosition()
end

----------------------------------------------------
-- Timer helpers
----------------------------------------------------

local function InterruptBar_UpdateText(text, cooldown)
    if cooldown < 10 then
        if cooldown <= 0.5 then
            text:SetText("")
        else
            text:SetFormattedText(" %d", cooldown)
        end
    else
        text:SetFormattedText("%d", cooldown)
    end

    if cooldown < 6 then
        text:SetTextColor(1, 0, 0, 1)
    else
        text:SetTextColor(1, 1, 0, 1)
    end
end

local function InterruptBar_StopAbility(ref, abilityName)
    if InterruptBarDB.hidden then
        ref:Hide()
    end

    if activetimers[abilityName] then
        activetimers[abilityName] = nil
        timerCount = timerCount - 1
        if timerCount < 0 then timerCount = 0 end
    end

    if InterruptBarDB.hidden then
        ReanchorActiveTimers()
    end

    ref.text:SetText("")
    ref.cd:Hide()
end

local elapsedAccumulator = 0

local function InterruptBar_OnUpdate(self, elapsed)
    elapsedAccumulator = elapsedAccumulator + elapsed
    if elapsedAccumulator < UPDATE_INTERVAL then
        return
    end

    for abilityName, ref in pairs(activetimers) do
        local remaining = ref.start + ref.duration - GetTime()
        ref.cooldown = remaining

        if remaining <= 0 then
            InterruptBar_StopAbility(ref, abilityName)
        else
            InterruptBar_UpdateText(ref.text, floor(remaining + 0.5))
        end
    end

    if timerCount == 0 then
        frame:SetScript("OnUpdate", nil)
    end

    elapsedAccumulator = elapsedAccumulator - UPDATE_INTERVAL
end

local function InterruptBar_StartTimer(ref, abilityName)
    if InterruptBarDB.hidden then
        ref:Show()
    end

    if not activetimers[abilityName] then
        activetimers[abilityName] = ref
        timerCount = timerCount + 1

        if InterruptBarDB.hidden then
            ReanchorActiveTimers()
        end

        ref.cd:Show()
        ref.cd:SetCooldown(GetTime() - 0.40, ref.duration)
        ref.start = GetTime()
        InterruptBar_UpdateText(ref.text, ref.duration)
    end

    frame:SetScript("OnUpdate", InterruptBar_OnUpdate)
end

----------------------------------------------------
-- Combat log handling
----------------------------------------------------

local function InterruptBar_COMBAT_LOG_EVENT_UNFILTERED(...)
    local spellID, abilityName, useSecondDuration

    -- 3.3.5 CLEU args (verified against Blizzard's shipped 3.3.5 client source,
    -- Blizzard_CombatLog.lua): timestamp, event, sourceGUID, sourceName,
    -- sourceFlags, destGUID, destName, destFlags, spellId, ... - no hideCaster
    -- (added 4.1.0) and no source/destRaidFlags (added 4.2.0) in this client.
    return function(_, eventtype, _, srcName, srcFlags, _, dstName, dstFlags, id)
        if (band(srcFlags, 0x00000040) == 0x00000040 and eventtype == "SPELL_CAST_SUCCESS") then
            spellID = id
        else
            return
        end

        useSecondDuration = false

        -- Feral Charge - Cat -> Feral Charge - Bear
        if spellID == 49376 then
            spellID = 16979
            useSecondDuration = true
        end

        abilityName = GetSpellInfo(spellID)

        if abilities[abilityName] then
            if spellID == 16979 then
                if useSecondDuration then
                    bar[abilityName].duration = 30
                else
                    bar[abilityName].duration = 15
                end
            end

            InterruptBar_StartTimer(bar[abilityName], abilityName)
        end
    end
end

InterruptBar_COMBAT_LOG_EVENT_UNFILTERED = InterruptBar_COMBAT_LOG_EVENT_UNFILTERED()

----------------------------------------------------
-- Misc helpers
----------------------------------------------------

local function InterruptBar_ResetAllTimers()
    for _, abilityName in ipairs(order) do
        local btn = bar[abilityName]
        if btn then
            InterruptBar_StopAbility(btn, abilityName)
        end
    end
end

local function InterruptBar_PLAYER_ENTERING_WORLD(self)
    InterruptBar_ResetAllTimers()
end

local function InterruptBar_Reset()
    InterruptBarDB = {
        scale  = 1,
        hidden = false,
        lock   = false,
    }
    InterruptBar_UpdateBar()
    InterruptBar_LoadPosition()
end

local function InterruptBar_Test()
    for _, abilityName in ipairs(order) do
        local btn = bar[abilityName]
        if btn then
            btn.duration = abilities[abilityName].duration
            InterruptBar_StartTimer(btn, abilityName)
        end
    end
end

----------------------------------------------------
-- Slash commands
----------------------------------------------------

local cmdfuncs = {
    scale = function(v)
        if v and v > 0 then
            InterruptBarDB.scale = v
            InterruptBar_UpdateBar()
        else
            ChatFrame1:AddMessage("InterruptBar: scale must be > 0", 1, 0, 0)
        end
    end,

    hidden = function()
        InterruptBarDB.hidden = not InterruptBarDB.hidden
        InterruptBar_UpdateBar()
    end,

    lock = function()
        InterruptBarDB.lock = not InterruptBarDB.lock
        InterruptBar_UpdateBar()
    end,

    reset = function()
        InterruptBar_Reset()
    end,

    test = function()
        InterruptBar_Test()
    end,
}

local cmdtbl = {}

local function InterruptBar_Command(cmd)
    for i = 1, #cmdtbl do
        cmdtbl[i] = nil
    end

    for v in gmatch(cmd, "[^ ]+") do
        tinsert(cmdtbl, v)
    end

    local cb = cmdfuncs[cmdtbl[1]]
    if cb then
        local arg = tonumber(cmdtbl[2])
        cb(arg)
    else
        ChatFrame1:AddMessage("InterruptBar Options | /ib", 0, 1, 0)
        ChatFrame1:AddMessage("-- scale <value> | current: " .. tostring(InterruptBarDB.scale), 0, 1, 0)
        ChatFrame1:AddMessage("-- hidden (toggle) | current: " .. tostring(InterruptBarDB.hidden), 0, 1, 0)
        ChatFrame1:AddMessage("-- lock (toggle) | current: " .. tostring(InterruptBarDB.lock), 0, 1, 0)
        ChatFrame1:AddMessage("-- test (execute)", 0, 1, 0)
        ChatFrame1:AddMessage("-- reset (execute)", 0, 1, 0)
    end
end

----------------------------------------------------
-- Addon init & events
----------------------------------------------------

local function InterruptBar_OnLoad(self)
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

    InterruptBarDB.scale  = InterruptBarDB.scale  or 1
    InterruptBarDB.hidden = InterruptBarDB.hidden or false
    InterruptBarDB.lock   = InterruptBarDB.lock   or false

    InterruptBar_CreateBar()

    SlashCmdList["InterruptBar"] = InterruptBar_Command
    SLASH_InterruptBar1 = "/ib"

    ChatFrame1:AddMessage("Type /ib for options.", 0, 1, 0)
end

local eventhandler = {
    ["PLAYER_LOGIN"] = function(self) InterruptBar_OnLoad(self) end,
    ["PLAYER_ENTERING_WORLD"] = function(self) InterruptBar_PLAYER_ENTERING_WORLD(self) end,
    ["COMBAT_LOG_EVENT_UNFILTERED"] = function(self, ...)
        InterruptBar_COMBAT_LOG_EVENT_UNFILTERED(...)
    end,
}

local function InterruptBar_OnEvent(self, event, ...)
    local handler = eventhandler[event]
    if handler then
        handler(self, ...)
    end
end

frame = CreateFrame("Frame", nil, UIParent)
frame:SetScript("OnEvent", InterruptBar_OnEvent)
frame:RegisterEvent("PLAYER_LOGIN")
