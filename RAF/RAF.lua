local addonName, RAF         = ...

RAF                          = RAF or {}
_G[addonName]                = RAF
local FONT_PATH_BOLD         = "Interface\\AddOns\\CompactNameplates\\Media\\font-bold.ttf"
local FONT_FLAG              = "OUTLINE"
-------------------------------------------------------
-- Saved variables
-------------------------------------------------------

RAFDB                        = RAFDB or {
    x      = 0,
    y      = 0,
    locked = false,
}

-------------------------------------------------------
-- Constants
-------------------------------------------------------

local ARENA_UNITS            = { "arena1", "arena2", "arena3" }
local frameWidth             = 110
local frameHeight            = 55

local TRINKET_SPELLS         = {
    [42292] = true,
    [59752] = true, -- Every Man for Himself (human racial)
}

local CC_BUTTON_SPELLS       = {
    [51724] = "DISORIENT",      -- Sap
    [1776]  = "DISORIENT",      -- Gouge
    [2094]  = "FEAR",           -- Blind
    [8643]  = "CONTROLLEDSTUN", -- Kidney Shot
    [1833]  = "OPENERSTUN",     -- Cheap Shot
    [44572] = "CONTROLLEDSTUN", -- Deep Freeze
    [10308] = "CONTROLLEDSTUN", -- Hammer of Justice
    [12809] = "CONTROLLEDSTUN", -- Concussion Blow
    [46968] = "CONTROLLEDSTUN", -- Shockwave
    [20252] = "CONTROLLEDSTUN", -- Intercept
    [5246]  = "FEAR",           -- Intimidating Shout
    [51722] = "DISARM",         -- Dismantle
    [676]   = "DISARM",         -- Disarm
    [1330]  = "SILENCE",        -- Garrote
    [20066] = "DISORIENT",      -- Repentance
    [61780] = "DISORIENT",      -- Polymorph
    [10326] = "FEAR",           -- Turn Evil
    [10890] = "FEAR",           -- Psychic Scream
    [7922]  = "CHARGE",         -- Charge
    [605]   = "MINDCONTROL",    -- Mind Control
}

-- DR state: DR_STATES[unitGUID][category] = { resetAt = time, stacks = n, buttonIndex = i }
local DR_STATES              = {}
local DR_RESET_TIME          = 18 -- Wrath DR reset

local spells                 = {
    [46924] = true, -- Bladestorm
    [23920] = true, -- Spell Reflection
    [31224] = true, -- Cloak of Shadows
    [45438] = true, -- Ice Block
    [642]   = true, -- Divine Shield
    [10278] = true, -- Hand of Protection
    [45479] = true, -- Icebound Fortitude
    [498]   = true, -- Divine Protection
    [19263] = true, -- Deterrence
    [19574] = true, -- Bestial Wrath
    [29574] = true, -- Innervate
    [32182] = true, -- Heroism
    [2825]  = true, -- Bloodlust
    [12472] = true, -- Icy Veins
    [49039] = true, -- Lichborne
    [48707] = true, -- Anti-Magic Shell
    [47585] = true, -- Dispersion
    [33206] = true, -- Pain Suppression
    [10060] = true, -- Power Infusion
    [26669] = true, -- Evasion
    [64205] = true, -- Divine Sacrifice
    [6940]  = true, -- Hand of Sacrifice
    [46968] = true, -- Shockwave
    [17197] = true, -- Recklessness
    [20230] = true, -- Retaliation
    [5246]  = true, -- Intimidating Shout
    [20066] = true, -- Repentance
    [10308] = true, -- Hammer of Justice
    [51713] = true, -- Shadow Dance
    [16166] = true, -- Elemental Mastery
    [50334] = true, -- Berserking
    [61336] = true, -- Survival Instincts
    [2094]  = true, -- Blind
    [19577] = true, -- Intimidation
    [51514] = true, -- Hex
    [47860] = true, -- Death Coil
    [47847] = true, -- Shadowfury
    [17928] = true, -- Howl of Terror
    [44572] = true, -- Deep Freeze
    [49560] = true, -- Death Grip
    [10890] = true, -- Psychic Scream
    [51722] = true, -- Dismantle
    [8643]  = true, -- Kidney Shot
    [5211]  = true, -- Bash
}

local DEFAULT_TRINKET_ICON   = select(3, GetSpellInfo(42292)) or "Interface\\Icons\\INV_Jewelry_TrinketPVP_01"
local HUMAN_TRINKET_SPELL_ID = 59752

local function HideDefaultArenaFrames()
    if not LoadAddOn("Blizzard_ArenaUI") then return end

    if ArenaEnemyFrames then
        ArenaEnemyFrames:UnregisterAllEvents()
        ArenaEnemyFrames:Hide()
    end

    for i = 1, 3 do
        local f = _G["ArenaEnemyFrame" .. i]
        if f then
            f:UnregisterAllEvents()
            f:Hide()
        end
        local cb = _G["ArenaEnemyFrame" .. i .. "CastingBar"]
        if cb then
            cb:UnregisterAllEvents()
            cb:Hide()
        end
    end
end

HideDefaultArenaFrames()
-------------------------------------------------------
-- Helpers
-------------------------------------------------------



local function GetDefaultTrinketIconForUnit(unit)
    local raceName, raceFile = UnitRace(unit)
    local faction            = UnitFactionGroup(unit)
    local level              = UnitLevel(unit)

    -- Human: show EMfH icon as the “default”
    if raceFile == "Human" then
        local _, _, tex = GetSpellInfo(HUMAN_TRINKET_SPELL_ID)
        if tex then return tex end
    end

    -- Non-human: faction-based medallion/necklace
    if faction == "Horde" then
        if level and level >= 80 then
            return "Interface\\Icons\\INV_Jewelry_Necklace_38"
        else
            return "Interface\\Icons\\INV_Jewelry_TrinketPVP_02"
        end
    else
        if level and level >= 80 then
            return "Interface\\Icons\\INV_Jewelry_Necklace_37"
        else
            return "Interface\\Icons\\INV_Jewelry_TrinketPVP_01"
        end
    end
end

local function IsInArena()
    local inInstance, instanceType = IsInInstance()
    return inInstance and instanceType == "arena"
end

local RAID_CLASS_COLORS = RAID_CLASS_COLORS

local function GetClassColor(unit)
    local _, class = UnitClass(unit)
    local c        = class and RAID_CLASS_COLORS[class]
    if c then
        return c.r, c.g, c.b
    end
    return 0.2, 0.2, 0.2
end

local POWER_COLORS = PowerBarColor or {}

local function GetPowerColor(unit)
    local powerType = UnitPowerType(unit)
    local color     = POWER_COLORS[powerType] or POWER_COLORS["MANA"]
    if color then
        return color.r, color.g, color.b
    end
    return 0.0, 0.0, 1.0 -- fallback: blue
end

local function GetDRColor(stacks)
    if stacks <= 1 then
        return 0.1, 1.0, 0.1 -- green
    elseif stacks == 2 then
        return 1.0, 0.9, 0.1 -- yellow
    else
        return 1.0, 0.1, 0.1 -- red
    end
end

-- DR state: DR_STATES[unitGUID][category] = { resetAt, stacks, buttonIndex, lastStart, drStart }
local function GetOrCreateDRState(unitGUID, category)
    DR_STATES[unitGUID] = DR_STATES[unitGUID] or {}
    local state         = DR_STATES[unitGUID][category]
    if not state then
        state = { resetAt = 0, stacks = 0, buttonIndex = nil, lastStart = 0, drStart = 0 }
        DR_STATES[unitGUID][category] = state
    end
    return state
end

local function StartIconTimer(frame, duration, absoluteEndTime)
    if not frame.durationText or not duration or duration <= 0 then return end

    -- absoluteEndTime is used for DR: we know the resetAt time
    if absoluteEndTime then
        frame.endTime = absoluteEndTime
    else
        frame.endTime = GetTime() + duration
    end

    frame:SetScript("OnUpdate", function(self, elapsed)
        if not self.endTime then
            self:SetScript("OnUpdate", nil)
            if self.durationText then
                self.durationText:SetText("")
            end
            return
        end

        local remaining = self.endTime - GetTime()
        if remaining <= 0 then
            self.endTime = nil
            if self.durationText then
                self.durationText:SetText("")
            end
            self:SetScript("OnUpdate", nil)
            return
        end

        local t
        if remaining > 1 then
            t = math.floor(remaining + 0.5)
        else
            t = 1
        end
        self.durationText:SetText(t)
    end)
end

-------------------------------------------------------
-- Root container & movement
-------------------------------------------------------

RAF.frame = RAF.frame or CreateFrame("Frame", addonName .. "Root", UIParent)
local root = RAF.frame

root:SetSize(frameWidth, frameHeight * #ARENA_UNITS + 8)
root:SetPoint("CENTER", UIParent, "CENTER", RAFDB.x, RAFDB.y)
root:SetMovable(true)
root:SetClampedToScreen(true)
root:EnableMouse(true)

root:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" and not RAFDB.locked and not InCombatLockdown() then
        self:StartMoving()
    end
end)

root:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" then
        self:StopMovingOrSizing()
        if not InCombatLockdown() then
            local x, y   = self:GetCenter()
            local ux, uy = UIParent:GetCenter()
            RAFDB.x      = x - ux
            RAFDB.y      = y - uy
        end
    end
end)

--root:SetScale(1.1)

-------------------------------------------------------
-- Overlay for layout editing
-------------------------------------------------------

RAF.overlay = RAF.overlay or CreateFrame("Frame", addonName .. "Overlay", root)
local overlay = RAF.overlay

overlay:SetFrameLevel(root:GetFrameLevel() + 10)
overlay:ClearAllPoints()
overlay:SetPoint("TOPLEFT", root, "TOPLEFT", -50, 10)
overlay:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 50, -10)
overlay:EnableMouse(false)

local tex = overlay.tex or overlay:CreateTexture(nil, "ARTWORK")
overlay.tex = tex
tex:SetAllPoints(overlay)
tex:SetColorTexture(0, 0, 0, 0.3)

if RAFDB.locked then
    overlay:Hide()
else
    overlay:Show()
end

overlay:EnableMouse(true)
overlay:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" and not RAFDB.locked and not InCombatLockdown() then
        root:StartMoving()
    end
end)

overlay:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" then
        root:StopMovingOrSizing()
        if not InCombatLockdown() then
            local x, y   = root:GetCenter()
            local ux, uy = UIParent:GetCenter()
            RAFDB.x      = x - ux
            RAFDB.y      = y - uy
        end
    end
end)

-------------------------------------------------------
-- Frame creation
-------------------------------------------------------

local function CreateArenaFrame(parent, index, unit)
    local f = CreateFrame("Button", addonName .. "Arena" .. index, parent, "SecureUnitButtonTemplate")
    f:SetSize(frameWidth, frameHeight)
    f.unit = unit

    if not InCombatLockdown() then
        f:SetAttribute("unit", unit)
        f:SetAttribute("type1", "target")
        f:RegisterForClicks("AnyUp")
        f:EnableMouse(true)
    end

    if index == 1 then
        f:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    else
        f:SetPoint("BOTTOMLEFT", parent.frames[index - 1], "TOPLEFT", 0, 4)
    end

    local bg = f:CreateTexture(nil, "BORDER")
    bg:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    bg:SetTexture(0, 0, 0, 0.8)
    f.bg = bg

    local border = f:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
    border:SetTexture(0, 0, 0, 0.6)
    border:Show()
    f.targetBorder = border

    local hp = CreateFrame("StatusBar", nil, f)
    hp:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    hp:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    hp:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    hp:SetHeight(frameHeight * 0.8)
    hp:SetMinMaxValues(0, 1)
    hp:SetValue(1)
    f.healthBar = hp

    local pp = CreateFrame("StatusBar", nil, f)
    pp:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    pp:SetPoint("TOPLEFT", hp, "BOTTOMLEFT", 0, -1)
    pp:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    pp:SetMinMaxValues(0, 1)
    pp:SetValue(1)
    f.powerBar = pp

    local labelFrame = CreateFrame("Frame", nil, f)
    labelFrame:SetFrameStrata("HIGH")
    labelFrame:SetFrameLevel(f:GetFrameLevel() + 5)
    labelFrame:SetAllPoints(f)

    local label = labelFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetText(index)
    label:SetPoint("CENTER", f.healthBar, "CENTER", 0, 0)
    label:SetTextColor(1, 1, 1)

    local font, size, flags = label:GetFont()
    label:SetFont(FONT_PATH_BOLD, size * 1.4, FONT_FLAG)

    f.labelFrame     = labelFrame
    f.label          = label

    local skullFrame = CreateFrame("Frame", nil, f.healthBar)
    skullFrame:SetAllPoints(f.healthBar)
    skullFrame:SetFrameStrata(labelFrame:GetFrameStrata())
    skullFrame:SetFrameLevel(labelFrame:GetFrameLevel() + 1)

    local skull = skullFrame:CreateTexture(nil, "OVERLAY")
    skull:SetSize(frameHeight * 0.5, frameHeight * 0.5)
    skull:SetPoint("CENTER", skullFrame, "CENTER", 0, 0)
    skull:SetTexture("Interface\\TARGETINGFRAME\\UI-TargetingFrame-Skull")
    skull:SetDesaturated(true)
    skull:Hide()

    f.deadIconFrame   = skullFrame
    f.deadIcon        = skull

    local trinketSize = frameHeight - 27
    local trinket     = CreateFrame("Frame", nil, f)
    trinket:SetSize(trinketSize, trinketSize)
    trinket:SetPoint("LEFT", f, "RIGHT", 4, 0)

    local tBorder = trinket:CreateTexture(nil, "BORDER")
    tBorder:SetPoint("TOPLEFT", trinket, "TOPLEFT", -1, 1)
    tBorder:SetPoint("BOTTOMRIGHT", trinket, "BOTTOMRIGHT", 1, -1)
    tBorder:SetTexture(0, 0, 0, 1)

    local tTex = trinket:CreateTexture(nil, "ARTWORK")
    tTex:SetAllPoints()
    tTex:SetTexCoord(0.1, 0.9, 0.1, 0.9)



    local tCD = CreateFrame("Cooldown", nil, trinket, "CooldownFrameTemplate")
    tCD:SetAllPoints()
    tCD.noomnicc        = true
    tCD.noCooldownCount = true
    local tTextFrame    = CreateFrame("Frame", nil, trinket)
    tTextFrame:SetAllPoints(trinket)
    tTextFrame:SetFrameStrata(trinket:GetFrameStrata())
    tTextFrame:SetFrameLevel(tCD:GetFrameLevel() + 1)

    local tDur = tTextFrame:CreateFontString(nil, "OVERLAY")
    tDur:SetPoint("CENTER", tTextFrame, "CENTER", 0, 0)
    tDur:SetFont(FONT_PATH_BOLD, 14, FONT_FLAG)
    tDur:SetText("")

    trinket.durationText = tDur
    trinket.icon         = tTex
    trinket.cd           = tCD
    trinket.cd:SetCooldown(0, 0)
    trinket:Hide()
    f.trinket = trinket

    local spellsSize = frameHeight - 27
    local spellsIcon = CreateFrame("Frame", nil, f)
    spellsIcon:SetSize(spellsSize, spellsSize)
    spellsIcon:SetPoint("RIGHT", f, "LEFT", -4, 0)

    local sBorder = spellsIcon:CreateTexture(nil, "BORDER")
    sBorder:SetPoint("TOPLEFT", spellsIcon, "TOPLEFT", -1, 1)
    sBorder:SetPoint("BOTTOMRIGHT", spellsIcon, "BOTTOMRIGHT", 1, -1)
    sBorder:SetTexture(0, 0, 0, 1)

    local sTex = spellsIcon:CreateTexture(nil, "ARTWORK")
    sTex:SetAllPoints()
    sTex:SetTexCoord(0.1, 0.9, 0.1, 0.9)



    local sCD = CreateFrame("Cooldown", nil, spellsIcon, "CooldownFrameTemplate")
    sCD:SetAllPoints()
    sCD.noomnicc        = true
    sCD.noCooldownCount = true
    local sTextFrame    = CreateFrame("Frame", nil, spellsIcon)
    sTextFrame:SetAllPoints(spellsIcon)
    sTextFrame:SetFrameStrata(spellsIcon:GetFrameStrata())
    sTextFrame:SetFrameLevel(sCD:GetFrameLevel() + 1)

    local sDur = sTextFrame:CreateFontString(nil, "OVERLAY")
    sDur:SetPoint("CENTER", sTextFrame, "CENTER", 0, 0)
    sDur:SetFont(FONT_PATH_BOLD, 14, FONT_FLAG)
    sDur:SetText("")

    spellsIcon.durationText = sDur
    spellsIcon.icon         = sTex
    spellsIcon.cd           = sCD
    spellsIcon:Hide()
    f.spellsIcon = spellsIcon

    f.ccButtons  = {}
    local ccSize = spellsSize
    local gap    = 2

    for idx = 1, 3 do
        local btn = CreateFrame("Frame", nil, f)
        btn:SetSize(ccSize, ccSize)

        if idx == 1 then
            btn:SetPoint("RIGHT", spellsIcon, "LEFT", -gap, 0)
        else
            btn:SetPoint("RIGHT", f.ccButtons[idx - 1], "LEFT", -gap, 0)
        end

        local bBorder = btn:CreateTexture(nil, "BORDER")
        bBorder:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, 1)
        bBorder:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
        bBorder:SetTexture(0, 0, 0, 1)

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)

        local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
        cd:SetAllPoints()
        cd.noomnicc        = true
        cd.noCooldownCount = true

        local textFrame    = CreateFrame("Frame", nil, btn)
        textFrame:SetAllPoints(btn)
        textFrame:SetFrameStrata(btn:GetFrameStrata())
        textFrame:SetFrameLevel(cd:GetFrameLevel() + 1)

        local dtext = textFrame:CreateFontString(nil, "OVERLAY")
        dtext:SetPoint("CENTER", textFrame, "CENTER", 0, 0)
        dtext:SetFont(FONT_PATH_BOLD, 14, FONT_FLAG)
        dtext:SetText("")

        btn.durationText = dtext

        btn.border       = bBorder
        btn.icon         = icon
        btn.cd           = cd
        btn:Hide()
        dtext:SetDrawLayer("OVERLAY", 7)
        f.ccButtons[idx] = btn
    end

    return f
end

root.frames = {}
for i, unit in ipairs(ARENA_UNITS) do
    root.frames[i] = CreateArenaFrame(root, i, unit)
end

-------------------------------------------------------
-- Spells icon & DR logic
-------------------------------------------------------

local function RAF_UpdateSpellsIconForUnitFrame(f)
    if not f.spellsIcon or not f.unit then return end

    local unit     = f.unit
    local unitGUID = UnitGUID(unit)
    if not unitGUID then return end

    local now = GetTime()

    local activeCategories = {}
    local bestSpellId, bestIcon, bestStart, bestDuration, bestRemaining

    local function handleAura(icon, duration, expirationTime, spellId)
        if not spellId then return end

        local now = GetTime() -- moved here

        if spells[spellId] and duration and duration > 0 and expirationTime then
            local remaining = expirationTime - now
            if remaining > 0 and (not bestRemaining or remaining > bestRemaining) then
                bestSpellId = spellId
                bestIcon = icon
                bestDuration = duration
                bestStart = expirationTime - duration
                bestRemaining = remaining
            end
        end

        local category = CC_BUTTON_SPELLS[spellId]
        if not category or not expirationTime or not duration or duration <= 0 then
            return
        end

        local state = GetOrCreateDRState(unitGUID, category)
        local start = expirationTime - duration

        if now > state.resetAt then
            state.stacks    = 0
            state.drStart   = 0
            state.lastStart = 0
            state.lastIcon  = nil
        end

        if start > (state.lastStart or 0) + 0.001 or start < (state.lastStart or 0) - 0.5 then
            state.stacks    = math.min((state.stacks or 0) + 1, 3)
            state.lastStart = start
            state.drStart   = now
            state.resetAt   = now + DR_RESET_TIME
        else
            state.resetAt = now + DR_RESET_TIME
        end

        state.lastIcon = icon

        activeCategories[category] = {
            icon     = icon,
            start    = start,
            duration = duration,
            stacks   = state.stacks,
        }
    end

    for i = 1, 40 do
        local name, _, icon, _, _, duration, expirationTime, _, _, _, spellId = UnitDebuff(unit, i)
        if not name then break end
        handleAura(icon, duration, expirationTime, spellId)
    end

    for i = 1, 40 do
        local name, _, icon, _, _, duration, expirationTime, _, _, _, spellId = UnitBuff(unit, i)
        if not name then break end
        handleAura(icon, duration, expirationTime, spellId)
    end

    if f.ccButtons then
        local drForUnit   = DR_STATES[unitGUID] or {}
        local usedButtons = {}

        for i, _btn in ipairs(f.ccButtons) do
            usedButtons[i] = false
        end

        for category, state in pairs(drForUnit) do
            if state.resetAt and now < state.resetAt then
                local data = activeCategories[category]
                if not data and state.lastIcon then
                    data = {
                        icon     = state.lastIcon,
                        start    = state.lastStart or 0,
                        duration = DR_RESET_TIME,
                        stacks   = state.stacks or 0,
                    }
                end

                if data then
                    local idx = state.buttonIndex
                    if not (idx and f.ccButtons[idx]) then
                        idx = nil
                        for i, btn in ipairs(f.ccButtons) do
                            if not usedButtons[i] then
                                idx = i
                                break
                            end
                        end
                        state.buttonIndex = idx
                    end

                    if idx then
                        local btn        = f.ccButtons[idx]
                        usedButtons[idx] = true

                        btn.icon:SetTexture(data.icon or "")
                        btn:Show()

                        local drDuration = math.max(0, state.resetAt - state.drStart)
                        local remaining  = math.max(0, state.resetAt - now)
                        if drDuration > 0 and remaining > 0 and state.drStart > 0 then
                            btn.cd:SetCooldown(state.drStart, drDuration)
                            StartIconTimer(btn, drDuration, state.resetAt)
                        else
                            btn.cd:SetCooldown(0, 0)
                            if btn.durationText then
                                btn.durationText:SetText("")
                            end
                        end
                        if btn.durationText then
                            local r, g, b = GetDRColor(state.stacks or 0)
                            btn.durationText:SetTextColor(r, g, b)
                        end
                    end
                end
            else
                state.buttonIndex = nil
            end
        end

        for i, btn in ipairs(f.ccButtons) do
            if not usedButtons[i] then
                btn:Hide()
                btn.timeLeft = nil
                btn:SetScript("OnUpdate", nil)
                if btn.durationText then
                    btn.durationText:SetText("")
                end
            end
        end
    end

    if bestSpellId then
        f.spellsIcon.icon:SetTexture(bestIcon or "")
        f.spellsIcon:Show()
        f.spellsIcon.cd:SetCooldown(bestStart, bestDuration)

        if f.spellsIcon.lastSpellId ~= bestSpellId or f.spellsIcon.lastStart ~= bestStart then
            StartIconTimer(f.spellsIcon, bestDuration)
            f.spellsIcon.lastSpellId = bestSpellId
            f.spellsIcon.lastStart = bestStart
        end

        if f.spellsIcon.durationText then
            f.spellsIcon.durationText:SetTextColor(1, 1, 1)
        end
    else
        f.spellsIcon:Hide()
        f.spellsIcon.lastSpellId = nil
        f.spellsIcon.lastStart = nil
    end
end

-------------------------------------------------------
-- Updating frames
-------------------------------------------------------

local function UpdateUnitFrame(f)
    local unit = f.unit

    if not IsInArena() then
        f:SetAlpha(0)
        return
    end

    if InCombatLockdown() then
        -- In combat: cannot change secure visibility, only update visuals/alpha
        if not UnitExists(unit) then
            -- Unit “gone” (stealth / out of LOS): fade frame, clear icons
            f:SetAlpha(0.2) -- or 0 for fully hidden
            if f.trinket then
                f.trinket.cd:SetCooldown(0, 0)
                f.trinket:Hide()
                if f.trinket.durationText then
                    f.trinket.durationText:SetText("")
                end
            end
            if f.spellsIcon then
                f.spellsIcon.cd:SetCooldown(0, 0)
                f.spellsIcon:Hide()
                if f.spellsIcon.durationText then
                    f.spellsIcon.durationText:SetText("")
                end
            end
            if f.ccButtons then
                for _, btn in ipairs(f.ccButtons) do
                    btn:Hide()
                    btn.timeLeft = nil
                    btn:SetScript("OnUpdate", nil)
                    if btn.durationText then
                        btn.durationText:SetText("")
                    end
                end
            end
            return
        else
            -- Unit exists in combat: make sure frame is visible via alpha
            f:SetAlpha(1)
        end
    else
        -- Out of combat: safe to actually show/hide
        if not UnitExists(unit) then
            f:SetAlpha(0)
            f:Hide()
            return
        end
        f:SetAlpha(1)
        f:Show()
    end

    local raceName, raceFile = UnitRace(unit)
    f.race                   = raceFile

    local r, g, b            = GetClassColor(unit)
    local pr, pg, pb         = GetPowerColor(unit)
    f.bg:SetTexture(0, 0, 0, 0.8)
    f.healthBar:SetStatusBarColor(r, g, b, 1)
    f.powerBar:SetStatusBarColor(pr, pg, pb, 1)

    local hp, hpMax = UnitHealth(unit), UnitHealthMax(unit)
    if hpMax and hpMax > 0 then
        f.healthBar:SetMinMaxValues(0, hpMax)
        f.healthBar:SetValue(hp)
    end

    local hp, hpMax = UnitHealth(unit), UnitHealthMax(unit)
    if hpMax and hpMax > 0 then
        f.healthBar:SetMinMaxValues(0, hpMax)
        f.healthBar:SetValue(hp)
    end

    if UnitIsDead(unit) or UnitIsGhost(unit) or hp <= 0 then
        -- Force 0 HP and show skull
        f.healthBar:SetValue(0)
        if f.deadIcon then
            f.deadIcon:Show()
        end
    else
        if f.deadIcon then
            f.deadIcon:Hide()
        end
    end

    local powerType = UnitPowerType(unit)
    local pp, ppMax = UnitPower(unit, powerType), UnitPowerMax(unit, powerType)
    if ppMax and ppMax > 0 then
        f.powerBar:SetMinMaxValues(0, ppMax)
        f.powerBar:SetValue(pp)
    end

    if UnitIsUnit("target", unit) then
        f.targetBorder:SetTexture(1, 1, 1, 0.6)
    else
        f.targetBorder:SetTexture(0, 0, 0, 0.6)
    end

    if f.trinket then
        local icon = GetDefaultTrinketIconForUnit(unit)
        f.trinket.icon:SetTexture(icon or DEFAULT_TRINKET_ICON)
        f.trinket:Show() -- NEW: always visible when unit exists
    end

    RAF_UpdateSpellsIconForUnitFrame(f)
end

function RAF:UpdateAll()
    for _, f in ipairs(root.frames) do
        UpdateUnitFrame(f)
    end
end

-------------------------------------------------------
-- Visibility & test mode
-------------------------------------------------------

RAF.testMode = RAF.testMode or false

function RAF:SetVisible(state)
    if not InCombatLockdown() then
        if state then
            root:Show()
        else
            root:Hide()
        end
    end
end

function RAF:RefreshVisibility()
    if InCombatLockdown() then
        return
    end

    if self.testMode then
        self:SetVisible(true)

        for i, f in ipairs(root.frames) do
            f:Show()
            f.bg:SetTexture(0, 0, 0, 0.8)
            f.healthBar:SetMinMaxValues(0, 100)
            f.healthBar:SetValue(80 - (i - 1) * 10)
            f.powerBar:SetMinMaxValues(0, 100)
            f.powerBar:SetValue(50 + (i - 1) * 10)
            f.healthBar:SetStatusBarColor(0.2, 0.6, 1, 1)
            f.powerBar:SetStatusBarColor(0.2, 0.6, 0.8, 1)
            f.targetBorder:Hide()

            if f.trinket then
                f.trinket.icon:SetTexture(DEFAULT_TRINKET_ICON)
                f.trinket:Show()
                f.trinket.cd:SetCooldown(0, 0)
            end

            if f.spellsIcon then
                local _, _, tex = GetSpellInfo(29574) -- Innervate
                f.spellsIcon.icon:SetTexture(tex or "")
                f.spellsIcon:Show()
                f.spellsIcon.cd:SetCooldown(GetTime() - 5, 20)
            end

            if f.ccButtons then
                local testSpells = { 6770, 1776, 1833 }
                local now        = GetTime()
                for idx, btn in ipairs(f.ccButtons) do
                    local spellId = testSpells[idx]
                    if spellId then
                        local _, _, tex = GetSpellInfo(spellId)
                        btn.icon:SetTexture(tex or "")
                        btn:Show()
                        btn.cd:SetCooldown(now - (idx * 3), 20)
                    else
                        btn:Hide()
                    end
                end
            end
        end

        return
    end

    if IsInArena() then
        self:SetVisible(true)

        for _, f in ipairs(root.frames) do
            if f.trinket then
                f.trinket.cd:SetCooldown(0, 0)
                -- do not force Show() here; UpdateUnitFrame handles per-unit visibility
            end
        end

        self:UpdateAll()
    else
        -- Clear per-unit frames
        for _, f in ipairs(root.frames) do
            if f.trinket then
                f.trinket.cd:SetCooldown(0, 0)
                f.trinket:Hide()
                if f.trinket.durationText then
                    f.trinket.durationText:SetText("")
                end
            end
            if f.spellsIcon then
                f.spellsIcon.cd:SetCooldown(0, 0)
                f.spellsIcon:Hide()
                if f.spellsIcon.durationText then
                    f.spellsIcon.durationText:SetText("")
                end
            end
            if f.ccButtons then
                for _, btn in ipairs(f.ccButtons) do
                    btn:Hide()
                    btn.timeLeft = nil
                    btn:SetScript("OnUpdate", nil)
                    if btn.durationText then
                        btn.durationText:SetText("")
                    end
                end
            end
            f:Hide()
        end

        -- NEW: clear DR state between arenas
        wipe(DR_STATES)

        self:SetVisible(false)
    end
end

-------------------------------------------------------
-- Combat log (trinkets)
-------------------------------------------------------

local function RAF_OnCombatLogEvent(...)
    local timestamp, eventType,
    srcGUID, srcName, srcFlags,
    dstGUID, dstName, dstFlags,
    spellID, spellName, spellSchool = ...

    if eventType ~= "SPELL_CAST_SUCCESS" then return end
    if not TRINKET_SPELLS[spellID] then return end

    for _, f in ipairs(root.frames) do
        if f.unit and UnitGUID(f.unit) == srcGUID and f.trinket then
            f.trinket:Show()
            f.trinket.cd:SetCooldown(GetTime(), 120)
            StartIconTimer(f.trinket, 120)
            if f.trinket.durationText then
                f.trinket.durationText:SetTextColor(1, 1, 1)
            end
        end
    end
end

-------------------------------------------------------
-- Events
-------------------------------------------------------

local ef = CreateFrame("Frame")
ef:RegisterEvent("PLAYER_LOGIN")
ef:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ef:RegisterEvent("PLAYER_ENTERING_WORLD")
ef:RegisterEvent("ARENA_OPPONENT_UPDATE")
ef:RegisterEvent("UNIT_HEALTH")
ef:RegisterEvent("UNIT_MAXHEALTH")
ef:RegisterEvent("UNIT_MANA")
ef:RegisterEvent("UNIT_RAGE")
ef:RegisterEvent("UNIT_ENERGY")
ef:RegisterEvent("UNIT_RUNIC_POWER")
ef:RegisterEvent("PLAYER_TARGET_CHANGED")
ef:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
ef:RegisterEvent("UNIT_AURA")

ef:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "PLAYER_LOGIN" then
        RAF:RefreshVisibility()

        if RAF.overlay then
            if RAFDB.locked then
                RAF.overlay:Hide()
            else
                RAF.overlay:Show()
            end
        end
    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
        RAF:RefreshVisibility()
    elseif event == "PLAYER_TARGET_CHANGED" then
        RAF:UpdateAll()
    elseif event == "ARENA_OPPONENT_UPDATE" then
        RAF:UpdateAll()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        RAF_OnCombatLogEvent(arg1, ...)
    elseif event:match("^UNIT_") and arg1 and arg1:match("^arena[1-3]$") then
        RAF:UpdateAll()
    elseif event == "UNIT_AURA" and arg1 and arg1:match("^arena[1-3]$") then
        RAF:UpdateAll()
    end
end)

-------------------------------------------------------
-- Slash commands
-------------------------------------------------------

SLASH_RAIDARENAFRAMES1 = "/raf"
SlashCmdList["RAIDARENAFRAMES"] = function(msg)
    msg = msg and msg:lower() or ""

    if msg == "test" then
        RAF.testMode = not RAF.testMode
        RAF:RefreshVisibility()
        DEFAULT_CHAT_FRAME:AddMessage("RaidArenaFrames test mode: " .. tostring(RAF.testMode), 0.4, 0.8, 1)
    elseif msg == "lock" then
        RAFDB.locked = not RAFDB.locked
        DEFAULT_CHAT_FRAME:AddMessage("RaidArenaFrames locked: " .. tostring(not RAFDB.locked), 0.4, 0.8, 1)

        if RAF.overlay then
            if RAFDB.locked then
                RAF.overlay:Hide()
            else
                RAF.overlay:Show()
            end
        end
    else
        DEFAULT_CHAT_FRAME:AddMessage("/raf test - toggle test mode", 0.4, 0.8, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/raf lock - toggle lock", 0.4, 0.8, 1)
    end
end
