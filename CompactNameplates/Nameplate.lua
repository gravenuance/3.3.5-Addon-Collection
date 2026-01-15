local ADDON_NAME, addon    = ...

local FONT_PATH            = "Interface\\AddOns\\CompactNameplates\\Media\\font.ttf"
local FONT_PATH_BOLD       = "Interface\\AddOns\\CompactNameplates\\Media\\font-bold.ttf"
local BORDER_PATH          = "Interface\\AddOns\\CompactNameplates\\Media\\border.tga"
local FONT_FLAG            = "OUTLINE"
local MAX_AURA_FRAMES      = 5
local LARGE_AURA_SIZE      = 21
local SMALL_AURA_SIZE      = 17
local AURA_SPACING         = 3

local DEBUFF_COLOR         = { r = 1, g = 0, b = 0 }   -- fallback for debuffs
local BUFF_COLOR           = { r = 0, g = 0.8, b = 0 } -- generic buffs
local DISPEL_COLORS        = {
    Magic   = { r = 0.2, g = 0.6, b = 1.0 },
    Curse   = { r = 0.6, g = 0, b = 1.0 },
    Disease = { r = 0.6, g = 0.4, b = 0 },
    Poison  = { r = 0, g = 0.6, b = 0 },
}

local Nameplate            = {}
addon.Nameplate            = Nameplate

-- High-priority totem names (localized as needed)
local HIGH_PRIORITY_TOTEMS = {
    ["Tremor Totem"]           = "Interface\\Icons\\Spell_Nature_TremorTotem",
    ["Grounding Totem"]        = "Interface\\Icons\\Spell_Nature_GroundingTotem",
    ["Poison Cleansing Totem"] = "Interface\\Icons\\Spell_Nature_PoisonCleansingTotem",
    ["Cleansing Totem"]        = "Interface\\Icons\\Spell_Nature_DiseaseCleansingTotem",
    ["Earthbind Totem"]        = "Interface\\Icons\\Spell_Nature_StrengthOfEarthTotem02",
}




-------------------------------------------------
-- Localized globals
-------------------------------------------------

local UnitExists          = UnitExists
local UnitGUID            = UnitGUID
local UnitName            = UnitName
local UnitClass           = UnitClass
local UnitIsPlayer        = UnitIsPlayer
local UnitCastingInfo     = UnitCastingInfo
local UnitChannelInfo     = UnitChannelInfo
local UnitHealthMax       = UnitHealthMax
local GetTime             = GetTime
local GetSpellInfo        = GetSpellInfo
local SecondsToTimeAbbrev = SecondsToTimeAbbrev

-------------------------------------------------
-- Helpers: base frame / default nameplate
-------------------------------------------------

local function IsTotemUnit(unitID)
    if not unitID or not UnitExists(unitID) then
        return false
    end
    local name = UnitName(unitID)
    return name and name:find("Totem") ~= nil
end

local function IsHighPriorityTotem(unitID)
    if not unitID or not UnitExists(unitID) then
        return false
    end
    local name = UnitName(unitID)
    if not name then return false end

    -- Substring matching so localization / formatting does not break it
    name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") -- strip color codes if any

    return name:find("Tremor") or name:find("Grounding")
        or name:find("Poison Cleansing") or name:find("Cleansing") or name:find("Earthbind")
end

local function GetTotemIcon(unitID)
    if not unitID or not UnitExists(unitID) then
        return nil
    end
    local name = UnitName(unitID)
    if not name then return nil end

    name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")

    if name:find("Tremor") then
        return "Interface\\Icons\\Spell_Nature_TremorTotem"
    elseif name:find("Grounding") then
        return "Interface\\Icons\\Spell_Nature_GroundingTotem"
    elseif name:find("Poison Cleansing") then
        return "Interface\\Icons\\Spell_Nature_PoisonCleansingTotem"
    elseif name:find("Cleansing") then
        return "Interface\\Icons\\Spell_Nature_DiseaseCleansingTotem"
    elseif name:find("Earthbind") then
        return "Interface\\Icons\\Spell_Nature_StrengthOfEarthTotem02"
    end
    return nil
end

local function GetDefaultFrame(nameplate)
    return nameplate:GetParent()
end

local function IsMouseover(nameplate)
    local default = GetDefaultFrame(nameplate)
    return UnitExists("mouseover") and default.highlight:IsShown()
end

function Nameplate:IsTarget(nameplate)
    local default = GetDefaultFrame(nameplate)
    return UnitExists("target") and default:GetAlpha() == 1
end

-- Legacy helper: direct name+maxHealth off the default plate
local function GetPlateNameAndMaxHealth(nameplate)
    local default = nameplate:GetParent()
    local name = default.unitName:GetText()
    local _, maxHealth = default.healthBar:GetMinMaxValues()
    return name, maxHealth
end

function addon.Nameplate:GetGUIDByNameAndHealthFromPlate(nameplate)
    local name, maxHealth = GetPlateNameAndMaxHealth(nameplate)
    if not name or not maxHealth then
        return nil
    end
    return addon.Units:GetGUID(name, maxHealth)
end

function addon.Nameplate:UpdateForGUID(guid)
    local plate = self:Get(guid)
    if plate then
        self:UpdateAuras(plate)
    end
end

-------------------------------------------------
-- GUID registry + unit candidate list
-------------------------------------------------

local nameplatesByGUID = {}

local function SetGUID(nameplate, unitGUID)
    if not unitGUID then return end
    nameplatesByGUID[unitGUID] = nameplate
    nameplate.unitGUID = unitGUID
end

local function ClearGUID(nameplate)
    local guid = nameplate.unitGUID
    if not guid then return end
    nameplatesByGUID[guid] = nil
    nameplate.unitGUID = nil
end

function Nameplate:Get(unitGUID)
    return nameplatesByGUID[unitGUID]
end

-- Cached candidate list
local UNIT_CANDIDATES

local function BuildUnitCandidates()
    if UNIT_CANDIDATES then
        return UNIT_CANDIDATES
    end

    local candidates = {}

    -- Arena enemies first
    for i = 1, 5 do
        candidates[#candidates + 1] = "arena" .. i
    end

    -- Player + pet
    candidates[#candidates + 1] = "player"
    candidates[#candidates + 1] = "pet"

    -- Target family
    candidates[#candidates + 1] = "target"
    candidates[#candidates + 1] = "focus"
    candidates[#candidates + 1] = "mouseover"

    -- Party + pets
    for i = 1, 5 do
        candidates[#candidates + 1] = "party" .. i
        candidates[#candidates + 1] = "partypet" .. i
    end

    -- Raid + pets
    for i = 1, 40 do
        candidates[#candidates + 1] = "raid" .. i
        candidates[#candidates + 1] = "raidpet" .. i
    end

    -- Boss frames
    for i = 1, 5 do
        candidates[#candidates + 1] = "boss" .. i
    end

    -- Nameplate units (if exposed)
    for i = 1, 40 do
        candidates[#candidates + 1] = "nameplate" .. i
    end

    UNIT_CANDIDATES = candidates
    return candidates
end

local function GetUnitID(nameplate)
    local guid = nameplate.unitGUID
    if guid then
        local candidates = BuildUnitCandidates()
        for _, unitID in ipairs(candidates) do
            if UnitExists(unitID) and UnitGUID(unitID) == guid then
                return unitID
            end
        end
    end

    -- Fallbacks when GUID is not set / not found
    if Nameplate:IsTarget(nameplate) then
        return "target"
    end

    if IsMouseover(nameplate) then
        return "mouseover"
    end

    return nil
end

-------------------------------------------------
-- Unit info helpers: name, level, maxHp
-------------------------------------------------

local function UnitNameAbbrev(unitName, maxLength)
    if not unitName or not maxLength then
        return unitName
    end

    if #unitName <= maxLength then
        return unitName
    end

    local firstWord, rest = strsplit(" ", unitName, 2)
    local abbrev = ""
    while rest do
        abbrev = abbrev .. firstWord:sub(1, 1) .. "."
        unitName = abbrev .. " " .. rest
        if #unitName <= maxLength then
            return unitName
        end
        firstWord, rest = strsplit(" ", rest, 2)
    end

    return unitName:sub(1, maxLength)
end

local function GetUnitName(nameplate)
    local default = GetDefaultFrame(nameplate)
    local text = default.unitName:GetText()
    return UnitNameAbbrev(text, 22)
end

local function GetUnitLevel(nameplate)
    local default = GetDefaultFrame(nameplate)
    if default.skullIcon:IsShown() then
        return "??"
    end
    return default.unitLevel:GetText()
end

local function GetUnitHealth(nameplate)
    local default = GetDefaultFrame(nameplate)
    local _, unitHealth = default.healthBar:GetMinMaxValues()
    return unitHealth
end

-------------------------------------------------
-- Class color, GUID updates
-------------------------------------------------

local function ResolveGUID(nameplate)
    local myGUID = nameplate.unitGUID
    if not myGUID then
        return nil
    end

    local candidates = BuildUnitCandidates()
    for _, unit in ipairs(candidates) do
        if UnitExists(unit) and UnitIsPlayer(unit) then
            local guid = UnitGUID(unit)
            if guid and guid == myGUID then
                local _, class = UnitClass(unit)
                addon.Units:SetGUID(guid, nil, nil, class)
                return class
            end
        end
    end

    return nil
end

local function SetClassColor(nameplate)
    local info  = nameplate.unitGUID and addon.Units:Get(nameplate.unitGUID)
    local class = info and info.class

    if not class then
        class = ResolveGUID(nameplate)
        if not class then
            local default = GetDefaultFrame(nameplate)
            local r, g, b = default.healthBar:GetStatusBarColor()
            nameplate.healthBar:SetStatusBarColor(r, g, b)
            return false
        end
    end

    local color = RAID_CLASS_COLORS[class]
    if not color then
        return false
    end

    nameplate.healthBar:SetStatusBarColor(color.r, color.g, color.b)
    return true
end

local function UpdateNameplateUnitInfo(nameplate)
    local default = GetDefaultFrame(nameplate)
    local unitName = GetUnitName(nameplate)
    local unitLevel = GetUnitLevel(nameplate)
    local _, maxHealth = default.healthBar:GetMinMaxValues()

    nameplate.healthBar:SetMinMaxValues(0, maxHealth)
    nameplate.healthBar:SetValue(default.healthBar:GetValue())
    local arenaIndex
    local unitID = GetUnitID(nameplate)
    if unitID then
        local idx = unitID:match("^arena(%d+)$")
        if idx then
            arenaIndex = idx
        end
    end

    if arenaIndex then
        nameplate.healthBar.unitName:SetText(arenaIndex)
    else
        nameplate.healthBar.unitName:SetText(unitName)
    end
    nameplate.healthBar.unitLevel:SetText(unitLevel)
end

local function UpdateNameplateGUID(nameplate, unitID)
    if not unitID or not UnitExists(unitID) then
        return
    end

    local unitGUID = UnitGUID(unitID)
    if not unitGUID or unitGUID == nameplate.unitGUID then
        return
    end

    local conflict = Nameplate:Get(unitGUID)
    if conflict then
        ClearGUID(conflict)
    end

    SetGUID(nameplate, unitGUID)

    local unitName   = GetUnitName(nameplate)
    local unitHealth = GetUnitHealth(nameplate)
    local _, class   = UnitClass(unitID)

    addon.Units:SetGUID(unitGUID, unitName, unitHealth, class)
end

-------------------------------------------------
-- Debug casting helper (optional)
-------------------------------------------------

local function DebugCasting(unitID)
    if not UnitExists(unitID) then
        print("DBG Cast:", unitID, "does not exist")
        return
    end

    local ci = { UnitCastingInfo(unitID) }
    local ch = { UnitChannelInfo(unitID) }

    local function dump(prefix, t)
        if #t == 0 then
            print(prefix, "nil")
        else
            local s = prefix
            for i, v in ipairs(t) do
                s = s .. " [" .. i .. "]=" .. tostring(v)
            end
            print(s)
        end
    end

    dump("DBG UnitCastingInfo(" .. unitID .. "):", ci)
    dump("DBG UnitChannelInfo(" .. unitID .. "):", ch)
end

-------------------------------------------------
-- Cast bar / health bar handlers
-------------------------------------------------

local function HealthBar_OnValueChanged(nameplate, value)
    nameplate.healthBar:SetValue(value)
    SetClassColor(nameplate)
end

-- Per-frame driver for the custom castbar
local function CastBar_OnUpdate(self, elapsed)
    local nameplate = self.__owner
    if not nameplate then
        self:SetScript("OnUpdate", nil)
        return
    end

    local default = GetDefaultFrame(nameplate)
    local unitID  = GetUnitID(nameplate)
    if not unitID or not UnitExists(unitID) then
        self:SetScript("OnUpdate", nil)
        nameplate.castBar:Hide()
        return
    end

    local spell, iconTexture, startTime, endTime
    local isChannel = false

    -- Casts
    do
        local a, _, _, d, e, f = UnitCastingInfo(unitID)
        if a and e and f and type(e) == "number" and type(f) == "number" then
            spell       = a
            iconTexture = d
            startTime   = e
            endTime     = f
            isChannel   = false
        end
    end

    -- Channels
    if not spell then
        local a, _, _, d, e, f = UnitChannelInfo(unitID)
        if a and e and f and type(e) == "number" and type(f) == "number" then
            spell       = a
            iconTexture = d
            startTime   = e
            endTime     = f
            isChannel   = true
        end
    end

    if not spell or not startTime or not endTime then
        -- No active cast/channel anymore
        self:SetScript("OnUpdate", nil)
        nameplate.castBar:Hide()
        return
    end

    local now      = GetTime()
    local startSec = startTime / 1000
    local endSec   = endTime / 1000
    local duration = endSec - startSec

    if duration <= 0 then
        self:SetScript("OnUpdate", nil)
        nameplate.castBar:Hide()
        return
    end

    -- Progress: 0 -> duration for both casts and channels
    local elapsedTime = now - startSec
    if elapsedTime < 0 then
        elapsedTime = 0
    elseif elapsedTime > duration then
        elapsedTime = duration
    end

    nameplate.castBar:SetMinMaxValues(0, duration)
    nameplate.castBar:SetValue(elapsedTime)
    nameplate.castBar.spellName:SetText(spell or "")
    nameplate.castBar.targetName:SetText(UnitName(unitID .. "target") or "")

    if iconTexture and type(iconTexture) == "string" then
        nameplate.castBar.spellIcon:SetTexture(iconTexture)
    else
        nameplate.castBar.spellIcon:SetTexture(default.spellIcon:GetTexture())
    end
end

local function CastBar_Start(nameplate)
    local bar = nameplate.castBar
    bar:SetParent(nameplate)
    bar.__owner = nameplate
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", nameplate, "BOTTOMLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", nameplate, "BOTTOMRIGHT", 0, 0)
    bar:SetHeight(18)
    bar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    bar:SetStatusBarColor(1, 0, 0)
    bar:SetScript("OnUpdate", CastBar_OnUpdate)
    bar:Show()
end

local function CastBar_Stop(nameplate)
    local bar = nameplate.castBar
    if not bar then return end

    bar:SetScript("OnUpdate", nil)
    bar:Hide()
    bar.__owner = nil
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)

    if bar.spellName then
        bar.spellName:SetText("")
    end
    if bar.targetName then
        bar.targetName:SetText("")
    end
    if bar.spellIcon then
        bar.spellIcon:SetTexture(nil)
    end
end

local function CastBar_OnShow(nameplate)
    CastBar_Start(nameplate)
end

local function CastBar_OnHide(nameplate)
    CastBar_Stop(nameplate)
end

local function CastBar_OnValueChanged(nameplate, value)
    -- Blizzard's value is intentionally ignored; OnUpdate drives the bar
end

-- Event frame that maps UNIT_* events to the owning plate
local CastEventFrame = CreateFrame("Frame")
CastEventFrame:RegisterEvent("UNIT_SPELLCAST_START")
CastEventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
CastEventFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
CastEventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
CastEventFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
CastEventFrame:RegisterEvent("UNIT_SPELLCAST_FAILED")

CastEventFrame:SetScript("OnEvent", function(self, event, unitID)
    if not unitID or not UnitExists(unitID) then
        return
    end

    local guid = UnitGUID(unitID)
    if not guid then
        return
    end

    local plate = addon.Nameplate:Get(guid)
    if not plate then
        return
    end

    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        CastBar_Start(plate)
    else
        CastBar_Stop(plate)
    end
end)

-------------------------------------------------
-- Aura duration / timer
-------------------------------------------------

local function AuraFrame_OnUpdate(self, elapsed)
    local durationFS = self.duration

    if self.timeLeft and self.timeLeft > 0 then
        self.timeLeft = math.max(self.timeLeft - elapsed, 0)

        local t
        if self.timeLeft > 1 then
            t = math.floor(self.timeLeft + 0.5)
        elseif self.timeLeft > 0 then
            -- Keep showing 1 while there is any time left
            t = 1
        else
            t = 0
        end

        durationFS:SetText(t > 0 and t or "")

        if self.timeLeft <= 3 then
            durationFS:SetVertexColor(1, 0.1, 0.1)
        elseif self.timeLeft <= 6 then
            durationFS:SetVertexColor(1, 0.9, 0.1)
        else
            durationFS:SetVertexColor(0.1, 1, 0.1)
        end

        durationFS:Show()
    else
        self.timeLeft = nil
        self:SetScript("OnUpdate", nil)
        durationFS:Hide()
        if self.cooldown then
            self.cooldown:Clear()
            self.cooldown:Hide()
        end
        self:Hide()
    end
end

local function AuraFrame_SetTimer(self, expirationTime)
    if self.duration then
        self.duration:SetFont(FONT_PATH_BOLD, 18, FONT_FLAG)
    end
    if not self.timeLeft then
        self:SetScript("OnUpdate", AuraFrame_OnUpdate)
    end
    self.timeLeft = expirationTime - GetTime()
end

--[[ local function ConfigureAuraFrame(frame, spellID, duration, expirationTime, auraTypeKey, dispelType)
    local _, _, spellIcon = GetSpellInfo(spellID)
    frame.icon:SetTexture(spellIcon)
    AuraFrame_SetTimer(frame, expirationTime)

    local color
    if auraTypeKey == "BUFF" then
        color = (dispelType and DISPEL_COLORS[dispelType]) or BUFF_COLOR
    else
        color = (dispelType and DISPEL_COLORS[dispelType]) or DEBUFF_COLOR
    end

    if frame.border and color then
        frame.border:SetVertexColor(color.r, color.g, color.b)
    end
end ]]

local function ConfigureAuraFrame(frame, spellID, duration, expirationTime, auraTypeKey, dispelType)
    local _, _, spellIcon = GetSpellInfo(spellID)

    frame.icon:SetTexture(spellIcon)

    -- Hard reset timer state
    frame.timeLeft = nil
    frame:SetScript("OnUpdate", nil)

    AuraFrame_SetTimer(frame, expirationTime)

    if frame.duration then
        frame.duration:Show()
    end

    local color
    if auraTypeKey == "BUFF" then
        color = (dispelType and DISPEL_COLORS[dispelType]) or BUFF_COLOR
    else
        color = (dispelType and DISPEL_COLORS[dispelType]) or DEBUFF_COLOR
    end

    if frame.border and color then
        frame.border:SetVertexColor(color.r, color.g, color.b)
    end

    frame:Show()
end

local function LayoutAuraFrame(frame, index, offset, container)
    if index > 1 then
        offset = offset + AURA_SPACING
    end
    frame:ClearAllPoints()
    frame:SetPoint("LEFT", container, "LEFT", offset, 0)
    frame:Show()
    return offset + frame:GetWidth()
end

local function CollectSorted(guid, auraType)
    local collected = {}
    local idx = 1
    local emptyHits = 0
    local MAX_EMPTY = 20 -- enough to cover any realistic list

    while emptyHits < MAX_EMPTY do
        local spellID, duration, expirationTime, auraTypeKey, dispelType =
            addon.Auras:Get(guid, auraType, idx)

        if spellID and duration and duration > 0 and expirationTime then
            collected[#collected + 1] = {
                spellID        = spellID,
                duration       = duration,
                expirationTime = expirationTime,
                auraTypeKey    = auraTypeKey,
                dispelType     = dispelType,
            }
        end

        if spellID then
            emptyHits = 0 -- reset on a hit
        else
            emptyHits = emptyHits + 1
        end

        idx = idx + 1
    end

    table.sort(collected, function(a, b)
        return a.duration > b.duration
    end)

    return collected
end
--[[ local function CollectSorted(guid, auraType)
    local collected = {}
    local idx = 1

    while true do
        local spellID, duration, expirationTime, auraTypeKey, dispelType =
            addon.Auras:Get(guid, auraType, idx)

        if not spellID or not duration or not expirationTime then
            break
        end

        collected[#collected + 1] = {
            spellID        = spellID,
            duration       = duration,
            expirationTime = expirationTime,
            auraTypeKey    = auraTypeKey,
            dispelType     = dispelType,
        }

        idx = idx + 1
    end

    table.sort(collected, function(a, b)
        return a.duration > b.duration
    end)

    return collected
end ]]

--[[ local function LayoutRow(frames, collected, container)
    local offset = 0
    for i, frame in ipairs(frames) do
        local aura = collected[i]
        if aura then
            ConfigureAuraFrame(
                frame,
                aura.spellID,
                aura.duration,
                aura.expirationTime,
                aura.auraTypeKey,
                aura.dispelType
            )
            offset = LayoutAuraFrame(frame, i, offset, container)
        else
            frame:Hide()
        end
    end
    container:SetWidth(offset)
end ]]

--[[ local function LayoutRow(frames, collected, container)
    local offset = 0
    local frameIndex = 1

    -- Assign auras sequentially to frames
    for auraIndex = 1, #collected do
        local aura = collected[auraIndex]
        local frame = frames[frameIndex]
        if not frame then
            break -- no more frames available
        end

        ConfigureAuraFrame(
            frame,
            aura.spellID,
            aura.duration,
            aura.expirationTime,
            aura.auraTypeKey,
            aura.dispelType
        )
        offset = LayoutAuraFrame(frame, frameIndex, offset, container)

        frameIndex = frameIndex + 1
    end

    -- Hide any leftover frames
    for i = frameIndex, #frames do
        frames[i]:Hide()
    end

    container:SetWidth(offset)
end ]]

local function LayoutRow(frames, collected, container)
    local offset = 0
    local frameIndex = 1

    for auraIndex = 1, #collected do
        local aura  = collected[auraIndex]
        local frame = frames[frameIndex]
        if not frame then break end

        ConfigureAuraFrame(
            frame,
            aura.spellID,
            aura.duration,
            aura.expirationTime,
            aura.auraTypeKey,
            aura.dispelType
        )

        offset = LayoutAuraFrame(frame, frameIndex, offset, container)
        frameIndex = frameIndex + 1
    end

    for i = frameIndex, #frames do
        frames[i].timeLeft = nil
        frames[i]:SetScript("OnUpdate", nil)
        frames[i]:Hide()
        if frames[i].duration then
            frames[i].duration:Hide()
        end
        if frames[i].cooldown then
            frames[i].cooldown:Clear()
            frames[i].cooldown:Hide()
        end
    end

    container:SetWidth(offset)
end

function Nameplate:UpdateAuras(nameplate)
    local unitID = GetUnitID(nameplate)
    if unitID and UnitExists(unitID) then
        addon.Auras:Refresh(unitID)
    end

    local guid = nameplate.unitGUID
    if not guid then
        if nameplate.debuffFrames then
            for _, f in ipairs(nameplate.debuffFrames) do
                f:Hide()
            end
        end
        if nameplate.buffFrames then
            for _, f in ipairs(nameplate.buffFrames) do
                f:Hide()
            end
        end
        return
    end

    local debuffs = CollectSorted(guid, "DEBUFF")
    local buffs   = CollectSorted(guid, "BUFF")

    if nameplate.debuffFrames then
        LayoutRow(nameplate.debuffFrames, debuffs, nameplate.debuffs)
    end
    if nameplate.buffFrames then
        LayoutRow(nameplate.buffFrames, buffs, nameplate.buffs)
    end
end

-------------------------------------------------
-- Nameplate show/hide / update
-------------------------------------------------

local function ResolveInitialUnit(nameplate)
    local plateName  = GetUnitName(nameplate)
    local candidates = BuildUnitCandidates()

    for _, unitID in ipairs(candidates) do
        if UnitExists(unitID) then
            local guid     = UnitGUID(unitID)
            local unitName = UnitName(unitID)
            if guid and unitName and unitName == plateName then
                local _, class = UnitClass(unitID)
                local maxHealth = UnitHealthMax(unitID) or 0
                SetGUID(nameplate, guid)
                addon.Units:SetGUID(guid, unitName, maxHealth, class)
                return unitID
            end
        end
    end

    return nil
end

local function ResolveOrFallbackGUID(nameplate)
    local unitID = ResolveInitialUnit(nameplate)
    if unitID then
        return unitID
    end

    -- fallback to old behaviour using cached GUID
    local unitName   = GetUnitName(nameplate)
    local unitHealth = GetUnitHealth(nameplate)
    local unitGUID   = addon.Units:GetGUID(unitName, unitHealth)

    if unitGUID and not Nameplate:Get(unitGUID) then
        SetGUID(nameplate, unitGUID)
    end

    return unitID
end

local function OnShow(nameplate)
    UpdateNameplateUnitInfo(nameplate)
    ResolveOrFallbackGUID(nameplate)
    nameplate._lastGUID = nameplate.unitGUID
    SetClassColor(nameplate)
    Nameplate:UpdateAuras(nameplate)
end

local function OnHide(nameplate)
    ClearGUID(nameplate)
    nameplate._lastGUID = nil
    Nameplate:UpdateAuras(nameplate)
end

--[[ local function OnUpdate(nameplate, elapsed)
    local default = GetDefaultFrame(nameplate)

    nameplate.raidIcon:SetTexCoord(default.raidIcon:GetTexCoord())
    nameplate.raidIcon:SetShown(default.raidIcon:IsShown())


    ResolveOrFallbackGUID(nameplate)
    Nameplate:UpdateAuras(nameplate)
    SetClassColor(nameplate)
end ]]

local function OnUpdate(nameplate, elapsed)
    local default = GetDefaultFrame(nameplate)

    nameplate.raidIcon:SetTexCoord(default.raidIcon:GetTexCoord())
    nameplate.raidIcon:SetShown(default.raidIcon:IsShown())

    local unitID = ResolveOrFallbackGUID(nameplate)

    local showPlate = true
    if nameplate.totemIcon then
        nameplate.totemIcon:Hide()
    end

    -- Totem detection as before (unitID + name fallback)
    if unitID and UnitExists(unitID) and IsTotemUnit(unitID) then
        showPlate = false

        if nameplate.totemIcon and IsHighPriorityTotem(unitID) then
            local iconTexture = GetTotemIcon(unitID)
            if nameplate.totemIcon and iconTexture then
                nameplate.totemIcon.icon:SetTexture(iconTexture)
                nameplate.totemIcon:Show()
            end
        end
    else
        local plateName = default.unitName:GetText()
        if plateName and plateName:find("Totem") then
            showPlate = false

            if nameplate.totemIcon then
                local iconTexture = HIGH_PRIORITY_TOTEMS[plateName]
                if nameplate.totemIcon and iconTexture then
                    nameplate.totemIcon.icon:SetTexture(iconTexture)
                    nameplate.totemIcon:Show()
                end
            end
        end
    end

    nameplate:SetShown(showPlate) -- hide whole custom frame
    -- Important: do NOT touch default.healthBar/default.castBar here

    if showPlate then
        ResolveOrFallbackGUID(nameplate)
        Nameplate:UpdateAuras(nameplate)
        SetClassColor(nameplate)
    end
end

-------------------------------------------------
-- Public API
-------------------------------------------------

function Nameplate:Create(default)
    local nameplate = CreateFrame("Frame", nil, default, "NameplateFrameTemplate")
    local nameFS    = nameplate.healthBar.unitName
    local levelFS   = nameplate.healthBar.unitLevel
    local pad       = 0
    do
        local _, _, defaultFlags = nameFS:GetFont()
        nameFS:SetFont(FONT_PATH, 14, defaultFlags or FONT_FLAG)
    end

    do
        local _, _, defaultFlags = levelFS:GetFont()
        levelFS:SetFont(FONT_PATH, 12, defaultFlags or FONT_FLAG)
    end
    -- Debuffs row (closer to the plate)
    nameplate.debuffs = CreateFrame("Frame", nil, nameplate)
    nameplate.debuffs:SetPoint("BOTTOMLEFT", nameplate, "TOPLEFT", 0, 10)
    nameplate.debuffs:SetHeight(LARGE_AURA_SIZE)

    -- Buffs row (above debuffs)
    nameplate.buffs = CreateFrame("Frame", nil, nameplate)
    nameplate.buffs:SetPoint("BOTTOMLEFT", nameplate, "TOPLEFT", 0, 45)
    nameplate.buffs:SetHeight(LARGE_AURA_SIZE)

    -- Create frames for DEBUFFS
    for i = 1, MAX_AURA_FRAMES do
        local frame = CreateFrame("Frame", nil, nameplate.debuffs, "NameplateAuraFrameTemplate")
        if frame.icon then
            frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        if not frame.border then
            local border = frame:CreateTexture(nil, "OVERLAY")
            frame.border = border
            border:SetTexture(BORDER_PATH)
            border:ClearAllPoints()
            border:SetPoint("TOPLEFT", frame, "TOPLEFT", -3, 3)
            border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 3, -3)
        end
        local duration   = frame.duration
        local icon       = frame.icon
        local durationBG = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
        durationBG:SetColorTexture(0, 0, 0, 0.2)
        durationBG:SetPoint("TOPLEFT", icon, "TOPLEFT", -pad, pad)
        durationBG:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", pad, -pad)
        frame.durationBG = durationBG

        duration:SetFont(FONT_PATH_BOLD, 18, FONT_FLAG)
    end

    -- Create frames for BUFFS
    for i = 1, MAX_AURA_FRAMES do
        local frame = CreateFrame("Frame", nil, nameplate.buffs, "NameplateAuraFrameTemplate")
        if frame.icon then
            frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        if not frame.border then
            local border = frame:CreateTexture(nil, "OVERLAY")
            frame.border = border
            border:SetTexture(BORDER_PATH)
            border:ClearAllPoints()
            border:SetPoint("TOPLEFT", frame, "TOPLEFT", -3, 3)
            border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 3, -3)
        end
        local duration   = frame.duration
        local icon       = frame.icon
        local durationBG = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
        durationBG:SetColorTexture(0, 0, 0, 0.2)
        durationBG:SetPoint("TOPLEFT", icon, "TOPLEFT", -pad, pad)
        durationBG:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", pad, -pad)
        frame.durationBG = durationBG

        duration:SetFont(FONT_PATH_BOLD, 18, FONT_FLAG)
    end

    -- Precompute ordered aura frame lists (avoid GetChildren/sort every update)
    do
        local debuffFrames = { nameplate.debuffs:GetChildren() }
        table.sort(debuffFrames, function(a, b) return a:GetID() < b:GetID() end)
        nameplate.debuffFrames = debuffFrames

        local buffFrames = { nameplate.buffs:GetChildren() }
        table.sort(buffFrames, function(a, b) return a:GetID() < b:GetID() end)
        nameplate.buffFrames = buffFrames
    end

    local default = nameplate:GetParent()

    local totemIconFrame = CreateFrame("Frame", nil, default)
    totemIconFrame:SetSize(32, 32)
    totemIconFrame:SetPoint("CENTER", default, "CENTER", 0, 10)
    totemIconFrame:Hide()

    -- Icon texture (zoomed like aura icons)
    local icon = totemIconFrame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(totemIconFrame)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Border using BORDER_PATH
    local border = totemIconFrame:CreateTexture(nil, "OVERLAY")
    border:SetTexture(BORDER_PATH)
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", totemIconFrame, "TOPLEFT", -3, 3)
    border:SetPoint("BOTTOMRIGHT", totemIconFrame, "BOTTOMRIGHT", 3, -3)

    totemIconFrame.icon = icon
    totemIconFrame.border = border

    nameplate.totemIcon = totemIconFrame

    default:HookScript("OnShow", function()
        OnShow(nameplate)
    end)

    default:HookScript("OnHide", function()
        OnHide(nameplate)
    end)

    default:HookScript("OnUpdate", function()
        OnUpdate(nameplate)
    end)

    default.healthBar:HookScript("OnValueChanged", function(_, value)
        HealthBar_OnValueChanged(nameplate, value)
    end)

    default.castBar:HookScript("OnShow", function()
        CastBar_OnShow(nameplate)
    end)

    default.castBar:HookScript("OnHide", function()
        CastBar_OnHide(nameplate)
    end)

    default.castBar:HookScript("OnValueChanged", function(_, value)
        CastBar_OnValueChanged(nameplate, value)
    end)

    OnShow(nameplate)
    return nameplate
end
