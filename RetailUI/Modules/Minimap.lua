--[[
    Copyright (c) Dmitriy. All rights reserved.
    Licensed under the MIT license. See LICENSE file in the project root for details.
]]

local RUI                            = LibStub('AceAddon-3.0'):GetAddon('RetailUI')
local moduleName                     = 'Minimap'
local Module                         = RUI:NewModule(moduleName, 'AceConsole-3.0', 'AceHook-3.0', 'AceEvent-3.0')
local isHooked                       = false
Module.minimapFrame                  = nil
Module.borderFrame                   = nil

-- Near the top, cache globals
local QueueStatusMinimapButton       = QueueStatusMinimapButton
local QueueStatusFrame               = QueueStatusFrame
local QueueStatusMinimapButtonGlow   = QueueStatusMinimapButtonGlow
local QueueStatusMinimapButtonBorder = QueueStatusMinimapButtonBorder
local MiniMapBattlefieldFrame        = MiniMapBattlefieldFrame
local MiniMapBattlefieldIcon         = MiniMapBattlefieldIcon

local function UpdateCalendarDate()
    local _, _, day = CalendarGetDate()

    local gameTimeFrame = GameTimeFrame

    local normalTexture = gameTimeFrame:GetNormalTexture()
    normalTexture:SetAllPoints(gameTimeFrame)
    SetAtlasTexture(normalTexture, 'Minimap-Calendar-' .. day .. '-Normal')

    local highlightTexture = gameTimeFrame:GetHighlightTexture()
    highlightTexture:SetAllPoints(gameTimeFrame)
    SetAtlasTexture(highlightTexture, 'Minimap-Calendar-' .. day .. '-Highlight')

    local pushedTexture = gameTimeFrame:GetPushedTexture()
    pushedTexture:SetAllPoints(gameTimeFrame)
    SetAtlasTexture(pushedTexture, 'Minimap-Calendar-' .. day .. '-Pushed')
end

local function FixQueueButtonStrata()
    -- New unified queue button (3.3.5 backport mods often enable this)
    if QueueStatusMinimapButton then
        QueueStatusMinimapButton:SetFrameStrata("HIGH")
        QueueStatusMinimapButton:SetFrameLevel(9)
    end

    if QueueStatusMinimapButtonGlow then
        QueueStatusMinimapButtonGlow:SetFrameStrata("HIGH")
        QueueStatusMinimapButtonGlow:SetFrameLevel(9)
    end

    if QueueStatusMinimapButtonBorder then
        QueueStatusMinimapButtonBorder:SetFrameStrata("HIGH")
        QueueStatusMinimapButtonBorder:SetFrameLevel(9)
    end

    -- Classic battleground/lfg button
    if MiniMapBattlefieldFrame then
        MiniMapBattlefieldFrame:SetFrameStrata("HIGH")
        MiniMapBattlefieldFrame:SetFrameLevel(9)
    end

    if MiniMapBattlefieldIcon then
        MiniMapBattlefieldIcon:SetDrawLayer("ARTWORK", 1)
    end
end

local function ReplaceBlizzardFrame(frame)
    local minimapCluster = MinimapCluster
    minimapCluster:ClearAllPoints()
    minimapCluster:SetPoint("CENTER", frame, "CENTER", 0, 0)

    local minimapBorderTop = MinimapBorderTop
    minimapBorderTop:ClearAllPoints()
    minimapBorderTop:SetPoint("TOP", 0, 25)
    SetAtlasTexture(minimapBorderTop, 'Minimap-Border-Top')
    minimapBorderTop:SetSize(156, 20)

    local minimapZoneButton = MinimapZoneTextButton
    minimapZoneButton:ClearAllPoints()
    minimapZoneButton:SetPoint("LEFT", minimapBorderTop, "LEFT", 7, 1)
    minimapZoneButton:SetWidth(108)

    minimapZoneButton:EnableMouse(true)
    minimapZoneButton:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            if WorldMapFrame:IsShown() then
                HideUIPanel(WorldMapFrame)
            else
                ShowUIPanel(WorldMapFrame)
            end
        end
    end)

    local minimapZoneText = MinimapZoneText
    minimapZoneText:SetAllPoints(minimapZoneButton)
    minimapZoneText:SetJustifyH("LEFT")

    local timeClockButton = TimeManagerClockButton
    timeClockButton:GetRegions():Hide()
    timeClockButton:ClearAllPoints()
    timeClockButton:SetPoint("RIGHT", minimapBorderTop, "RIGHT", -5, 0)
    timeClockButton:SetWidth(30)

    timeClockButton:SetAlpha(1)
    timeClockButton:SetScript("OnEnter", nil)
    timeClockButton:SetScript("OnLeave", nil)

    local gameTimeFrame = GameTimeFrame
    gameTimeFrame:ClearAllPoints()
    gameTimeFrame:SetPoint("LEFT", minimapBorderTop, "RIGHT", 3, -1)
    gameTimeFrame:SetSize(26, 24)
    gameTimeFrame:SetHitRectInsets(0, 0, 0, 0)
    gameTimeFrame:GetFontString():Hide()

    gameTimeFrame:SetAlpha(1)
    gameTimeFrame:SetScript("OnEnter", nil)
    gameTimeFrame:SetScript("OnLeave", nil)

    hooksecurefunc(gameTimeFrame, "SetAlpha", function(self, a)
        if a ~= 1 then self:SetAlpha(1) end
    end)

    hooksecurefunc(timeClockButton, "SetAlpha", function(self, a)
        if a ~= 1 then self:SetAlpha(1) end
    end)

    UpdateCalendarDate()

    local minimapBattlefieldFrame = MiniMapBattlefieldFrame
    minimapBattlefieldFrame:ClearAllPoints()
    minimapBattlefieldFrame:SetPoint("BOTTOMLEFT", 8, 2)

    local minimapLFGFrame = MiniMapLFGFrame
    minimapLFGFrame:ClearAllPoints()
    minimapLFGFrame:SetPoint("BOTTOMLEFT", -5, 15)
    minimapLFGFrame:SetSize(50, 50)
    minimapLFGFrame:SetHitRectInsets(0, 0, 0, 0)

    local eyeFrame = _G[minimapLFGFrame:GetName() .. 'Icon']
    eyeFrame:SetAllPoints(minimapLFGFrame)

    local iconTexture = eyeFrame.texture
    iconTexture:SetAllPoints(eyeFrame)
    iconTexture:SetTexture("Interface\\AddOns\\RetailUI\\Textures\\Minimap\\EyeGroupFinderFlipbook.blp")

    local minimapInstanceFrame = MiniMapInstanceDifficulty
    minimapInstanceFrame:ClearAllPoints()
    minimapInstanceFrame:SetPoint("TOP", minimapBorderTop, 'BOTTOMRIGHT', -18, 9)

    local minimapTracking = MiniMapTracking
    minimapTracking:ClearAllPoints()
    minimapTracking:SetPoint("RIGHT", minimapBorderTop, "LEFT", -3, 0)
    minimapTracking:SetSize(26, 24)

    local minimapMailFrame = MiniMapMailFrame
    minimapMailFrame:ClearAllPoints()
    minimapMailFrame:SetPoint("TOP", minimapTracking, "BOTTOM", 0, -3)
    minimapMailFrame:SetSize(24, 18)
    minimapMailFrame:SetHitRectInsets(0, 0, 0, 0)

    local minimapMailIconTexture = MiniMapMailIcon
    minimapMailIconTexture:SetAllPoints(minimapMailFrame)
    SetAtlasTexture(minimapMailIconTexture, 'Minimap-Mail-Normal')

    local backgroundTexture = _G[minimapTracking:GetName() .. "Background"]
    backgroundTexture:SetAllPoints(minimapTracking)
    SetAtlasTexture(backgroundTexture, 'Minimap-Tracking-Background')

    local minimapTrackingButton = _G[minimapTracking:GetName() .. 'Button']
    minimapTrackingButton:ClearAllPoints()
    minimapTrackingButton:SetPoint("CENTER", 0, 0)

    minimapTrackingButton:SetSize(17, 15)
    minimapTrackingButton:SetHitRectInsets(0, 0, 0, 0)

    local shineTexture = _G[minimapTrackingButton:GetName() .. "Shine"]
    shineTexture:SetTexture(nil)

    local normalTexture = minimapTrackingButton:GetNormalTexture() or minimapTrackingButton:CreateTexture(nil, "BORDER")
    normalTexture:SetAllPoints(minimapTrackingButton)
    SetAtlasTexture(normalTexture, 'Minimap-Tracking-Normal')

    minimapTrackingButton:SetNormalTexture(normalTexture)

    local highlightTexture = minimapTrackingButton:GetHighlightTexture()
    highlightTexture:SetAllPoints(minimapTrackingButton)
    SetAtlasTexture(highlightTexture, 'Minimap-Tracking-Highlight')

    local pushedTexture = minimapTrackingButton:GetPushedTexture() or minimapTrackingButton:CreateTexture(nil, "BORDER")
    pushedTexture:SetAllPoints(minimapTrackingButton)
    SetAtlasTexture(pushedTexture, 'Minimap-Tracking-Pushed')

    minimapTrackingButton:SetPushedTexture(pushedTexture)

    local minimapFrame = Minimap
    minimapFrame:ClearAllPoints()
    minimapFrame:SetPoint("CENTER", minimapCluster, "CENTER", 0, 0)
    minimapFrame:SetSize(170, 170)

    local minimapBackdropTexture = MinimapBackdrop
    minimapBackdropTexture:ClearAllPoints()
    minimapBackdropTexture:SetPoint("CENTER", minimapFrame, "CENTER", 0, 3)

    local minimapBorderTexture = MinimapBorder
    SetAtlasTexture(minimapBorderTexture, 'Minimap-Border')

    local zoomInButton = MinimapZoomIn
    zoomInButton:ClearAllPoints()
    zoomInButton:SetPoint("BOTTOMRIGHT", 0, 15)

    zoomInButton:SetSize(25, 24)
    zoomInButton:SetHitRectInsets(0, 0, 0, 0)

    normalTexture = zoomInButton:GetNormalTexture()
    normalTexture:SetAllPoints(zoomInButton)
    SetAtlasTexture(normalTexture, 'Minimap-ZoomIn-Normal')

    highlightTexture = zoomInButton:GetHighlightTexture()
    highlightTexture:SetAllPoints(zoomInButton)
    SetAtlasTexture(highlightTexture, 'Minimap-ZoomIn-Highlight')

    pushedTexture = zoomInButton:GetPushedTexture()
    pushedTexture:SetAllPoints(zoomInButton)
    SetAtlasTexture(pushedTexture, 'Minimap-ZoomIn-Pushed')

    local disabledTexture = zoomInButton:GetDisabledTexture()
    disabledTexture:SetAllPoints(zoomInButton)
    SetAtlasTexture(disabledTexture, 'Minimap-ZoomIn-Pushed')

    local zoomOutButton = MinimapZoomOut
    zoomOutButton:ClearAllPoints()
    zoomOutButton:SetPoint("BOTTOMRIGHT", -22, 0)

    zoomOutButton:SetSize(20, 12)
    zoomOutButton:SetHitRectInsets(0, 0, 0, 0)

    normalTexture = zoomOutButton:GetNormalTexture()
    normalTexture:SetAllPoints(zoomOutButton)
    SetAtlasTexture(normalTexture, 'Minimap-ZoomOut-Normal')

    highlightTexture = zoomOutButton:GetHighlightTexture()
    highlightTexture:SetAllPoints(zoomOutButton)
    SetAtlasTexture(highlightTexture, 'Minimap-ZoomOut-Highlight')

    pushedTexture = zoomOutButton:GetPushedTexture()
    pushedTexture:SetAllPoints(zoomOutButton)
    SetAtlasTexture(pushedTexture, 'Minimap-ZoomOut-Pushed')

    disabledTexture = zoomOutButton:GetDisabledTexture()
    disabledTexture:SetAllPoints(zoomOutButton)
    SetAtlasTexture(disabledTexture, 'Minimap-ZoomOut-Pushed')
    FixQueueButtonStrata()
end

local function CreateMinimapBorderFrame(width, height)
    local minimapBorderFrame = CreateFrame('Frame', UIParent)
    minimapBorderFrame:SetSize(width, height)
    minimapBorderFrame:SetScript("OnUpdate", function(self)
        local angle = GetPlayerFacing()
        self.border:SetRotation(angle)
    end)

    do
        local texture = minimapBorderFrame:CreateTexture(nil, "BORDER")
        texture:SetAllPoints(minimapBorderFrame)
        texture:SetTexture("Interface\\AddOns\\RetailUI\\Textures\\Minimap\\MinimapBorder.blp")

        minimapBorderFrame.border = texture
    end

    minimapBorderFrame:Hide()
    return minimapBorderFrame
end



local function RemoveBlizzardFrames()
    if MiniMapWorldMapButton then
        MiniMapWorldMapButton:Hide()
        MiniMapWorldMapButton:UnregisterAllEvents()
        MiniMapWorldMapButton:SetScript("OnClick", nil)
        MiniMapWorldMapButton:SetScript("OnEnter", nil)
        MiniMapWorldMapButton:SetScript("OnLeave", nil)
    end

    local blizzFrames = {
        MiniMapTrackingIcon,
        MiniMapTrackingIconOverlay,
        MiniMapMailBorder,
        MiniMapTrackingButtonBorder,
        MiniMapLFGFrameBorder
    }

    for _, frame in pairs(blizzFrames) do
        frame:SetAlpha(0)
    end
end

local function Minimap_UpdateRotationSetting()
    local minimapBorder = MinimapBorder
    if GetCVar("rotateMinimap") == "1" then
        Module.borderFrame:Show()
        minimapBorder:Hide()
    else
        Module.borderFrame:Hide()
        minimapBorder:Show()
    end

    MinimapNorthTag:Hide()
    MinimapCompassTexture:Hide()
end

local selectedRaidDifficulty
local allowedRaidDifficulty

local function MiniMapInstanceDifficulty_OnEvent(self)
    local _, instanceType, difficulty, _, maxPlayers, playerDifficulty, isDynamicInstance = GetInstanceInfo()
    if (instanceType == "party" or instanceType == "raid") and not (difficulty == 1 and maxPlayers == 5) then
        local isHeroic = false
        if instanceType == "party" and difficulty == 2 then
            isHeroic = true
        elseif instanceType == "raid" then
            if isDynamicInstance then
                selectedRaidDifficulty = difficulty
                if playerDifficulty == 1 then
                    if selectedRaidDifficulty <= 2 then
                        selectedRaidDifficulty = selectedRaidDifficulty + 2
                    end
                    isHeroic = true
                end
                -- if modified difficulty is normal then you are allowed to select heroic, and vice-versa
                if selectedRaidDifficulty == 1 then
                    allowedRaidDifficulty = 3
                elseif selectedRaidDifficulty == 2 then
                    allowedRaidDifficulty = 4
                elseif selectedRaidDifficulty == 3 then
                    allowedRaidDifficulty = 1
                elseif selectedRaidDifficulty == 4 then
                    allowedRaidDifficulty = 2
                end
                allowedRaidDifficulty = "RAID_DIFFICULTY" .. allowedRaidDifficulty
            elseif difficulty > 2 then
                isHeroic = true
            end
        end

        MiniMapInstanceDifficultyText:SetText(maxPlayers)
        -- the 1 looks a little off when text is centered
        local xOffset = 0
        if maxPlayers >= 10 and maxPlayers <= 19 then
            xOffset = -1
        end

        local minimapInstanceTexture = MiniMapInstanceDifficultyTexture

        if isHeroic then
            SetAtlasTexture(minimapInstanceTexture, 'Minimap-GuildBanner-Heroic')
            MiniMapInstanceDifficultyText:SetPoint("CENTER", xOffset, -6)
        else
            SetAtlasTexture(minimapInstanceTexture, 'Minimap-GuildBanner-Normal')
            MiniMapInstanceDifficultyText:SetPoint("CENTER", xOffset, 2)
        end
        minimapInstanceTexture:SetSize(minimapInstanceTexture:GetWidth() * 0.45,
            minimapInstanceTexture:GetHeight() * 0.45)
        self:Show()
    else
        self:Hide()
    end
end

function Module:OnEnable()
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    if not isHooked then
        MiniMapInstanceDifficulty:HookScript('OnEvent', MiniMapInstanceDifficulty_OnEvent)
    end

    self:SecureHook('Minimap_UpdateRotationSetting', Minimap_UpdateRotationSetting)

    self.minimapFrame = CreateUIFrame(230, 230, 'MinimapFrame')

    self.borderFrame = CreateMinimapBorderFrame(232, 232)
    self.borderFrame:SetPoint("CENTER", MinimapBorder, "CENTER", 0, -2)

    if not IsAddOnLoaded('Blizzard_TimeManager') then
        LoadAddOn('Blizzard_TimeManager')
    end
end

function Module:OnDisable()
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")

    MiniMapInstanceDifficulty:Unhook('OnEvent', MiniMapInstanceDifficulty_OnEvent)

    self:Unhook('Minimap_UpdateRotationSetting', Minimap_UpdateRotationSetting)
end

local function DisableBlizzardMinimapMouse()
    if MinimapCluster then
        MinimapCluster:EnableMouse(true)
        MinimapCluster:SetMovable(false)
        MinimapCluster:SetClampedToScreen(false)
        MinimapCluster:SetScript("OnMouseDown", nil)
        MinimapCluster:SetScript("OnMouseUp", nil)
        MinimapCluster:SetScript("OnDragStart", nil)
        MinimapCluster:SetScript("OnDragStop", nil)
    end

    if Minimap then
        Minimap:EnableMouse(true)
        Minimap:SetScript("OnMouseDown", nil)
        --Minimap:SetScript("OnMouseUp", nil)
        Minimap:SetScript("OnDragStart", nil)
        Minimap:SetScript("OnDragStop", nil)
    end
end

function Module:PLAYER_ENTERING_WORLD()
    RemoveBlizzardFrames()
    ReplaceBlizzardFrame(self.minimapFrame)
    DisableBlizzardMinimapMouse()
    FixQueueButtonStrata()
    CheckSettingsExists(Module, { 'minimap' })
end

function Module:LoadDefaultSettings()
    RUI.DB.profile.widgets.minimap = { anchor = "TOPRIGHT", posX = 0, posY = 0 }
end

function Module:UpdateWidgets()
    local widgetOptions = RUI.DB.profile.widgets.minimap
    self.minimapFrame:SetPoint(widgetOptions.anchor, widgetOptions.posX, widgetOptions.posY)
end

function Module:ShowEditorTest()
    HideUIFrame(self.minimapFrame)
end

function Module:HideEditorTest(refresh)
    ShowUIFrame(self.minimapFrame)
    SaveUIFramePosition(self.minimapFrame, 'minimap')

    if refresh then
        self:UpdateWidgets()
    end
end
