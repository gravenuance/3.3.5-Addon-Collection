local ADDON_NAME, addon  = ...

local Auras              = {}
addon.Auras              = Auras

local Settings           = addon.Settings

local DEBUFF_WHITELIST   = Settings.AURA_DEBUFF_WHITELIST
local BUFF_WHITELIST     = Settings.AURA_BUFF_WHITELIST

local MAX_TRACK_DURATION = 5 * 60


local function ShouldTrackAura(spellID, duration, auraType)
    local name = GetSpellInfo(spellID)
    if not name then
        return false
    end

    if auraType == "DEBUFF" then
        if not DEBUFF_WHITELIST[name] then
            return false
        end
    elseif auraType == "BUFF" then
        if not BUFF_WHITELIST[name] then
            return false
        end
    end

    if not duration or duration <= 0 then
        return false
    end

    if duration > MAX_TRACK_DURATION then
        return false
    end

    return true
end

local aurasByGUID = {}

local function GetAuraList(unitGUID, auraType, create)
    local byGUID = aurasByGUID[unitGUID]
    if not byGUID and create then
        byGUID = {}
        aurasByGUID[unitGUID] = byGUID
    end
    if not byGUID then return end

    local list = byGUID[auraType]
    if not list and create then
        list = {}
        byGUID[auraType] = list
    end
    return list
end

-------------------------------------------------
-- Public API
-------------------------------------------------

function Auras:Get(unitGUID, auraType, index)
    local byGUID = aurasByGUID[unitGUID]
    local list = byGUID and byGUID[auraType]
    local aura = list and list[index]
    if aura then
        -- spellID, duration, expirationTime, auraTypeKey, dispelType
        return aura[1], aura[2], aura[3], aura[4], aura[5]
    end
end

local function AddAura(unitGUID, auraType, spellID, duration, expirationTime, dispelType)
    local list = GetAuraList(unitGUID, auraType, true)
    list[#list + 1] = { spellID, duration, expirationTime, auraType, dispelType }
end

function Auras:Refresh(unitID)
    local unitGUID = UnitGUID(unitID)
    if not unitGUID then return end

    aurasByGUID[unitGUID] = nil

    -- Debuffs
    local i = 1
    while true do
        local _, _, _, _, dispelType, duration, expirationTime, _, _, _, spellID =
            UnitAura(unitID, i, "HARMFUL")
        if not spellID then break end

        if ShouldTrackAura(spellID, duration, "DEBUFF") then
            AddAura(unitGUID, "DEBUFF", spellID, duration, expirationTime, dispelType)
        end
        i = i + 1
    end

    -- Buffs
    i = 1
    while true do
        local _, _, _, _, dispelType, duration, expirationTime, _, _, _, spellID =
            UnitAura(unitID, i, "HELPFUL")
        if not spellID then break end

        if ShouldTrackAura(spellID, duration, "BUFF") then
            AddAura(unitGUID, "BUFF", spellID, duration, expirationTime, dispelType)
        end
        i = i + 1
    end
end

function Auras:OnApply(_, _, _, _, _, unitGUID, _, _, spellID, _, _, auraType)
    local _, _, _, _, _, duration, _, _, _, _ = GetSpellInfo(spellID)
    --print(duration, spellID, auraType)
    if not duration then return end
    --print(duration, spellID, auraType, 2)
    local auraTypeKey = (auraType == "BUFF") and "BUFF" or "DEBUFF"
    --print(duration, spellID, auraType, 3)
    if not ShouldTrackAura(spellID, duration, auraTypeKey) then
        return
    end
    AddAura(unitGUID, auraTypeKey, spellID, duration, GetTime() + duration, nil)

    addon.Nameplate:UpdateForGUID(unitGUID)
end

function Auras:OnRemove(_, _, _, _, _, unitGUID, _, _, spellID, _, _, auraType)
    local byGUID = aurasByGUID[unitGUID]
    if not byGUID then return end

    local auraTypeKey = (auraType == "BUFF") and "BUFF" or "DEBUFF"
    local list = byGUID[auraTypeKey]
    if not list then return end

    for i = #list, 1, -1 do
        if list[i][1] == spellID then
            table.remove(list, i)
        end
    end

    if (not byGUID.BUFF or #byGUID.BUFF == 0)
        and (not byGUID.DEBUFF or #byGUID.DEBUFF == 0) then
        aurasByGUID[unitGUID] = nil
    end

    addon.Nameplate:UpdateForGUID(unitGUID)
end

function Auras:OnStolen(_, _, _, sourceGUID, _, _, destGUID, _, _, _, _, _,
                        extraSpellID, _, _, auraType)
    -- Remove the stolen aura from the original target
    self:OnRemove(nil, nil, nil, nil, nil, destGUID, nil, nil, extraSpellID, nil, nil, auraType)
    addon.Nameplate:UpdateForGUID(destGUID)
    if not sourceGUID then return end

    local auraTypeKey = "BUFF" -- stolen effects are buffs on the stealer
    local _, _, _, _, _, duration = GetSpellInfo(extraSpellID)
    if not duration or duration <= 0 then
        return
    end

    if not ShouldTrackAura(extraSpellID, duration, auraTypeKey) then
        return
    end

    AddAura(sourceGUID, auraTypeKey, extraSpellID, duration, GetTime() + duration, nil)
    addon.Nameplate:UpdateForGUID(sourceGUID)
end
