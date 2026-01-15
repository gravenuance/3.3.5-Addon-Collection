--[[
Copyright (c) Dmitriy. All rights reserved.
Licensed under the MIT license. See LICENSE file in the project root for details.
]]

local LibStub           = LibStub
local CreateFrame       = CreateFrame
local UnitBuff          = UnitBuff
local ConsolidatedBuffs = ConsolidatedBuffs
local BuffFrame         = BuffFrame
local _G                = _G

local RUI               = LibStub("AceAddon-3.0"):GetAddon("RetailUI")
local moduleName        = "BuffFrame"
local Module            = RUI:NewModule(moduleName, "AceConsole-3.0", "AceHook-3.0", "AceEvent-3.0")

Module.buffFrame        = nil
Module.debuffFrame      = nil

local MAX_CHECKED_BUFFS = 16

local function ToggleAllBuffButtons(show)
    for index = 1, BUFF_ACTUAL_DISPLAY do
        local button = _G["BuffButton" .. index]
        if button then
            if show then
                button:Show()
            else
                button:Hide()
            end
        end
    end
end

local function ReplaceBlizzardFrame(frame)
    frame.toggleButton = frame.toggleButton or CreateFrame("Button", nil, UIParent)
    local toggleButton = frame.toggleButton

    toggleButton.toggle = true
    toggleButton:SetPoint("RIGHT", frame, "RIGHT", 0, -3)
    toggleButton:SetSize(9, 17)
    toggleButton:SetHitRectInsets(0, 0, 0, 0)

    local normalTexture = toggleButton:GetNormalTexture() or toggleButton:CreateTexture(nil, "BORDER")
    normalTexture:SetAllPoints(toggleButton)
    SetAtlasTexture(normalTexture, "CollapseButton-Right")
    toggleButton:SetNormalTexture(normalTexture)

    local highlightTexture = toggleButton:GetHighlightTexture() or toggleButton:CreateTexture(nil, "HIGHLIGHT")
    highlightTexture:SetAllPoints(toggleButton)
    SetAtlasTexture(highlightTexture, "CollapseButton-Right")
    toggleButton:SetHighlightTexture(highlightTexture)

    toggleButton:SetScript("OnClick", function(self)
        local showBuffs

        if self.toggle then
            local nTex = self:GetNormalTexture()
            SetAtlasTexture(nTex, "CollapseButton-Left")

            local hTex = toggleButton:GetHighlightTexture()
            SetAtlasTexture(hTex, "CollapseButton-Left")

            showBuffs = false
        else
            local nTex = self:GetNormalTexture()
            SetAtlasTexture(nTex, "CollapseButton-Right")

            local hTex = toggleButton:GetHighlightTexture()
            SetAtlasTexture(hTex, "CollapseButton-Right")

            showBuffs = true
        end

        ToggleAllBuffButtons(showBuffs)
        self.toggle = not self.toggle
    end)

    local consolidatedBuffFrame = ConsolidatedBuffs
    local consolidatedDebuffFrame = ConsolidatedDebuffs or CreateFrame("Frame", "RetailUI_ConsolidatedDebuffs", UIParent)
    consolidatedBuffFrame:SetMovable(true)
    consolidatedBuffFrame:SetUserPlaced(true)
    consolidatedBuffFrame:ClearAllPoints()
    consolidatedBuffFrame:SetPoint("RIGHT", toggleButton, "LEFT", -6, 0)

    consolidatedDebuffFrame:SetMovable(true)
    consolidatedDebuffFrame:SetUserPlaced(true)
    consolidatedDebuffFrame:ClearAllPoints()
    consolidatedDebuffFrame:SetPoint("RIGHT", Module.debuffFrame, "LEFT", -6, 0)
end

local function ShowToggleButtonIf(condition)
    local button = Module.buffFrame and Module.buffFrame.toggleButton
    if not button then return end

    if condition then
        button:Show()
    else
        button:Hide()
    end
end

local function GetUnitBuffCount(unit, range)
    local count = 0
    for index = 1, range do
        local name = UnitBuff(unit, index)
        if not name then
            break
        end
        count = count + 1
    end
    return count
end

local function HasAnyBuff(unit)
    return GetUnitBuffCount(unit, MAX_CHECKED_BUFFS) > 0
end

function Module:OnEnable()
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("UNIT_AURA")
    self:RegisterEvent("UNIT_ENTERED_VEHICLE")
    self:RegisterEvent("UNIT_EXITED_VEHICLE")

    self.buffFrame = CreateUIFrame(BuffFrame:GetWidth(), BuffFrame:GetHeight(), "BuffFrame")
    self.debuffFrame = CreateUIFrame(BuffFrame:GetWidth(), BuffFrame:GetHeight(), "DebuffFrame")
end

function Module:OnDisable()
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    self:UnregisterEvent("UNIT_AURA")
    self:UnregisterEvent("UNIT_ENTERED_VEHICLE")
    self:UnregisterEvent("UNIT_EXITED_VEHICLE")
end

function Module:PLAYER_ENTERING_WORLD()
    ReplaceBlizzardFrame(self.buffFrame)
    ShowToggleButtonIf(HasAnyBuff("player"))
    CheckSettingsExists(self, { "buffs", "debuffs" })
end

function Module:UNIT_AURA(_, unit)
    if unit == "vehicle" then
        ShowToggleButtonIf(HasAnyBuff("vehicle"))
    elseif unit == "player" then
        ShowToggleButtonIf(HasAnyBuff("player"))
    end
end

function Module:UNIT_ENTERED_VEHICLE(_, unit)
    if unit ~= "player" then return end
    ShowToggleButtonIf(HasAnyBuff("vehicle"))
end

function Module:UNIT_EXITED_VEHICLE(_, unit)
    if unit ~= "player" then return end
    ShowToggleButtonIf(HasAnyBuff("player"))
end

function Module:LoadDefaultSettings()
    RUI.DB.profile.widgets.buffs = { anchor = "TOPRIGHT", posX = -260, posY = -20 }
    RUI.DB.profile.widgets.debuffs = { anchor = "TOPRIGHT", posX = -260, posY = -80 }
end

function Module:UpdateWidgets()
    local buffOpts   = RUI.DB.profile.widgets.buffs
    local debuffOpts = RUI.DB.profile.widgets.debuffs

    self.buffFrame:SetPoint(buffOpts.anchor, buffOpts.posX, buffOpts.posY)
    self.debuffFrame:SetPoint(debuffOpts.anchor, debuffOpts.posX, debuffOpts.posY)
end

function Module:ShowEditorTest()
    HideUIFrame(self.buffFrame)
    HideUIFrame(self.debuffFrame)
end

function Module:HideEditorTest(refresh)
    ShowUIFrame(self.buffFrame)
    SaveUIFramePosition(self.buffFrame, "buffs")

    ShowUIFrame(self.debuffFrame)
    SaveUIFramePosition(self.debuffFrame, "debuffs")

    if refresh then
        self:UpdateWidgets()
    end
end
