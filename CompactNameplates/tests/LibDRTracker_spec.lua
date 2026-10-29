-- Runs in the standalone interpreter and replaces client globals with stubs on purpose.
---@diagnostic disable: duplicate-set-field, undefined-global
local t = ...

local LIB_DIR      = "Libs/LibDRTracker-1.0/"
local PLAYER_FLAGS = 0x0548 -- hostile player
local PET_FLAGS    = 0x1148 -- hostile player-controlled pet
local NPC_FLAGS    = 0x0A48 -- hostile NPC

local KIDNEY_SHOT  = 8643  -- stun
local CHEAP_SHOT   = 1833  -- opener_stun
local BLIND        = 2094  -- fear
local MIND_CONTROL = 605   -- mind_control
local TAUNT        = 355   -- taunt
local POLYMORPH    = 118   -- incapacitate (rank 1)
local NO_DR_SPELL  = 1     -- not in the table

local function band(a, b)
  local result, bitValue = 0, 1
  while a > 0 and b > 0 do
    if a % 2 == 1 and b % 2 == 1 then result = result + bitValue end
    a, b, bitValue = math.floor(a / 2), math.floor(b / 2), bitValue * 2
  end
  return result
end

-- Fresh LibStub and library per test, because both live in globals.
local function setup()
  local env = { now = 0, events = {}, fired = {} }

  _G.LibStub = nil
  _G.strmatch = string.match
  _G.bit = { band = band }
  _G.wipe = function(tbl) for k in pairs(tbl) do tbl[k] = nil end return tbl end
  _G.GetTime = function() return env.now end
  _G.securecall = function(fn, ...) return fn(...) end
  _G.CreateFrame = function()
    return {
      UnregisterAllEvents = function() env.events = {} end,
      RegisterEvent = function(_, event) env.events[event] = true end,
      SetScript = function(_, _, fn) env.onEvent = fn end,
    }
  end

  t.newNamespace("Libs/LibStub/LibStub.lua", LIB_DIR .. "LibDRTracker-1.0.lua", LIB_DIR .. "Spells.lua")
  env.lib = LibStub("LibDRTracker-1.0")
  env.lib:RegisterCallback("spec", function(guid, category)
    env.fired[#env.fired + 1] = guid .. ":" .. category
  end)
  return env
end

local function aura(env, event, guid, flags, spellID, auraType)
  env.onEvent(nil, "COMBAT_LOG_EVENT_UNFILTERED", 0, event, "0xSRC", "Src", PLAYER_FLAGS,
    guid, "Dst", flags, spellID, "Spell", 1, auraType or "DEBUFF")
end

-- Data and factors

t.test("Every rank and variant is categorised", function()
  local env = setup()
  t.eq(env.lib:GetCategory(KIDNEY_SHOT), "stun")
  t.eq(env.lib:GetCategory(408), "stun", "Kidney Shot rank 1")
  t.eq(env.lib:GetCategory(POLYMORPH), "incapacitate")
  t.eq(env.lib:GetCategory(61780), "incapacitate", "Polymorph: Turkey")
  t.eq(env.lib:GetCategory(20253), "stun", "Intercept stun")
  t.eq(env.lib:GetCategory(BLIND), "fear")
  t.eq(env.lib:GetCategory(CHEAP_SHOT), "opener_stun")
  t.eq(env.lib:GetCategory(NO_DR_SPELL), nil)
  t.eq(env.lib:GetCategory(nil), nil)
end)

t.test("Factors halve twice, then immune; taunts diminish more slowly", function()
  local env = setup()
  t.eq({ env.lib:GetFactor("stun", 1), env.lib:GetFactor("stun", 2), env.lib:GetFactor("stun", 3),
    env.lib:GetFactor("stun", 4) }, { 1, 0.5, 0.25, 0 })
  t.eq({ env.lib:GetFactor("taunt", 2), env.lib:GetFactor("taunt", 4), env.lib:GetFactor("taunt", 5) },
    { 0.65, 0.27, 0 })
end)

-- Windows

t.test("Four CCs in one window get full, half, quarter, immune", function()
  local env = setup()
  local factors = {}
  for i = 1, 4 do
    factors[i] = env.lib:OnApplied("0x01", KIDNEY_SHOT, env.now)
    env.now = env.now + 1
    env.lib:OnRemoved("0x01", KIDNEY_SHOT, env.now)
    env.now = env.now + 1
  end
  t.eq(factors, { 1, 0.5, 0.25, 0 })
end)

t.test("The window closes 20 s after the CC ends, not before", function()
  local env = setup()
  env.lib:OnApplied("0x01", KIDNEY_SHOT, 0)
  env.lib:OnRemoved("0x01", KIDNEY_SHOT, 6)
  t.eq(env.lib:OnApplied("0x01", KIDNEY_SHOT, 25.9), 0.5, "at 19.9 s after removal")

  env.lib:OnRemoved("0x01", KIDNEY_SHOT, 30)
  t.eq(env.lib:OnApplied("0x01", KIDNEY_SHOT, 50), 1, "at 20 s after removal")
end)

t.test("The window stays open while a long CC is up", function()
  local env = setup()
  env.lib:OnApplied("0x01", MIND_CONTROL, 0)
  t.eq(env.lib:OnApplied("0x01", MIND_CONTROL, 30), 0.5)
end)

t.test("A CC whose removal was never seen ends after the stale limit", function()
  local env = setup()
  env.lib:OnApplied("0x01", KIDNEY_SHOT, 0)
  t.eq(env.lib:GetState("0x01", "stun", 79.9), 1, "still open at 79.9 s")
  t.eq(env.lib:GetState("0x01", "stun", 80), nil, "closed at 80 s")
  t.eq(env.lib:OnApplied("0x01", KIDNEY_SHOT, 80), 1)
end)

t.test("A removal without a seen application opens a window", function()
  local env = setup()
  env.lib:OnRemoved("0x01", KIDNEY_SHOT, 10)
  t.eq({ env.lib:GetState("0x01", "stun", 10) }, { 1, 30, false })
  t.eq(env.lib:OnApplied("0x01", KIDNEY_SHOT, 11), 0.5)
end)

t.test("GetState reports the CC as active until it's removed", function()
  local env = setup()
  env.lib:OnApplied("0x01", KIDNEY_SHOT, 0)
  local count, _, active = env.lib:GetState("0x01", "stun", 1)
  t.eq({ count, active }, { 1, true })
  env.lib:OnRemoved("0x01", KIDNEY_SHOT, 4)
  t.eq({ env.lib:GetState("0x01", "stun", 5) }, { 1, 24, false })
end)

t.test("Categories and GUIDs are independent", function()
  local env = setup()
  env.lib:OnApplied("0x01", KIDNEY_SHOT, 0)
  t.eq(env.lib:OnApplied("0x01", BLIND, 1), 1, "other category")
  t.eq(env.lib:OnApplied("0x01", CHEAP_SHOT, 1), 1, "opener stun is its own category")
  t.eq(env.lib:OnApplied("0x02", KIDNEY_SHOT, 1), 1, "other GUID")
end)

t.test("Spells without DR and missing arguments are ignored", function()
  local env = setup()
  t.eq(env.lib:OnApplied("0x01", NO_DR_SPELL, 0), nil)
  t.eq(env.lib:OnApplied(nil, KIDNEY_SHOT, 0), nil)
  env.lib:OnRemoved(nil, KIDNEY_SHOT, 0)
  env.lib:OnRemoved("0x01", nil, 0)
  t.eq(env.lib:GetState("0x01", nil, 0), nil)
  t.eq(env.lib:GetState(nil, "stun", 0), nil)
  t.eq(env.lib.guidCount, 0)
  t.eq(#env.fired, 0)
end)

t.test("Expired windows are forgotten", function()
  local env = setup()
  env.lib:OnApplied("0x01", KIDNEY_SHOT, 0)
  env.lib:OnRemoved("0x01", KIDNEY_SHOT, 1)
  t.eq(env.lib.guidCount, 1)
  env.lib:GetState("0x01", "stun", 21)
  t.eq(env.lib.guidCount, 0)
  t.eq(env.lib.states["0x01"], nil)
end)

t.test("The store wipes once it holds 4000 GUIDs", function()
  local env = setup()
  for i = 1, 4000 do env.lib:OnApplied("g" .. i, KIDNEY_SHOT, 0) end
  t.eq(env.lib:GetState("g1", "stun", 0), 1, "first GUID before the cap")
  env.lib:OnApplied("g4001", KIDNEY_SHOT, 0)
  t.eq(env.lib:GetState("g1", "stun", 0), nil, "first GUID after the cap")
  t.eq(env.lib:GetState("g4001", "stun", 0), 1)
  t.eq(env.lib.guidCount, 1)
end)

t.test("Reset forgets everything", function()
  local env = setup()
  env.lib:OnApplied("0x01", KIDNEY_SHOT, 0)
  env.lib:Reset()
  t.eq(env.lib:GetState("0x01", "stun", 0), nil)
  t.eq(env.lib.guidCount, 0)
end)

-- Combat log

t.test("The combat log counts applies and refreshes and times the reset from removal", function()
  local env = setup()
  aura(env, "SPELL_AURA_APPLIED", "0x01", PLAYER_FLAGS, KIDNEY_SHOT)
  env.now = 2
  aura(env, "SPELL_AURA_REFRESH", "0x01", PLAYER_FLAGS, KIDNEY_SHOT)
  env.now = 5
  aura(env, "SPELL_AURA_REMOVED", "0x01", PLAYER_FLAGS, KIDNEY_SHOT)
  t.eq({ env.lib:GetState("0x01", "stun", 5) }, { 2, 25, false })
  t.eq(env.fired, { "0x01:stun", "0x01:stun", "0x01:stun" })
end)

t.test("Pets get PvP DR like players", function()
  local env = setup()
  aura(env, "SPELL_AURA_APPLIED", "0xF1", PET_FLAGS, BLIND)
  t.eq(env.lib:GetState("0xF1", "fear", 0), 1)
end)

t.test("NPCs only diminish in the PvE categories", function()
  local env = setup()
  aura(env, "SPELL_AURA_APPLIED", "0xA1", NPC_FLAGS, POLYMORPH)
  aura(env, "SPELL_AURA_APPLIED", "0xA1", NPC_FLAGS, BLIND)
  t.eq(env.lib:GetState("0xA1", "incapacitate", 0), nil)
  t.eq(env.lib:GetState("0xA1", "fear", 0), nil)

  aura(env, "SPELL_AURA_APPLIED", "0xA1", NPC_FLAGS, KIDNEY_SHOT)
  aura(env, "SPELL_AURA_APPLIED", "0xA1", NPC_FLAGS, CHEAP_SHOT)
  aura(env, "SPELL_AURA_APPLIED", "0xA1", NPC_FLAGS, TAUNT)
  t.eq(env.lib:GetState("0xA1", "stun", 0), 1)
  t.eq(env.lib:GetState("0xA1", "opener_stun", 0), 1)
  t.eq(env.lib:GetState("0xA1", "taunt", 0), 1)
end)

t.test("Buffs, other subevents and spells without DR are ignored", function()
  local env = setup()
  aura(env, "SPELL_AURA_APPLIED", "0x01", PLAYER_FLAGS, KIDNEY_SHOT, "BUFF")
  aura(env, "SPELL_DAMAGE", "0x01", PLAYER_FLAGS, KIDNEY_SHOT)
  aura(env, "SPELL_AURA_APPLIED", "0x01", PLAYER_FLAGS, NO_DR_SPELL)
  aura(env, "SPELL_AURA_APPLIED", nil, PLAYER_FLAGS, KIDNEY_SHOT)
  t.eq(env.lib:GetState("0x01", "stun", 0), nil)
  t.eq(#env.fired, 0)
end)

t.test("Entering the world wipes DR state", function()
  local env = setup()
  t.truthy(env.events.COMBAT_LOG_EVENT_UNFILTERED and env.events.PLAYER_ENTERING_WORLD)
  aura(env, "SPELL_AURA_APPLIED", "0x01", PLAYER_FLAGS, KIDNEY_SHOT)
  env.onEvent(nil, "PLAYER_ENTERING_WORLD")
  t.eq(env.lib:GetState("0x01", "stun", 0), nil)
end)

t.test("An unregistered callback stops firing", function()
  local env = setup()
  env.lib:UnregisterCallback("spec")
  env.lib:OnApplied("0x01", KIDNEY_SHOT, 0)
  t.eq(#env.fired, 0)
end)

-- Embedding

local function readFile(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local content = file:read("*a")
  file:close()
  return content
end

t.test("Every embedded copy matches the canonical library", function()
  local canonical = t.root .. "/" .. LIB_DIR
  for _, addon in ipairs({ "RAF" }) do
    local copy = t.root .. "/../" .. addon .. "/" .. LIB_DIR
    for _, file in ipairs({ "LibDRTracker-1.0.lua", "Spells.lua" }) do
      local expected = readFile(canonical .. file)
      t.truthy(expected, "canonical " .. file)
      t.truthy(readFile(copy .. file) == expected, addon .. " copy of " .. file .. " differs or is missing")
    end
  end
end)
