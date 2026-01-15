--[[

Copyright (c) Dmitriy. All rights reserved.
Licensed under the MIT license. See LICENSE file in the project root for details.

]]

-- Addon/module declaration
local RUI                    = LibStub('AceAddon-3.0'):GetAddon('RetailUI')
local moduleName             = 'UnitFrame'
local Module                 = RUI:NewModule(moduleName, 'AceConsole-3.0', 'AceHook-3.0', 'AceEvent-3.0')
_G.RetailUI_UnitFrameLoaded  = true

-- Frame handles (anchors for Blizzard frames)
Module.playerFrame           = nil -- main player anchor frame
Module.targetFrame           = nil -- main target anchor frame
Module.targetOfTargetFrame   = nil -- ToT anchor frame
Module.focusFrame            = nil -- focus anchor frame
Module.petFrame              = nil -- pet anchor frame
Module.bossFrames            = {}  -- boss1..boss4 anchor frames

-- Local upvalues for performance (optional but nice)
local _G                     = _G
local pairs                  = pairs
local UnitClass              = UnitClass
local UnitIsPlayer           = UnitIsPlayer
local UnitIsConnected        = UnitIsConnected
local UnitExists             = UnitExists
local UnitIsFriend           = UnitIsFriend
local UnitPowerType          = UnitPowerType
local UnitHasVehicleUI       = UnitHasVehicleUI
local UnitVehicleSkin        = UnitVehicleSkin
local UnitVehicleSeatCount   = UnitVehicleSeatCount
local UnitClassification     = UnitClassification
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitHealth             = UnitHealth
local UnitPower              = UnitPower
local UnitName               = UnitName
local UnitLevel              = UnitLevel
local UnitSelectionColor     = UnitSelectionColor
local RAID_CLASS_COLORS      = RAID_CLASS_COLORS
local PowerBarColor          = PowerBarColor
local MAX_TOTEMS             = MAX_TOTEMS
local MAX_RAID_MEMBERS       = MAX_RAID_MEMBERS
local MAX_COMBO_POINTS       = MAX_COMBO_POINTS
local AnimateTexCoords       = AnimateTexCoords
local SetPortraitTexture     = SetPortraitTexture

-- External helpers expected from the addon (declared here for clarity)
-- CreateUIFrame(width, height, key)
-- HideUIFrame(frame)
-- ShowUIFrame(frame)
-- SaveUIFramePosition(frame, key)
-- CheckSettingsExists(Module, widgetKeys)
-- SetAtlasTexture(texture, atlasName)
-- SetUpAnimation(frame, animTable, onFinished, reverse)

-------------------------------------------------
-- Widget defaults
-------------------------------------------------

function Module:LoadDefaultSettings()
    RUI.DB.profile.widgets                = RUI.DB.profile.widgets or {}

    RUI.DB.profile.widgets.player         = { anchor = "TOPLEFT", posX = 5, posY = -20, scale = 1 }
    RUI.DB.profile.widgets.target         = { anchor = "TOPLEFT", posX = 215, posY = -20, scale = 1 }
    RUI.DB.profile.widgets.focus          = { anchor = "TOPLEFT", posX = 105, posY = -165, scale = 1 }
    RUI.DB.profile.widgets.pet            = { anchor = "TOPLEFT", posX = 90, posY = -105, scale = 1 }
    RUI.DB.profile.widgets.targetOfTarget = { anchor = "TOPLEFT", posX = 370, posY = -80, scale = 1 }

    RUI.DB.profile.widgets["boss" .. 1]   = { anchor = "TOPRIGHT", posX = -100, posY = -270 }

    for index = 2, 4 do
        RUI.DB.profile.widgets["boss" .. index] = { anchor = "RIGHT", posX = 0, posY = 0 }
    end
end

-- Aura layout configuration
local AURA_CONFIG = {
    offsetY = 3,
    startX  = 6,
    startY  = 16,
}

local function Aura_SetSize(button, size)
    button:SetWidth(size)
    button:SetHeight(size)
end

local function Aura_SetBorderSize(prefixName, index, size)
    local border = _G[prefixName .. index .. "Border"]
    if border then
        border:SetWidth(size + 2)
        border:SetHeight(size + 2)
    end
end

local function Aura_AnchorFirstBuff(frame, buff, numDebuffs, offsetY)
    if UnitIsFriend("player", frame.unit) or numDebuffs == 0 then
        -- Friendly or no debuffs: buffs start directly under frame
        buff:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", AURA_CONFIG.startX, AURA_CONFIG.startY)
    else
        -- Hostile and there are debuffs: buffs start below debuff row
        buff:SetPoint("TOPLEFT", frame.debuffs, "BOTTOMLEFT", 0, -offsetY)
    end

    frame.buffs:SetPoint("TOPLEFT", buff, "TOPLEFT", 0, 0)
    frame.buffs:SetPoint("BOTTOMLEFT", buff, "BOTTOMLEFT", 0, -AURA_CONFIG.offsetY)
    frame.spellbarAnchor = buff
end

local function Aura_AnchorFirstDebuff(frame, debuff, numBuffs, offsetY)
    local isFriend = UnitIsFriend("player", frame.unit)

    if isFriend and numBuffs > 0 then
        -- Friendly with buffs: debuffs start below buff row
        debuff:SetPoint("TOPLEFT", frame.buffs, "BOTTOMLEFT", 0, -offsetY)
    else
        -- Hostile or no buffs: debuffs start directly under frame
        debuff:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", AURA_CONFIG.startX, AURA_CONFIG.startY)
    end

    frame.debuffs:SetPoint("TOPLEFT", debuff, "TOPLEFT", 0, 0)
    frame.debuffs:SetPoint("BOTTOMLEFT", debuff, "BOTTOMLEFT", 0, -AURA_CONFIG.offsetY)

    if isFriend or (not isFriend and numBuffs == 0) then
        frame.spellbarAnchor = debuff
    end
end

local function Aura_AnchorNewRow(frame, button, anchorPrefix, anchorIndex, offsetY, containerField)
    local anchor = _G[anchorPrefix .. anchorIndex]
    button:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -offsetY)

    local container = frame[containerField]
    container:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, -AURA_CONFIG.offsetY)
end

local function Aura_AnchorSameRow(prefixName, index, anchorIndex, offsetX)
    local prev = _G[prefixName .. anchorIndex]
    local button = _G[prefixName .. index]
    button:SetPoint("TOPLEFT", prev, "TOPRIGHT", offsetX, 0)
end

-- Buff anchor (keeps original signature for SecureHook)
local function TargetFrame_UpdateBuffAnchor(self, buffName, index, numDebuffs, anchorIndex, size, offsetX, offsetY)
    local buff = _G[buffName .. index]
    if not buff then
        return
    end

    if index == 1 then
        Aura_AnchorFirstBuff(self, buff, numDebuffs, offsetY)
    elseif anchorIndex ~= index - 1 then
        Aura_AnchorNewRow(self, buff, buffName, anchorIndex, offsetY, "buffs")
        self.spellbarAnchor = buff
    else
        Aura_AnchorSameRow(buffName, index, anchorIndex, offsetX)
    end

    Aura_SetSize(buff, size)
end

-- Debuff anchor (keeps original signature for SecureHook)
local function TargetFrame_UpdateDebuffAnchor(self, debuffName, index, numBuffs, anchorIndex, size, offsetX, offsetY)
    local debuff = _G[debuffName .. index]
    if not debuff then
        return
    end

    local isFriend = UnitIsFriend("player", self.unit)

    if index == 1 then
        Aura_AnchorFirstDebuff(self, debuff, numBuffs, offsetY)
    elseif anchorIndex ~= index - 1 then
        Aura_AnchorNewRow(self, debuff, debuffName, anchorIndex, offsetY, "debuffs")
        if isFriend or (not isFriend and numBuffs == 0) then
            self.spellbarAnchor = debuff
        end
    else
        Aura_AnchorSameRow(debuffName, index, anchorIndex, offsetX)
    end

    Aura_SetSize(debuff, size)
    Aura_SetBorderSize(debuffName, index, size)
end

-- Power color configuration (3.3.5 tokens)
local POWER_COLORS = {
    MANA        = { r = 0.02, g = 0.32, b = 0.71 },
    RAGE        = { r = 1.00, g = 0.00, b = 0.00 },
    FOCUS       = { r = 1.00, g = 0.50, b = 0.25 },
    ENERGY      = { r = 1.00, g = 1.00, b = 0.00 },
    HAPPINESS   = { r = 0.00, g = 1.00, b = 1.00 },
    RUNES       = { r = 0.50, g = 0.50, b = 0.50 },
    RUNIC_POWER = { r = 0.00, g = 0.82, b = 1.00 },
    AMMOSLOT    = { r = 0.80, g = 0.60, b = 0.00 },
    FUEL        = { r = 0.00, g = 0.55, b = 0.50 },
}

-- Numeric indices used in 3.3.5 UnitPowerType
POWER_COLORS[0] = POWER_COLORS.MANA
POWER_COLORS[1] = POWER_COLORS.RAGE
POWER_COLORS[2] = POWER_COLORS.FOCUS
POWER_COLORS[3] = POWER_COLORS.ENERGY
POWER_COLORS[4] = POWER_COLORS.HAPPINESS
POWER_COLORS[5] = POWER_COLORS.RUNES
POWER_COLORS[6] = POWER_COLORS.RUNIC_POWER

local function SetPowerBarColorByUnit(manaBar)
    if not manaBar or manaBar.lockColor or not manaBar.unit then
        return
    end

    local powerType, powerToken, altR, altG, altB = UnitPowerType(manaBar.unit)

    -- Prefer token (e.g. "MANA", "RAGE") if available
    local info = POWER_COLORS[powerToken]

    if info then
        manaBar:SetStatusBarColor(info.r, info.g, info.b)
        return
    end

    if altR then
        manaBar:SetStatusBarColor(altR, altG, altB)
        return
    end

    info = POWER_COLORS[powerType] or POWER_COLORS.MANA
    manaBar:SetStatusBarColor(info.r, info.g, info.b)
end

local function UnitFrameManaBar_UpdateType(manaBar)
    -- Preserve original name/signature for SecureHook
    SetPowerBarColorByUnit(manaBar)
end

-- Health color configuration
local HEALTH_COLOR_DEFAULT = { r = 0.48, g = 0.86, b = 0.15 }
local HEALTH_COLOR_DISCONNECTED = { r = 0.5, g = 0.5, b = 0.5 }

local function SetHealthBarColorByUnit(statusBar, unit)
    if not unit or not UnitExists(unit) or not statusBar or statusBar.lockColor then
        return
    end

    if not UnitIsConnected(unit) then
        statusBar:SetStatusBarColor(
            HEALTH_COLOR_DISCONNECTED.r,
            HEALTH_COLOR_DISCONNECTED.g,
            HEALTH_COLOR_DISCONNECTED.b
        )
        return
    end

    if UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        local color = RAID_CLASS_COLORS[class]
        if color then
            statusBar:SetStatusBarColor(color.r, color.g, color.b)
            return
        end
    end

    -- Fallback for NPCs etc.
    statusBar:SetStatusBarColor(
        HEALTH_COLOR_DEFAULT.r,
        HEALTH_COLOR_DEFAULT.g,
        HEALTH_COLOR_DEFAULT.b
    )
end

local function setHealthBarColor(statusBar, unit)
    -- Preserve original public helper name; used by hooks
    unit = unit or (statusBar and statusBar.unit)
    if not unit then
        return
    end

    SetHealthBarColorByUnit(statusBar, unit)
end

local function UnitFrameHealthBar_Update(statusBar, unit)
    if not statusBar or statusBar.lockValues then
        return
    end

    if unit ~= statusBar.unit then
        return
    end

    statusBar.disconnected = not UnitIsConnected(unit)

    if statusBar.disconnected then
        if not statusBar.lockColor then
            statusBar:SetStatusBarColor(
                HEALTH_COLOR_DISCONNECTED.r,
                HEALTH_COLOR_DISCONNECTED.g,
                HEALTH_COLOR_DISCONNECTED.b
            )
        end
    else
        if not statusBar.lockColor then
            setHealthBarColor(statusBar, unit)
        end
    end
end

local function HealthBar_OnValueChanged(self, value)
    if self.lockColor then
        return
    end
    setHealthBarColor(self)
end

-- General layout helpers
local function Frame_SetSizeAndPoint(frame, w, h, relativeTo, point, relPoint, x, y)
    frame:ClearAllPoints()
    frame:SetPoint(point or "LEFT", relativeTo, relPoint or "LEFT", x or 0, y or 0)
    frame:SetSize(w, h)
    frame:SetHitRectInsets(0, 0, 0, 0)
end

local function StatusBar_ApplyLayout(bar, cfg)
    bar:SetFrameLevel(cfg.frameLevel or (bar:GetParent():GetFrameLevel() + 1))
    bar:ClearAllPoints()
    bar:SetPoint(unpack(cfg.point))
    bar:SetSize(cfg.width, cfg.height)

    local tex = bar:GetStatusBarTexture()
    tex:SetAllPoints(bar)
    if cfg.atlas then
        SetAtlasTexture(tex, cfg.atlas)
    end
end

local function Texture_ApplyLayout(tex, cfg)
    tex:ClearAllPoints()
    tex:SetPoint(unpack(cfg.point))
    if cfg.width and cfg.height then
        tex:SetSize(cfg.width, cfg.height)
    end
    if cfg.tex then
        tex:SetTexture(cfg.tex)
    end
    if cfg.texCoord then
        tex:SetTexCoord(unpack(cfg.texCoord))
    end
    if cfg.layer then
        tex:SetDrawLayer(cfg.layer)
    end
    if cfg.blend then
        tex:SetBlendMode(cfg.blend)
    end
end

local function FontString_ApplyLayout(fs, cfg)
    fs:ClearAllPoints()
    fs:SetPoint(unpack(cfg.point))
    if cfg.width then
        fs:SetWidth(cfg.width)
    end
    if cfg.justifyH then
        fs:SetJustifyH(cfg.justifyH)
    end
    if cfg.layer then
        fs:SetDrawLayer(cfg.layer)
    end
end

-- Player frame layout
local PLAYER_LAYOUT = {
    size = { 192, 68 },
    portrait = {
        point = { "LEFT", 14, 10 },
        width = 56,
        height = 56,
        layer = "BACKGROUND",
    },
    healthBar = {
        point = { "TOPLEFT", 72, -15 },
        width = 123,
        height = 20,
        atlas = "PlayerFrame-StatusBar-Health",
        frameLevel = nil,
    },
    manaBar = {
        point = { "TOPLEFT", 72, -37 },
        width = 123,
        height = 9,
        atlas = "PlayerFrame-StatusBar-Mana",
        frameLevel = nil,
    },
    name = {
        point = { "CENTER", 25, 27 },
        width = 90,
        justifyH = "LEFT",
        layer = "OVERLAY",
    },
    level = {
        point = { "CENTER", 88, 27 },
        layer = "OVERLAY",
    },
}

local function ReplaceBlizzardPlayerFrame(anchorFrame)
    local playerFrame = PlayerFrame

    Frame_SetSizeAndPoint(
        playerFrame,
        PLAYER_LAYOUT.size[1],
        PLAYER_LAYOUT.size[2],
        anchorFrame,
        "LEFT",
        "LEFT",
        0,
        0
    )

    -- Portrait
    Texture_ApplyLayout(PlayerPortrait, {
        point  = PLAYER_LAYOUT.portrait.point,
        width  = PLAYER_LAYOUT.portrait.width,
        height = PLAYER_LAYOUT.portrait.height,
        layer  = PLAYER_LAYOUT.portrait.layer,
    })

    -- Main border + vehicle border
    local tex = _G[playerFrame:GetName() .. "Texture"]
    Texture_ApplyLayout(tex, {
        point = { "BOTTOMLEFT", 0, 0 },
        layer = "BORDER",
    })

    local vehTex = _G[playerFrame:GetName() .. "VehicleTexture"]
    Texture_ApplyLayout(vehTex, {
        point = { "BOTTOMLEFT", 0, 0 },
        layer = "BORDER",
    })

    -- Bars
    PLAYER_LAYOUT.healthBar.frameLevel = playerFrame:GetFrameLevel() + 2
    PLAYER_LAYOUT.manaBar.frameLevel   = playerFrame:GetFrameLevel() + 2

    StatusBar_ApplyLayout(_G[playerFrame:GetName() .. "HealthBar"], PLAYER_LAYOUT.healthBar)
    StatusBar_ApplyLayout(_G[playerFrame:GetName() .. "ManaBar"], PLAYER_LAYOUT.manaBar)

    -- Name / level / values
    FontString_ApplyLayout(PlayerName, PLAYER_LAYOUT.name)
    FontString_ApplyLayout(PlayerLevelText, PLAYER_LAYOUT.level)

    local healthText = _G[playerFrame:GetName() .. "HealthBarText"]
    local manaText   = _G[playerFrame:GetName() .. "ManaBarText"]
    healthText:SetDrawLayer("OVERLAY")
    manaText:SetDrawLayer("OVERLAY")

    -- Rest, attack, status, pvp timer, flash, hit, role, group indicator:
    Texture_ApplyLayout(PlayerRestIcon, {
        point = { "TOPLEFT", 50, 23 },
        tex   = "Interface\\AddOns\\RetailUI\\Textures\\PlayerFrame\\PlayerRestFlipbook.blp",
        layer = "ARTWORK",
    })

    Texture_ApplyLayout(PlayerAttackIcon, {
        point = { "BOTTOMLEFT", 50, 17 },
        layer = "OVERLAY",
    })
    SetAtlasTexture(PlayerAttackIcon, "PlayerFrame-AttackIcon")

    Texture_ApplyLayout(PlayerStatusTexture, {
        point = { "BOTTOMLEFT", 0, 0 },
        layer = "OVERLAY",
    })

    PlayerPVPTimerText:ClearAllPoints()
    PlayerPVPTimerText:SetPoint("CENTER", playerFrame, "BOTTOMLEFT", 12, 5)

    local flashTexture = _G[playerFrame:GetName() .. "Flash"]
    Texture_ApplyLayout(flashTexture, {
        point = { "BOTTOMLEFT", 0, 0 },
        layer = "OVERLAY",
    })

    local hitText = PlayerHitIndicator
    hitText:ClearAllPoints()
    hitText:SetJustifyH("CENTER")
    hitText:SetPoint("LEFT", 5, 7)
    hitText:SetWidth(75)

    local roleIconTexture = _G[playerFrame:GetName() .. "RoleIcon"]
    Texture_ApplyLayout(roleIconTexture, {
        point = { "BOTTOM", playerFrame, "TOP", 88, 0 },
    })

    local groupIndicatorFrame = _G[playerFrame:GetName() .. "GroupIndicator"]
    local backgroundTexture   = _G[playerFrame:GetName() .. "GroupIndicatorMiddle"]
    backgroundTexture:SetAllPoints(groupIndicatorFrame)
    SetAtlasTexture(backgroundTexture, "PlayerFrame-GroupIndicator")
    backgroundTexture:SetVertexColor(1, 1, 1, 1)
    groupIndicatorFrame:SetSize(backgroundTexture:GetWidth(), backgroundTexture:GetHeight())

    local groupText = _G["PlayerFrameGroupIndicatorText"]
    groupText:ClearAllPoints()
    groupText:SetPoint("CENTER", groupIndicatorFrame, 0, 0)
    groupText:SetJustifyH("CENTER")
end

local TARGET_LAYOUT = {
    size = { 192, 68 },
    healthBar = {
        point = { "TOPLEFT", 5, -15 },
        width = 124,
        height = 20,
        atlas = "TargetFrame-StatusBar-Health",
    },
    manaBar = {
        point = { "TOPLEFT", 4, -37 },
        width = 132,
        height = 10,
        atlas = "TargetFrame-StatusBar-Mana",
    },
}

local function ReplaceBlizzardTargetFrame(anchorFrame, targetFrame, isBoss)
    isBoss = isBoss or false

    Frame_SetSizeAndPoint(
        targetFrame,
        TARGET_LAYOUT.size[1],
        TARGET_LAYOUT.size[2],
        anchorFrame,
        "LEFT",
        "LEFT",
        0,
        0
    )

    local borderTexture = _G[targetFrame:GetName() .. "TextureFrameTexture"]
    Texture_ApplyLayout(borderTexture, {
        point = { "BOTTOMLEFT", 0, 0 },
        layer = "BORDER",
    })
    SetAtlasTexture(borderTexture, isBoss and "TargetFrame-TextureFrame-RareElite" or "TargetFrame-TextureFrame-Normal")

    local portraitTexture = _G[targetFrame:GetName() .. "Portrait"]
    Texture_ApplyLayout(portraitTexture, {
        point = { "RIGHT", -5, 8 },
        width = 56,
        height = 56,
        layer = "BACKGROUND",
    })

    local backgroundTexture = _G[targetFrame:GetName() .. "NameBackground"]
    Texture_ApplyLayout(backgroundTexture, {
        point    = { "TOPLEFT", 4, -2 },
        width    = nil,
        height   = nil, -- using SetPoint to both corners below
        tex      = "Interface\\AddOns\\RetailUI\\Textures\\TargetFrame\\NameBackground.blp",
        texCoord = { 0.05, 0.95, 0.05, 0.95 },
        layer    = "BORDER",
        blend    = "ADD",
    })
    backgroundTexture:SetPoint("BOTTOMRIGHT", -56, 44)

    local healthBar = _G[targetFrame:GetName() .. "HealthBar"]
    TARGET_LAYOUT.healthBar.frameLevel = targetFrame:GetFrameLevel() + 1
    StatusBar_ApplyLayout(healthBar, TARGET_LAYOUT.healthBar)

    local manaBar = _G[targetFrame:GetName() .. "ManaBar"]
    TARGET_LAYOUT.manaBar.frameLevel = targetFrame:GetFrameLevel() + 1
    StatusBar_ApplyLayout(manaBar, TARGET_LAYOUT.manaBar)

    local nameText = _G[targetFrame:GetName() .. "TextureFrameName"]
    FontString_ApplyLayout(nameText, {
        point    = { "CENTER", -20, 27 },
        width    = 80,
        justifyH = "LEFT",
        layer    = "OVERLAY",
    })

    local levelText = _G[targetFrame:GetName() .. "TextureFrameLevelText"]
    FontString_ApplyLayout(levelText, {
        point    = { "CENTER", -80, 27 },
        justifyH = "LEFT",
        layer    = "OVERLAY",
    })

    local highLevelTexture = _G[targetFrame:GetName() .. "TextureFrameHighLevelTexture"]
    Texture_ApplyLayout(highLevelTexture, {
        point = { "CENTER", levelText, "CENTER", 0, 0 },
    })
    SetAtlasTexture(highLevelTexture, "TargetFrame-HighLevelIcon")

    local healthText = _G[targetFrame:GetName() .. "TextureFrameHealthBarText"]
    FontString_ApplyLayout(healthText, {
        point = { "CENTER", -25, 8 },
        layer = "OVERLAY",
    })

    local deathText = _G[targetFrame:GetName() .. "TextureFrameDeadText"]
    FontString_ApplyLayout(deathText, {
        point = { "CENTER", -25, 8 },
        layer = "OVERLAY",
    })

    local manaText = _G[targetFrame:GetName() .. "TextureFrameManaBarText"]
    FontString_ApplyLayout(manaText, {
        point = { "CENTER", -25, -8 },
        layer = "OVERLAY",
    })

    local pvpIconTexture = _G[targetFrame:GetName() .. "TextureFramePVPIcon"]
    Texture_ApplyLayout(pvpIconTexture, {
        point = { "CENTER", targetFrame, "BOTTOMRIGHT", 6, 14 },
    })

    local leaderIconTexture = _G[targetFrame:GetName() .. "TextureFrameLeaderIcon"]
    Texture_ApplyLayout(leaderIconTexture, {
        point = { "BOTTOM", targetFrame, "TOP", 26, -3 },
    })

    local flashTexture = _G[targetFrame:GetName() .. "Flash"]
    flashTexture:SetDrawLayer("OVERLAY")

    local raidTargetIconTexture = _G["TargetFrameTextureFrameRaidTargetIcon"]
    Texture_ApplyLayout(raidTargetIconTexture, {
        point = { "TOPRIGHT", -20, 18 },
    })

    local numericalThreatFrame = _G[targetFrame:GetName() .. "NumericalThreat"]
    numericalThreatFrame:ClearAllPoints()
    numericalThreatFrame:SetPoint("BOTTOM", targetFrame, "TOP", -22, -2)
    for _, region in pairs { numericalThreatFrame:GetRegions() } do
        if region:GetObjectType() == "Texture" and region:GetDrawLayer() == "ARTWORK" then
            region:SetAllPoints(numericalThreatFrame)
            SetAtlasTexture(region, "PlayerFrame-GroupIndicator")
            region:SetVertexColor(1, 1, 1, 1)
        end
    end

    targetFrame.ShowTest = function(self)
        local portraitTexture = _G[self:GetName() .. "Portrait"]
        SetPortraitTexture(portraitTexture, "player")

        local backgroundTexture = _G[self:GetName() .. "NameBackground"]
        backgroundTexture:SetVertexColor(UnitSelectionColor("player"))

        local deathText = _G[self:GetName() .. "TextureFrameDeadText"]
        deathText:Hide()

        local highLevelTexture = _G[self:GetName() .. "TextureFrameHighLevelTexture"]
        highLevelTexture:Hide()

        local nameText = _G[self:GetName() .. "TextureFrameName"]
        nameText:SetText(UnitName("player"))

        local levelText = _G[self:GetName() .. "TextureFrameLevelText"]
        levelText:SetText(UnitLevel("player"))
        levelText:Show()

        local healthText = _G[self:GetName() .. "TextureFrameHealthBarText"]
        local curHealth = UnitHealth("player")
        healthText:SetText(curHealth .. "/" .. curHealth)

        local manaText = _G[self:GetName() .. "TextureFrameManaBarText"]
        local curMana = UnitPower("player", Mana)
        manaText:SetText(curMana .. "/" .. curMana)

        local healthBar = _G[self:GetName() .. "HealthBar"]
        healthBar:SetMinMaxValues(0, curHealth)
        healthBar:SetStatusBarColor(0.29, 0.69, 0.07)
        healthBar:SetValue(curHealth)
        healthBar:Show()

        local manaBar = _G[self:GetName() .. "ManaBar"]
        manaBar:SetMinMaxValues(0, curMana)
        manaBar:SetValue(curMana)
        manaBar:SetStatusBarColor(0.02, 0.32, 0.71)
        manaBar:Show()

        self:Show()
    end

    targetFrame.HideTest = function(self)
        self:Hide()
    end
end

local PET_LAYOUT = {
    size = { 120, 47 },
    healthBar = {
        point = { "TOPLEFT", 43, -16 },
        width = 71,
        height = 9,
        atlas = "PartyFrame-StatusBar-Health",
    },
    manaBar = {
        point = { "TOPLEFT", 41, -27 },
        width = 73,
        height = 7,
        atlas = "PartyFrame-StatusBar-Mana",
    },
}

local function ReplaceBlizzardPetFrame(anchorFrame)
    local petFrame = PetFrame

    Frame_SetSizeAndPoint(
        petFrame,
        PET_LAYOUT.size[1],
        PET_LAYOUT.size[2],
        anchorFrame,
        "LEFT",
        "LEFT",
        0,
        0
    )

    Texture_ApplyLayout(PetPortrait, {
        point = { "LEFT", 6, 0 },
        width = 34,
        height = 34,
        layer = "BACKGROUND",
    })

    local borderTexture = _G[petFrame:GetName() .. "Texture"]
    Texture_ApplyLayout(borderTexture, {
        point = { "BOTTOMLEFT", 0, 0 },
        layer = "BORDER",
    })

    local healthBar = _G[petFrame:GetName() .. "HealthBar"]
    PET_LAYOUT.healthBar.frameLevel = petFrame:GetFrameLevel() + 2
    StatusBar_ApplyLayout(healthBar, PET_LAYOUT.healthBar)

    local manaBar = _G[petFrame:GetName() .. "ManaBar"]
    PET_LAYOUT.manaBar.frameLevel = petFrame:GetFrameLevel() + 2
    StatusBar_ApplyLayout(manaBar, PET_LAYOUT.manaBar)

    local flashTexture = _G[petFrame:GetName() .. "Flash"]
    Texture_ApplyLayout(flashTexture, {
        point = { "BOTTOMLEFT", 0, 0 },
        layer = "OVERLAY",
    })
    SetAtlasTexture(flashTexture, "PartyFrame-Flash")

    Texture_ApplyLayout(PetAttackModeTexture, {
        point = { "BOTTOMLEFT", 0, 0 },
        layer = "OVERLAY",
    })
    SetAtlasTexture(PetAttackModeTexture, "PartyFrame-Status")

    FontString_ApplyLayout(PetName, {
        point    = { "CENTER", 16, 16 },
        width    = 65,
        justifyH = "LEFT",
        layer    = "OVERLAY",
    })

    local healthText = _G[petFrame:GetName() .. "HealthBarText"]
    FontString_ApplyLayout(healthText, {
        point = { "CENTER", 19, 4 },
        layer = "OVERLAY",
    })

    local manaText = _G[petFrame:GetName() .. "ManaBarText"]
    FontString_ApplyLayout(manaText, {
        point = { "CENTER", 19, -7 },
        layer = "OVERLAY",
    })

    local happinessTexture = _G[petFrame:GetName() .. "Happiness"]
    Texture_ApplyLayout(happinessTexture, {
        point = { "LEFT", petFrame, "RIGHT", 1, -2 },
    })
end

-------------------------------------------------
-- Rune / Totem / Combo replacements
-------------------------------------------------

local function UpdateRune(button)
    local runeIndex = button:GetID()
    local runeType = GetRuneType(runeIndex)
    if not runeType then
        return
    end

    local runeTexture = _G[button:GetName() .. "Rune"]
    if not runeTexture then
        return
    end

    runeTexture:SetTexture("Interface\\AddOns\\RetailUI\\Textures\\PlayerFrame\\ClassOverlayDeathKnightRunes.BLP")

    -- 1: Blood, 2: Unholy, 3: Frost, 4: Death
    if runeType == 1 then
        runeTexture:SetTexCoord(0 / 128, 34 / 128, 0 / 128, 34 / 128)
    elseif runeType == 2 then
        runeTexture:SetTexCoord(0 / 128, 34 / 128, 68 / 128, 102 / 128)
    elseif runeType == 3 then
        runeTexture:SetTexCoord(34 / 128, 68 / 128, 0 / 128, 34 / 128)
    elseif runeType == 4 then
        runeTexture:SetTexCoord(68 / 128, 102 / 128, 0 / 128, 34 / 128)
    end
end

local function ReplaceBlizzardRuneFrame()
    for index = 1, 6 do
        local button = _G["RuneButtonIndividual" .. index]
        if button then
            button:ClearAllPoints()
            if index > 1 then
                button:SetPoint("LEFT", _G["RuneButtonIndividual" .. (index - 1)], "RIGHT", 4, 0)
            else
                button:SetPoint("CENTER", PlayerFrame, "BOTTOM", -20, 0)
            end
            UpdateRune(button)
        end
    end
end

local function ReplaceBlizzardTotemFrame()
    for index = 1, MAX_TOTEMS do
        local button = _G["TotemFrameTotem" .. index]
        if button then
            button:ClearAllPoints()
            button:SetSize(32, 32)

            local backgroundTexture = _G[button:GetName() .. "Background"]
            if backgroundTexture then
                backgroundTexture:SetAllPoints(button)
            end

            for _, child in pairs { button:GetChildren() } do
                for _, region in pairs { child:GetRegions() } do
                    if region:GetObjectType() == "Texture" and region:GetDrawLayer() == "OVERLAY" then
                        region:SetAllPoints(button)
                    end
                end
            end

            local iconTexture = _G[button:GetName() .. "IconTexture"]
            if iconTexture then
                iconTexture:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -7)
                iconTexture:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -7, 7)
                iconTexture:SetTexCoord(0.05, 0.95, 0.05, 0.95)
                iconTexture:SetDrawLayer("BACKGROUND")
            end

            if index > 1 then
                button:SetPoint("LEFT", _G["TotemFrameTotem" .. (index - 1)], "RIGHT", 2, 0)
            else
                button:SetPoint("CENTER", PlayerFrame, "BOTTOM", -15, -4)
            end
        end
    end
end

local function ReplaceBlizzardComboFrame()
    local comboOffsets = {
        { anchor = "TOPRIGHT", x = 3,  y = 2 },
        { anchor = "TOP",      x = 6,  y = 4 },
        { anchor = "TOP",      x = 3,  y = 2 },
        { anchor = "TOP",      x = -1, y = 2 },
        { anchor = "TOP",      x = -6, y = 3 },
    }

    local comboFrame = ComboFrame
    comboFrame:ClearAllPoints()
    comboFrame:SetPoint("CENTER", TargetFrame, "CENTER", -34, 22)

    for index = 1, MAX_COMBO_POINTS do
        local comboPoint = _G["ComboPoint" .. index]
        if comboPoint then
            local cfg = comboOffsets[index]
            if index > 1 then
                comboPoint:SetPoint(cfg.anchor, _G["ComboPoint" .. (index - 1)], "BOTTOM", cfg.x, cfg.y)
            else
                comboPoint:SetPoint(cfg.anchor, cfg.x, cfg.y)
            end

            comboPoint:SetSize(14, 14)

            for _, region in pairs { comboPoint:GetRegions() } do
                if region:GetObjectType() == "Texture" and region:GetDrawLayer() == "BACKGROUND" then
                    region:SetAllPoints(comboPoint)
                    region:SetTexture("Interface\\AddOns\\RetailUI\\Textures\\PlayerFrame\\ClassOverlayComboPoints.BLP")
                    region:SetTexCoord(76 / 128, 98 / 128, 19 / 64, 41 / 64)
                end
            end

            local shineTexture = _G[comboPoint:GetName() .. "Shine"]
            if shineTexture then
                shineTexture:ClearAllPoints()
                shineTexture:SetPoint("CENTER", comboPoint, "CENTER", 0, 0)
            end

            local highlightTexture = _G[comboPoint:GetName() .. "Highlight"]
            if highlightTexture then
                highlightTexture:ClearAllPoints()
                highlightTexture:SetPoint("CENTER", comboPoint, "CENTER", 0, 0)
                highlightTexture:SetTexture(
                    "Interface\\AddOns\\RetailUI\\Textures\\PlayerFrame\\ClassOverlayComboPoints.BLP")
                highlightTexture:SetTexCoord(55 / 128, 75 / 128, 21 / 64, 41 / 64)
                highlightTexture:SetSize(13, 13)
            end
        end
    end
end

-------------------------------------------------
-- Player group indicator and status
-------------------------------------------------

local function UpdateGroupIndicator()
    local playerFrame = PlayerFrame
    local groupIndicatorFrame = _G[playerFrame:GetName() .. "GroupIndicator"]
    local groupText = _G[playerFrame:GetName() .. "GroupIndicatorText"]

    groupIndicatorFrame:Hide()

    local numRaid = GetNumRaidMembers()
    if numRaid == 0 then
        return
    end

    for i = 1, MAX_RAID_MEMBERS do
        if i <= numRaid then
            local name, _, subgroup = GetRaidRosterInfo(i)
            if name == UnitName("player") then
                groupText:SetText(GROUP .. " " .. subgroup)

                local backgroundTexture = _G[playerFrame:GetName() .. "GroupIndicatorMiddle"]
                groupIndicatorFrame:SetSize(backgroundTexture:GetWidth(), backgroundTexture:GetHeight())
                groupIndicatorFrame:Show()
                break
            end
        end
    end
end

local function PlayerFrame_OnUpdate(self, elapsed)
    local playerRestIcon = PlayerRestIcon
    AnimateTexCoords(playerRestIcon, 512, 512, 64, 64, 42, elapsed, 0.05)
end

local function PlayerFrame_UpdateStatus()
    PlayerStatusGlow:Hide()
end

local function PlayerFrame_UpdateGroupIndicator()
    UpdateGroupIndicator()
end

-------------------------------------------------
-- Player art / vehicle art
-------------------------------------------------

local function PlayerFrame_ToPlayerArt(self)
    local playerFrame = PlayerFrame

    -- Portrait
    local portraitTexture = PlayerPortrait
    portraitTexture:ClearAllPoints()
    portraitTexture:SetPoint("LEFT", 14, 10)
    portraitTexture:SetSize(56, 56)

    -- Main border
    local borderTexture = _G[playerFrame:GetName() .. "Texture"]
    SetAtlasTexture(borderTexture, "PlayerFrame-TextureFrame-Normal")

    -- Health / mana bars
    local healthBar = _G[playerFrame:GetName() .. "HealthBar"]
    healthBar:ClearAllPoints()
    healthBar:SetPoint("TOPLEFT", 72, -15)
    healthBar:SetSize(123, 20)

    local manaBar = _G[playerFrame:GetName() .. "ManaBar"]
    manaBar:ClearAllPoints()
    manaBar:SetPoint("TOPLEFT", 72, -37)
    manaBar:SetSize(123, 9)

    -- Texts
    local nameText = PlayerName
    nameText:ClearAllPoints()
    nameText:SetPoint("CENTER", 25, 27)

    local healthText = _G[playerFrame:GetName() .. "HealthBarText"]
    healthText:ClearAllPoints()
    healthText:SetPoint("CENTER", 36, 8)

    local manaText = _G[playerFrame:GetName() .. "ManaBarText"]
    manaText:ClearAllPoints()
    manaText:SetPoint("CENTER", 36, -8)

    -- Status texture
    local statusTexture = PlayerStatusTexture
    SetAtlasTexture(statusTexture, "PlayerFrame-Status")

    -- Leader / master icons
    local leaderIconTexture = PlayerLeaderIcon
    leaderIconTexture:ClearAllPoints()
    leaderIconTexture:SetPoint("BOTTOM", playerFrame, "TOP", -15, -3)

    local masterIconTexture = PlayerMasterIcon
    masterIconTexture:ClearAllPoints()
    masterIconTexture:SetPoint("BOTTOM", playerFrame, "TOP", 2, -1)

    -- Flash
    local flashTexture = PlayerFrameFlash
    SetAtlasTexture(flashTexture, "PlayerFrame-Flash")

    -- Group indicator
    local groupIndicatorFrame = PlayerFrameGroupIndicator
    groupIndicatorFrame:ClearAllPoints()
    groupIndicatorFrame:SetPoint("BOTTOMLEFT", playerFrame, "TOP", 20, -2)

    -- PvP icon
    local pvpIconTexture = PlayerPVPIcon
    pvpIconTexture:ClearAllPoints()
    pvpIconTexture:SetPoint("CENTER", playerFrame, "BOTTOMLEFT", 22, 14)

    -- Show runes when in player art
    for index = 1, 6 do
        local button = _G["RuneButtonIndividual" .. index]
        if button then
            button:Show()
        end
    end

    UpdateGroupIndicator()
end

local function PlayerFrame_ToVehicleArt(self, vehicleType)
    local playerFrame = PlayerFrame

    -- Portrait
    local portraitTexture = PlayerPortrait
    portraitTexture:ClearAllPoints()
    portraitTexture:SetPoint("LEFT", 14, 10)
    portraitTexture:SetSize(62, 62)

    -- Vehicle border
    local borderTexture = _G[playerFrame:GetName() .. "VehicleTexture"]
    SetAtlasTexture(borderTexture, "PlayerFrame-TextureFrame-Vehicle")

    -- Health / mana bars
    local healthBar = _G[playerFrame:GetName() .. "HealthBar"]
    healthBar:ClearAllPoints()
    healthBar:SetPoint("TOPLEFT", 78, -15)
    healthBar:SetSize(117, 20)

    local manaBar = _G[playerFrame:GetName() .. "ManaBar"]
    manaBar:ClearAllPoints()
    manaBar:SetPoint("TOPLEFT", 78, -37)
    manaBar:SetSize(117, 9)

    -- Texts
    local nameText = PlayerName
    nameText:ClearAllPoints()
    nameText:SetPoint("CENTER", 30, 26)

    local healthText = _G[playerFrame:GetName() .. "HealthBarText"]
    healthText:ClearAllPoints()
    healthText:SetPoint("CENTER", 40, 8)

    local manaText = _G[playerFrame:GetName() .. "ManaBarText"]
    manaText:ClearAllPoints()
    manaText:SetPoint("CENTER", 40, -8)

    -- Leader / master icons
    local leaderIconTexture = PlayerLeaderIcon
    leaderIconTexture:ClearAllPoints()
    leaderIconTexture:SetPoint("BOTTOM", playerFrame, "TOP", -15, -3)

    local masterIconTexture = PlayerMasterIcon
    masterIconTexture:ClearAllPoints()
    masterIconTexture:SetPoint("BOTTOM", playerFrame, "TOP", 2, -1)

    -- Group indicator
    local groupIndicatorFrame = _G[playerFrame:GetName() .. "GroupIndicator"]
    groupIndicatorFrame:ClearAllPoints()
    groupIndicatorFrame:SetPoint("BOTTOMLEFT", playerFrame, "TOP", 20, 0)

    -- PvP icon
    local pvpIconTexture = PlayerPVPIcon
    pvpIconTexture:ClearAllPoints()
    pvpIconTexture:SetPoint("CENTER", playerFrame, "BOTTOMLEFT", 20, 10)

    -- Hide runes in vehicle art
    for index = 1, 6 do
        local button = _G["RuneButtonIndividual" .. index]
        if button then
            button:Hide()
        end
    end
end

-------------------------------------------------
-- Player frame animations and roles
-------------------------------------------------

local function PlayerFrame_SequenceFinished(self)
    local playerFrame = PlayerFrame
    playerFrame:ClearAllPoints()
    playerFrame:SetPoint("LEFT", Module.playerFrame, "LEFT", 0, 0)
end

local function PlayerFrame_AnimPos(self, fraction)
    local _, _, relativePoint, posX, posY = self:GetPoint("CENTER")
    return relativePoint, posX, posY + 1000
end

local PlayerFrameAnimTable = {
    totalTime  = 0.0,
    updateFunc = "SetPoint",
    getPosFunc = PlayerFrame_AnimPos,
}

local function PlayerFrame_AnimateOut(self)
    SetUpAnimation(PlayerFrame, PlayerFrameAnimTable, PlayerFrame_AnimFinished, false)
end

local function PlayerFrame_UpdateArt(self)
    if self.animFinished and self.inSeat and self.inSequence then
        SetUpAnimation(PlayerFrame, PlayerFrameAnimTable, PlayerFrame_SequenceFinished, true)

        if UnitHasVehicleUI("player") then
            PlayerFrame_ToVehicleArt(self, UnitVehicleSkin("player"))
        else
            PlayerFrame_ToPlayerArt(self)
        end
    end
end

local function PlayerFrame_UpdateRolesAssigned()
    local iconTexture = _G[PlayerFrame:GetName() .. "RoleIcon"]
    if not iconTexture or not UnitGroupRolesAssigned then
        return
    end

    local isTank, isHealer, isDamage = UnitGroupRolesAssigned("player")
    if isTank then
        SetAtlasTexture(iconTexture, "LFGRole-Tank")
        iconTexture:SetSize(iconTexture:GetWidth() * 0.9, iconTexture:GetHeight() * 0.9)
        iconTexture:Show()
    elseif isHealer then
        SetAtlasTexture(iconTexture, "LFGRole-Healer")
        iconTexture:SetSize(iconTexture:GetWidth() * 0.9, iconTexture:GetHeight() * 0.9)
        iconTexture:Show()
    elseif isDamage then
        SetAtlasTexture(iconTexture, "LFGRole-Damage")
        iconTexture:SetSize(iconTexture:GetWidth() * 0.9, iconTexture:GetHeight() * 0.9)
        iconTexture:Show()
    else
        iconTexture:Hide()
    end
end

-------------------------------------------------
-- Target classification styling
-------------------------------------------------

local function TargetFrame_CheckClassification(self, forceNormalTexture)
    local healthBar      = _G[self:GetName() .. "HealthBar"]
    local manaBar        = _G[self:GetName() .. "ManaBar"]
    local nameText       = _G[self:GetName() .. "TextureFrameName"]
    local levelText      = _G[self:GetName() .. "TextureFrameLevelText"]
    local pvpIconTexture = _G[self:GetName() .. "TextureFramePVPIcon"]

    -- Reset to default layout
    healthBar:SetSize(124, 20)
    manaBar:SetSize(132, 10)

    nameText:ClearAllPoints()
    nameText:SetPoint("CENTER", -20, 27)

    levelText:ClearAllPoints()
    levelText:SetPoint("CENTER", -80, 27)

    pvpIconTexture:ClearAllPoints()
    pvpIconTexture:SetPoint("CENTER", self, "BOTTOMRIGHT", 6, 14)

    local classification = UnitClassification(self.unit)

    if classification == "worldboss" or classification == "elite" then
        SetAtlasTexture(self.borderTexture, "TargetFrame-TextureFrame-Elite")
    elseif classification == "rareelite" then
        SetAtlasTexture(self.borderTexture, "TargetFrame-TextureFrame-RareElite")
    elseif classification == "rare" then
        SetAtlasTexture(self.borderTexture, "TargetFrame-TextureFrame-Rare")
    else
        local isVehicle = UnitVehicleSeatCount(self.unit) > 0
        if isVehicle then
            healthBar:SetSize(116, 20)
            manaBar:SetSize(123, 10)

            nameText:SetPoint("CENTER", -20, 26)
            levelText:SetPoint("CENTER", -80, 26)

            pvpIconTexture:SetPoint("CENTER", self, "BOTTOMRIGHT", 8, 10)

            SetAtlasTexture(self.borderTexture, "TargetFrame-TextureFrame-Vehicle")
        else
            SetAtlasTexture(self.borderTexture, "TargetFrame-TextureFrame-Normal")
        end
    end

    self.threatIndicator:ClearAllPoints()
    self.threatIndicator:SetPoint("BOTTOMLEFT", 0, 0)
    SetAtlasTexture(self.threatIndicator, "TargetFrame-Status")
end

-------------------------------------------------
-- Focus frame size behavior
-------------------------------------------------

local function FocusFrame_SetSmallSize(smallSize, onChange)
    -- Reapply our custom layout whenever Blizzard toggles small size
    ReplaceBlizzardTargetFrame(Module.focusFrame, FocusFrame)
end

-------------------------------------------------
-- Pet frame extras
-------------------------------------------------

local function PetFrame_Update(self)
    SetAtlasTexture(PetFrameTexture, "PartyFrame-TextureFrame-Normal")
end

-------------------------------------------------
-- Target-of-Target frame replacement
-------------------------------------------------

local function ReplaceBlizzardTOTFrame(anchorFrame)
    local targetFrameToT = TargetFrameToT

    targetFrameToT:ClearAllPoints()
    targetFrameToT:SetPoint("LEFT", anchorFrame, "LEFT", 0, 0)
    targetFrameToT:SetSize(anchorFrame:GetWidth(), anchorFrame:GetHeight())
    targetFrameToT:SetHitRectInsets(0, 0, 0, 0)

    local portraitTexture = _G[targetFrameToT:GetName() .. "Portrait"]
    portraitTexture:ClearAllPoints()
    portraitTexture:SetPoint("LEFT", 4, 0)
    portraitTexture:SetSize(34, 34)
    portraitTexture:SetDrawLayer("BACKGROUND")

    local borderTexture = _G[targetFrameToT:GetName() .. "TextureFrameTexture"]
    borderTexture:ClearAllPoints()
    borderTexture:SetPoint("BOTTOMLEFT", 0, 0)
    SetAtlasTexture(borderTexture, "PartyFrame-TextureFrame-Normal")
    borderTexture:SetDrawLayer("BORDER")

    local healthBar = _G[targetFrameToT:GetName() .. "HealthBar"]
    healthBar:SetFrameLevel(targetFrameToT:GetFrameLevel() + 2)
    healthBar:ClearAllPoints()
    healthBar:SetPoint("TOPLEFT", 43, -16)
    healthBar:SetSize(71, 9)

    local statusBarTexture = healthBar:GetStatusBarTexture()
    statusBarTexture:SetAllPoints(healthBar)
    SetAtlasTexture(statusBarTexture, "PartyFrame-StatusBar-Health")

    local manaBar = _G[targetFrameToT:GetName() .. "ManaBar"]
    manaBar:SetFrameLevel(targetFrameToT:GetFrameLevel() + 2)
    manaBar:ClearAllPoints()
    manaBar:SetPoint("TOPLEFT", 41, -27)
    manaBar:SetSize(73, 7)

    statusBarTexture = manaBar:GetStatusBarTexture()
    statusBarTexture:SetAllPoints(manaBar)
    SetAtlasTexture(statusBarTexture, "PartyFrame-StatusBar-Mana")

    local nameText = _G[targetFrameToT:GetName() .. "TextureFrameName"]
    nameText:ClearAllPoints()
    nameText:SetPoint("CENTER", 16, 16)
    nameText:SetJustifyH("LEFT")
    nameText:SetDrawLayer("OVERLAY")
    nameText:SetWidth(65)
end

-------------------------------------------------
-- Widget application
-------------------------------------------------

local function EnsureScale(opts)
    if not opts.scale or opts.scale <= 0 then
        opts.scale = 1
    end
end

function Module:UpdateWidgets()
    local widgets = RUI.DB.profile.widgets
    if not widgets then
        return
    end

    -- Player
    local opts = widgets.player
    if opts then
        EnsureScale(opts)
        self.playerFrame:SetPoint(opts.anchor, opts.posX, opts.posY)
        PlayerFrame:SetScale(opts.scale) -- Blizzard frame uses our anchor as reference
    end

    -- Target
    opts = widgets.target
    if opts then
        EnsureScale(opts)
        self.targetFrame:SetPoint(opts.anchor, opts.posX, opts.posY)
        TargetFrame:SetScale(opts.scale)
    end

    -- Focus
    opts = widgets.focus
    if opts then
        EnsureScale(opts)
        self.focusFrame:SetPoint(opts.anchor, opts.posX, opts.posY)
        FocusFrame:SetScale(opts.scale)
    end

    -- Pet
    opts = widgets.pet
    if opts then
        EnsureScale(opts)
        self.petFrame:SetPoint(opts.anchor, opts.posX, opts.posY)
        PetFrame:SetScale(opts.scale)
    end

    -- Target of Target
    opts = widgets.targetOfTarget
    if opts then
        EnsureScale(opts)
        self.targetOfTargetFrame:SetPoint(opts.anchor, opts.posX, opts.posY)
        TargetFrameToT:SetScale(opts.scale)
    end

    -- Boss frames
    for index, frame in pairs(self.bossFrames) do
        if index > 1 then
            frame:SetPoint("TOP", self.bossFrames[index - 1], "BOTTOM", 0, -2)
        else
            opts = widgets["boss" .. index]
            if opts then
                frame:SetPoint(opts.anchor, opts.posX, opts.posY)
            end
        end
    end
end

-- existing refactored layout code...





-------------------------------------------------
-- Editor test mode
-------------------------------------------------

function Module:ShowEditorTest()
    -- Hide anchor frames and show Blizzard frames in test mode
    HideUIFrame(self.playerFrame)
    HideUIFrame(self.targetFrame)
    TargetFrame:ShowTest()

    HideUIFrame(self.focusFrame)
    FocusFrame:ShowTest()

    HideUIFrame(self.petFrame)
    HideUIFrame(self.targetOfTargetFrame)

    HideUIFrame(self.bossFrames[1])
    for index, _ in pairs(self.bossFrames) do
        _G["Boss" .. index .. "TargetFrame"]:ShowTest()
    end
end

function Module:HideEditorTest(refresh)
    -- Player
    ShowUIFrame(self.playerFrame)
    SaveUIFramePosition(self.playerFrame, "player")

    -- Target
    ShowUIFrame(self.targetFrame)
    SaveUIFramePosition(self.targetFrame, "target")
    TargetFrame:HideTest()

    -- Focus
    ShowUIFrame(self.focusFrame)
    SaveUIFramePosition(self.focusFrame, "focus")
    FocusFrame:HideTest()

    -- Pet
    ShowUIFrame(self.petFrame)
    SaveUIFramePosition(self.petFrame, "pet")

    -- ToT
    ShowUIFrame(self.targetOfTargetFrame)
    SaveUIFramePosition(self.targetOfTargetFrame, "targetOfTarget")

    -- Boss
    ShowUIFrame(self.bossFrames[1])
    SaveUIFramePosition(self.bossFrames[1], "boss" .. 1)

    for index, _ in pairs(self.bossFrames) do
        _G["Boss" .. index .. "TargetFrame"]:HideTest()
    end

    if refresh then
        self:UpdateWidgets()
    end
end

local isHooked = false

function Module:OnEnable()
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("RUNE_TYPE_UPDATE")

    if not isHooked then
        PlayerFrame:HookScript("OnUpdate", PlayerFrame_OnUpdate)
        PlayerFrameHealthBar:HookScript("OnValueChanged", HealthBar_OnValueChanged)
        TargetFrameHealthBar:HookScript("OnValueChanged", HealthBar_OnValueChanged)
        FocusFrameHealthBar:HookScript("OnValueChanged", HealthBar_OnValueChanged)
        PetFrameHealthBar:HookScript("OnValueChanged", HealthBar_OnValueChanged)
        isHooked = true
    end

    self:SecureHook("PlayerFrame_UpdateStatus", PlayerFrame_UpdateStatus)
    self:SecureHook("PlayerFrame_UpdateGroupIndicator", PlayerFrame_UpdateGroupIndicator)
    self:SecureHook("PlayerFrame_ToPlayerArt", PlayerFrame_ToPlayerArt)
    self:SecureHook("PlayerFrame_ToVehicleArt", PlayerFrame_ToVehicleArt)
    self:SecureHook("PlayerFrame_UpdateArt", PlayerFrame_UpdateArt)
    self:SecureHook("PlayerFrame_SequenceFinished", PlayerFrame_SequenceFinished)
    self:SecureHook("PlayerFrame_AnimateOut", PlayerFrame_AnimateOut)

    self:SecureHook("TargetFrame_UpdateBuffAnchor", TargetFrame_UpdateBuffAnchor)
    self:SecureHook("TargetFrame_UpdateDebuffAnchor", TargetFrame_UpdateDebuffAnchor)
    self:SecureHook("TargetFrame_CheckClassification", TargetFrame_CheckClassification)
    self:SecureHook("FocusFrame_SetSmallSize", FocusFrame_SetSmallSize)

    self:SecureHook("UnitFrameHealthBar_Update", UnitFrameHealthBar_Update)
    self:SecureHook("UnitFrameManaBar_UpdateType", UnitFrameManaBar_UpdateType)
    self:SecureHook("PetFrame_Update", PetFrame_Update)
    self:SecureHook("PlayerFrame_UpdateRolesAssigned", PlayerFrame_UpdateRolesAssigned)

    self.playerFrame         = CreateUIFrame(192, 68, "PlayerFrame")
    self.targetFrame         = CreateUIFrame(192, 68, "TargetFrame")
    self.focusFrame          = CreateUIFrame(192, 68, "FocusFrame")
    self.petFrame            = CreateUIFrame(120, 47, "PetFrame")
    self.targetOfTargetFrame = CreateUIFrame(120, 47, "TOTFrame")

    for index = 1, 4 do
        self.bossFrames[index] = CreateUIFrame(192, 68, "Boss" .. index .. "Frame")
    end
end

function Module:OnDisable()
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    self:UnregisterEvent("RUNE_TYPE_UPDATE")

    if self:IsHooked(PlayerFrame, "OnUpdate") then
        PlayerFrame:Unhook("OnUpdate", PlayerFrame_OnUpdate)
    end

    if self:IsHooked(PlayerFrameHealthBar, "OnValueChanged") then
        PlayerFrameHealthBar:Unhook("OnValueChanged", HealthBar_OnValueChanged)
    end

    if self:IsHooked(TargetFrameHealthBar, "OnValueChanged") then
        TargetFrameHealthBar:Unhook("OnValueChanged", HealthBar_OnValueChanged)
    end

    if self:IsHooked(FocusFrameHealthBar, "OnValueChanged") then
        FocusFrameHealthBar:Unhook("OnValueChanged", HealthBar_OnValueChanged)
    end

    if self:IsHooked(PetFrameHealthBar, "OnValueChanged") then
        PetFrameHealthBar:Unhook("OnValueChanged", HealthBar_OnValueChanged)
    end

    self:Unhook("PlayerFrame_UpdateStatus", PlayerFrame_UpdateStatus)
    self:Unhook("PlayerFrame_UpdateGroupIndicator", PlayerFrame_UpdateGroupIndicator)
    self:Unhook("PlayerFrame_ToPlayerArt", PlayerFrame_ToPlayerArt)
    self:Unhook("PlayerFrame_ToVehicleArt", PlayerFrame_ToVehicleArt)
    self:Unhook("PlayerFrame_UpdateArt", PlayerFrame_UpdateArt)
    self:Unhook("PlayerFrame_SequenceFinished", PlayerFrame_SequenceFinished)
    self:Unhook("PlayerFrame_AnimateOut", PlayerFrame_AnimateOut)

    self:Unhook("TargetFrame_UpdateBuffAnchor", TargetFrame_UpdateBuffAnchor)
    self:Unhook("TargetFrame_UpdateDebuffAnchor", TargetFrame_UpdateDebuffAnchor)
    self:Unhook("TargetFrame_CheckClassification", TargetFrame_CheckClassification)
    self:Unhook("FocusFrame_SetSmallSize", FocusFrame_SetSmallSize)

    self:Unhook("UnitFrameHealthBar_Update", UnitFrameHealthBar_Update)
    self:Unhook("UnitFrameManaBar_UpdateType", UnitFrameManaBar_UpdateType)
    self:Unhook("PetFrame_Update", PetFrame_Update)
    self:Unhook("PlayerFrame_UpdateRolesAssigned", PlayerFrame_UpdateRolesAssigned)
end

local isHookedWorld = false

function Module:RUNE_TYPE_UPDATE(eventName, rune)
    UpdateRune(_G["RuneButtonIndividual" .. rune])
end

local function RemoveBlizzardFrames()
    local blizzFrames = {
        PlayerFrameBackground,
        PlayerAttackBackground,
        TargetFrameBackground,
        Boss1TargetFrameBackground,
        Boss2TargetFrameBackground,
        Boss3TargetFrameBackground,
        Boss4TargetFrameBackground,
        TargetFrameNumericalThreatBG,
        TargetFrameToTBackground,
        FocusFrameBackground,
        PlayerFrameRoleIcon,
        PlayerGuideIcon,
        PlayerFrameGroupIndicatorLeft,
        PlayerFrameGroupIndicatorRight,
    }

    for _, frame in pairs(blizzFrames) do
        if frame then
            frame:SetAlpha(0)
        end
    end
end

local function HidePlayerStrip()
    local child = select(9, PlayerFrame:GetChildren())
    if child then
        child:Hide()
        child:SetScript("OnShow", child.Hide)
    end
end

function Module:PLAYER_ENTERING_WORLD()
    RemoveBlizzardFrames()

    ReplaceBlizzardPlayerFrame(self.playerFrame)
    ReplaceBlizzardRuneFrame()
    ReplaceBlizzardTotemFrame()
    ReplaceBlizzardTargetFrame(self.targetFrame, TargetFrame)
    ReplaceBlizzardComboFrame()
    ReplaceBlizzardTargetFrame(self.focusFrame, FocusFrame)
    ReplaceBlizzardPetFrame(self.petFrame)
    ReplaceBlizzardTOTFrame(self.targetOfTargetFrame)
    HidePlayerStrip()
    UpdateGroupIndicator()

    for index, frame in pairs(self.bossFrames) do
        ReplaceBlizzardTargetFrame(frame, _G["Boss" .. index .. "TargetFrame"], true)
    end

    local widgets = {
        "player",
        "target",
        "focus",
        "pet",
        "targetOfTarget",
        "boss1",
        "boss2",
        "boss3",
        "boss4",
    }
    CheckSettingsExists(Module, widgets)

    -- Party healthbar class-color hook (unchanged from old file)
    for i = 1, 4 do
        if isHookedWorld then
            break
        end

        local frame = _G["PartyMemberFrame" .. i]
        if frame and frame.healthbar then
            self:HookScript(frame.healthbar, "OnValueChanged", function(bar)
                local unit = frame.unit
                if UnitIsPlayer(unit) and not UnitIsUnit(unit, "player") then
                    local _, class = UnitClass(unit)
                    local color = RAID_CLASS_COLORS[class]
                    if color then
                        bar:SetStatusBarColor(color.r, color.g, color.b)
                    end
                end
            end)

            self:SecureHook(frame.healthbar, "SetStatusBarColor", function(bar, r, g, b)
                local unit = frame.unit
                if UnitIsPlayer(unit) and not UnitIsUnit(unit, "player") then
                    local _, class = UnitClass(unit)
                    local color = RAID_CLASS_COLORS[class]
                    if color and (r ~= color.r or g ~= color.g or b ~= color.b) then
                        bar:SetStatusBarColor(color.r, color.g, color.b)
                    end
                end
            end)
        end
    end

    isHookedWorld = true
end
