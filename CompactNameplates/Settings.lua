local ADDON_NAME, addon = ...

local Settings = {}
addon.Settings = Settings

local CVAR_DEFAULTS = {
    nameplateZ = 1.0,
    nameplateIntersectOpacity = 0.1,
    nameplateIntersectUseCamera = 1,
    -- nameplateFadeIn = 0,  -- removed / not available, so don't set
}

-- Debuff whitelist (by spellID)
Settings.AURA_DEBUFF_WHITELIST = {
    -- Global / restrictions
    ["Forbearance"] = true, -- 25771, Paladin restriction
    ["Hypothermia"] = true, -- 41425, Mage Ice Block restriction

    ----------------------------------------------------------------
    -- Warrior: CC, snares, offensive debuffs
    ----------------------------------------------------------------
    ["Concussion Blow"] = true,    -- 12809, stun
    ["Shockwave"] = true,          -- 46968, stun
    ["Intimidating Shout"] = true, -- 5246, fear
    ["Hamstring"] = true,          -- 1715, snare
    ["Improved Hamstring"] = true, -- 23694, root
    ["Challenging Shout"] = true,  -- 1161, taunt, situational

    ----------------------------------------------------------------
    -- Paladin: CC, restrictions, offensive
    ----------------------------------------------------------------
    ["Hammer of Justice"] = true, -- 853, stun
    ["Repentance"] = true,        -- 20066, incapacitate
    ["Avenger's Shield"] = true,  -- 31935, silence/interrupt
    ["Dazed"] = true,             -- 63529, Exorcism glyph etc., if present

    ----------------------------------------------------------------
    -- Rogue: CC, poisons, offensive debuffs
    ----------------------------------------------------------------
    ["Sap"] = true,               -- 51724, incapacitate
    ["Blind"] = true,             -- 2094, disorient
    ["Kidney Shot"] = true,       -- 408 / 8643, stun
    ["Cheap Shot"] = true,        -- 1833, stun
    ["Gouge"] = true,             -- 1776, incapacitate
    ["Garrote - Silence"] = true, -- 1330
    ["Garrote"] = true,           -- 37066
    -- ["Crippling Poison"] = true,       -- 3409, snare (commented out)
    -- ["Mind-numbing Poison"] = true,    -- 5760, cast slow
    -- ["Wound Poison VII"] = true,       -- 57975, healing reduction
    -- ["Waylay"] = true,                 -- 51693, snare/slow, if relevant

    ----------------------------------------------------------------
    -- Priest: CC, DoTs, offensive debuffs
    ----------------------------------------------------------------
    ["Psychic Scream"] = true,    -- 8122, fear
    ["Mind Control"] = true,      -- 605, CC
    ["Silence"] = true,           -- 15487, silence
    ["Psychic Horror"] = true,    -- 64044, disarm/horror
    ["Shadow Word: Pain"] = true, -- 589, DoT
    ["Vampiric Touch"] = true,    -- 34914, DoT
    ["Devouring Plague"] = true,  -- 2944, DoT
    ["Weakened Soul"] = true,     -- 6788, shield debuff

    ----------------------------------------------------------------
    -- Mage: CC, slows, offensive debuffs
    ----------------------------------------------------------------
    ["Polymorph"] = true,            -- 65801, sheep
    ["Polymorph: Black Cat"] = true, -- 61305, polymorph variant
    ["Frost Nova"] = true,           -- 65792, root
    ["Frostbite"] = true,            -- 12494, root
    ["Cone of Cold"] = true,         -- 65023, slow
    ["Frostbolt"] = true,            -- 72502, slow
    ["Dragon's Breath"] = true,      -- 29964, disorient
    ["Freeze"] = true,               -- 33395, pet nova
    ["Slow"] = true,                 -- 31589, movement / cast slow

    ----------------------------------------------------------------
    -- Warlock: CC, DoTs
    ----------------------------------------------------------------
    ["Fear"] = true,                -- 5782
    ["Howl of Terror"] = true,      -- 5484
    ["Seduction"] = true,           -- 6358, pet
    ["Unstable Affliction"] = true, -- 30108, DoT + silence
    ["Corruption"] = true,          -- 172, DoT
    ["Curse of Agony"] = true,      -- 980, DoT
    ["Immolate"] = true,            -- 348, DoT
    ["Conflagrate"] = true,         -- 17962, short debuff component
    ["Shadowfury"] = true,          -- 30283, stun

    ----------------------------------------------------------------
    -- Hunter: CC, snares, offensive debuffs
    ----------------------------------------------------------------
    ["Freezing Trap"] = true,   -- 3355, CC
    ["Wyvern Sting"] = true,    -- 19386 / 49012, sleep
    ["Intimidation"] = true,    -- 24394, stun
    ["Concussive Shot"] = true, -- 5116, slow
    ["Entrapment"] = true,      -- 19387, Improved Wing Clip root/slow
    ["Silencing Shot"] = true,  -- 34490
    ["Scatter Shot"] = true,    -- 19503

    ----------------------------------------------------------------
    -- Shaman: CC, slows, offensive debuffs, DoTs
    ----------------------------------------------------------------
    ["Earthbind"] = true,   -- 3600, slow
    ["Flame Shock"] = true, -- 8050, DoT
    ["Stormstrike"] = true, -- 17364, offensive debuff
    ["Earth Shock"] = true, -- 8042, interrupt debuff
    ["Frost Shock"] = true, -- 8056, slow
    ["Hex"] = true,         -- 51514, CC

    ----------------------------------------------------------------
    -- Druid: CC, roots, DoTs
    ----------------------------------------------------------------
    ["Bash"] = true,             -- 5211 / 6798, stun
    ["Cyclone"] = true,          -- 33786, CC
    ["Hibernate"] = true,        -- 2637, sleep
    ["Entangling Roots"] = true, -- 339, root
    ["Pounce"] = true,           -- 9005, stun
    ["Maim"] = true,             -- 22570, stun
    ["Moonfire"] = true,         -- 8921, DoT
    ["Insect Swarm"] = true,     -- 5570, DoT
    ["Rake"] = true,             -- 1822, DoT + slow
    ["Rip"] = true,              -- 1079, DoT

    ----------------------------------------------------------------
    -- Death Knight: CC, diseases, offensive debuffs
    ----------------------------------------------------------------
    ["Chains of Ice"] = true,  -- 45524, root/slow
    ["Frost Fever"] = true,    -- 55095, disease DoT
    ["Blood Plague"] = true,   -- 55078, disease DoT
    ["Unholy Frenzy"] = true,  -- 49016, Hysteria, offensive buff as debuff
    ["Strangulate"] = true,    -- 47476, silence
    ["Hungering Cold"] = true, -- 49203, CC
    ["Chilblains"] = true,     -- 50041, other slow debuffs

    ----------------------------------------------------------------
    -- Misc / racials / trinkets
    ----------------------------------------------------------------
    ["Arcane Torrent"] = true, -- 25046, silence debuff
    ["Chastise"] = true,       -- 44041, similar priest CC, if debuff form
}

-- Buff whitelist (by name)
Settings.AURA_BUFF_WHITELIST = {
    -- Warrior
    ["Bladestorm"] = true,           -- 46924, huge offensive
    ["Retaliation"] = true,          -- 20230, major defensive
    ["Recklessness"] = true,         -- 1719, major offensive
    ["Shield Block"] = true,         -- 2565, key tank/defensive in PvP
    ["Shield Wall"] = true,          -- 871, main defensive
    ["Spell Reflection"] = true,     -- 23920, clutch defensive
    ["Intervene"] = true,            -- 3411, peel / damage redirect
    ["Sweeping Strikes"] = true,     -- 12328, burst cleave window
    ["Berserker Rage"] = true,       -- 18499, fear break
    ["Enraged Regeneration"] = true, -- 55694, strong heal CD
    ["Last Stand"] = true,           -- 12976, major defensive

    -- Paladin
    ["Divine Protection"] = true,  -- 498, core defensive
    ["Divine Sacrifice"] = true,   -- 64205, strong sac window
    ["Hand of Sacrifice"] = true,  -- 6940, top-tier defensive
    ["Divine Shield"] = true,      -- 642, major immunity
    ["Hand of Freedom"] = true,    -- 1044, root/snare break
    ["Avenging Wrath"] = true,     -- 31884, major offensive
    ["Hand of Protection"] = true, -- 10278, physical immunity
    ["Aura Mastery"] = true,       -- 31821, defensive / anti-silence
    ["Divine Favor"] = true,       -- 20216, guaranteed crit heal / burst

    -- Rogue
    ["Cloak of Shadows"] = true, -- 31224, core defensive
    ["Shadowdance"] = true,      -- 51713, major offensive window
    ["Killing Spree"] = true,    -- 51690, major offensive
    ["Adrenaline Rush"] = true,  -- 13750, strong offensive CD
    ["Evasion"] = true,          -- 26669, main melee defensive
    ["Vanish"] = true,           -- 26889, reset / immunity window
    ["Cold Blood"] = true,       -- 14177, burst enabler
    ["Shadowstep"] = true,       -- 36554, high-impact gap closer

    -- Priest
    ["Fear Ward"] = true,        -- 6346, high-impact anti-CC
    ["Pain Suppression"] = true, -- 33206, core defensive
    ["Power Infusion"] = true,   -- 10060, offensive / throughput CD
    ["Guardian Spirit"] = true,  -- 47788, huge external defensive
    ["Dispersion"] = true,       -- 47585, major defensive

    -- Death Knight
    ["Empower Rune Weapon"] = true, -- 47568, big offensive/utility CD
    ["Lichborne"] = true,           -- 49039, fear/charm immunity, self-heal combo
    ["Icebound Fortitude"] = true,  -- 48792, main defensive
    ["Anti-Magic Shell"] = true,    -- 48707, crucial magic defensive
    ["Anti-Magic Zone"] = true,     -- 51052, team defensive
    ["Deathchill"] = true,          -- 49796, burst crit enabler
    ["Unbreakable Armor"] = true,   -- 51271, strong defensive

    -- Mage
    ["Invisibility"] = true,     -- 66, escape/reset
    ["Arcane Power"] = true,     -- 12042, major offensive
    ["Presence of Mind"] = true, -- 12043, burst enabler
    ["Combustion"] = true,       -- 28682, major offensive
    ["Ice Barrier"] = true,      -- 43039, key defensive
    ["Icy Veins"] = true,        -- 12472, major offensive
    ["Ice Block"] = true,        -- 45438, immunity

    -- Warlock
    ["Fel Domination"] = true, -- 18708, fast pet / survival utility

    -- Shaman
    ["Heroism"] = true,            -- 32182, major offensive
    ["Bloodlust"] = true,          -- 2825, major offensive
    ["Shamanistic Rage"] = true,   -- 30823, core defensive
    ["Nature's Swiftness"] = true, -- 16188, emergency heal / CC combo
    ["Elemental Mastery"] = true,  -- 16166, burst enabler
    ["Tidal Force"] = true,        -- 55166, throughput/burst heal CD
    ["Earth Shield"] = true,       -- 49284, key healer defensive/throughput buff

    -- Druid
    ["Barkskin"] = true,              -- 22812, core defensive
    ["Innervate"] = true,             -- 29166, important mana CD
    ["Nature's Grasp"] = true,        -- 53312, peel/root proc
    ["Frenzied Regeneration"] = true, -- 22842, major defensive
    ["Nature's Swiftness"] = true,    -- 17116, instant clone/heal
    ["Survival Instincts"] = true,    -- 61336, major defensive
    ["Tiger's Fury"] = true,          -- 50213, energy/burst window
    ["Force of Nature"] = true,       -- 33831, major offensive/utility
    ["Swiftmend"] = true,             -- 18562, big heal
    ["Berserk"] = true,               -- 50334, major offensive
    ["Predator's Swiftness"] = true,  -- 69369, instant heal/CC proc

    -- Hunter
    ["Readiness"] = true,     -- 23989, huge CD reset
    ["Rapid Fire"] = true,    -- 3045, offensive
    ["Master's Call"] = true, -- 53271, root/snare break
    ["Deterrence"] = true,    -- 19263, main defensive
    ["Bestial Wrath"] = true, -- 19574, major offensive/defensive
}

local function SafeSetCVar(cvar, value)
    if GetCVar(cvar) ~= nil then
        SetCVar(cvar, value)
    end
end

function Settings:ApplyDefaults()
    for cvar, value in pairs(CVAR_DEFAULTS) do
        SafeSetCVar(cvar, value)
    end
end
