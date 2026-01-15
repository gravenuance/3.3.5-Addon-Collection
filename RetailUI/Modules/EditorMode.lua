--[[
Copyright (c) Dmitriy. All rights reserved.
Licensed under the MIT license. See LICENSE file in the project root for details.
]]

local LibStub            = LibStub
local CreateFrame        = CreateFrame
local GetScreenWidth     = GetScreenWidth
local GetScreenHeight    = GetScreenHeight
local InCombatLockdown   = InCombatLockdown
local DEFAULT_CHAT_FRAME = DEFAULT_CHAT_FRAME

local RUI                = LibStub("AceAddon-3.0"):GetAddon("RetailUI")
local moduleName         = "EditorMode"
local Module             = RUI:NewModule(moduleName, "AceConsole-3.0", "AceHook-3.0", "AceEvent-3.0")

local UnitFrameModule
local CastingBarModule
local ActionBarModule
local MinimapModule
local QuestTrackerModule
local BuffFrameModule

Module.editorGridFrame   = nil

local function CreateEditorGridFrame()
    local editorGridFrame = CreateFrame("Frame", "RUI_EditorGridFrame", UIParent)
    editorGridFrame:SetPoint("TOPLEFT", 0, 0)
    editorGridFrame:SetSize(GetScreenWidth(), GetScreenHeight())
    editorGridFrame:SetFrameLevel(0)
    editorGridFrame:SetFrameStrata("BACKGROUND")

    local texture = editorGridFrame:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints(editorGridFrame)
    texture:SetTexture("Interface\\AddOns\\RetailUI\\Textures\\UI\\EditorGrid.blp", "REPEAT", "REPEAT")
    texture:SetTexCoord(0, 1, 0, 1)
    texture:SetVertTile(true)
    texture:SetHorizTile(true)
    texture:SetSize(32, 32)
    texture:SetAlpha(0.4)

    editorGridFrame:Hide()
    return editorGridFrame
end

function Module:OnEnable()
    UnitFrameModule      = RUI:GetModule("UnitFrame")
    CastingBarModule     = RUI:GetModule("CastingBar")
    ActionBarModule      = RUI:GetModule("ActionBar")
    MinimapModule        = RUI:GetModule("Minimap")
    QuestTrackerModule   = RUI:GetModule("QuestTracker")
    BuffFrameModule      = RUI:GetModule("BuffFrame")

    self.editorGridFrame = CreateEditorGridFrame()
end

function Module:OnDisable()
end

local function ForEachModule(func)
    func(ActionBarModule)
    func(UnitFrameModule)
    func(CastingBarModule)
    func(MinimapModule)
    func(QuestTrackerModule)
    func(BuffFrameModule)
end

function Module:Show()
    if InCombatLockdown() then
        self:Printf(DEFAULT_CHAT_FRAME, "Cannot open settings while in combat")
        return
    end

    self.editorGridFrame:Show()

    ForEachModule(function(m)
        m:ShowEditorTest()
    end)
end

function Module:Hide()
    self.editorGridFrame:Hide()

    ForEachModule(function(m)
        m:HideEditorTest(true)
    end)
end

function Module:IsShown()
    return self.editorGridFrame:IsShown()
end
