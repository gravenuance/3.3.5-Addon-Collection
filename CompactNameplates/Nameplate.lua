local ADDON_NAME, addon    = ...

local FONT_PATH            = "Interface\\AddOns\\CompactNameplates\\Media\\font.ttf"
local FONT_PATH_BOLD       = "Interface\\AddOns\\CompactNameplates\\Media\\font-bold.ttf"
local BORDER_PATH          = "Interface\\AddOns\\CompactNameplates\\Media\\border.tga"
local FONT_FLAG            = "OUTLINE"
local MAX_AURA_FRAMES      = 5
local AURA_SIZE            = 28
local AURA_SPACING         = 4
local TOTEM_SIZE           = 32

-- Combat-log events already keep aura data accurate in real time; this is
-- just a periodic safety net against a missed event, not the primary path.
local AURA_SAFETY_REFRESH_INTERVAL = 2

-- Seconds between full unit-token scans per plate (also the retry delay for
-- class lookups that came up empty).
local RESOLVE_INTERVAL = 0.25

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

local UnitExists      = UnitExists
local UnitGUID        = UnitGUID
local UnitName        = UnitName
local UnitClass       = UnitClass
local UnitIsPlayer    = UnitIsPlayer
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local UnitHealthMax   = UnitHealthMax
local GetTime         = GetTime
local GetSpellInfo    = GetSpellInfo

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

    name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")

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
    if not nameplate then
        return false
    end
    local default = nameplate:GetParent()
    if not default then
        return false
    end
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

-- A binding is `proven` (token, raid mark or a unique name) or guessed; only a conflicting proof replaces a proven one.
local function ClearGUID(nameplate)
    local guid = nameplate.unitGUID
    if not guid then return end
    if nameplatesByGUID[guid] == nameplate then
        nameplatesByGUID[guid] = nil
    end
    nameplate.unitGUID = nil
    nameplate._bindProven = false
    nameplate._boundName = nil
    nameplate._cachedUnitID = nil
    nameplate._noClassUntil = nil
end

-- A GUID is on one plate at a time: the plate that held it is left unbound and both are redrawn.
-- Returns true when the plate's GUID changed.
local function BindGUID(nameplate, guid, proven)
    if nameplate.unitGUID == guid then
        nameplate._bindProven = nameplate._bindProven or proven
        return false
    end

    local previousHolder = nameplatesByGUID[guid]
    ClearGUID(nameplate)
    if previousHolder then
        ClearGUID(previousHolder)
    end

    nameplatesByGUID[guid] = nameplate
    nameplate.unitGUID = guid
    nameplate._bindProven = proven
    nameplate._boundName = Nameplate:GetPlateName(nameplate)
    nameplate._noClassUntil = nil

    if previousHolder then
        Nameplate:UpdateAuras(previousHolder)
    end
    Nameplate:UpdateAuras(nameplate)
    return true
end

function Nameplate:Get(unitGUID)
    return nameplatesByGUID[unitGUID]
end

local function IsInDungeon()
    local inInstance, instanceType = IsInInstance()
    return inInstance and instanceType == "party"
end

local function IsInRaidInstance()
    local inInstance, instanceType = IsInInstance()
    return inInstance and instanceType == "raid"
end

--[[ local function IsInArenaInstance()
    local inInstance, instanceType = IsInInstance()
    return inInstance and instanceType == "arena"
end ]]

-- Cached candidate list
local UNIT_CANDIDATES

local function BuildUnitCandidates()
    if UNIT_CANDIDATES then
        return UNIT_CANDIDATES
    end

    local candidates = {}

    --if IsInArenaInstance() then
    for i = 1, 5 do
        candidates[#candidates + 1] = "arena" .. i
        candidates[#candidates + 1] = "arena" .. i .. "target"
        candidates[#candidates + 1] = "arenapet" .. i
        candidates[#candidates + 1] = "arenapet" .. i .. "target"
    end
    --end


    -- Player + pet
    candidates[#candidates + 1] = "player"
    candidates[#candidates + 1] = "pet"

    -- Target family
    candidates[#candidates + 1] = "target"
    candidates[#candidates + 1] = "focus"
    candidates[#candidates + 1] = "mouseover"

    candidates[#candidates + 1] = "targettarget"
    candidates[#candidates + 1] = "focustarget"
    candidates[#candidates + 1] = "mouseovertarget"

    if GetNumPartyMembers() > 0 then
        for i = 1, 5 do
            candidates[#candidates + 1] = "party" .. i
            candidates[#candidates + 1] = "partypet" .. i
            candidates[#candidates + 1] = "party" .. i .. "target"
            candidates[#candidates + 1] = "partypet" .. i .. "target"
        end
    elseif GetNumRaidMembers() > 0 then
        for i = 1, 40 do
            candidates[#candidates + 1] = "raid" .. i
            candidates[#candidates + 1] = "raidpet" .. i
            candidates[#candidates + 1] = "raid" .. i .. "target"
            candidates[#candidates + 1] = "raidpet" .. i .. "target"
        end
    end

    if IsInDungeon() or IsInRaidInstance() then
        for i = 1, 5 do
            candidates[#candidates + 1] = "boss" .. i
            candidates[#candidates + 1] = "boss" .. i .. "target"
        end
    end

    UNIT_CANDIDATES = candidates
    return candidates
end

-- The list depends on group makeup and instance type
local candidatesInvalidator = CreateFrame("Frame")
candidatesInvalidator:RegisterEvent("PARTY_MEMBERS_CHANGED")
candidatesInvalidator:RegisterEvent("RAID_ROSTER_UPDATE")
candidatesInvalidator:RegisterEvent("PLAYER_ENTERING_WORLD")
candidatesInvalidator:SetScript("OnEvent", function()
    UNIT_CANDIDATES = nil
end)

-- Cheap re-validation of a nameplate's last-known unit token before paying
-- for a full BuildUnitCandidates() scan (which, in a 40-man raid, is ~180
-- unit tokens - each checked with UnitExists/UnitGUID). Token-to-GUID
-- mapping is stable frame-to-frame for the vast majority of ticks, so this
-- turns the common case into 2 cheap API calls instead of hundreds.
local function ResolveUnitIDForGUID(nameplate, guid)
    local cached = nameplate._cachedUnitID
    if cached and UnitExists(cached) and UnitGUID(cached) == guid then
        return cached
    end

    local candidates = BuildUnitCandidates()
    for _, unitID in ipairs(candidates) do
        if UnitExists(unitID) and UnitGUID(unitID) == guid then
            nameplate._cachedUnitID = unitID
            return unitID
        end
    end

    nameplate._cachedUnitID = nil
    return nil
end

local function GetUnitID(nameplate)
    local guid = nameplate.unitGUID
    if guid then
        local unitID = ResolveUnitIDForGUID(nameplate, guid)
        if unitID then
            return unitID
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

function Nameplate:GetUnitID(nameplate)
    return GetUnitID(nameplate)
end

function Nameplate:GetUnitCandidates()
    return BuildUnitCandidates()
end

function addon.Nameplate:IsTargetPlate(nameplate)
    if not nameplate then
        return false
    end
    local unitID = Nameplate:GetUnitID(nameplate)
    if unitID == "target" then
        return true
    end
    local default = nameplate:GetParent()
    return UnitExists("target") and default and default:GetAlpha() == 1
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

function addon.Nameplate:GetPlateName(nameplate)
    local default = nameplate and nameplate:GetParent()
    if not default or not default.unitName then
        return nil
    end
    return default.unitName:GetText()
end

local function GetUnitLevel(nameplate)
    local default = GetDefaultFrame(nameplate)
    if default.skullIcon:IsShown() then
        return "??"
    end
    return default.unitLevel:GetText()
end

-------------------------------------------------
-- Class color, GUID updates
-------------------------------------------------

-- Shares a class found through a unit token with plates that never get one.
local function NoteUnitClass(unitID, guid, class)
    if not class or not UnitIsPlayer(unitID) or addon.ClassIntel:ClassForGUID(guid) then
        return
    end
    local name, realm = UnitName(unitID)
    if name and realm and realm ~= "" then
        name = name .. "-" .. realm
    end
    addon.ClassIntel:Note(guid, name, class)
end

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
                NoteUnitClass(unit, guid, class)
                return class
            end
        end
    end

    return nil
end

local function SetClassColor(nameplate)
    local guid  = nameplate.unitGUID
    local info  = guid and addon.Units:Get(guid)
    local class = info and info.class
        or addon.ClassIntel:ClassForGUID(guid)
        or addon.ClassIntel:ClassForName(Nameplate:GetPlateName(nameplate))

    if not class then
        -- NPCs never get a class, so don't rescan every candidate each frame
        local now = GetTime()
        if not nameplate._noClassUntil or now >= nameplate._noClassUntil then
            class = ResolveGUID(nameplate)
            if not class then
                nameplate._noClassUntil = now + RESOLVE_INTERVAL
            end
        end
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

local function HideAuraFrame(self)
    self.timeLeft = nil
    self:SetScript("OnUpdate", nil)
    if self.duration then
        self.duration:Hide()
    end
    if self.cooldown then
        self.cooldown:Clear()
        self.cooldown:Hide()
    end
    self:Hide()
end

-- An aura of unknown duration shows its icon only and hides itself when its estimate runs out.
local function AuraFrame_OnUpdateNoTimer(self, elapsed)
    self.timeLeft = self.timeLeft - elapsed
    if self.timeLeft <= 0 then
        HideAuraFrame(self)
    end
end

local function AuraFrame_OnUpdate(self, elapsed)
    local durationFS = self.duration

    if self.timeLeft and self.timeLeft > 0 then
        self.timeLeft = math.max(self.timeLeft - elapsed, 0)

        local t
        if self.timeLeft > 1 then
            t = math.floor(self.timeLeft + 0.5)
        elseif self.timeLeft > 0 then
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
        HideAuraFrame(self)
    end
end

local function AuraFrame_SetTimer(self, expirationTime)
    if self.duration then
        self.duration:SetFont(FONT_PATH_BOLD, math.ceil(AURA_SIZE * 0.5), FONT_FLAG)
    end
    if not self.timeLeft then
        self:SetScript("OnUpdate", AuraFrame_OnUpdate)
    end
    self.timeLeft = expirationTime - GetTime()
end

local function ConfigureAuraFrame(frame, spellID, duration, expirationTime, auraTypeKey, dispelType)
    local _, _, spellIcon = GetSpellInfo(spellID)

    frame.icon:SetTexture(spellIcon)

    frame.timeLeft = nil
    frame:SetScript("OnUpdate", nil)

    if duration > 0 then
        AuraFrame_SetTimer(frame, expirationTime)
        if frame.duration then
            frame.duration:Show()
        end
    else
        if frame.duration then
            frame.duration:Hide()
        end
        frame.timeLeft = expirationTime - GetTime()
        frame:SetScript("OnUpdate", AuraFrame_OnUpdateNoTimer)
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

-- Reused by every row: a row is laid out before the next one is collected.
local collectedAuras = {}

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
            aura.auraType,
            aura.dispelType
        )

        offset = LayoutAuraFrame(frame, frameIndex, offset, container)
        frameIndex = frameIndex + 1
    end

    for i = frameIndex, #frames do
        HideAuraFrame(frames[i])
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

    if nameplate.debuffFrames then
        LayoutRow(nameplate.debuffFrames, addon.Auras:Collect(guid, "DEBUFF", collectedAuras), nameplate.debuffs)
    end
    if nameplate.buffFrames then
        LayoutRow(nameplate.buffFrames, addon.Auras:Collect(guid, "BUFF", collectedAuras), nameplate.buffs)
    end
end

-------------------------------------------------
-- Nameplate show/hide / update
-------------------------------------------------

local function LearnFromToken(unitID, guid)
    local _, class = UnitClass(unitID)
    addon.Units:SetGUID(guid, UnitName(unitID), UnitHealthMax(unitID) or 0, class)
    NoteUnitClass(unitID, guid, class)
end

-- Proof 1: the plate is the target or the mouseover, and that unit has the plate's name.
local function TokenProof(nameplate, plateName)
    local unitID
    if Nameplate:IsTarget(nameplate) then
        unitID = "target"
    elseif IsMouseover(nameplate) then
        unitID = "mouseover"
    end
    if unitID and UnitName(unitID) == plateName then
        return UnitGUID(unitID)
    end
    return nil
end

-- Proof 2: the plate shows a raid mark whose GUID the combat log or a token revealed.
local function MarkProof(nameplate)
    local icon = GetDefaultFrame(nameplate).raidIcon
    if not icon:IsShown() then return nil end
    local mark = addon.MarkIntel.RaidMarkFromTexCoord(icon:GetTexCoord())
    return addon.MarkIntel:GUIDForMark(mark)
end

local function CountOtherPlatesShowing(nameplate, plateName)
    local plates = addon.GetAllNameplates()
    local count = 0
    for i = 1, #plates do
        local other = plates[i]
        if other ~= nameplate then
            local default = GetDefaultFrame(other)
            if default:IsShown() and default.unitName:GetText() == plateName then
                count = count + 1
            end
        end
    end
    return count
end

-- Proof 3: one token GUID has the plate's name and no other visible plate shows it.
local function NameProof(nameplate, plateName)
    local candidates = BuildUnitCandidates()
    local found
    for i = 1, #candidates do
        local unitID = candidates[i]
        if UnitExists(unitID) and UnitName(unitID) == plateName then
            local guid = UnitGUID(unitID)
            if guid and found and guid ~= found then
                return nil
            end
            found = found or guid
        end
    end
    if found and CountOtherPlatesShowing(nameplate, plateName) == 0 then
        return found
    end
    return nil
end

-- Only fills an empty plate with a GUID no plate holds: name and health seen
-- through a token, or a player seen only in the combat log.
local function Guess(nameplate)
    if nameplate.unitGUID then return end
    local guid = Nameplate:GetGUIDByNameAndHealthFromPlate(nameplate)
        or addon.ClassIntel:GUIDForName(Nameplate:GetPlateName(nameplate))
    if guid and not nameplatesByGUID[guid] then
        BindGUID(nameplate, guid, false)
    end
end

-- Order: target/mouseover token, raid mark, unique name, then guesses. A proven
-- binding only gives way to another token or mark proof.
local function ResolveOrFallbackGUID(nameplate)
    local plateName = Nameplate:GetPlateName(nameplate)
    if plateName then
        -- Blizzard reuses plate frames; a new name means a new unit.
        if nameplate._boundName and nameplate._boundName ~= plateName then
            ClearGUID(nameplate)
        end

        local guid = TokenProof(nameplate, plateName) or MarkProof(nameplate)
        if not guid and not nameplate._bindProven then
            guid = NameProof(nameplate, plateName)
        end

        if guid then
            local changed = BindGUID(nameplate, guid, true)
            local unitID = ResolveUnitIDForGUID(nameplate, guid)
            if changed and unitID then
                LearnFromToken(unitID, guid)
            end
            return unitID
        end
        Guess(nameplate)
    end

    local guid = nameplate.unitGUID
    return guid and ResolveUnitIDForGUID(nameplate, guid) or nil
end

---Resolves the plate's GUID and returns the unit token that currently shows it, if any.
function Nameplate:Resolve(nameplate)
    return ResolveOrFallbackGUID(nameplate)
end

---Drops the plate's GUID, e.g. when its frame is hidden.
function Nameplate:Unbind(nameplate)
    ClearGUID(nameplate)
end

local function OnShow(nameplate)
    UpdateNameplateUnitInfo(nameplate)
    ResolveOrFallbackGUID(nameplate)
    nameplate._lastGUID = nameplate.unitGUID
    SetClassColor(nameplate)
    Nameplate:UpdateAuras(nameplate)

    if nameplate.combo and addon.ComboPoints and addon.ComboPoints.Update then
        local isTarget = Nameplate:IsTarget(nameplate)
        addon.ComboPoints:Update(nameplate.combo, isTarget)
    end
end

local function OnHide(nameplate)
    nameplate._resolvedUnitID = nil
    nameplate._resolveElapsed = nil
    ClearGUID(nameplate)
    nameplate._lastGUID = nil
    Nameplate:UpdateAuras(nameplate)
end

local function OnUpdate(nameplate, elapsed)
    local default = GetDefaultFrame(nameplate)

    nameplate.raidIcon:SetTexCoord(default.raidIcon:GetTexCoord())
    nameplate.raidIcon:SetShown(default.raidIcon:IsShown())

    -- Re-resolve on a timer, or at once if the cached token no longer matches
    local unitID = nameplate._resolvedUnitID
    nameplate._resolveElapsed = (nameplate._resolveElapsed or RESOLVE_INTERVAL) + (elapsed or 0)
    if nameplate._resolveElapsed >= RESOLVE_INTERVAL
        or (unitID and UnitGUID(unitID) ~= nameplate.unitGUID) then
        nameplate._resolveElapsed = 0
        unitID = ResolveOrFallbackGUID(nameplate)
        nameplate._resolvedUnitID = unitID
    end

    local showPlate = true
    if nameplate.totemIcon then
        nameplate.totemIcon:Hide()
    end

    if nameplate.combo and addon.ComboPoints and addon.ComboPoints.Update then
        local isTarget = Nameplate:IsTarget(nameplate)
        addon.ComboPoints:Update(nameplate.combo, isTarget)
    end

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

    nameplate:SetShown(showPlate)

    if showPlate then
        SetClassColor(nameplate)

        -- Auras are already kept accurate in real time via combat-log
        -- events (Auras:OnApply/OnRemove/OnStolen -> UpdateForGUID, see
        -- Auras.lua/CompactNameplates.lua) and via OnShow when a plate
        -- first appears. Re-fetching + re-sorting + re-laying-out every
        -- single frame for every visible plate was pure redundant work on
        -- top of that; this periodic pass is just a safety net in case an
        -- event was ever missed.
        nameplate._auraRefreshElapsed = (nameplate._auraRefreshElapsed or 0) + (elapsed or 0)
        if nameplate._auraRefreshElapsed >= AURA_SAFETY_REFRESH_INTERVAL then
            nameplate._auraRefreshElapsed = 0
            Nameplate:UpdateAuras(nameplate)
        end
    end
end

-------------------------------------------------
-- Public API
-------------------------------------------------

function Nameplate:Create(default)
    local nameplate = CreateFrame("Frame", nil, default, "NameplateFrameTemplate")
    nameplate:ClearAllPoints()
    nameplate:SetPoint("CENTER", default, "CENTER", 0, 10)
    if addon.ComboPoints and addon.ComboPoints.Create then
        nameplate.combo = addon.ComboPoints:Create(nameplate)
        nameplate.combo:ClearAllPoints()
        nameplate.combo:SetPoint("TOP", nameplate, "BOTTOM", 0, 10)
    end
    local nameFS  = nameplate.healthBar.unitName
    local levelFS = nameplate.healthBar.unitLevel
    local pad     = 0
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
    nameplate.debuffs:SetPoint("BOTTOMLEFT", nameplate, "TOPLEFT", 0, math.ceil(AURA_SIZE * 0.3))
    nameplate.debuffs:SetHeight(AURA_SIZE)

    -- Buffs row (above debuffs)
    nameplate.buffs = CreateFrame("Frame", nil, nameplate)
    nameplate.buffs:SetPoint("BOTTOMLEFT", nameplate, "TOPLEFT", 0, math.ceil(AURA_SIZE * 1.6))
    nameplate.buffs:SetHeight(AURA_SIZE)

    -- Create frames for DEBUFFS
    for i = 1, MAX_AURA_FRAMES do
        local frame = CreateFrame("Frame", nil, nameplate.debuffs, "NameplateAuraFrameTemplate")
        if frame.icon then
            frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        frame:SetSize(AURA_SIZE, AURA_SIZE)
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
        durationBG:SetTexture(0, 0, 0, 0.2)
        durationBG:SetPoint("TOPLEFT", icon, "TOPLEFT", -pad, pad)
        durationBG:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", pad, -pad)
        frame.durationBG = durationBG

        duration:SetFont(FONT_PATH_BOLD, math.ceil(AURA_SIZE * 0.5), FONT_FLAG)
    end

    -- Create frames for BUFFS
    for i = 1, MAX_AURA_FRAMES do
        local frame = CreateFrame("Frame", nil, nameplate.buffs, "NameplateAuraFrameTemplate")
        frame:SetSize(AURA_SIZE, AURA_SIZE)
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
        durationBG:SetTexture(0, 0, 0, 0.2)
        durationBG:SetPoint("TOPLEFT", icon, "TOPLEFT", -pad, pad)
        durationBG:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", pad, -pad)
        frame.durationBG = durationBG

        duration:SetFont(FONT_PATH_BOLD, math.ceil(AURA_SIZE * 0.5), FONT_FLAG)
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
    totemIconFrame:SetSize(TOTEM_SIZE, TOTEM_SIZE)
    totemIconFrame:SetPoint("CENTER", default, "CENTER", 0, 20)
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

    default:HookScript("OnUpdate", function(_, elapsed)
        OnUpdate(nameplate, elapsed)
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
