local ADDON_NAME, addon = ...

local Auras = {}
addon.Auras = Auras

-- Static aura info: [spellID] = {name, duration, type, dispelType}
local auraInfo = {
    -- Shaman
    [3600]  = { "Earthbind", 5, "DEBUFF", "Magic" },
    [8185]  = { "Fire Resistance", nil, "BUFF" },
    [10534] = { "Fire Resistance", nil, "BUFF" },
    [10535] = { "Fire Resistance", nil, "BUFF" },
    [24464] = { "Fire Resistance", nil, "BUFF" },
    [8050]  = { "Flame Shock", 12, "DEBUFF", "Magic" },
    [8052]  = { "Flame Shock", 12, "DEBUFF", "Magic" },
    [8053]  = { "Flame Shock", 12, "DEBUFF", "Magic" },
    [10447] = { "Flame Shock", 12, "DEBUFF", "Magic" },
    [10448] = { "Flame Shock", 12, "DEBUFF", "Magic" },
    [29228] = { "Flame Shock", 12, "DEBUFF", "Magic" },
    [16257] = { "Flurry", 15, "BUFF" },
    [16277] = { "Flurry", 15, "BUFF" },
    [16278] = { "Flurry", 15, "BUFF" },
    [16279] = { "Flurry", 15, "BUFF" },
    [16280] = { "Flurry", 15, "BUFF" },
    [43339] = { "Focused", 15, "BUFF", "Magic" },
    [8182]  = { "Frost Resistance", nil, "BUFF" },
    [10476] = { "Frost Resistance", nil, "BUFF" },
    [10477] = { "Frost Resistance", nil, "BUFF" },
    [8056]  = { "Frost Shock", 8, "DEBUFF", "Magic" },
    [8058]  = { "Frost Shock", 8, "DEBUFF", "Magic" },
    [10472] = { "Frost Shock", 8, "DEBUFF", "Magic" },
    [10473] = { "Frost Shock", 8, "DEBUFF", "Magic" },
    [8034]  = { "Frostbrand Attack", 8, "DEBUFF" },
    [8037]  = { "Frostbrand Attack", 8, "DEBUFF" },
    [10458] = { "Frostbrand Attack", 8, "DEBUFF" },
    [16352] = { "Frostbrand Attack", 8, "DEBUFF" },
    [16353] = { "Frostbrand Attack", 8, "DEBUFF" },
    [8836]  = { "Grace of Air", nil, "BUFF" },
    [10626] = { "Grace of Air", nil, "BUFF" },
    [25360] = { "Grace of Air", nil, "BUFF" },
    [8178]  = { "Grounding Totem Effect", nil, "BUFF" },
    [5672]  = { "Healing Stream", nil, "BUFF" },
    [6371]  = { "Healing Stream", nil, "BUFF" },
    [6372]  = { "Healing Stream", nil, "BUFF" },
    [10460] = { "Healing Stream", nil, "BUFF" },
    [10461] = { "Healing Stream", nil, "BUFF" },
    [324]   = { "Lightning Shield", 600, "BUFF", "Magic" },
    [325]   = { "Lightning Shield", 600, "BUFF", "Magic" },
    [905]   = { "Lightning Shield", 600, "BUFF", "Magic" },
    [945]   = { "Lightning Shield", 600, "BUFF", "Magic" },
    [8134]  = { "Lightning Shield", 600, "BUFF", "Magic" },
    [10431] = { "Lightning Shield", 600, "BUFF", "Magic" },
    [10432] = { "Lightning Shield", 600, "BUFF", "Magic" },
    [5677]  = { "Mana Spring", nil, "BUFF" },
    [10491] = { "Mana Spring", nil, "BUFF" },
    [10493] = { "Mana Spring", nil, "BUFF" },
    [10494] = { "Mana Spring", nil, "BUFF" },
    [16191] = { "Mana Tide", nil, "BUFF" },
    [17355] = { "Mana Tide", nil, "BUFF" },
    [17360] = { "Mana Tide", nil, "BUFF" },
    [10596] = { "Nature Resistance", nil, "BUFF" },
    [10598] = { "Nature Resistance", nil, "BUFF" },
    [10599] = { "Nature Resistance", nil, "BUFF" },
    [84647] = { "Primal Wielding", 4.5, "BUFF" },
    [8072]  = { "Stoneskin", nil, "BUFF" },
    [8156]  = { "Stoneskin", nil, "BUFF" },
    [8157]  = { "Stoneskin", nil, "BUFF" },
    [10403] = { "Stoneskin", nil, "BUFF" },
    [10404] = { "Stoneskin", nil, "BUFF" },
    [10405] = { "Stoneskin", nil, "BUFF" },
    [17364] = { "Stormstrike", 12, "DEBUFF", "Magic" },
    [8076]  = { "Strength of Earth", nil, "BUFF" },
    [8162]  = { "Strength of Earth", nil, "BUFF" },
    [8163]  = { "Strength of Earth", nil, "BUFF" },
    [10441] = { "Strength of Earth", nil, "BUFF" },
    [25362] = { "Strength of Earth", nil, "BUFF" },
    [25909] = { "Tranquil Air", nil, "BUFF" },
    [131]   = { "Water Breathing", 600, "BUFF", "Magic" },
    [546]   = { "Water Walking", 600, "BUFF", "Magic" },
}

-- Blacklist (by spellID)
local BLACKLIST = {
    [57975] = true, -- Wound Poison VII
    [3409]  = true, -- Crippling Poison
    [51693] = true, -- Waylay
    [5760]  = true, -- Mind-numbing Poison
}

local BUFF_WHITELIST = {
    [46924] = true, -- Bladestorm
    [20230] = true, -- Retaliation
    [1719] = true,  -- Recklessness
    [2565] = true,  -- Shield Block
    [871] = true,   -- Shield Wall
    [23920] = true, -- Spell Reflection
    [3411] = true,  -- Intervene
    [12328] = true, -- Sweeping Strikes
    [18499] = true, -- Berserker Rage
    [55694] = true, -- Enraged Regeneration




    [12976] = true, -- Last Stand
    -- Paladin

    [54428] = true, -- Divine Plea

    [498] = true,   -- Divine Protection
    [64205] = true, -- Divine Sacrifice
    [6940] = true,  -- Hand of Sacrifice
    [642] = true,   -- Divine Shield

    [1044] = true,  -- Hand of Freedom
    [31884] = true, -- Avenging Wrath
    [10278] = true, -- Hand of Protection

    [31821] = true, -- Aura Mastery
    [31842] = true, -- Divine Illumination

    [20216] = true, -- Divine Favor

    -- Rogue
    [31224] = true, -- Cloak of Shadows
    [57934] = true, -- Tricks of the Trade
    [51713] = true, -- Shadowdance
    [51690] = true, -- Killing Spree
    [13750] = true, -- Adrenaline Rush
    [26669] = true, -- Evasion
    [11305] = true, -- Sprint
    [26889] = true, -- Vanish
    [14177] = true, -- Cold Blood
    [36554] = true, -- Shadowstep
    -- Priest
    [6346] = true,  -- Fear Ward
    [33206] = true, -- Pain Suppression
    [10060] = true, -- Power Infusion
    [48173] = true, -- Desperate Prayer
    [64844] = true, -- Divine Hymn
    [64904] = true, -- Hymn of Hope
    [47585] = true, -- Dispresion
    [586] = true,   -- Fade
    -- Death Knight
    [45529] = true, -- Blood Tap
    [48743] = true, -- Death Pact
    [47568] = true, -- Empower Rune Weapon
    [49039] = true, -- Lichborne
    [48792] = true, -- Icebound Fortitude
    [48707] = true, -- Anti-Magic Shell
    [51052] = true, -- Anti-Magic Zone
    [49560] = true, -- Death Grip
    [49203] = true, -- Hungering Cold
    [49796] = true, -- Deathchill
    [51271] = true, -- Unbreakable Armor
    --Mage
    [66] = true,    -- Invisibility
    [12051] = true, -- Evocation
    [12042] = true, -- Arcane Power
    [12043] = true, -- Presence of Mind
    [28682] = true, -- Combustion
    [43039] = true, -- Ice Barrier
    [12472] = true, -- Icy Veins
    [45438] = true, -- Ice Block
    -- Warlock
    [18708] = true, -- Fel Domination
    [61290] = true, -- Shadowflame
    [47827] = true, -- Shadowburn
    -- Shaman
    [32182] = true, -- Heroism
    [2825] = true,  -- Bloodlust
    [30823] = true, -- Shamanistic Rage
    [16188] = true, -- Nature's Swiftness
    [16166] = true, -- Elemental Mastery
    [55166] = true, -- Tidal Force
    -- Druid
    [22812] = true, -- Barkskin
    [29166] = true, -- Innervate
    [53312] = true, -- Nature's Grasp
    [22842] = true, -- Frenzied Regeneration
    [17116] = true, -- Nature's Swiftness
    [48447] = true, -- Tranquility
    [61336] = true, -- Survival Instincts
    [50213] = true, -- Tiger's Fury
    [33831] = true, -- Force of Nature
    [18562] = true, -- Swiftmend
    [50334] = true, -- Berserk
    [33357] = true, -- Dash
    [5229] = true,  -- Enrage
    [69369] = true, -- Predator's Swiftness
    -- Hunter
    [23989] = true, -- Readiness
    [3045] = true,  -- Rapid Fire
    [53271] = true, -- Master's Call
    [19263] = true, -- Deterrence
    [781] = true,   -- Disengage
    [19574] = true, -- Bestial Wrath
}

local MAX_TRACK_DURATION = 5 * 60 -- 20 minutes

local function ShouldTrackAura(spellID, duration, auraType)
    -- Blacklist (shared)
    if BLACKLIST[spellID] then
        return false
    end

    -- Buff whitelist: only track whitelisted buffs
    if auraType == "BUFF" then
        if not BUFF_WHITELIST[spellID] then
            return false
        end
    end

    -- Require a real duration
    if not duration or duration <= 0 then
        return false
    end

    -- Skip very long / pseudo-permanent
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
    if not ShouldTrackAura(spellID, duration, auraType) then
        return
    end
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
        local name, _, _, _, dispelType, duration, expirationTime, _, _, _, spellID =
            UnitAura(unitID, i, "HARMFUL")
        if not spellID then break end

        auraInfo[spellID] = { name, duration, "DEBUFF", dispelType }
        if ShouldTrackAura(spellID, duration, "DEBUFF") then
            AddAura(unitGUID, "DEBUFF", spellID, duration, expirationTime, dispelType)
        end
        i = i + 1
    end

    -- Buffs
    i = 1
    while true do
        local name, _, _, _, dispelType, duration, expirationTime, _, _, _, spellID =
            UnitAura(unitID, i, "HELPFUL")
        if not spellID then break end

        auraInfo[spellID] = { name, duration, "BUFF", dispelType }
        if ShouldTrackAura(spellID, duration, "BUFF") then
            AddAura(unitGUID, "BUFF", spellID, duration, expirationTime, dispelType)
        end
        i = i + 1
    end
end

function Auras:OnApply(_, _, _, _, _, unitGUID, _, _, spellID, _, _, auraType)
    local info = auraInfo[spellID]
    if not info then return end

    local _, duration = unpack(info)
    local auraTypeKey = (auraType == "BUFF") and "BUFF" or "DEBUFF"

    if not ShouldTrackAura(spellID, duration, auraTypeKey) then
        return
    end

    AddAura(unitGUID, auraTypeKey, spellID, duration, GetTime() + duration, info[4])

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
