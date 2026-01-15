--[[
Copyright (c) Dmitriy. All rights reserved.
Licensed under the MIT license. See LICENSE file in the project root for details.
]]

local LibStub      = LibStub
local CreateFrame  = CreateFrame
local GetBuildInfo = GetBuildInfo
local GetCVar      = GetCVar
local SetCVar      = SetCVar
local print        = print
local tinsert      = tinsert
local pairs        = pairs

local RUI          = LibStub("AceAddon-3.0"):NewAddon("RetailUI", "AceConsole-3.0")
local AceConfig    = LibStub("AceConfig-3.0")
local AceDB        = LibStub("AceDB-3.0")

RetailUIDB         = RetailUIDB or {}
if RetailUIDB.bagsExpanded == nil then
	RetailUIDB.bagsExpanded = false -- Standard: sichtbar
end

RUI.InterfaceVersion = select(4, GetBuildInfo())
RUI.Wrath            = (RUI.InterfaceVersion >= 30300)
RUI.DB               = nil

function RUI:OnInitialize()
	self.DB = AceDB:New("RetailUIDB", self.default, true)
	AceConfig:RegisterOptionsTable("RUI Commands", self.optionsSlash, "rui")
end

function RUI:OnEnable()
	if GetCVar("useUiScale") == "0" then
		SetCVar("useUiScale", 1)
		SetCVar("uiScale", 0.75)
	end
end

function RUI:OnDisable()
end

-------------------------------------------------------
-- Frame helpers
-------------------------------------------------------

function CreateUIFrame(width, height, frameName)
	local frame = CreateFrame("Frame", "RUI_" .. frameName, UIParent)
	frame:SetSize(width, height)

	frame:RegisterForDrag("LeftButton")
	frame:EnableMouse(false)
	frame:SetMovable(false)

	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

	frame:SetFrameLevel(1)
	frame:SetFrameStrata("MEDIUM")

	do
		local tex = frame:CreateTexture(nil, "BACKGROUND")
		tex:SetAllPoints(frame)
		tex:SetTexture("Interface\\AddOns\\RetailUI\\Textures\\UI\\ActionBarHorizontal.blp")
		tex:SetTexCoord(0, 512 / 512, 14 / 2048, 85 / 2048)
		tex:Hide()
		frame.editorTexture = tex
	end

	do
		local fontString = frame:CreateFontString(nil, "BORDER", "GameFontNormal")
		fontString:SetAllPoints(frame)
		fontString:SetText(frameName)
		fontString:Hide()
		frame.editorText = fontString
	end

	return frame
end

RUI.frames = {}

function ShowUIFrame(frame)
	frame:SetMovable(false)
	frame:EnableMouse(false)

	frame.editorTexture:Hide()
	frame.editorText:Hide()

	local stored = RUI.frames[frame]
	if stored then
		for _, target in pairs(stored) do
			target:SetAlpha(1)
		end
	end

	RUI.frames[frame] = nil
end

function HideUIFrame(frame, exclude)
	frame:SetMovable(true)
	frame:EnableMouse(true)

	frame.editorTexture:Show()
	frame.editorText:Show()

	local list = {}
	RUI.frames[frame] = list

	exclude = exclude or {}
	for _, target in pairs(exclude) do
		target:SetAlpha(0)
		tinsert(list, target)
	end
end

function SaveUIFramePosition(frame, widgetName)
	local _, _, relativePoint, posX, posY = frame:GetPoint("CENTER")
	local w                               = RUI.DB.profile.widgets[widgetName]

	w.anchor                              = relativePoint
	w.posX                                = posX
	w.posY                                = posY
end

function SaveUIFrameScale(input, widgetName)
	local scale = tonumber(input)
	if not scale or scale <= 0 then
		print("Invalid scale. Please provide a positive number.")
		return
	end

	RUI.DB.profile.widgets[widgetName].scale = scale

	local UnitFrameModule = RUI:GetModule("UnitFrame")
	UnitFrameModule:UpdateWidgets()

	print(widgetName .. " Frame Scale saved as " .. GetUIFrameScale(widgetName))
end

function GetUIFrameScale(widgetName)
	return RUI.DB.profile.widgets[widgetName].scale
end

function CheckSettingsExists(self, widgets)
	local profileWidgets = RUI.DB.profile.widgets
	for _, widget in pairs(widgets) do
		if profileWidgets[widget] == nil then
			self:LoadDefaultSettings()
			break
		end
	end
	self:UpdateWidgets()
end

-------------------------------------------------------
-- One‑time chat positioning
-------------------------------------------------------

local function MoveChatOnFirstLoad()
	local chat = ChatFrame1
	if not chat or chat:IsUserPlaced() then return end

	chat:ClearAllPoints()
	chat:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 32, 32)
	chat:SetWidth(chat:GetWidth() - 40)
	chat:SetMovable(true)
	chat:SetUserPlaced(true)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(self)
	MoveChatOnFirstLoad()
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
end)
