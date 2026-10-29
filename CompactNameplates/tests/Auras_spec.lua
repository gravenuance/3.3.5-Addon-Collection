-- Runs in the standalone interpreter and replaces client globals with stubs on purpose.
---@diagnostic disable: duplicate-set-field, undefined-global
local t = ...

local LIB_DIR      = "Libs/LibDRTracker-1.0/"
local PLAYER_FLAGS = 0x0548 -- hostile player
local PET_FLAGS    = 0x1148 -- hostile player-controlled pet
local NPC_FLAGS    = 0x0A48 -- hostile NPC
local SRC_GUID     = "0xSRC"

local KIDNEY_SHOT  = 8643  -- stun, DR
local POLYMORPH    = 118   -- incapacitate, DR on players only
local HYPOTHERMIA  = 41425 -- no DR
local FORBEARANCE  = 25771 -- no DR
local ICE_BLOCK    = 45438 -- buff
local RANDOM_AURA  = 999   -- on no whitelist

local P, N = "0xPLAYER", "0xNPC"

local function band(a, b)
  local result, bitValue = 0, 1
  while a > 0 and b > 0 do
    if a % 2 == 1 and b % 2 == 1 then result = result + bitValue end
    a, b, bitValue = math.floor(a / 2), math.floor(b / 2), bitValue * 2
  end
  return result
end

local function freshDB(player, npc)
  return { version = 1, durations = { player = player or {}, npc = npc or {} } }
end

-- Fresh client stubs, LibStub, DR library and module per test, because all of them live in globals or upvalues.
local function setup(db)
  local env = {
    now = 0,
    redraws = {},
    units = {},
    names = {
      [KIDNEY_SHOT] = "Kidney Shot", [POLYMORPH] = "Polymorph", [HYPOTHERMIA] = "Hypothermia",
      [FORBEARANCE] = "Forbearance", [ICE_BLOCK] = "Ice Block", [RANDOM_AURA] = "Random Aura",
    },
  }

  _G.LibStub = nil
  _G.strmatch = string.match
  _G.bit = { band = band }
  _G.wipe = function(tbl) for k in pairs(tbl) do tbl[k] = nil end return tbl end
  _G.GetTime = function() return env.now end
  _G.securecall = function(fn, ...) return fn(...) end
  _G.CreateFrame = function()
    return {
      UnregisterAllEvents = function() end,
      RegisterEvent = function() end,
      SetScript = function(_, _, fn) env.onEvent = fn end,
    }
  end
  _G.GetSpellInfo = function(spellID) return env.names[spellID] end
  _G.UnitGUID = function(unit) return env.units[unit] and env.units[unit].guid end
  _G.UnitPlayerControlled = function(unit) return env.units[unit].player end
  _G.UnitAura = function(unit, index, filter)
    local row = env.units[unit].auras[filter][index]
    if not row then return nil end
    return env.names[row.spellID], "", "icon", 1, row.dispelType, row.duration, row.expires,
      "player", false, false, row.spellID
  end

  local ns = {
    Settings = {
      AURA_DEBUFF_WHITELIST = { ["Kidney Shot"] = true, ["Polymorph"] = true, ["Hypothermia"] = true,
        ["Forbearance"] = true },
      AURA_BUFF_WHITELIST = { ["Ice Block"] = true },
    },
    Nameplate = { UpdateForGUID = function(_, guid) env.redraws[#env.redraws + 1] = guid end },
  }
  for _, file in ipairs({ "Libs/LibStub/LibStub.lua", LIB_DIR .. "LibDRTracker-1.0.lua", LIB_DIR .. "Spells.lua" }) do
    t.loadAddonFile(file, {})
  end
  t.loadAddonFile("Auras.lua", ns)

  env.auras = ns.Auras
  env.db = env.auras:LoadDB(db or freshDB())
  return env
end

-- Feeds one aura event to the DR library and then to the module, like two frames on the same event.
local function logEvent(env, event, guid, flags, spellID, auraType)
  env.onEvent(nil, "COMBAT_LOG_EVENT_UNFILTERED", env.now, event, SRC_GUID, "Src", PLAYER_FLAGS,
    guid, "Dst", flags, spellID, env.names[spellID], 1, auraType)
end

local function apply(env, guid, flags, spellID, auraType, event)
  auraType, event = auraType or "DEBUFF", event or "SPELL_AURA_APPLIED"
  logEvent(env, event, guid, flags, spellID, auraType)
  env.auras:OnApply(env.now, event, SRC_GUID, "Src", PLAYER_FLAGS, guid, "Dst", flags, spellID,
    env.names[spellID], 1, auraType)
end

local function remove(env, guid, flags, spellID, auraType)
  auraType = auraType or "DEBUFF"
  logEvent(env, "SPELL_AURA_REMOVED", guid, flags, spellID, auraType)
  env.auras:OnRemove(env.now, "SPELL_AURA_REMOVED", SRC_GUID, "Src", PLAYER_FLAGS, guid, "Dst", flags,
    spellID, env.names[spellID], 1, auraType)
end

local function at(env, now)
  env.now = now
end

-- Sets the clock, applies and runs the tick.
local function applyAt(env, now, guid, flags, spellID, auraType, event)
  env.now = now
  apply(env, guid, flags, spellID, auraType, event)
  env.auras:Tick()
end

-- Rows of { spellID, duration, expirationTime } in display order.
local function shown(env, guid, auraType)
  local rows = {}
  for i, entry in ipairs(env.auras:Collect(guid, auraType or "DEBUFF", {})) do
    rows[i] = { entry.spellID, entry.duration, entry.expirationTime }
  end
  return rows
end

local function setUnit(env, unit, guid, isPlayer, harmful, helpful)
  env.units[unit] = { guid = guid, player = isPlayer, auras = { HARMFUL = harmful or {}, HELPFUL = helpful or {} } }
end

-- Estimating

t.test("An apply on a never-targeted GUID shows the learned duration after the next tick", function()
  local env = setup(freshDB({ [KIDNEY_SHOT] = 6 }))
  at(env, 100)
  apply(env, P, PLAYER_FLAGS, KIDNEY_SHOT)
  t.eq(shown(env, P), {}, "nothing before the tick")
  t.eq(env.redraws, {})
  at(env, 100.5)
  env.auras:Tick()
  t.eq(shown(env, P), { { KIDNEY_SHOT, 6, 106 } })
  t.eq(env.redraws, { P })
end)

t.test("The second stun inside the DR window lasts half as long", function()
  local env = setup(freshDB({ [KIDNEY_SHOT] = 6 }))
  applyAt(env, 100, P, PLAYER_FLAGS, KIDNEY_SHOT)
  at(env, 106)
  remove(env, P, PLAYER_FLAGS, KIDNEY_SHOT)
  applyAt(env, 110, P, PLAYER_FLAGS, KIDNEY_SHOT)
  t.eq(shown(env, P), { { KIDNEY_SHOT, 3, 113 } })
end)

t.test("The third stun lasts a quarter", function()
  local env = setup(freshDB({ [KIDNEY_SHOT] = 6 }))
  applyAt(env, 100, P, PLAYER_FLAGS, KIDNEY_SHOT)
  at(env, 106)
  remove(env, P, PLAYER_FLAGS, KIDNEY_SHOT)
  applyAt(env, 110, P, PLAYER_FLAGS, KIDNEY_SHOT)
  at(env, 113)
  remove(env, P, PLAYER_FLAGS, KIDNEY_SHOT)
  applyAt(env, 114, P, PLAYER_FLAGS, KIDNEY_SHOT)
  t.eq(shown(env, P), { { KIDNEY_SHOT, 1.5, 115.5 } })
end)

t.test("The fourth stun is immune: nothing is shown and the earlier entry goes", function()
  local env = setup(freshDB({ [KIDNEY_SHOT] = 6 }))
  applyAt(env, 100, P, PLAYER_FLAGS, KIDNEY_SHOT)
  at(env, 106)
  remove(env, P, PLAYER_FLAGS, KIDNEY_SHOT)
  applyAt(env, 110, P, PLAYER_FLAGS, KIDNEY_SHOT)
  at(env, 113)
  remove(env, P, PLAYER_FLAGS, KIDNEY_SHOT)
  applyAt(env, 114, P, PLAYER_FLAGS, KIDNEY_SHOT)
  t.eq(#shown(env, P), 1, "third stun is up")
  applyAt(env, 115, P, PLAYER_FLAGS, KIDNEY_SHOT, "DEBUFF", "SPELL_AURA_REFRESH")
  t.eq(shown(env, P), {})
end)

t.test("An immune apply is dropped even when no duration was learned", function()
  local env = setup()
  for i = 1, 3 do
    applyAt(env, 100 + i * 10, P, PLAYER_FLAGS, KIDNEY_SHOT)
    at(env, 100 + i * 10 + 2)
    remove(env, P, PLAYER_FLAGS, KIDNEY_SHOT)
  end
  applyAt(env, 140, P, PLAYER_FLAGS, KIDNEY_SHOT)
  t.eq(shown(env, P), {})
end)

t.test("A DR count is read after the library has counted, whichever frame ran first", function()
  local env = setup(freshDB({ [KIDNEY_SHOT] = 6 }))
  applyAt(env, 100, P, PLAYER_FLAGS, KIDNEY_SHOT)
  at(env, 106)
  remove(env, P, PLAYER_FLAGS, KIDNEY_SHOT)
  at(env, 110)
  env.auras:OnApply(env.now, "SPELL_AURA_APPLIED", SRC_GUID, "Src", PLAYER_FLAGS, P, "Dst", PLAYER_FLAGS,
    KIDNEY_SHOT, "Kidney Shot", 1, "DEBUFF")
  logEvent(env, "SPELL_AURA_APPLIED", P, PLAYER_FLAGS, KIDNEY_SHOT, "DEBUFF")
  env.auras:Tick()
  t.eq(shown(env, P), { { KIDNEY_SHOT, 3, 113 } })
end)

t.test("A spell without DR keeps its full learned duration however often it is applied", function()
  local env = setup(freshDB({ [HYPOTHERMIA] = 30 }))
  applyAt(env, 100, P, PLAYER_FLAGS, HYPOTHERMIA)
  at(env, 101)
  remove(env, P, PLAYER_FLAGS, HYPOTHERMIA)
  applyAt(env, 102, P, PLAYER_FLAGS, HYPOTHERMIA)
  at(env, 103)
  remove(env, P, PLAYER_FLAGS, HYPOTHERMIA)
  applyAt(env, 104, P, PLAYER_FLAGS, HYPOTHERMIA)
  t.eq(shown(env, P), { { HYPOTHERMIA, 30, 134 } })
end)

t.test("Players and their pets use the player duration, NPCs the NPC one", function()
  local env = setup(freshDB({ [HYPOTHERMIA] = 30 }, { [HYPOTHERMIA] = 12 }))
  applyAt(env, 100, "0xA", PLAYER_FLAGS, HYPOTHERMIA)
  applyAt(env, 100, "0xB", PET_FLAGS, HYPOTHERMIA)
  applyAt(env, 100, "0xC", NPC_FLAGS, HYPOTHERMIA)
  t.eq(shown(env, "0xA"), { { HYPOTHERMIA, 30, 130 } })
  t.eq(shown(env, "0xB"), { { HYPOTHERMIA, 30, 130 } })
  t.eq(shown(env, "0xC"), { { HYPOTHERMIA, 12, 112 } })
end)

t.test("A refresh replaces the entry instead of adding a second one", function()
  local env = setup(freshDB({ [HYPOTHERMIA] = 30 }))
  applyAt(env, 100, P, PLAYER_FLAGS, HYPOTHERMIA)
  applyAt(env, 110, P, PLAYER_FLAGS, HYPOTHERMIA, "DEBUFF", "SPELL_AURA_REFRESH")
  t.eq(shown(env, P), { { HYPOTHERMIA, 30, 140 } })
end)

t.test("Two applies in one frame leave one entry, the later one", function()
  local env = setup(freshDB({ [HYPOTHERMIA] = 30 }))
  at(env, 100)
  apply(env, P, PLAYER_FLAGS, HYPOTHERMIA)
  at(env, 100.2)
  apply(env, P, PLAYER_FLAGS, HYPOTHERMIA, "DEBUFF", "SPELL_AURA_REFRESH")
  env.auras:Tick()
  t.eq(shown(env, P), { { HYPOTHERMIA, 30, 130.2 } })
  t.eq(env.redraws, { P, P })
end)

t.test("A buff is estimated into the buff list only", function()
  local env = setup(freshDB({ [ICE_BLOCK] = 10 }))
  applyAt(env, 100, P, PLAYER_FLAGS, ICE_BLOCK, "BUFF")
  t.eq(shown(env, P, "BUFF"), { { ICE_BLOCK, 10, 110 } })
  t.eq(shown(env, P, "DEBUFF"), {})
end)

t.test("Different spells on one GUID are kept apart", function()
  local env = setup(freshDB({ [HYPOTHERMIA] = 30, [KIDNEY_SHOT] = 6 }))
  applyAt(env, 100, P, PLAYER_FLAGS, HYPOTHERMIA)
  applyAt(env, 100, P, PLAYER_FLAGS, KIDNEY_SHOT)
  t.eq(#shown(env, P), 2)
end)

t.test("No learned duration shows the icon without a timer for 60 seconds from the apply", function()
  local env = setup()
  at(env, 100)
  apply(env, P, PLAYER_FLAGS, KIDNEY_SHOT)
  at(env, 101)
  env.auras:Tick()
  t.eq(shown(env, P), { { KIDNEY_SHOT, 0, 160 } })
  at(env, 159.9)
  t.eq(#shown(env, P), 1, "still up")
  at(env, 160)
  t.eq(shown(env, P), {}, "dropped")
end)

t.test("An estimate past its expiration is not collected", function()
  local env = setup(freshDB({ [KIDNEY_SHOT] = 6 }))
  applyAt(env, 100, P, PLAYER_FLAGS, KIDNEY_SHOT)
  at(env, 105.9)
  t.eq(#shown(env, P), 1)
  at(env, 106)
  t.eq(shown(env, P), {})
end)

-- Ignored input

t.test("Applies that are not tracked are ignored", function()
  local env = setup(freshDB({ [KIDNEY_SHOT] = 6, [RANDOM_AURA] = 6 }))
  at(env, 100)
  apply(env, P, PLAYER_FLAGS, RANDOM_AURA)                                  -- not on a whitelist
  apply(env, P, PLAYER_FLAGS, KIDNEY_SHOT, "BUFF")                          -- debuff name as a buff
  apply(env, P, PLAYER_FLAGS, ICE_BLOCK, "DEBUFF")                          -- buff name as a debuff
  env.auras:OnApply(env.now, "SPELL_AURA_APPLIED", SRC_GUID, "Src", PLAYER_FLAGS, P, "Dst", PLAYER_FLAGS,
    KIDNEY_SHOT, "Kidney Shot", 1, nil)                                     -- no aura type
  env.auras:OnApply(env.now, "SPELL_AURA_APPLIED", SRC_GUID, "Src", PLAYER_FLAGS, nil, "Dst", PLAYER_FLAGS,
    KIDNEY_SHOT, "Kidney Shot", 1, "DEBUFF")                                -- no GUID
  env.auras:OnApply(env.now, "SPELL_AURA_APPLIED", SRC_GUID, "Src", PLAYER_FLAGS, P, "Dst", PLAYER_FLAGS,
    nil, "Kidney Shot", 1, "DEBUFF")                                        -- no spell ID
  env.auras:OnApply(env.now, "SPELL_AURA_APPLIED", SRC_GUID, "Src", PLAYER_FLAGS, P, "Dst", PLAYER_FLAGS,
    KIDNEY_SHOT, nil, 1, "DEBUFF")                                          -- no spell name
  env.auras:Tick()
  t.eq(shown(env, P, "DEBUFF"), {})
  t.eq(shown(env, P, "BUFF"), {})
  t.eq(env.redraws, {})
end)

t.test("Removal events with a missing GUID or spell do nothing", function()
  local env = setup(freshDB({ [HYPOTHERMIA] = 30 }))
  applyAt(env, 100, P, PLAYER_FLAGS, HYPOTHERMIA)
  env.redraws = {}
  env.auras:OnRemove(100, "SPELL_AURA_REMOVED", SRC_GUID, "Src", PLAYER_FLAGS, nil, "Dst", PLAYER_FLAGS,
    HYPOTHERMIA, "Hypothermia", 1, "DEBUFF")
  env.auras:OnRemove(100, "SPELL_AURA_REMOVED", SRC_GUID, "Src", PLAYER_FLAGS, P, "Dst", PLAYER_FLAGS,
    nil, "Hypothermia", 1, "DEBUFF")
  env.auras:OnDied(100, "UNIT_DIED", nil, nil, 0, nil)
  t.eq(#shown(env, P), 1)
  t.eq(env.redraws, {})
end)

-- Removal

local function withEntry(spellID, auraType)
  local env = setup(freshDB({ [spellID] = 30 }))
  applyAt(env, 100, P, PLAYER_FLAGS, spellID, auraType)
  env.redraws = {}
  return env
end

t.test("SPELL_AURA_REMOVED clears the entry and redraws the plate", function()
  local env = withEntry(HYPOTHERMIA)
  remove(env, P, PLAYER_FLAGS, HYPOTHERMIA)
  t.eq(shown(env, P), {})
  t.eq(env.redraws, { P })
end)

t.test("A removal is idempotent and removing nothing does not redraw", function()
  local env = withEntry(HYPOTHERMIA)
  remove(env, P, PLAYER_FLAGS, HYPOTHERMIA)
  env.redraws = {}
  remove(env, P, PLAYER_FLAGS, HYPOTHERMIA)
  remove(env, "0xUNKNOWN", PLAYER_FLAGS, HYPOTHERMIA)
  t.eq(shown(env, P), {})
  t.eq(env.redraws, {})
end)

t.test("A removal of another spell or kind keeps the entry", function()
  local env = withEntry(HYPOTHERMIA)
  remove(env, P, PLAYER_FLAGS, FORBEARANCE)
  remove(env, P, PLAYER_FLAGS, HYPOTHERMIA, "BUFF")
  t.eq(#shown(env, P), 1)
end)

t.test("SPELL_AURA_BROKEN clears the entry", function()
  local env = withEntry(HYPOTHERMIA)
  env.auras:OnRemove(100, "SPELL_AURA_BROKEN", SRC_GUID, "Src", PLAYER_FLAGS, P, "Dst", PLAYER_FLAGS,
    HYPOTHERMIA, "Hypothermia", 1, "DEBUFF")
  t.eq(shown(env, P), {})
  t.eq(env.redraws, { P })
end)

t.test("SPELL_AURA_BROKEN_SPELL clears the broken buff, whose type is the fifteenth argument", function()
  local env = withEntry(ICE_BLOCK, "BUFF")
  env.auras:OnBrokenSpell(100, "SPELL_AURA_BROKEN_SPELL", SRC_GUID, "Src", PLAYER_FLAGS, P, "Dst", PLAYER_FLAGS,
    ICE_BLOCK, "Ice Block", 1, 133, "Fireball", 4, "BUFF")
  t.eq(shown(env, P, "BUFF"), {})
  t.eq(env.redraws, { P })
end)

t.test("SPELL_AURA_BROKEN_SPELL clears a broken debuff and ignores the breaking spell's ID", function()
  local env = withEntry(HYPOTHERMIA)
  applyAt(env, 100, P, PLAYER_FLAGS, FORBEARANCE)
  env.auras:OnBrokenSpell(100, "SPELL_AURA_BROKEN_SPELL", SRC_GUID, "Src", PLAYER_FLAGS, P, "Dst", PLAYER_FLAGS,
    HYPOTHERMIA, "Hypothermia", 1, FORBEARANCE, "Forbearance", 1, "DEBUFF")
  t.eq(#shown(env, P), 1)
  t.eq(shown(env, P)[1][1], FORBEARANCE)
end)

t.test("A stolen buff leaves the target and both plates redraw", function()
  local env = withEntry(ICE_BLOCK, "BUFF")
  env.auras:OnStolen(100, "SPELL_AURA_STOLEN", "0xTHIEF", "Thief", PLAYER_FLAGS, P, "Dst", PLAYER_FLAGS,
    1, "Spellsteal", 64, ICE_BLOCK, "Ice Block", 1, "BUFF")
  t.eq(shown(env, P, "BUFF"), {})
  t.eq(env.redraws, { P, "0xTHIEF" })
end)

t.test("UNIT_DIED wipes that GUID only", function()
  local env = setup(freshDB({ [HYPOTHERMIA] = 30 }))
  applyAt(env, 100, "0xA", PLAYER_FLAGS, HYPOTHERMIA)
  applyAt(env, 100, "0xB", PLAYER_FLAGS, HYPOTHERMIA)
  env.redraws = {}
  env.auras:OnDied(101, "UNIT_DIED", nil, nil, 0, "0xA", "Dead", PLAYER_FLAGS)
  t.eq(shown(env, "0xA"), {})
  t.eq(#shown(env, "0xB"), 1)
  t.eq(env.redraws, { "0xA" })
end)

t.test("Entering the world wipes every aura but keeps what was learned", function()
  local env = setup(freshDB({ [HYPOTHERMIA] = 30 }))
  applyAt(env, 100, "0xA", PLAYER_FLAGS, HYPOTHERMIA)
  applyAt(env, 100, "0xB", NPC_FLAGS, ICE_BLOCK, "BUFF")
  env.auras:OnEnteringWorld()
  t.eq(shown(env, "0xA"), {})
  t.eq(shown(env, "0xB", "BUFF"), {})
  t.eq(env.db.durations.player[HYPOTHERMIA], 30)
end)

t.test("A removal before the tick drops the queued apply", function()
  local env = setup(freshDB({ [HYPOTHERMIA] = 30 }))
  at(env, 100)
  apply(env, P, PLAYER_FLAGS, HYPOTHERMIA)
  remove(env, P, PLAYER_FLAGS, HYPOTHERMIA)
  env.redraws = {}
  env.auras:Tick()
  t.eq(shown(env, P), {})
  t.eq(env.redraws, {}, "nothing was left to resolve")
end)

t.test("A removal drops only the queued apply it matches", function()
  local env = setup(freshDB({ [HYPOTHERMIA] = 30, [FORBEARANCE] = 60 }))
  at(env, 100)
  apply(env, P, PLAYER_FLAGS, HYPOTHERMIA)
  apply(env, P, PLAYER_FLAGS, FORBEARANCE)
  apply(env, "0xOTHER", PLAYER_FLAGS, HYPOTHERMIA)
  remove(env, P, PLAYER_FLAGS, HYPOTHERMIA)
  remove(env, P, PLAYER_FLAGS, ICE_BLOCK, "BUFF")
  env.auras:Tick()
  t.eq(shown(env, P), { { FORBEARANCE, 60, 160 } })
  t.eq(shown(env, "0xOTHER"), { { HYPOTHERMIA, 30, 130 } })
end)

t.test("A removal of the same spell ID as another kind leaves the queued apply", function()
  local env = setup(freshDB({ [HYPOTHERMIA] = 30 }))
  at(env, 100)
  apply(env, P, PLAYER_FLAGS, HYPOTHERMIA)
  remove(env, P, PLAYER_FLAGS, HYPOTHERMIA, "BUFF")
  env.auras:Tick()
  t.eq(shown(env, P), { { HYPOTHERMIA, 30, 130 } })
end)

t.test("A queued apply is dropped by UNIT_DIED for its GUID and by entering the world", function()
  local env = setup(freshDB({ [HYPOTHERMIA] = 30 }))
  at(env, 100)
  apply(env, "0xA", PLAYER_FLAGS, HYPOTHERMIA)
  apply(env, "0xB", PLAYER_FLAGS, HYPOTHERMIA)
  env.auras:OnDied(100, "UNIT_DIED", nil, nil, 0, "0xA")
  env.auras:Tick()
  t.eq(shown(env, "0xA"), {})
  t.eq(#shown(env, "0xB"), 1)

  apply(env, "0xC", PLAYER_FLAGS, HYPOTHERMIA)
  env.auras:OnEnteringWorld()
  env.auras:Tick()
  t.eq(shown(env, "0xC"), {})
end)

-- Units with a token

t.test("UnitAura data replaces the estimates of a unit that has a token", function()
  local env = setup(freshDB({ [HYPOTHERMIA] = 30 }))
  applyAt(env, 100, P, PLAYER_FLAGS, HYPOTHERMIA)
  applyAt(env, 100, P, PLAYER_FLAGS, KIDNEY_SHOT)
  setUnit(env, "target", P, true, { { spellID = KIDNEY_SHOT, duration = 4, expires = 104, dispelType = nil } })
  env.auras:Refresh("target")
  t.eq(shown(env, P), { { KIDNEY_SHOT, 4, 104 } })
end)

t.test("Refresh tracks whitelisted buffs and debuffs and skips the rest", function()
  local env = setup()
  setUnit(env, "target", P, true,
    { { spellID = KIDNEY_SHOT, duration = 4, expires = 104 }, { spellID = RANDOM_AURA, duration = 4, expires = 104 },
      { spellID = HYPOTHERMIA, duration = 0, expires = 0 }, { spellID = FORBEARANCE, duration = 301, expires = 401 } },
    { { spellID = ICE_BLOCK, duration = 10, expires = 110 } })
  at(env, 100)
  env.auras:Refresh("target")
  t.eq(shown(env, P, "DEBUFF"), { { KIDNEY_SHOT, 4, 104 } })
  t.eq(shown(env, P, "BUFF"), { { ICE_BLOCK, 10, 110 } })
end)

t.test("Refresh keeps two auras of one spell from different casters", function()
  local env = setup()
  setUnit(env, "target", P, true,
    { { spellID = HYPOTHERMIA, duration = 30, expires = 130 }, { spellID = HYPOTHERMIA, duration = 20, expires = 120 } })
  at(env, 100)
  env.auras:Refresh("target")
  t.eq(#shown(env, P), 2)
end)

t.test("Refresh of a unit without a GUID changes nothing", function()
  local env = setup(freshDB({ [HYPOTHERMIA] = 30 }))
  applyAt(env, 100, P, PLAYER_FLAGS, HYPOTHERMIA)
  setUnit(env, "ghost", nil, true)
  env.auras:Refresh("ghost")
  t.eq(#shown(env, P), 1)
end)

t.test("A refreshed unit with no auras leaves nothing behind", function()
  local env = setup(freshDB({ [HYPOTHERMIA] = 30 }))
  applyAt(env, 100, P, PLAYER_FLAGS, HYPOTHERMIA)
  setUnit(env, "target", P, true)
  env.auras:Refresh("target")
  t.eq(shown(env, P), {})
end)

-- Learning

t.test("Refresh learns the full duration, separately for players and NPCs, latest sighting winning", function()
  local env = setup()
  at(env, 100)
  setUnit(env, "target", P, true, { { spellID = HYPOTHERMIA, duration = 30, expires = 130 } })
  setUnit(env, "focus", N, false, { { spellID = HYPOTHERMIA, duration = 12, expires = 112 } })
  env.auras:Refresh("target")
  env.auras:Refresh("focus")
  t.eq(env.db.durations, { player = { [HYPOTHERMIA] = 30 }, npc = { [HYPOTHERMIA] = 12 } })
  setUnit(env, "target", P, true, { { spellID = HYPOTHERMIA, duration = 25, expires = 125 } })
  env.auras:Refresh("target")
  t.eq(env.db.durations.player[HYPOTHERMIA], 25)
end)

t.test("A learned duration is used for the next apply", function()
  local env = setup()
  at(env, 100)
  setUnit(env, "target", P, true, { { spellID = KIDNEY_SHOT, duration = 6, expires = 106 } })
  env.auras:Refresh("target")
  applyAt(env, 200, "0xOTHER", PLAYER_FLAGS, KIDNEY_SHOT)
  t.eq(shown(env, "0xOTHER"), { { KIDNEY_SHOT, 6, 206 } })
  applyAt(env, 200, "0xNPC2", NPC_FLAGS, KIDNEY_SHOT)
  t.eq(shown(env, "0xNPC2"), { { KIDNEY_SHOT, 0, 260 } }, "no NPC duration learned yet")
end)

t.test("The first application of a DR spell is learned", function()
  local env = setup()
  applyAt(env, 100, P, PLAYER_FLAGS, KIDNEY_SHOT)
  setUnit(env, "target", P, true, { { spellID = KIDNEY_SHOT, duration = 6, expires = 106 } })
  env.auras:Refresh("target")
  t.eq(env.db.durations.player[KIDNEY_SHOT], 6)
end)

t.test("A DR spell with no DR state yet is learned", function()
  local env = setup()
  setUnit(env, "target", P, true, { { spellID = KIDNEY_SHOT, duration = 6, expires = 106 } })
  env.auras:Refresh("target")
  t.eq(env.db.durations.player[KIDNEY_SHOT], 6)
end)

t.test("A diminished sighting is not learned", function()
  local env = setup(freshDB({ [KIDNEY_SHOT] = 6 }))
  applyAt(env, 100, P, PLAYER_FLAGS, KIDNEY_SHOT)
  at(env, 106)
  remove(env, P, PLAYER_FLAGS, KIDNEY_SHOT)
  applyAt(env, 110, P, PLAYER_FLAGS, KIDNEY_SHOT)
  setUnit(env, "target", P, true, { { spellID = KIDNEY_SHOT, duration = 3, expires = 113 } })
  env.auras:Refresh("target")
  t.eq(env.db.durations.player[KIDNEY_SHOT], 6, "second application")

  at(env, 113)
  remove(env, P, PLAYER_FLAGS, KIDNEY_SHOT)
  applyAt(env, 114, P, PLAYER_FLAGS, KIDNEY_SHOT)
  setUnit(env, "target", P, true, { { spellID = KIDNEY_SHOT, duration = 1.5, expires = 115.5 } })
  env.auras:Refresh("target")
  t.eq(env.db.durations.player[KIDNEY_SHOT], 6, "third application")
end)

t.test("The DR window is per GUID", function()
  local env = setup()
  applyAt(env, 100, "0xOTHER", PLAYER_FLAGS, KIDNEY_SHOT)
  at(env, 106)
  remove(env, "0xOTHER", PLAYER_FLAGS, KIDNEY_SHOT)
  applyAt(env, 110, "0xOTHER", PLAYER_FLAGS, KIDNEY_SHOT)
  setUnit(env, "target", P, true, { { spellID = KIDNEY_SHOT, duration = 6, expires = 116 } })
  env.auras:Refresh("target")
  t.eq(env.db.durations.player[KIDNEY_SHOT], 6)
end)

t.test("Untracked auras are not learned", function()
  local env = setup()
  setUnit(env, "target", P, true,
    { { spellID = RANDOM_AURA, duration = 10, expires = 110 }, { spellID = HYPOTHERMIA, duration = 0, expires = 0 },
      { spellID = FORBEARANCE, duration = 301, expires = 401 } })
  env.auras:Refresh("target")
  t.eq(env.db.durations, { player = {}, npc = {} })
end)

t.test("A buff duration is learned too", function()
  local env = setup()
  setUnit(env, "target", P, true, {}, { { spellID = ICE_BLOCK, duration = 10, expires = 110 } })
  env.auras:Refresh("target")
  t.eq(env.db.durations.player[ICE_BLOCK], 10)
end)

-- Display

t.test("Timed auras sort by duration, longest first, and auras without a timer come last", function()
  local env = setup(freshDB({ [HYPOTHERMIA] = 30, [KIDNEY_SHOT] = 6 }))
  applyAt(env, 100, P, PLAYER_FLAGS, POLYMORPH)
  applyAt(env, 100, P, PLAYER_FLAGS, KIDNEY_SHOT)
  applyAt(env, 100, P, PLAYER_FLAGS, HYPOTHERMIA)
  t.eq(shown(env, P), { { HYPOTHERMIA, 30, 130 }, { KIDNEY_SHOT, 6, 106 }, { POLYMORPH, 0, 160 } })
end)

t.test("Equal durations sort by spell ID", function()
  local env = setup(freshDB({ [HYPOTHERMIA] = 30, [FORBEARANCE] = 30 }))
  applyAt(env, 100, P, PLAYER_FLAGS, HYPOTHERMIA)
  applyAt(env, 100, P, PLAYER_FLAGS, FORBEARANCE)
  t.eq(shown(env, P), { { FORBEARANCE, 30, 130 }, { HYPOTHERMIA, 30, 130 } })
end)

t.test("Collect clears the array it is given and handles unknown GUIDs", function()
  local env = setup()
  t.eq(env.auras:Collect("0xNONE", "DEBUFF", { "stale" }), {})
  t.eq(env.auras:Collect(nil, "DEBUFF", { "stale" }), {})
end)

t.test("An entry freed by a removal is reused by the next apply, without stale fields", function()
  local env = setup(freshDB({ [HYPOTHERMIA] = 30 }))
  setUnit(env, "target", P, true, { { spellID = KIDNEY_SHOT, duration = 4, expires = 104, dispelType = "Magic" } })
  at(env, 100)
  env.auras:Refresh("target")
  local first = env.auras:Collect(P, "DEBUFF", {})[1]
  t.eq(first.dispelType, "Magic")

  setUnit(env, "target", P, true)
  env.auras:Refresh("target")
  applyAt(env, 100, N, PLAYER_FLAGS, HYPOTHERMIA)
  local second = env.auras:Collect(N, "DEBUFF", {})[1]
  t.truthy(rawequal(first, second), "pooled table reused")
  t.eq(second.dispelType, nil)
  t.eq({ second.spellID, second.duration, second.expirationTime }, { HYPOTHERMIA, 30, 130 })
end)

t.test("An estimate replacing a UnitAura entry drops its dispel type", function()
  local env = setup(freshDB({ [KIDNEY_SHOT] = 6 }))
  setUnit(env, "target", P, true, { { spellID = KIDNEY_SHOT, duration = 4, expires = 104, dispelType = "Magic" } })
  at(env, 100)
  env.auras:Refresh("target")
  applyAt(env, 101, P, PLAYER_FLAGS, KIDNEY_SHOT)
  t.eq(env.auras:Collect(P, "DEBUFF", {})[1].dispelType, nil)
end)

-- Memory cap

t.test("The 4001st GUID wipes all auras", function()
  local env = setup()
  at(env, 100)
  for i = 1, 4000 do
    apply(env, "0x" .. i, NPC_FLAGS, HYPOTHERMIA)
  end
  env.auras:Tick()
  t.eq(#shown(env, "0x1"), 1, "first of 4000 is kept")
  t.eq(#shown(env, "0x4000"), 1, "last of 4000 is kept")

  apply(env, "0x4001", NPC_FLAGS, HYPOTHERMIA)
  env.auras:Tick()
  t.eq(shown(env, "0x1"), {})
  t.eq(shown(env, "0x4000"), {})
  t.eq(#shown(env, "0x4001"), 1)
end)

t.test("A removed GUID frees its slot in the cap", function()
  local env = setup()
  at(env, 100)
  for i = 1, 4000 do
    apply(env, "0x" .. i, NPC_FLAGS, HYPOTHERMIA)
  end
  env.auras:Tick()
  remove(env, "0x2", NPC_FLAGS, HYPOTHERMIA)
  apply(env, "0x4001", NPC_FLAGS, HYPOTHERMIA)
  env.auras:Tick()
  t.eq(#shown(env, "0x1"), 1, "no wipe")
  t.eq(#shown(env, "0x4001"), 1)
end)

-- Saved cache

t.test("A missing or malformed saved table is replaced by a fresh one", function()
  local env = setup()
  for _, bad in ipairs({ "junk", 5, true }) do
    t.eq(env.auras:LoadDB(bad), freshDB(), "value " .. tostring(bad))
  end
  t.eq(env.auras:LoadDB(nil), freshDB())
end)

t.test("A saved table of another version is discarded", function()
  local env = setup()
  t.eq(env.auras:LoadDB({ version = 2, durations = { player = { [KIDNEY_SHOT] = 6 }, npc = {} } }), freshDB())
  t.eq(env.auras:LoadDB({ durations = { player = { [KIDNEY_SHOT] = 6 }, npc = {} } }), freshDB())
end)

t.test("Good saved entries are kept and used", function()
  local env = setup()
  local saved = freshDB({ [KIDNEY_SHOT] = 6, [FORBEARANCE] = 300, [HYPOTHERMIA] = 0.5 }, { [KIDNEY_SHOT] = 4 })
  local db = env.auras:LoadDB(saved)
  t.truthy(rawequal(db, saved), "the saved table itself is used")
  t.eq(db, freshDB({ [KIDNEY_SHOT] = 6, [FORBEARANCE] = 300, [HYPOTHERMIA] = 0.5 }, { [KIDNEY_SHOT] = 4 }))
  applyAt(env, 100, N, NPC_FLAGS, KIDNEY_SHOT)
  t.eq(shown(env, N), { { KIDNEY_SHOT, 4, 104 } })
end)

t.test("Bad saved entries are dropped", function()
  local env = setup()
  local db = env.auras:LoadDB(freshDB(
    { [KIDNEY_SHOT] = 6, [POLYMORPH] = 0, [1] = 301, [2] = -1, [3] = "6", [4] = 300, ["name"] = 5, [5] = {} },
    { [6] = 0 / 0, [7] = math.huge, [8] = 8 }))
  t.eq(db.durations.player, { [KIDNEY_SHOT] = 6, [4] = 300 })
  t.eq(db.durations.npc, { [8] = 8 })
end)

t.test("Missing or malformed duration tables are rebuilt", function()
  local env = setup()
  t.eq(env.auras:LoadDB({ version = 1 }), freshDB())
  t.eq(env.auras:LoadDB({ version = 1, durations = "x" }), freshDB())
  t.eq(env.auras:LoadDB({ version = 1, durations = { player = "x", npc = { [8] = 8 } } }), freshDB({}, { [8] = 8 }))
end)

t.test("Learned durations are written into the saved table", function()
  local env = setup()
  local db = env.auras:LoadDB(nil)
  setUnit(env, "target", P, true, { { spellID = HYPOTHERMIA, duration = 30, expires = 130 } })
  env.auras:Refresh("target")
  t.eq(db.durations.player[HYPOTHERMIA], 30)
end)
