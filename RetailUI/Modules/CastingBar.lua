--[[
Copyright (c) Dmitriy. All rights reserved.
Licensed under the MIT license. See LICENSE file in the project root for details.
]]

local LibStub                = LibStub
local CreateFrame            = CreateFrame
local GetTime                = GetTime
local UnitCastingInfo        = UnitCastingInfo
local UnitChannelInfo        = UnitChannelInfo
local UnitExists             = UnitExists
local UnitGUID               = UnitGUID
local UIFrameFadeOut         = UIFrameFadeOut
local UIFrameFadeRemoveFrame = UIFrameFadeRemoveFrame
local min, abs               = min, abs
local pairs                  = pairs
local _G                     = _G

local RUI                    = LibStub("AceAddon-3.0"):GetAddon("RetailUI")
local moduleName             = "CastingBar"
local Module                 = RUI:NewModule(moduleName, "AceConsole-3.0", "AceHook-3.0", "AceEvent-3.0")

Module.playerCastingBar      = nil
Module.isEditorTest          = false

local isHooked               = false

-------------------------------------------------------
-- Layout helpers
-------------------------------------------------------

local function ReplaceBlizzardCastingBarFrame(castingBarFrame, attachTo)
    local statusBar = castingBarFrame

    statusBar:SetMovable(true)
    statusBar:SetUserPlaced(true)
    statusBar:ClearAllPoints()
    statusBar:SetMinMaxValues(0.0, 1.0)
    statusBar:SetFrameLevel(statusBar:GetParent():GetFrameLevel() + 1)
    statusBar.selfInterrupt = false

    if attachTo then
        statusBar:SetPoint("LEFT", attachTo, "LEFT", 0, 0)
        statusBar:SetSize(attachTo:GetWidth() - 3, attachTo:GetHeight() - 3)
    end

    local statusBarTexture = statusBar:GetStatusBarTexture()
    statusBarTexture:SetAllPoints(statusBar)
    statusBarTexture:SetDrawLayer("BORDER")

    local borderTexture = _G[statusBar:GetName() .. "Border"]
    borderTexture:ClearAllPoints()
    borderTexture:SetPoint("TOPLEFT", -3, 2)
    borderTexture:SetPoint("BOTTOMRIGHT", 3, -2)
    SetAtlasTexture(borderTexture, "CastingBar-Border")

    for _, region in pairs { statusBar:GetRegions() } do
        if region:GetObjectType() == "Texture" and region:GetDrawLayer() == "BACKGROUND" then
            region:SetAllPoints(borderTexture)
            SetAtlasTexture(region, "CastingBar-Background")
        end
    end

    local sparkTexture = _G[statusBar:GetName() .. "Spark"]
    SetAtlasTexture(sparkTexture, "CastingBar-Spark")
    sparkTexture:SetSize(4, statusBar:GetHeight() * 1.25)

    local castingNameText = _G[statusBar:GetName() .. "Text"]
    castingNameText:ClearAllPoints()
    castingNameText:SetPoint("BOTTOMLEFT", 5, -16)
    castingNameText:SetJustifyH("LEFT")
    castingNameText:SetWidth(statusBar:GetWidth() * 0.6)

    statusBar.backgroundInfo = statusBar.backgroundInfo or CreateFrame("Frame", nil, statusBar)
    statusBar.backgroundInfo.background = statusBar.backgroundInfo.background or
        statusBar:CreateTexture(nil, "BACKGROUND")

    local backgroundTexture = statusBar.backgroundInfo.background
    backgroundTexture:SetAllPoints(statusBar)
    backgroundTexture:SetPoint("BOTTOMRIGHT", 1, -16)
    SetAtlasTexture(backgroundTexture, "CastingBar-MainBackground")

    local iconTexture = _G[statusBar:GetName() .. "Icon"]
    iconTexture:ClearAllPoints()
    iconTexture:SetPoint("RIGHT", backgroundTexture, "LEFT", -5, 0)
    iconTexture:SetSize(24, 24)

    statusBar.castingTime = statusBar.castingTime or statusBar:CreateFontString(nil, "BORDER", "GameFontHighlightSmall")
    local castTimeText = statusBar.castingTime
    castTimeText:SetPoint("BOTTOMRIGHT", -4, -14)
    castTimeText:SetJustifyH("RIGHT")

    local flashTexture = _G[statusBar:GetName() .. "Flash"]
    flashTexture:SetAlpha(0)

    local borderShieldTexture = _G[statusBar:GetName() .. "BorderShield"]
    borderShieldTexture:ClearAllPoints()
    borderShieldTexture:SetPoint("CENTER", _G[statusBar:GetName() .. "Icon"], "CENTER", 0, 0)
    SetAtlasTexture(borderShieldTexture, "CastingBar-BorderShield")
    borderShieldTexture:SetDrawLayer("BACKGROUND")
    borderShieldTexture:SetSize(borderShieldTexture:GetWidth() / 2.5, borderShieldTexture:GetHeight() / 2.5)

    function statusBar:ShowTest()
        local tex = self:GetStatusBarTexture()
        SetAtlasTexture(tex, "CastingBar-StatusBar-Casting")
        tex:SetVertexColor(1, 1, 1, 1)

        self:SetValue(0.5)
        local textRegion = _G[self:GetName() .. "Text"]
        textRegion:SetText("Healing Wave")
        self.castingTime:SetText(string.format("%.1f/%.2f", 0.5, 1.0))
        self:SetAlpha(1.0)
        self:Show()
    end

    function statusBar:HideTest()
        self:Hide()
    end
end

-------------------------------------------------------
-- OnUpdate driver
-------------------------------------------------------

local function CastingBarFrame_OnUpdate(self, elapsed)
    local currentTime = GetTime()
    local value, remainingTime = 0, 0

    if self.channelingEx or self.castingEx then
        local startTime = self.startTime
        local endTime   = self.endTime

        -- Guard: if timing invalid, stop and hide
        if not startTime or not endTime or endTime <= startTime then
            self.castingEx, self.channelingEx = nil, nil
            self.fadeOutEx = true
            -- Also clear texts safely
            if self.castingTime then
                self.castingTime:SetText("")
            end
            return
        end

        local duration = endTime - startTime
        if duration <= 0 then
            self.castingEx, self.channelingEx = nil, nil
            self.fadeOutEx = true
            if self.castingTime then
                self.castingTime:SetText("")
            end
            return
        end

        if self.castingEx then
            remainingTime = min(currentTime, endTime) - startTime
            value = remainingTime / duration
        elseif self.channelingEx then
            remainingTime = endTime - currentTime
            value = remainingTime / duration
        end

        -- Clamp value
        if value ~= value or value < 0 then value = 0 end
        if value > 1 then value = 1 end

        self:SetValue(value)

        -- Safe format: protect against nils
        local rt = abs(remainingTime or 0)
        local dur = duration or 0
        if self.castingTime and dur > 0 then
            self.castingTime:SetText(string.format("%.1f/%.2f", rt, dur))
        elseif self.castingTime then
            self.castingTime:SetText("")
        end

        local sparkTexture = _G[self:GetName() .. "Spark"]
        if sparkTexture then
            sparkTexture:ClearAllPoints()
            sparkTexture:SetPoint("CENTER", self, "LEFT", value * self:GetWidth(), 0)
        end

        if currentTime > self.endTime then
            self.castingEx, self.channelingEx = nil, nil
            self.fadeOutEx = true
        end
    elseif self.fadeOutEx then
        local sparkTexture = _G[self:GetName() .. "Spark"]
        if sparkTexture then
            sparkTexture:Hide()
        end
        if self:GetAlpha() <= 0.0 then
            self:Hide()
        end
    end
end

-------------------------------------------------------
-- Target spellbar positioning
-------------------------------------------------------

local function Target_Spellbar_AdjustPosition(self)
    self.SetPoint = UIParent.SetPoint

    local parentFrame = self:GetParent()
    self:ClearAllPoints()

    if parentFrame.haveToT then
        if parentFrame.auraRows <= 1 then
            self:SetPoint("TOPLEFT", parentFrame, "BOTTOMLEFT", 25, -40)
        else
            self:SetPoint("TOPLEFT", parentFrame.spellbarAnchor, "BOTTOMLEFT", 20, -20)
        end
    elseif parentFrame.haveElite then
        if parentFrame.auraRows <= 1 then
            self:SetPoint("TOPLEFT", parentFrame, "BOTTOMLEFT", 25, -10)
        else
            self:SetPoint("TOPLEFT", parentFrame.spellbarAnchor, "BOTTOMLEFT", 20, -10)
        end
    else
        if parentFrame.auraRows > 0 then
            self:SetPoint("TOPLEFT", parentFrame.spellbarAnchor, "BOTTOMLEFT", 20, -10)
        else
            self:SetPoint("TOPLEFT", parentFrame, "BOTTOMLEFT", 25, -10)
        end
    end

    self.SetPoint = function() end
end

-------------------------------------------------------
-- Module lifecycle
-------------------------------------------------------

function Module:OnEnable()
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("UNIT_SPELLCAST_START")
    self:RegisterEvent("UNIT_SPELLCAST_STOP")
    self:RegisterEvent("UNIT_SPELLCAST_FAILED")
    self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    self:RegisterEvent("UNIT_SPELLCAST_DELAYED")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_INTERRUPTED")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
    self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTIBLE")
    self:RegisterEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
    self:RegisterEvent("PLAYER_TARGET_CHANGED")
    self:RegisterEvent("PLAYER_FOCUS_CHANGED")

    CastingBarFrame:UnregisterAllEvents()
    FocusFrameSpellBar:UnregisterAllEvents()
    TargetFrameSpellBar:UnregisterAllEvents()
    PetCastingBarFrame:UnregisterAllEvents()

    if not isHooked then
        CastingBarFrame:HookScript("OnUpdate", CastingBarFrame_OnUpdate)
        TargetFrameSpellBar:HookScript("OnUpdate", CastingBarFrame_OnUpdate)
        FocusFrameSpellBar:HookScript("OnUpdate", CastingBarFrame_OnUpdate)
        PetCastingBarFrame:HookScript("OnUpdate", CastingBarFrame_OnUpdate)
        isHooked = true
    end

    self:SecureHook("Target_Spellbar_AdjustPosition", Target_Spellbar_AdjustPosition)

    self.playerCastingBar = CreateUIFrame(228, 18, "CastingBarFrame")
end

function Module:OnDisable()
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    self:UnregisterEvent("UNIT_SPELLCAST_START")
    self:UnregisterEvent("UNIT_SPELLCAST_STOP")
    self:UnregisterEvent("UNIT_SPELLCAST_FAILED")
    self:UnregisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    self:UnregisterEvent("UNIT_SPELLCAST_DELAYED")
    self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_INTERRUPTED")
    self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
    self:UnregisterEvent("UNIT_SPELLCAST_INTERRUPTIBLE")
    self:UnregisterEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
    self:UnregisterEvent("PLAYER_TARGET_CHANGED")
    self:UnregisterEvent("PLAYER_FOCUS_CHANGED")

    CastingBarFrame:Unhook("OnUpdate", CastingBarFrame_OnUpdate)
    TargetFrameSpellBar:Unhook("OnUpdate", CastingBarFrame_OnUpdate)
    FocusFrameSpellBar:Unhook("OnUpdate", CastingBarFrame_OnUpdate)
    PetCastingBarFrame:Unhook("OnUpdate", CastingBarFrame_OnUpdate)

    self:Unhook("Target_Spellbar_AdjustPosition", Target_Spellbar_AdjustPosition)
end

function Module:PLAYER_ENTERING_WORLD()
    ReplaceBlizzardCastingBarFrame(CastingBarFrame, self.playerCastingBar)
    ReplaceBlizzardCastingBarFrame(TargetFrameSpellBar)
    ReplaceBlizzardCastingBarFrame(FocusFrameSpellBar)
    ReplaceBlizzardCastingBarFrame(PetCastingBarFrame)

    CheckSettingsExists(self, { "playerCastingBar" })
end

-------------------------------------------------------
-- Target/focus visibility helpers
-------------------------------------------------------

local function UpdateUnitBarVisibility(unit, bar)
    if UnitExists(unit) and bar.unit == UnitGUID(unit) then
        if GetTime() > bar.endTime then
            bar:Hide()
        else
            bar:Show()
        end
    else
        bar:Hide()
    end
end

function Module:PLAYER_TARGET_CHANGED()
    UpdateUnitBarVisibility("target", TargetFrameSpellBar)
end

function Module:PLAYER_FOCUS_CHANGED()
    UpdateUnitBarVisibility("focus", FocusFrameSpellBar)
end

-------------------------------------------------------
-- Shared event helpers
-------------------------------------------------------

local function ResolveStatusBar(unit)
    if unit == "player" then
        return CastingBarFrame
    elseif unit == "target" then
        TargetFrameSpellBar.unit = UnitGUID("target")
        return TargetFrameSpellBar
    elseif unit == "focus" then
        FocusFrameSpellBar.unit = UnitGUID("focus")
        return FocusFrameSpellBar
    elseif unit == "pet" then
        return PetCastingBarFrame
    end
end

local function GuardUnitGUID(unit, bar)
    if unit == "target" and bar.unit ~= UnitGUID("target") then
        return false
    end
    if unit == "focus" and bar.unit ~= UnitGUID("focus") then
        return false
    end
    return true
end

-------------------------------------------------------
-- Cast/channel start
-------------------------------------------------------

function Module:UNIT_SPELLCAST_START(eventName, unit)
    if self.isEditorTest then
        return
    end
    local statusBar = ResolveStatusBar(unit)
    if not statusBar then return end

    local spell, rank, displayName, icon, startTime, endTime
    if eventName == "UNIT_SPELLCAST_START" then
        spell, rank, displayName, icon, startTime, endTime = UnitCastingInfo(unit)
        statusBar.castingEx, statusBar.channelingEx = true, false
        SetAtlasTexture(statusBar:GetStatusBarTexture(), "CastingBar-StatusBar-Casting")
    else
        spell, rank, displayName, icon, startTime, endTime = UnitChannelInfo(unit)
        statusBar.castingEx, statusBar.channelingEx = false, true
        SetAtlasTexture(statusBar:GetStatusBarTexture(), "CastingBar-StatusBar-Channeling")
    end

    if not spell or not startTime or not endTime or endTime <= startTime then
        -- Do not leave Ex flags set with bad timing
        statusBar.castingEx, statusBar.channelingEx = nil, nil
        return
    end

    local iconTexture = _G[statusBar:GetName() .. "Icon"]
    if unit ~= "player" then
        iconTexture:SetTexture(icon)
        iconTexture:Show()
    else
        iconTexture:Hide()
    end

    local castingNameText = _G[statusBar:GetName() .. "Text"]
    castingNameText:SetText(displayName)

    local tex = statusBar:GetStatusBarTexture()
    tex:SetVertexColor(1, 1, 1, 1)

    statusBar.startTime = startTime / 1000
    statusBar.endTime   = endTime / 1000

    UIFrameFadeRemoveFrame(statusBar)

    local sparkTexture = _G[statusBar:GetName() .. "Spark"]
    sparkTexture:Show()

    statusBar:SetAlpha(1.0)
    statusBar:Show()
end

Module.UNIT_SPELLCAST_CHANNEL_START = Module.UNIT_SPELLCAST_START

-------------------------------------------------------
-- Stop / channel stop
-------------------------------------------------------

function Module:UNIT_SPELLCAST_STOP(eventName, unit)
    local statusBar = ResolveStatusBar(unit)
    if not statusBar or not GuardUnitGUID(unit, statusBar) then return end

    if statusBar.castingEx then
        SetAtlasTexture(statusBar:GetStatusBarTexture(), "CastingBar-StatusBar-Casting")
    elseif statusBar.channelingEx then
        SetAtlasTexture(statusBar:GetStatusBarTexture(), "CastingBar-StatusBar-Channeling")
        statusBar.selfInterrupt = true
    end

    statusBar:GetStatusBarTexture():SetVertexColor(1, 1, 1, 1)
    statusBar.castingEx, statusBar.channelingEx = false, false
    statusBar.fadeOutEx = true
    UIFrameFadeOut(statusBar, 1, 1.0, 0.0)
end

Module.UNIT_SPELLCAST_CHANNEL_STOP = Module.UNIT_SPELLCAST_STOP

-------------------------------------------------------
-- Failed / interrupted
-------------------------------------------------------

function Module:UNIT_SPELLCAST_FAILED(eventName, unit)
    local statusBar = ResolveStatusBar(unit)
    if not statusBar or not GuardUnitGUID(unit, statusBar) then return end

    if statusBar.castingEx then
        SetAtlasTexture(statusBar:GetStatusBarTexture(), "CastingBar-StatusBar-Casting")
    elseif statusBar.channelingEx then
        SetAtlasTexture(statusBar:GetStatusBarTexture(), "CastingBar-StatusBar-Channeling")
    end

    statusBar:GetStatusBarTexture():SetVertexColor(1, 1, 1, 1)
end

function Module:UNIT_SPELLCAST_INTERRUPTED(eventName, unit)
    local statusBar = ResolveStatusBar(unit)
    if not statusBar or not GuardUnitGUID(unit, statusBar) then return end

    if not statusBar.selfInterrupt then
        statusBar:SetValue(1.0)
        SetAtlasTexture(statusBar:GetStatusBarTexture(), "CastingBar-StatusBar-Failed")
        statusBar:GetStatusBarTexture():SetVertexColor(1, 1, 1, 1)

        local castingNameText = _G[statusBar:GetName() .. "Text"]
        castingNameText:SetText("Interrupted")
    else
        statusBar.selfInterrupt = false
    end

    statusBar.castingEx, statusBar.channelingEx = false, false
    statusBar.fadeOutEx = true
    UIFrameFadeOut(statusBar, 1, 1.0, 0.0)
end

Module.UNIT_SPELLCAST_CHANNEL_INTERRUPTED = Module.UNIT_SPELLCAST_INTERRUPTED

-------------------------------------------------------
-- Delay / channel update
-------------------------------------------------------

function Module:UNIT_SPELLCAST_DELAYED(eventName, unit)
    local statusBar = ResolveStatusBar(unit)
    if not statusBar or not GuardUnitGUID(unit, statusBar) then return end

    local spell, rank, displayName, icon, startTime, endTime
    if statusBar.castingEx then
        spell, rank, displayName, icon, startTime, endTime = UnitCastingInfo(unit)
    elseif statusBar.channelingEx then
        spell, rank, displayName, icon, startTime, endTime = UnitChannelInfo(unit)
    end

    if not spell then
        statusBar:Hide()
        return
    end

    statusBar.startTime = startTime / 1000
    statusBar.endTime   = endTime / 1000
end

Module.UNIT_SPELLCAST_CHANNEL_UPDATE = Module.UNIT_SPELLCAST_DELAYED

-------------------------------------------------------
-- Interruptible shield
-------------------------------------------------------

local function ResolveInterruptibleBar(unit)
    if unit == "target" then
        return TargetFrameSpellBar, "target"
    elseif unit == "focus" then
        return FocusFrameSpellBar, "focus"
    elseif unit == "pet" then
        return PetCastingBarFrame, nil
    end
end

function Module:UNIT_SPELLCAST_INTERRUPTIBLE(unit)
    local statusBar, guidUnit = ResolveInterruptibleBar(unit)
    if not statusBar then return end
    if guidUnit and statusBar.unit ~= UnitGUID(guidUnit) then return end

    local borderShieldTexture = _G[statusBar:GetName() .. "BorderShield"]
    borderShieldTexture:Show()
end

function Module:UNIT_SPELLCAST_NOT_INTERRUPTIBLE(unit)
    local statusBar, guidUnit = ResolveInterruptibleBar(unit)
    if not statusBar then return end
    if guidUnit and statusBar.unit ~= UnitGUID(guidUnit) then return end

    local borderShieldTexture = _G[statusBar:GetName() .. "BorderShield"]
    borderShieldTexture:Hide()
end

-------------------------------------------------------
-- Config integration
-------------------------------------------------------

function Module:LoadDefaultSettings()
    RUI.DB.profile.widgets.playerCastingBar = { anchor = "BOTTOM", posX = 0, posY = 270 }
end

function Module:UpdateWidgets()
    local widgetOptions = RUI.DB.profile.widgets.playerCastingBar
    self.playerCastingBar:SetPoint(widgetOptions.anchor, widgetOptions.posX, widgetOptions.posY)
end

function Module:ShowEditorTest()
    self.isEditorTest = true
    if CastingBarFrame and CastingBarFrame.ShowTest then
        CastingBarFrame:ShowTest()
    end
end

function Module:HideEditorTest()
    self.isEditorTest = false
    if CastingBarFrame and CastingBarFrame.HideTest then
        -- Clear any fake state and hide
        CastingBarFrame.castingEx = nil
        CastingBarFrame.channelingEx = nil
        CastingBarFrame.fadeOutEx = nil
        CastingBarFrame.startTime = nil
        CastingBarFrame.endTime = nil
        if CastingBarFrame.castingTime then
            CastingBarFrame.castingTime:SetText("")
        end
        local sparkTexture = _G[CastingBarFrame:GetName() .. "Spark"]
        if sparkTexture then
            sparkTexture:Hide()
        end
        CastingBarFrame:Hide()
    end
end
